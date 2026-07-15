defmodule Guava.Socket do
  @moduledoc """
  A reliable, self-reconnecting GuavaSocket connection.

  Wraps a WebSocket connection and drives the pure reliable-protocol
  state machine (`Guava.Socket.Reliable`). It performs the open/open-ack
  handshake, retransmits unacked messages across reconnects, keeps the
  connection alive with pings, and reconnects with backoff — mirroring the
  Python `GuavaSocket`.

  ## Messages delivered to the owner

    * `{:guava_socket, pid, :ready}` — handshake complete, socket open
    * `{:guava_socket, pid, {:payload, map}}` — an inbound payload arrived
    * `{:guava_socket, pid, {:closed, reason, description}}` — permanently closed
  """
  use GenServer
  require Logger

  alias Guava.Socket.{Reliable, Conn, Protocol}
  alias Guava.Internal

  @open_ack_timeout 10_000
  @idle_ping_ms 10_000
  @max_consecutive_failures 10
  @max_opens_per_minute 15

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :url,
      :headers,
      :owner,
      :reliable,
      :conn,
      :conn_ref,
      :max_age_ms,
      :started_ms,
      :ack_timer,
      :idle_timer,
      consecutive_failures: 0,
      opens: [],
      closing: false
    ]
  end

  # ---- Public API ----

  @doc """
  Start a socket.

  ## Options
    * `:name` — a label for logging (string)
    * `:url` — the `ws(s)://` URL to connect to
    * `:headers` — auth/identification headers (list of `{k, v}`)
    * `:owner` — pid to deliver events to (defaults to the caller)
    * `:max_age_ms` — optionally close the socket after this many ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Enqueue a payload map to send to the peer (buffered until deliverable)."
  @spec send_payload(pid(), map()) :: :ok
  def send_payload(pid, payload), do: GenServer.cast(pid, {:send, payload})

  @doc "Close the socket permanently."
  @spec close(pid()) :: :ok
  def close(pid),
    do: GenServer.cast(pid, {:client_close, "done", "The socket was closed by the client."})

  # ---- GenServer ----

  @impl true
  def init(opts) do
    name = opts[:name] || "guava-socket"
    connection_id = Internal.random_hex(10)

    state = %State{
      name: name,
      url: Keyword.fetch!(opts, :url),
      headers: opts[:headers] || [],
      owner: opts[:owner] || self(),
      reliable: Reliable.new(name, connection_id),
      max_age_ms: opts[:max_age_ms],
      started_ms: Internal.now_ms()
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl true
  def handle_cast({:send, payload}, %State{} = state) do
    {reliable, frame} = Reliable.send_payload(state.reliable, payload)
    state = %{state | reliable: reliable}

    if state.conn && Reliable.open?(reliable) do
      send_frame(state, frame)
    end

    {:noreply, state}
  end

  def handle_cast({:client_close, reason, desc}, %State{} = state) do
    {:stop, :normal, shutdown(state, reason, desc)}
  end

  @impl true
  def handle_info({:conn_up, conn_pid}, %State{} = state) do
    # WebSocket established; run the open handshake.
    {reliable, open_frame} = Reliable.prepare_open(state.reliable)
    state = %{state | reliable: reliable, consecutive_failures: 0}
    Conn.send_text(conn_pid, Protocol.encode!(open_frame))
    ack_timer = Process.send_after(self(), :open_ack_timeout, @open_ack_timeout)
    {:noreply, %{state | ack_timer: ack_timer}}
  end

  def handle_info({:ws_frame, text}, %State{} = state) do
    state = reset_idle_timer(state)
    frame = Protocol.decode!(text)
    {reliable, actions} = Reliable.handle_frame(state.reliable, frame, Internal.now_ms())
    state = %{state | reliable: reliable}
    {:noreply, run_actions(state, actions)}
  end

  def handle_info(:open_ack_timeout, %State{reliable: %{status: :open}} = state) do
    # Already open; the handshake completed before the timeout fired.
    {:noreply, state}
  end

  def handle_info(:open_ack_timeout, %State{} = state) do
    Logger.warning("[#{state.name}] open-ack not received in time; reconnecting.")
    {:noreply, reconnect(teardown_conn(state), :open_ack_timeout)}
  end

  def handle_info({:ws_down, _reason}, %State{closing: true} = state), do: {:noreply, state}

  def handle_info({:ws_down, reason}, %State{} = state) do
    Logger.debug("[#{state.name}] websocket down: #{inspect(reason)}")
    {:noreply, reconnect(teardown_conn(state), reason)}
  end

  def handle_info(:reconnect, %State{} = state), do: {:noreply, connect(state)}

  def handle_info(:idle_ping, %State{} = state) do
    state = check_max_age(state)

    if not state.closing and Reliable.open?(state.reliable) do
      send_frame(state, Reliable.ping(state.reliable, Internal.now_ms()))
    end

    {:noreply, schedule_idle_ping(state)}
  end

  # A monitored Conn going down that we didn't already handle via :ws_down.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{conn_ref: ref} = state) do
    handle_info({:ws_down, reason}, %{state | conn: nil, conn_ref: nil})
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  # ---- internals ----

  defp connect(%State{} = state) do
    case Conn.start(state.url, self(), state.headers) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        %{state | conn: pid, conn_ref: ref}

      {:error, reason} ->
        Logger.warning("[#{state.name}] connect failed: #{inspect(reason)}")
        reconnect(state, reason)
    end
  end

  defp reconnect(%State{closing: true} = state, _reason), do: state

  defp reconnect(%State{} = state, reason) do
    failures = state.consecutive_failures + 1

    cond do
      failures >= @max_consecutive_failures ->
        Logger.error("[#{state.name}] could not connect after #{failures} attempts.")
        shutdown(state, "reconnection-failed", "Couldn't connect after #{failures} attempts.")

      too_many_opens?(state) ->
        shutdown(state, "server-error", "Too many connections in the last minute.")

      true ->
        _ = reason
        delay = backoff_ms(failures)
        Process.send_after(self(), :reconnect, delay)
        %{state | consecutive_failures: failures}
    end
  end

  # Backoff schedule mirrors the Python SDK (jittered).
  defp backoff_ms(attempt) when attempt <= 3, do: jitter(1_000, 500)
  defp backoff_ms(attempt) when attempt <= 5, do: jitter(5_000, 2_000)
  defp backoff_ms(_attempt), do: jitter(10_000, 5_000)

  defp jitter(base, spread), do: max(0, base + :rand.uniform(2 * spread + 1) - 1 - spread)

  defp run_actions(state, actions), do: Enum.reduce(actions, state, &run_action(&2, &1))

  defp run_action(state, {:send, frame}) do
    send_frame(state, frame)
    state
  end

  defp run_action(state, {:deliver, payload}) do
    notify(state, {:payload, payload})
    state
  end

  defp run_action(state, :ready) do
    cancel_timer(state.ack_timer)
    opens = [Internal.now_ms() | state.opens] |> recent_opens()
    state = %{state | ack_timer: nil, consecutive_failures: 0, opens: opens}
    notify(state, :ready)
    schedule_idle_ping(state)
  end

  defp run_action(state, {:closed, reason, desc}) do
    notify(state, {:closed, reason, desc})
    teardown_conn(%{state | closing: true})
  end

  defp send_frame(%State{conn: conn}, frame) when is_pid(conn) do
    Conn.send_text(conn, Protocol.encode!(frame))
  rescue
    _ -> :ok
  end

  defp send_frame(_state, _frame), do: :ok

  defp notify(%State{owner: owner}, msg), do: send(owner, {:guava_socket, self(), msg})

  defp shutdown(%State{} = state, reason, desc) do
    reliable = Reliable.close(state.reliable, reason, desc)
    state = %{state | reliable: reliable, closing: true}
    notify(state, {:closed, reliable.close_reason, reliable.close_description})
    teardown_conn(state)
  end

  defp teardown_conn(%State{conn: nil} = state), do: state

  defp teardown_conn(%State{conn: conn, conn_ref: ref} = state) do
    if ref, do: Process.demonitor(ref, [:flush])
    if Process.alive?(conn), do: Process.exit(conn, :shutdown)
    %{state | conn: nil, conn_ref: nil}
  end

  defp too_many_opens?(%State{opens: opens}),
    do: length(recent_opens(opens)) >= @max_opens_per_minute

  defp recent_opens(opens) do
    cutoff = Internal.now_ms() - 60_000
    Enum.filter(opens, &(&1 > cutoff))
  end

  defp check_max_age(%State{max_age_ms: nil} = state), do: state

  defp check_max_age(%State{max_age_ms: max, started_ms: started} = state) do
    if Internal.now_ms() - started > max do
      Logger.warning("[#{state.name}] socket hit max age limit; closing.")
      shutdown(state, "other", "The socket hit its max age limit.")
    else
      state
    end
  end

  defp schedule_idle_ping(state) do
    cancel_timer(state.idle_timer)
    %{state | idle_timer: Process.send_after(self(), :idle_ping, @idle_ping_ms)}
  end

  defp reset_idle_timer(state) do
    if Reliable.open?(state.reliable), do: schedule_idle_ping(state), else: state
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end

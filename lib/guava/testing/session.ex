defmodule Guava.Testing.Session do
  @moduledoc """
  Drives an agent under test against Guava's `v1/test-agent` endpoint.

  Inject caller utterances with `say/2`, wait for the agent's turn with
  `wait_for_turn/1`, read the running `get_transcript/1`, and assert outcomes
  with `evaluate/2`. Created for you by `Guava.Testing.session/3` and
  `Guava.Testing.roleplay/3`.
  """
  use GenServer
  require Logger

  alias Guava.{HTTP, LLM}
  alias Guava.Testing.Protocol

  alias Guava.Testing.Protocol.{
    Ping,
    Pong,
    BotTTS,
    TurnStarted,
    SessionStarted,
    InjectASR,
    WaitForTurn
  }

  @idle_ping_ms 5_000

  defmodule State do
    @moduledoc false
    defstruct [
      :conn,
      :client,
      :session_id,
      :runtime,
      events: [],
      queue: [],
      waiting: nil,
      closed: false
    ]
  end

  # ---- API ----

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Inject a caller utterance."
  @spec say(pid(), String.t()) :: :ok
  def say(pid, utterance), do: GenServer.cast(pid, {:say, utterance})

  @doc "Receive the next server event (a `BotTTS` or `TurnStarted`), or `:closed`."
  @spec recv(pid(), timeout()) :: struct() | :closed
  def recv(pid, timeout \\ 30_000), do: GenServer.call(pid, :recv, timeout)

  @doc "Block until the agent yields the turn back to the caller."
  @spec wait_for_turn(pid()) :: :ok
  def wait_for_turn(pid) do
    request_id = Guava.Internal.random_hex(8)
    GenServer.cast(pid, {:send, %WaitForTurn{request_id: request_id}})
    wait_turn_loop(pid, request_id)
  end

  defp wait_turn_loop(pid, request_id) do
    case recv(pid) do
      %TurnStarted{request_id: ^request_id} -> :ok
      :closed -> :ok
      _ -> wait_turn_loop(pid, request_id)
    end
  end

  @doc "The conversation transcript so far."
  @spec get_transcript(pid()) :: String.t()
  def get_transcript(pid), do: GenServer.call(pid, :get_transcript)

  @doc "The session id assigned by the server."
  @spec session_id(pid()) :: String.t()
  def session_id(pid), do: GenServer.call(pid, :session_id)

  @doc "Stop the session."
  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid, :normal)

  @doc """
  Evaluate the transcript against pass/fail criteria using the LLM endpoint.
  Raises if any pass criterion is unmet or any fail criterion is triggered.
  """
  @spec evaluate(pid(), [String.t()], [String.t()]) :: :ok
  def evaluate(pid, pass_criteria \\ [], fail_criteria \\ []) do
    all = Enum.map(pass_criteria, &{:pass, &1}) ++ Enum.map(fail_criteria, &{:fail, &1})
    if all == [], do: throw_ok(), else: do_evaluate(pid, all)
  end

  defp throw_ok, do: :ok

  defp do_evaluate(pid, all) do
    client = GenServer.call(pid, :client)
    transcript = get_transcript(pid)

    criteria_list =
      all |> Enum.with_index(1) |> Enum.map_join("\n", fn {{_k, c}, i} -> "#{i}. #{c}" end)

    schema = %{
      "type" => "object",
      "required" => ["results"],
      "properties" => %{
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["passed"],
            "properties" => %{
              "passed" => %{"type" => "boolean"},
              "reasoning" => %{"type" => "string"}
            }
          }
        }
      }
    }

    prompt = """
    Evaluate whether the following criteria are met based on the conversation transcript below.
    Return one result object per criterion in the same order as listed.

    Transcript:
    #{if transcript == "", do: "(empty — no conversation occurred)", else: transcript}

    Criteria:
    #{criteria_list}
    """

    results = client |> LLM.generate!(prompt, schema) |> Jason.decode!() |> Map.fetch!("results")

    if length(results) != length(all) do
      raise "Evaluation returned #{length(results)} results for #{length(all)} criteria."
    end

    failures =
      all
      |> Enum.zip(results)
      |> Enum.flat_map(fn {{kind, criterion}, %{"passed" => passed} = r} ->
        reason = if r["reasoning"], do: " — #{r["reasoning"]}", else: ""

        cond do
          kind == :pass and not passed ->
            ["Pass criterion not met: #{inspect(criterion)}#{reason}"]

          kind == :fail and passed ->
            ["Fail criterion triggered: #{inspect(criterion)}#{reason}"]

          true ->
            []
        end
      end)

    if failures != [] do
      raise "Session evaluation failed:\n" <> Enum.map_join(failures, "\n", &"  • #{&1}")
    end

    :ok
  end

  # ---- GenServer ----

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    variables = opts[:variables] || %{}
    client = opts[:client] || Guava.Client.new!()

    url = HTTP.ws_url(client, "v1/test-agent")
    {:ok, conn} = raw_connect(url, HTTP.headers(client))

    session_id = await_session_started(conn)

    {:ok, runtime} =
      Guava.Call.Runtime.start_link(
        agent: agent,
        client: client,
        call_id: session_id,
        call_info: %Guava.CallInfo.PSTN{from_number: nil, to_number: "+15555555555"},
        initial_variables: variables,
        route: "v2/connect-call"
      )

    Process.send_after(self(), :idle_ping, @idle_ping_ms)
    {:ok, %State{conn: conn, client: client, session_id: session_id, runtime: runtime}}
  end

  # The test-agent socket is a raw WebSocket (no GuavaSocket framing); reuse the
  # relay used by Guava.Socket to forward frames to us.
  defp raw_connect(url, headers), do: Guava.Socket.Conn.start(url, self(), headers)

  defp await_session_started(_conn) do
    receive do
      {:conn_up, _pid} ->
        await_session_started(nil)

      {:ws_frame, text} ->
        case Protocol.decode_json(text) do
          %SessionStarted{session_id: id} -> id
          _ -> await_session_started(nil)
        end
    after
      15_000 -> raise "Timed out waiting for test session to start."
    end
  end

  @impl true
  def handle_call(:recv, _from, %State{queue: [head | rest]} = state) do
    {:reply, head, %{state | queue: rest}}
  end

  def handle_call(:recv, _from, %State{closed: true} = state), do: {:reply, :closed, state}
  def handle_call(:recv, from, state), do: {:noreply, %{state | waiting: from}}

  def handle_call(:get_transcript, _from, state) do
    transcript =
      state.events
      |> Enum.reverse()
      |> Enum.map_join("\n", fn
        %InjectASR{utterance: u} -> "[caller]: #{u}"
        %BotTTS{transcript: t} -> "[agent]: #{t}"
      end)

    {:reply, transcript, state}
  end

  def handle_call(:session_id, _from, state), do: {:reply, state.session_id, state}
  def handle_call(:client, _from, state), do: {:reply, state.client, state}

  @impl true
  def handle_cast({:say, utterance}, state) do
    msg = %InjectASR{utterance: utterance}
    send_frame(state, msg)
    {:noreply, %{state | events: [msg | state.events]}}
  end

  def handle_cast({:send, msg}, state) do
    send_frame(state, msg)
    {:noreply, state}
  end

  @impl true
  def handle_info({:conn_up, _pid}, state), do: {:noreply, state}

  def handle_info({:ws_frame, text}, state) do
    {:noreply, on_server_event(Protocol.decode(Jason.decode!(text)), state)}
  end

  def handle_info({:ws_down, _reason}, state) do
    state = %{state | closed: true}
    state = if state.waiting, do: reply_waiting(state, :closed), else: state
    {:noreply, state}
  end

  def handle_info(:idle_ping, state) do
    unless state.closed, do: send_frame(state, %Ping{})
    Process.send_after(self(), :idle_ping, @idle_ping_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.runtime && Process.alive?(state.runtime), do: GenServer.stop(state.runtime, :normal)
    :ok
  end

  # ---- helpers ----

  defp on_server_event(%Ping{}, state) do
    send_frame(state, %Pong{})
    state
  end

  defp on_server_event(%Pong{}, state), do: state

  defp on_server_event(%BotTTS{} = e, state) do
    deliver(%{state | events: [e | state.events]}, e)
  end

  defp on_server_event(%TurnStarted{} = e, state), do: deliver(state, e)

  # Deliver a "real" event to a waiting recv, or buffer it.
  defp deliver(%State{waiting: nil} = state, event), do: %{state | queue: state.queue ++ [event]}
  defp deliver(state, event), do: reply_waiting(state, event)

  defp reply_waiting(%State{waiting: from} = state, value) do
    GenServer.reply(from, value)
    %{state | waiting: nil}
  end

  defp send_frame(%State{conn: conn}, msg),
    do: Guava.Socket.Conn.send_text(conn, Protocol.encode!(msg))
end

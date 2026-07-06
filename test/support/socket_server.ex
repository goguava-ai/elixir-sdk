defmodule Guava.Test.SocketServer do
  @moduledoc false
  # A minimal server-side implementation of the GuavaSocket handshake, used to
  # integration-test Guava.Socket. Speaks: open -> open-ack, message -> ack
  # (+ echo when payload has an "echo" key), ping -> pong. Optionally forwards
  # everything it receives to a test inbox process registered in :persistent_term.
  @behaviour WebSock

  alias Guava.Socket.Protocol
  alias Guava.Socket.Protocol.{OpenAck, Ack, Pong, Message, Close}

  @impl true
  def init(_opts) do
    {:ok, %{server_seq: 0, mode: nil, inbox: :persistent_term.get(:guava_test_inbox, nil)}}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    frame = Protocol.decode!(text)
    forward(state, {:server_recv, frame})
    on_frame(frame, state)
  end

  def handle_in(_other, state), do: {:ok, state}

  # Allow the test to drive server-initiated frames via handle_info.
  @impl true
  def handle_info({:server_send, %_{} = frame}, state) do
    {:push, {:text, Protocol.encode!(frame)}, state}
  end

  def handle_info(:server_close, state) do
    {:push,
     {:text, Protocol.encode!(%Close{reason: "state-lost", description: "server closing"})},
     state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  defp on_frame(%Protocol.Open{is_reopen: r, name: name}, state) do
    ack = {:text, Protocol.encode!(%OpenAck{is_reopen: r, last_seen_sequence: 0})}
    forward(state, {:server_opened, self()})
    mode = if name == "listen-inbound", do: :listen, else: :default
    state = %{state | mode: mode}

    if mode == :listen do
      # Drive the inbound-listener handshake: announce, then offer a call.
      {frames, state} =
        state
        |> server_message(%{"message_type" => "listen-started", "other_listeners" => 0})
        |> then(fn {f1, s} ->
          {f2, s} = server_message(s, %{"message_type" => "incoming-call", "call_id" => "c1"})
          {[f1, f2], s}
        end)

      {:push, [ack | frames], state}
    else
      {:push, ack, state}
    end
  end

  # Inbound-listener control messages arrive as GuavaSocket message payloads.
  defp on_frame(
         %Message{
           sequence: seq,
           payload: %{"message_type" => "claim-call", "call_id" => call_id}
         },
         state
       ) do
    ack = {:text, Protocol.encode!(%Ack{last_seen_sequence: seq})}

    assign = %{
      "message_type" => "assign-call",
      "call_id" => call_id,
      "call_info" => %{
        "call_type" => "pstn",
        "from_number" => "+14155550100",
        "to_number" => "+14155550111",
        "caller_id" => nil
      }
    }

    {frame, state} = server_message(state, assign)
    {:push, [ack, frame], state}
  end

  defp on_frame(
         %Message{
           sequence: seq,
           payload: %{"message_type" => "answer-call", "call_id" => call_id}
         },
         state
       ) do
    forward(state, {:answered, call_id})
    {:push, {:text, Protocol.encode!(%Ack{last_seen_sequence: seq})}, state}
  end

  defp on_frame(%Message{sequence: seq, payload: payload}, state) do
    ack = {:text, Protocol.encode!(%Ack{last_seen_sequence: seq})}

    case payload do
      %{"echo" => echoed} ->
        {msg, state} = server_message(state, echoed)
        {:push, [ack, msg], state}

      _ ->
        {:push, ack, state}
    end
  end

  defp on_frame(%Protocol.Ping{ping_timestamp: ts}, state) do
    {:push, {:text, Protocol.encode!(%Pong{ping_timestamp: ts, pong_timestamp: 0})}, state}
  end

  defp on_frame(_other, state), do: {:ok, state}

  # Build a server-initiated GuavaSocket message frame with the next sequence.
  defp server_message(state, payload) do
    seq = state.server_seq + 1

    {{:text, Protocol.encode!(%Message{sequence: seq, payload: payload})},
     %{state | server_seq: seq}}
  end

  defp forward(%{inbox: nil}, _msg), do: :ok
  defp forward(%{inbox: pid}, msg), do: send(pid, msg)
end

defmodule Guava.Test.SocketPlug do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    WebSockAdapter.upgrade(conn, Guava.Test.SocketServer, [], timeout: 60_000)
  end
end

defmodule Guava.Test.Server do
  @moduledoc false
  # Starts a Bandit server on a free port for socket integration tests.

  @spec start() :: {:ok, pid(), non_neg_integer()}
  def start do
    port = free_port()
    {:ok, pid} = Bandit.start_link(plug: Guava.Test.SocketPlug, port: port, ip: :loopback)
    {:ok, pid, port}
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end

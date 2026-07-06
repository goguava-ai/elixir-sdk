defmodule Guava.Socket.Reliable do
  @moduledoc """
  Pure state machine for the GuavaSocket reliable-messaging layer.

  This models everything the Python `GuavaSocket` does at the frame level —
  sequence numbering, per-message acks, the retransmission buffer, inbound
  dedup, and the open/open-ack handshake — as pure transitions, so it can be
  tested exhaustively without any transport. The transport
  (`Guava.Socket`) owns timers, reconnection/backoff, and the actual WebSocket.

  Each transition returns `{state, actions}` where an action is one of:

    * `{:send, frame}` — send this frame struct to the peer
    * `{:deliver, payload}` — hand this decoded payload map to the owner
    * `:ready` — the socket completed its handshake and is open
    * `{:closed, reason, description}` — the peer closed the socket
  """
  require Logger

  alias Guava.Socket.Protocol.{Open, OpenAck, Close, Message, Ping, Pong, Ack}

  @type status :: :never_opened | :connecting | :open | :closed
  @type action ::
          {:send, struct()} | {:deliver, map()} | :ready | {:closed, String.t(), String.t()}

  defstruct name: nil,
            connection_id: nil,
            last_seen_sequence: 0,
            last_sent_sequence: 0,
            rtx_buffer: [],
            opened_once: false,
            status: :never_opened,
            close_reason: nil,
            close_description: nil

  @type t :: %__MODULE__{}

  @doc "Create a new reliable-protocol state."
  @spec new(String.t(), String.t()) :: t()
  def new(name, connection_id) do
    %__MODULE__{name: name, connection_id: connection_id}
  end

  @doc "Whether the socket is currently open."
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: :open}), do: true
  def open?(%__MODULE__{}), do: false

  @doc "Whether the socket is permanently closed."
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{status: :closed}), do: true
  def closed?(%__MODULE__{}), do: false

  @doc """
  Produce the `open` frame to send after a WebSocket connection is established.

  `is_reopen` is true on any connection after the first successful open,
  matching the Python behavior of retaining `open` state across reconnects.
  """
  @spec prepare_open(t()) :: {t(), Open.t()}
  def prepare_open(%__MODULE__{} = s) do
    frame = %Open{
      name: s.name,
      connection_id: s.connection_id,
      is_reopen: s.opened_once,
      last_seen_sequence: s.last_seen_sequence
    }

    {%{s | status: :connecting}, frame}
  end

  @doc """
  Handle the server's `open-ack`: retransmit buffered messages the peer hasn't
  seen, prune the retransmission buffer, and mark the socket open/ready.
  """
  @spec handle_open_ack(t(), OpenAck.t()) :: {t(), [action()]}
  def handle_open_ack(%__MODULE__{} = s, %OpenAck{last_seen_sequence: peer}) do
    retransmits =
      for {seq, payload} <- s.rtx_buffer, seq > peer do
        {:send, %Message{sequence: seq, payload: payload}}
      end

    s = %{s | rtx_buffer: prune(s.rtx_buffer, peer), status: :open, opened_once: true}
    {s, retransmits ++ [:ready]}
  end

  @doc """
  Handle an inbound frame (`now_ms` is used to stamp pong replies).

  Returns `{state, actions}`.
  """
  @spec handle_frame(t(), struct(), integer()) :: {t(), [action()]}
  def handle_frame(%__MODULE__{} = s, %Close{reason: reason, description: desc}, _now) do
    s = set_close_reason(s, reason, desc)
    {%{s | status: :closed}, [{:closed, s.close_reason, s.close_description}]}
  end

  def handle_frame(%__MODULE__{} = s, %Message{sequence: seq, payload: payload}, _now) do
    {s, deliver} =
      cond do
        seq <= s.last_seen_sequence ->
          Logger.warning("Got a message for a sequence already seen (#{seq}). Skipping.")
          {s, []}

        true ->
          if seq != s.last_seen_sequence + 1 do
            Logger.warning(
              "A sequence number has been skipped (got #{seq}, expected #{s.last_seen_sequence + 1})."
            )
          end

          {%{s | last_seen_sequence: seq}, [{:deliver, payload}]}
      end

    # An ack is always sent after a message frame, even duplicates.
    {s, deliver ++ [{:send, %Ack{last_seen_sequence: s.last_seen_sequence}}]}
  end

  def handle_frame(%__MODULE__{} = s, %Ping{ping_timestamp: ts}, now) do
    {s, [{:send, %Pong{ping_timestamp: ts, pong_timestamp: now}}]}
  end

  def handle_frame(%__MODULE__{} = s, %Pong{}, _now), do: {s, []}

  def handle_frame(%__MODULE__{} = s, %Ack{last_seen_sequence: peer}, _now) do
    {%{s | rtx_buffer: prune(s.rtx_buffer, peer)}, []}
  end

  def handle_frame(%__MODULE__{} = s, %OpenAck{} = ack, _now), do: handle_open_ack(s, ack)

  @doc """
  Enqueue an outbound payload: assign the next sequence, buffer it for
  retransmission, and produce the `message` frame to send.
  """
  @spec send_payload(t(), map()) :: {t(), Message.t()}
  def send_payload(%__MODULE__{} = s, payload) do
    seq = s.last_sent_sequence + 1
    frame = %Message{sequence: seq, payload: payload}
    {%{s | last_sent_sequence: seq, rtx_buffer: s.rtx_buffer ++ [{seq, payload}]}, frame}
  end

  @doc "Produce a `ping` frame (sent when the connection is idle)."
  @spec ping(t(), integer()) :: Ping.t()
  def ping(%__MODULE__{}, now), do: %Ping{ping_timestamp: now}

  @doc "Mark the socket closed by the client. The first close reason wins."
  @spec close(t(), String.t(), String.t()) :: t()
  def close(%__MODULE__{} = s, reason, description) do
    %{set_close_reason(s, reason, description) | status: :closed}
  end

  # first reason wins
  defp set_close_reason(%__MODULE__{close_reason: nil} = s, reason, description) do
    %{s | close_reason: reason, close_description: description}
  end

  defp set_close_reason(%__MODULE__{} = s, _reason, _description), do: s

  defp prune(rtx_buffer, peer_last_seen) do
    Enum.reject(rtx_buffer, fn {seq, _payload} -> seq <= peer_last_seen end)
  end
end

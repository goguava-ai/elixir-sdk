defmodule Guava.Socket.Protocol.Open do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "open",
            name: nil,
            connection_id: nil,
            is_reopen: false,
            last_seen_sequence: 0
end

defmodule Guava.Socket.Protocol.OpenAck do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "open-ack", is_reopen: false, last_seen_sequence: 0
end

defmodule Guava.Socket.Protocol.Close do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "close", reason: "unknown", description: ""
end

defmodule Guava.Socket.Protocol.Message do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "message", sequence: 0, payload: %{}
end

defmodule Guava.Socket.Protocol.Ping do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "ping", ping_timestamp: 0
end

defmodule Guava.Socket.Protocol.Pong do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "pong", ping_timestamp: 0, pong_timestamp: 0
end

defmodule Guava.Socket.Protocol.Ack do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "ack", last_seen_sequence: 0
end

defmodule Guava.Socket.Protocol do
  @moduledoc """
  The GuavaSocket framing protocol: a reliable-messaging layer carried as JSON
  text frames over a WebSocket. Mirrors `guava.socket.protocol`.
  """

  alias Guava.Socket.Protocol.{Open, OpenAck, Close, Message, Ping, Pong, Ack}

  @type frame :: Open.t() | OpenAck.t() | Close.t() | Message.t() | Ping.t() | Pong.t() | Ack.t()

  @valid_close_reasons ~w(authentication-failure state-lost done other server-error reconnection-failed unknown)

  @doc "Valid `close` reasons."
  @spec close_reasons() :: [String.t()]
  def close_reasons, do: @valid_close_reasons

  @doc "Encode a frame struct to a JSON string."
  @spec encode!(frame()) :: String.t()
  def encode!(frame), do: Jason.encode!(frame)

  @doc "Decode a JSON string into a frame struct. Raises on unknown types."
  @spec decode!(String.t() | binary()) :: frame()
  def decode!(json), do: json |> Jason.decode!() |> from_map()

  @doc "Build a frame struct from a decoded JSON map."
  @spec from_map(map()) :: frame()
  def from_map(%{"message_type" => "open"} = m) do
    %Open{
      name: m["name"],
      connection_id: m["connection_id"],
      is_reopen: m["is_reopen"],
      last_seen_sequence: m["last_seen_sequence"]
    }
  end

  def from_map(%{"message_type" => "open-ack"} = m) do
    %OpenAck{is_reopen: m["is_reopen"], last_seen_sequence: m["last_seen_sequence"]}
  end

  def from_map(%{"message_type" => "close"} = m) do
    %Close{reason: m["reason"], description: m["description"]}
  end

  def from_map(%{"message_type" => "message"} = m) do
    %Message{sequence: m["sequence"], payload: m["payload"]}
  end

  def from_map(%{"message_type" => "ping"} = m), do: %Ping{ping_timestamp: m["ping_timestamp"]}

  def from_map(%{"message_type" => "pong"} = m) do
    %Pong{ping_timestamp: m["ping_timestamp"], pong_timestamp: m["pong_timestamp"]}
  end

  def from_map(%{"message_type" => "ack"} = m),
    do: %Ack{last_seen_sequence: m["last_seen_sequence"]}

  def from_map(%{"message_type" => other}) do
    raise Guava.Error, message: "Unknown GuavaSocket frame type: #{inspect(other)}"
  end
end

defmodule Guava.Testing.Protocol.Ping do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "ping"
end

defmodule Guava.Testing.Protocol.Pong do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "pong"
end

defmodule Guava.Testing.Protocol.InjectASR do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "inject-asr", utterance: nil
end

defmodule Guava.Testing.Protocol.WaitForTurn do
  @moduledoc false
  @derive Jason.Encoder
  defstruct message_type: "wait-for-caller-turn", request_id: nil
end

defmodule Guava.Testing.Protocol.SessionStarted do
  @moduledoc false
  defstruct message_type: "session-started", session_id: nil
end

defmodule Guava.Testing.Protocol.BotTTS do
  @moduledoc false
  defstruct message_type: "bot-tts", transcript: nil
end

defmodule Guava.Testing.Protocol.TurnStarted do
  @moduledoc false
  defstruct message_type: "caller-turn-started", request_id: nil
end

defmodule Guava.Testing.Protocol do
  @moduledoc false
  # Wire protocol for the raw test-agent socket (v1/test-agent).

  alias Guava.Testing.Protocol.{Ping, Pong, SessionStarted, BotTTS, TurnStarted}

  def encode!(msg), do: Jason.encode!(msg)

  def decode(%{"message_type" => "ping"}), do: %Ping{}
  def decode(%{"message_type" => "pong"}), do: %Pong{}

  def decode(%{"message_type" => "session-started"} = m),
    do: %SessionStarted{session_id: m["session_id"]}

  def decode(%{"message_type" => "bot-tts"} = m), do: %BotTTS{transcript: m["transcript"]}

  def decode(%{"message_type" => "caller-turn-started"} = m),
    do: %TurnStarted{request_id: m["request_id"]}

  def decode_json(json), do: json |> Jason.decode!() |> decode()
end

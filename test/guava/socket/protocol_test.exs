defmodule Guava.Socket.ProtocolTest do
  use ExUnit.Case, async: true

  alias Guava.Socket.Protocol
  alias Guava.Socket.Protocol.{Open, OpenAck, Close, Message, Ping, Pong, Ack}

  @fixtures "test/fixtures/wire.json" |> File.read!() |> Jason.decode!()
  defp dump(key), do: @fixtures["frames"][key]["dump"]

  test "frames encode identically to pydantic" do
    frames = %{
      "open" => %Open{
        name: "call-1",
        connection_id: "deadbeef",
        is_reopen: false,
        last_seen_sequence: 0
      },
      "open_ack" => %OpenAck{is_reopen: true, last_seen_sequence: 5},
      "close" => %Close{reason: "done", description: "bye"},
      "message" => %Message{
        sequence: 4,
        payload: %{"command_type" => "read-script", "script" => "x"}
      },
      "ping" => %Ping{ping_timestamp: 1_717_171_717_000},
      "pong" => %Pong{ping_timestamp: 1_717_171_717_000, pong_timestamp: 1_717_171_717_050},
      "ack" => %Ack{last_seen_sequence: 9}
    }

    for {key, frame} <- frames do
      assert frame |> Protocol.encode!() |> Jason.decode!() == dump(key), "mismatch for #{key}"
    end
  end

  test "round-trips through decode!" do
    for key <- ["open", "open_ack", "close", "message", "ping", "pong", "ack"] do
      json = @fixtures["frames"][key]["json"]
      decoded = Protocol.decode!(json)
      assert decoded |> Protocol.encode!() |> Jason.decode!() == dump(key)
    end
  end

  test "decode! rejects unknown frame types" do
    assert_raise Guava.Error, ~r/Unknown GuavaSocket frame/, fn ->
      Protocol.decode!(~s({"message_type":"nope"}))
    end
  end
end

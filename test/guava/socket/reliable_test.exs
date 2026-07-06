defmodule Guava.Socket.ReliableTest do
  use ExUnit.Case, async: true

  alias Guava.Socket.Reliable
  alias Guava.Socket.Protocol.{Open, OpenAck, Close, Message, Ping, Pong, Ack}

  defp new, do: Reliable.new("call-1", "conn-abc")

  describe "open handshake" do
    test "first open is not a reopen" do
      {s, %Open{} = frame} = Reliable.prepare_open(new())
      assert frame.is_reopen == false
      assert frame.connection_id == "conn-abc"
      assert frame.last_seen_sequence == 0
      assert s.status == :connecting
    end

    test "open-ack marks the socket ready" do
      {s, _} = Reliable.prepare_open(new())
      {s, actions} = Reliable.handle_open_ack(s, %OpenAck{last_seen_sequence: 0})
      assert actions == [:ready]
      assert Reliable.open?(s)
      assert s.opened_once
    end

    test "second connection is a reopen and retransmits unacked messages" do
      s = new()
      {s, _} = Reliable.prepare_open(s)
      {s, _} = Reliable.handle_open_ack(s, %OpenAck{last_seen_sequence: 0})

      # Send two messages.
      {s, %Message{sequence: 1}} = Reliable.send_payload(s, %{"n" => 1})
      {s, %Message{sequence: 2}} = Reliable.send_payload(s, %{"n" => 2})

      # Reconnect: prepare_open now signals reopen.
      {s, open} = Reliable.prepare_open(s)
      assert open.is_reopen == true

      # Server acked up through 1; only message 2 should be retransmitted.
      {s, actions} = Reliable.handle_open_ack(s, %OpenAck{last_seen_sequence: 1})
      assert [{:send, %Message{sequence: 2, payload: %{"n" => 2}}}, :ready] = actions
      assert s.rtx_buffer == [{2, %{"n" => 2}}]
    end
  end

  describe "outbound messages" do
    test "assign increasing sequence numbers and buffer for retransmit" do
      s = new()
      {s, f1} = Reliable.send_payload(s, %{"a" => 1})
      {s, f2} = Reliable.send_payload(s, %{"b" => 2})
      assert f1.sequence == 1
      assert f2.sequence == 2
      assert s.rtx_buffer == [{1, %{"a" => 1}}, {2, %{"b" => 2}}]
    end

    test "ack prunes the retransmission buffer" do
      s = new()
      {s, _} = Reliable.send_payload(s, %{"a" => 1})
      {s, _} = Reliable.send_payload(s, %{"b" => 2})
      {s, _} = Reliable.send_payload(s, %{"c" => 3})
      {s, actions} = Reliable.handle_frame(s, %Ack{last_seen_sequence: 2}, 0)
      assert actions == []
      assert s.rtx_buffer == [{3, %{"c" => 3}}]
    end
  end

  describe "inbound messages" do
    test "new message delivers payload then acks" do
      s = new()
      {s, actions} = Reliable.handle_frame(s, %Message{sequence: 1, payload: %{"x" => 1}}, 0)
      assert actions == [{:deliver, %{"x" => 1}}, {:send, %Ack{last_seen_sequence: 1}}]
      assert s.last_seen_sequence == 1
    end

    test "duplicate message is not delivered but is still acked" do
      s = new()
      {s, _} = Reliable.handle_frame(s, %Message{sequence: 1, payload: %{"x" => 1}}, 0)
      {s, actions} = Reliable.handle_frame(s, %Message{sequence: 1, payload: %{"x" => 1}}, 0)
      assert actions == [{:send, %Ack{last_seen_sequence: 1}}]
      assert s.last_seen_sequence == 1
    end

    test "sequential messages advance last_seen" do
      s = new()
      {s, _} = Reliable.handle_frame(s, %Message{sequence: 1, payload: %{}}, 0)
      {s, _} = Reliable.handle_frame(s, %Message{sequence: 2, payload: %{}}, 0)
      assert s.last_seen_sequence == 2
    end
  end

  describe "keepalive and close" do
    test "ping is answered with a pong carrying both timestamps" do
      s = new()
      {_s, actions} = Reliable.handle_frame(s, %Ping{ping_timestamp: 111}, 222)
      assert actions == [{:send, %Pong{ping_timestamp: 111, pong_timestamp: 222}}]
    end

    test "pong is ignored" do
      s = new()
      assert {^s, []} = Reliable.handle_frame(s, %Pong{ping_timestamp: 1, pong_timestamp: 2}, 0)
    end

    test "ping/2 builds a ping frame" do
      assert %Ping{ping_timestamp: 999} = Reliable.ping(new(), 999)
    end

    test "server close transitions to closed" do
      s = new()

      {s, actions} =
        Reliable.handle_frame(s, %Close{reason: "state-lost", description: "gone"}, 0)

      assert actions == [{:closed, "state-lost", "gone"}]
      assert Reliable.closed?(s)
    end

    test "client close marks closed; first reason wins" do
      s = new() |> Reliable.close("done", "bye")
      assert Reliable.closed?(s)
      assert s.close_reason == "done"
      s2 = Reliable.close(s, "other", "later")
      assert s2.close_reason == "done"
    end
  end
end

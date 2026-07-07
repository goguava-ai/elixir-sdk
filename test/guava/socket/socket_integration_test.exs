defmodule Guava.SocketIntegrationTest do
  @moduledoc "End-to-end transport tests against a local GuavaSocket server."
  use ExUnit.Case, async: false

  alias Guava.Socket

  setup do
    :persistent_term.put(:guava_test_inbox, self())
    {:ok, server, port} = Guava.Test.Server.start()
    on_exit(fn -> :persistent_term.erase(:guava_test_inbox) end)
    {:ok, server: server, port: port, url: "ws://127.0.0.1:#{port}/socket"}
  end

  defp start_socket(url) do
    {:ok, pid} = Socket.start_link(url: url, name: "test", owner: self())
    pid
  end

  test "completes the handshake and reports ready", %{url: url} do
    _pid = start_socket(url)
    assert_receive {:guava_socket, _pid, :ready}, 2_000
    assert_receive {:server_recv, %Guava.Socket.Protocol.Open{is_reopen: false}}, 2_000
  end

  test "sends a payload; server acks and echoes back", %{url: url} do
    pid = start_socket(url)
    assert_receive {:guava_socket, _pid, :ready}, 2_000

    Socket.send_payload(pid, %{"hello" => "world", "echo" => %{"pong" => 1}})

    # Server received our message frame.
    assert_receive {:server_recv, %Guava.Socket.Protocol.Message{payload: %{"hello" => "world"}}},
                   2_000

    # Server echoed a message back; the socket delivers its payload to us.
    assert_receive {:guava_socket, _pid, {:payload, %{"pong" => 1}}}, 2_000
  end

  test "delivers a server-initiated message and acks it", %{url: url} do
    pid = start_socket(url)
    assert_receive {:guava_socket, _pid, :ready}, 2_000
    assert_receive {:server_opened, server_conn}, 2_000

    send(
      server_conn,
      {:server_send, %Guava.Socket.Protocol.Message{sequence: 1, payload: %{"from" => "server"}}}
    )

    assert_receive {:guava_socket, ^pid, {:payload, %{"from" => "server"}}}, 2_000
    # The socket acks the delivered message.
    assert_receive {:server_recv, %Guava.Socket.Protocol.Ack{last_seen_sequence: 1}}, 2_000
  end

  test "propagates a server close", %{url: url} do
    pid = start_socket(url)
    assert_receive {:guava_socket, _pid, :ready}, 2_000
    assert_receive {:server_opened, server_conn}, 2_000

    send(server_conn, :server_close)
    assert_receive {:guava_socket, ^pid, {:closed, "state-lost", "server closing"}}, 2_000
  end

  test "reconnects after a transport drop and retransmits unacked messages", %{url: url} do
    # "test-noack": the server withholds acks, so a sent message stays in the
    # client's retransmit buffer and is unacked when the connection drops.
    {:ok, pid} = Socket.start_link(url: url, name: "test-noack", owner: self())

    assert_receive {:guava_socket, ^pid, :ready}, 2_000
    assert_receive {:server_recv, %Guava.Socket.Protocol.Open{is_reopen: false}}, 2_000
    assert_receive {:server_opened, server_conn}, 2_000

    # Send a payload; the server records it but does not ack it.
    Socket.send_payload(pid, %{"n" => 1})

    assert_receive {:server_recv, %Guava.Socket.Protocol.Message{sequence: 1, payload: %{"n" => 1}}},
                   2_000

    # Force a transport-level drop (no Guava Close frame).
    send(server_conn, :server_drop)

    # The socket reconnects, redoes the handshake as a reopen, retransmits the
    # still-unacked message (same sequence), and reports ready again.
    assert_receive {:server_recv, %Guava.Socket.Protocol.Open{is_reopen: true}}, 5_000

    assert_receive {:server_recv, %Guava.Socket.Protocol.Message{sequence: 1, payload: %{"n" => 1}}},
                   5_000

    assert_receive {:guava_socket, ^pid, :ready}, 5_000
  end

  test "client close notifies owner and stops the process", %{url: url} do
    pid = start_socket(url)
    assert_receive {:guava_socket, _pid, :ready}, 2_000
    ref = Process.monitor(pid)

    Socket.close(pid)
    assert_receive {:guava_socket, ^pid, {:closed, "done", _}}, 2_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end
end

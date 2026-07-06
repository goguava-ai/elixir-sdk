defmodule Guava.InboundIntegrationTest do
  @moduledoc "Drives the full inbound-listener flow against a local server."
  use ExUnit.Case, async: false

  alias Guava.{Client, Channel}
  alias Guava.Socket.Protocol.Message

  defmodule TestAgent do
    use Guava.Agent, name: "Nova", organization: "Acme", purpose: "help"
  end

  setup do
    :persistent_term.put(:guava_test_inbox, self())
    {:ok, _server, port} = Guava.Test.Server.start()
    on_exit(fn -> :persistent_term.erase(:guava_test_inbox) end)
    {:ok, base: "http://127.0.0.1:#{port}/"}
  end

  test "listens, claims, answers, and attaches a runtime that sends the persona", %{base: base} do
    client = Client.new!(api_key: "x", base_url: base)

    {:ok, worker} =
      Channel.Worker.start_link(
        agent: TestAgent,
        client: client,
        mode: {:listen, [phone_number: "+14155550100"]}
      )

    assert_receive {:answered, "c1"}, 3_000

    assert_receive {:server_recv,
                    %Message{payload: %{"command_type" => "set-persona", "agent_name" => "Nova"}}},
                   3_000

    assert_receive {:server_recv, %Message{payload: %{"command_type" => "registered-hooks"}}},
                   3_000

    Process.exit(worker, :kill)
  end
end

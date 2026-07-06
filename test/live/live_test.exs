defmodule Guava.LiveTest do
  @moduledoc """
  Live, read-only smoke tests against the real Guava API.

  Excluded by default. Run with:

      GUAVA_API_KEY=gva-... mix test --include live

  These only perform safe, read-only or free operations. Sending real SMS or
  placing real calls is intentionally left out (add opt-in tests once the
  customer confirms a safe from/to number).
  """
  use ExUnit.Case, async: false
  @moduletag :live

  alias Guava.Client

  defmodule RoleplayAgent do
    use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Greet the caller."

    @impl true
    def handle_start(call, state) do
      Guava.Call.set_task(call, "greet",
        objective: "Greet the caller warmly and ask how you can help."
      )

      {:noreply, state}
    end
  end

  setup do
    key = System.get_env("GUAVA_API_KEY") || flunk("Set GUAVA_API_KEY to run live tests.")
    {:ok, client: Client.new!(api_key: key)}
  end

  test "check_sdk_deprecation returns a status", %{client: client} do
    assert is_binary(Client.check_sdk_deprecation!(client))
  end

  test "list_numbers returns account phone numbers", %{client: client} do
    numbers = Client.list_numbers!(client)
    assert is_list(numbers)
    assert Enum.all?(numbers, &match?(%Guava.PhoneNumberInfo{}, &1))
  end

  test "create_webrtc_agent returns a code", %{client: client} do
    assert is_binary(Client.create_webrtc_agent!(client, 300))
  end

  test "create_sip_agent returns a code", %{client: client} do
    assert is_binary(Client.create_sip_agent!(client))
  end

  test "GUAVA_AGENT_NUMBER (if set) is one of the account's numbers", %{client: client} do
    case System.get_env("GUAVA_AGENT_NUMBER") do
      nil ->
        :ok

      number ->
        numbers = client |> Client.list_numbers!() |> Enum.map(& &1.phone_number)

        assert number in numbers,
               "GUAVA_AGENT_NUMBER #{number} not found in account numbers: #{inspect(numbers)}"
    end
  end

  @tag :live_agent
  test "test-agent roleplay runs end to end", %{client: client} do
    session =
      Guava.Testing.roleplay(
        RoleplayAgent,
        "You are a friendly caller who says hello and then hangs up.",
        client: client
      )

    transcript = Guava.Testing.Session.get_transcript(session)
    assert is_binary(transcript)
    Guava.Testing.Session.stop(session)
  end
end

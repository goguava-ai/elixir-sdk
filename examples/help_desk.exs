# Help-desk agent example (port of examples/help_desk.py).
#
# Run against a phone number:
#   GUAVA_API_KEY=gva-... elixir examples/help_desk.exs +14155550123
#
# Or test it locally with an LLM-roleplayed caller (no phone needed):
#   GUAVA_API_KEY=gva-... elixir examples/help_desk.exs --roleplay

Mix.install([{:guava, "~> 0.35"}])

alias Guava.{Agent, Call, Client, IntentRecognizer}

client = Client.new()

intent =
  IntentRecognizer.new(client, %{
    "sales" => "New purchases, product availability, pricing, promotions, order status and changes",
    "delivery-and-returns" => "Delivery scheduling, installation, damaged items, returns, exchanges, refunds, warranty",
    "account-management" => "Charges, invoices, payment plans, billing disputes, rewards, business orders",
    "other" => "Anything else not listed under another category."
  })

transfer_to = fn call, dept ->
  Call.transfer(call, "+15555555555", "Notify the caller you're transferring them to #{dept}.")
end

agent =
  Agent.new(
    name: "Nova",
    organization: "Clearfield Home & Living",
    purpose: "Answer questions and route callers to the appropriate department.",
    client: client
  )
  |> Agent.on_question(fn _call, question ->
    # Swap in a Guava.DocumentQA here for real retrieval.
    "I'm not sure about that, let me connect you with someone who can help: #{question}"
  end)
  |> Agent.on_action_request(fn _call, request -> IntentRecognizer.classify(intent, request) end)
  |> Agent.on_action("sales", &transfer_to.(&1, "Sales"))
  |> Agent.on_action("delivery-and-returns", &transfer_to.(&1, "Delivery and Returns"))
  |> Agent.on_action("account-management", &transfer_to.(&1, "Account Management"))
  |> Agent.on_action("other", &transfer_to.(&1, "a service representative"))

case System.argv() do
  ["--roleplay"] ->
    session = Agent.test_roleplay(agent, "You are a caller asking about a damaged couch delivery.")
    IO.puts(Guava.Testing.Session.get_transcript(session))
    Guava.Testing.Session.stop(session)

  [number] ->
    Agent.listen_phone(agent, number)

  _ ->
    IO.puts("Usage: help_desk.exs <phone_number> | --roleplay")
end

# Testing

Exercise an agent module end-to-end without a phone, against Guava's
`v1/test-agent` endpoint. Two entry points on `Guava.Testing`.

## Scripted: `session/3`

Runs the agent and hands your function a `Guava.Testing.Session`, stopping it
when the function returns.

```elixir
Guava.Testing.session(MyAgent, fn session ->
  alias Guava.Testing.Session

  Session.say(session, "Hi, what are your hours?")
  Session.wait_for_turn(session)
  IO.puts(Session.get_transcript(session))

  Session.evaluate(session,
    ["The agent stated its business hours."],   # pass criteria
    ["The agent transferred the call."]         # fail criteria
  )
end)
```

`Guava.Testing.Session` functions: `say/2`, `wait_for_turn/1`, `recv/2`,
`get_transcript/1`, `evaluate/3`, `stop/1`. Seed variables with
`Guava.Testing.session(MyAgent, fun, variables: %{"tier" => "gold"})`.

## Automated: `roleplay/3`

An LLM plays the caller against your agent. Returns the (still-running) session
so you can evaluate then stop it.

```elixir
session = Guava.Testing.roleplay(MyAgent, "You are a frustrated customer trying to cancel.")
Guava.Testing.Session.evaluate(session, ["The agent attempted to retain the customer."], [])
Guava.Testing.Session.stop(session)
```

## In ExUnit

```elixir
test "answers an hours question" do
  Guava.Testing.session(MyAgent, fn session ->
    Guava.Testing.Session.say(session, "What time do you open?")
    Guava.Testing.Session.wait_for_turn(session)
    Guava.Testing.Session.evaluate(session, ["The agent gave opening hours."], [])
  end)
end
```

These hit the live API, so gate them behind a tag and provide `GUAVA_API_KEY`.
This repo excludes `@tag :live` by default; run with `mix test --include live`.

### Unit-testing your callbacks without the network

Because callbacks are plain functions on a module, most logic is testable
directly. For a full call loop with recorded commands, drive
`Guava.Call.Runtime` with an injected `:emit` function (see the SDK's own
`test/guava/agent_test.exs`).

Next: [Deployment](deployment.md).

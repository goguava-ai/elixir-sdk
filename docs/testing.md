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

Callbacks are plain functions on your module, so you can call them directly and
assert on what they do — no phone, no LLM, no live session. `Guava.Testing.MockCall`
gives you a `Guava.Call` handle that records the commands a handler emits and
serves field/variable reads from an in-memory store.

```elixir
test "assigns the intake task on call start" do
  mock = Guava.Testing.MockCall.new()

  {:noreply, _state} = MyAgent.handle_call_started(mock.call, MyAgent.initial_state())

  assert [%Guava.Commands.SetTask{task_id: "intake"}] =
           Guava.Testing.MockCall.commands(mock)
end
```

Pre-seed fields and variables a handler reads back, then assert on its result:

```elixir
test "rejects an invalid email" do
  mock = Guava.Testing.MockCall.new(fields: %{"email" => "nope"})

  assert {:reply, {:error, _reason}, _state} =
           MyAgent.handle_validate("email", mock.call, "nope", MyAgent.initial_state())
end
```

`MockCall` functions: `new/1` (`:id`, `:call_info`, `:fields`, `:variables`),
`set_field/3`, `put_variable/3`, `commands/1` (structs), `command_maps/1` (wire
maps), and `clear/1` (drop recorded commands between simulated turns). Pass a
`%Guava.CallInfo.WebRTC{}` as `:call_info` to exercise WebRTC-only guards.

A mock exercises a handler in isolation; it does not run the call runtime, so
runtime orchestration (e.g. validators firing automatically when a task
completes) belongs in a live `session/3` test. For a full call loop with
recorded commands, drive the internal Guava.Call.Runtime with an injected
`:emit` function (see the SDK's own `test/guava/agent_test.exs`).

Next: [Deployment](deployment.md).

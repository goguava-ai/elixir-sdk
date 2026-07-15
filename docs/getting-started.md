# Getting started

## Install

```elixir
# mix.exs
def deps do
  [{:guava, "~> 0.34"}]
end
```

Then `mix deps.get`. Requires Elixir ~> 1.15 and Erlang/OTP 26+. The SDK starts
its own supervision tree as an OTP application — you don't start anything yourself.

## Authenticate

Credentials resolve in this order:

1. `config :guava, api_key: "gva-..."`
2. an explicit `:api_key` passed to `Guava.Client.new/1`
3. a Guava-deploy token file at `/var/run/secrets/guava/token`
4. the `GUAVA_API_KEY` environment variable
5. a logged-in Guava CLI session

```elixir
{:ok, client} = Guava.Client.new(api_key: "gva-...")
client = Guava.Client.new!()   # from config/env; raises on failure
```

Set the base URL with `config :guava, base_url: ...` or `GUAVA_BASE_URL`.

Agents build their own client for the realtime socket, so for agent code you
usually don't touch `Guava.Client` directly.

## Your first agent

```elixir
defmodule MyAgent do
  use Guava.Agent, name: "Nova", organization: "Clearfield Home",
    purpose: "Answer questions and route callers to the right department."

  @impl true
  def handle_start(call, state) do
    Guava.Call.set_task(call, "greeting", objective: "Greet the caller and ask how you can help.")
    {:noreply, state}
  end

  @impl true
  def handle_question(_call, question, state) do
    {:reply, "Thanks for asking — let me help with: #{question}", state}
  end
end
```

Attach it to a phone number:

```elixir
# in a supervision tree
{Guava.Channel, agent: MyAgent, listen: {:phone, "+14155550123"}}

# or blocking, for a script
Guava.listen_phone(MyAgent, "+14155550123")
```

## Try it without a phone

```elixir
Guava.Testing.session(MyAgent, fn session ->
  Guava.Testing.Session.say(session, "Hi, do you sell dining tables?")
  Guava.Testing.Session.wait_for_turn(session)
  IO.puts(Guava.Testing.Session.get_transcript(session))
end)
```

See [Testing](testing.md) for LLM-roleplayed callers and pass/fail evaluation.

Next: [Agents](agents.md).

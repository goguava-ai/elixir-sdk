# Guava (Elixir)

[![Hex.pm](https://img.shields.io/hexpm/v/guava.svg)](https://hex.pm/packages/guava)
[![Hexdocs](https://img.shields.io/badge/hex-docs-8e7ce6.svg)](https://hexdocs.pm/guava)
[![Guava Python SDK](https://img.shields.io/badge/Guava%20Python%20SDK-v0.35.0-6C4AB6)](PARITY.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/goguava-ai/elixir-sdk/blob/main/LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-~%3E%201.15-663399)](https://github.com/goguava-ai/elixir-sdk/blob/main/.tool-versions)

The Elixir SDK for the [Guava](https://goguava.ai) voice-agent platform.

**Tracks the [Guava Python SDK](https://github.com/goguava-ai/python-sdk)
`v0.35.0`.** The Elixir package version mirrors the Python version it tracks, so
`~> 0.35` here corresponds to Python `0.35.x`.

> Community-maintained and actively developed. Support is best-effort — issues
> and pull requests are welcome. The public API is adapted to idiomatic Elixir;
> see [`PARITY.md`](PARITY.md) for how it maps to the Python SDK.

## Installation

```elixir
def deps do
  [{:guava, "~> 0.35"}]
end
```

Requires Elixir ~> 1.15 and Erlang/OTP 26+.

## Documentation

Full guides live in [`docs/`](docs/README.md):

- [Architecture](docs/architecture.md)
- [Getting started](docs/getting-started.md)
- [Agents](docs/agents.md)
- [Calls](docs/calls.md)
- [Tasks & Fields](docs/tasks-and-fields.md)
- [Handlers](docs/handlers.md)
- [Channels](docs/channels.md)
- [Campaigns](docs/campaigns.md)
- [Messaging](docs/messaging.md)
- [Client](docs/client.md)
- [RAG & LLM](docs/rag-and-llm.md)
- [Testing](docs/testing.md)
- [Deployment](docs/deployment.md)

## Authentication

Credentials resolve from `config :guava, api_key: ...`, then a deploy token file,
then `GUAVA_API_KEY`, then a logged-in CLI session:

```elixir
{:ok, client} = Guava.Client.new(api_key: "gva-...")
client = Guava.Client.new!()   # raises on failure
```

## Building an agent

An agent is a module that `use`s `Guava.Agent` — like a `GenServer`/`LiveView`.
Each call gets its own process; your callbacks thread a per-call **state** and
use the `Guava.Call` handle to drive the conversation. Implement only what you need.

```elixir
defmodule MyAgent do
  use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Answer questions and route callers."

  @impl true
  def init(_call_info), do: {:ok, %{}}

  @impl true
  def handle_start(call, state) do
    Guava.Call.set_task(call, "greet", objective: "Greet the caller and ask how you can help.")
    {:noreply, state}
  end

  @impl true
  def handle_question(_call, question, state), do: {:reply, MyKB.answer(question), state}

  @impl true
  def handle_action("sales", call, state) do
    Guava.Call.transfer(call, "+14155550100", "Transferring you to sales.")
    {:noreply, state}
  end
end
```

Attach it to a channel. In your supervision tree:

```elixir
children = [
  {Guava.Channel, agent: MyAgent, listen: {:phone, "+14155550123"}}
]
```

Or, for scripts, use the blocking helpers:

```elixir
Guava.listen_phone(MyAgent, "+14155550123")
Guava.call_phone(MyAgent, "+14155550100", "+16285550123", %{"customer" => "Ada"})
Guava.run({Guava.Channel, agent: MyAgent, campaign: "camp_abc"})
```

A persona-only agent (no callbacks) is valid:

```elixir
defmodule Greeter do
  use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Greet callers warmly."
end
```

## Client operations

Each returns `{:ok, result} | {:error, %Guava.Error{}}`, with a `!` variant that raises:

```elixir
{:ok, numbers} = Guava.Client.list_numbers(client)
:ok = Guava.Client.send_sms!(client, "+1415…", "+1628…", "Hello!")
```

## Testing an agent (no phone)

```elixir
Guava.Testing.session(MyAgent, fn session ->
  Guava.Testing.Session.say(session, "Hi, what are your hours?")
  Guava.Testing.Session.wait_for_turn(session)
  Guava.Testing.Session.evaluate(session, ["The agent stated its hours."], [])
end)
```

## Development

Develop locally with the standard Elixir toolchain — no Docker required. The
repo pins Erlang + Elixir in [`.tool-versions`](https://github.com/goguava-ai/elixir-sdk/blob/main/.tool-versions), so a version
manager ([`mise`](https://mise.jdx.dev) or [`asdf`](https://asdf-vm.com)) sets
you up with the exact toolchain:

```bash
mise install        # or: asdf install  — reads .tool-versions
mix deps.get
mix test                 # unit + local integration
mix test --include live  # also live tests (requires GUAVA_API_KEY)
mix credo --strict
```

> **No sudo?** `mise`/`asdf` compile Erlang from source (needs `build-essential`,
> `libssl-dev`, `libncurses-dev`, `autoconf`). If you can't install those, drop a
> precompiled Erlang + Elixir into `~/.local` with no compilation and no sudo —
> see [`docs/local-development.md`](docs/local-development.md).

### Docker (optional fallback)

A pinned container is available via the `./emix` wrapper (see `Dockerfile.dev`)
if you'd rather not install the toolchain. `_build`/`deps` live in named volumes,
so it won't touch your native build:

```bash
./emix deps.get
./emix test
./emix credo --strict
```

See [`PARITY.md`](PARITY.md) for parity status and intentional deviations.

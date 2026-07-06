# Guava Elixir SDK — Documentation

Unofficial Elixir port of the [Guava](https://goguava.ai) voice-agent SDK.
These guides mirror the [official Guava docs](https://goguava.ai/docs), adapted
to Elixir idioms. For per-function API reference, see the moduledocs (rendered
on HexDocs once published, or via `mix docs`).

## Guides

1. [Architecture](architecture.md) — how a Guava call works: the hosted Dialog System and your Expert.
2. [Getting started](getting-started.md) — install, authenticate, and run your first agent.
3. [Agents](agents.md) — building an `Guava.Agent`, registering handlers, attaching channels.
4. [Calls](calls.md) — the `Guava.Call` handle: steering a live call.
5. [Tasks & Fields](tasks-and-fields.md) — objectives, checklists, and structured data collection.
6. [Handlers](handlers.md) — reference for every `on_*` callback.
7. [Channels](channels.md) — inbound (phone/WebRTC/SIP), outbound, and running multiple agents.
8. [Campaigns](campaigns.md) — bulk outbound calling and contact management.
9. [Messaging](messaging.md) — sending and receiving SMS.
10. [Client](client.md) — account-level operations.
11. [RAG & LLM helpers](rag-and-llm.md) — `DocumentQA`, `IntentRecognizer`, and friends.
12. [Testing](testing.md) — driving agents in tests without a phone.
13. [Deployment](deployment.md) — supervision, releases, and production notes.

See also [`../PARITY.md`](../PARITY.md) for how this port maps to the Python
SDK and its intentional deviations.

## The 30-second version

```elixir
defmodule MyAgent do
  use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Answer questions."

  @impl true
  def handle_start(call, state) do
    Guava.Call.set_task(call, "greet", objective: "Greet the caller and ask how you can help.")
    {:noreply, state}
  end

  @impl true
  def handle_question(_call, question, state), do: {:reply, MyKB.answer(question), state}
end

Guava.listen_phone(MyAgent, "+14155550123")
```

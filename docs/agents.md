# Agents

A `Guava.Agent` is a **behaviour** you `use` — think `GenServer`/`Phoenix.LiveView`
for phone calls. Give it a persona, implement only the callbacks you need, and
each call runs in its own process threading a per-call **state** value.

## Creating an agent

```elixir
defmodule MyAgent do
  use Guava.Agent,
    name: "Nova",                       # what the agent calls itself
    organization: "Clearfield Home",    # who it represents
    purpose: "Answer questions and route callers.",
    voice: "alloy",                     # optional
    accept_dtmf: true                   # optional; let callers enter numbers via keypad (default true)
end
```

A persona-only agent (no callbacks) is valid and will greet + answer with
sensible defaults. Add callbacks to take over behavior.

## State

`init/1` builds the per-call state (any term — usually a map or struct); every
callback receives it and returns an updated one. This replaces the "mutable call
object" pattern — your data lives in `state`, not hung off the call.

```elixir
@impl true
def init(_call_info), do: {:ok, %{verified?: false, patient: nil}}
```

## Return contract

Callbacks return standard tuples (like LiveView):

  * side-effecting callbacks → `{:noreply, state}`
  * reply callbacks (`handle_question`, `handle_action_request`,
    `handle_search_query`) → `{:reply, value, state}`
  * `init/1` → `{:ok, state}`; `handle_call_received/1` → `:accept` | `:decline`

Use the `Guava.Call` handle passed to each callback to drive the call
(`set_task`, `transfer`, `get_field`, …) — see [Calls](calls.md). `Call.*`
actions are side effects; `state` is your own data.

```elixir
defmodule MyAgent do
  use Guava.Agent, name: "Nova", organization: "Acme", purpose: "Answer questions."

  @impl true
  def handle_start(call, state) do
    Guava.Call.set_task(call, "greet", objective: "Greet the caller.")
    {:noreply, state}
  end

  @impl true
  def handle_question(_call, question, state), do: {:reply, answer(question), state}

  @impl true
  def handle_action("sales", call, state) do
    Guava.Call.transfer(call, "+14155550100")
    {:noreply, state}
  end
end
```

Per-key handlers are a **single callback you pattern-match**:
`handle_action(action_key, call, state)` and
`handle_task_complete(task_id, call, state)`.

## Error handling

If a callback raises, the SDK logs it, keeps the previous `state`, and — where a
reply is expected — sends a safe fallback (a default answer, or an "expert
error" notice) so the call continues. A raise never drops a live call.

## Long / blocking work

Callbacks for one call run **serially** (so state can't race). For slow work
(a long RAG lookup, an external API), spawn a `Task` and send the result back to
the call process; handle it in `handle_info/3`:

```elixir
@impl true
def handle_caller_speech(call, _event, state) do
  parent = self()
  Task.start(fn -> send(parent, {:enriched, SlowAPI.lookup()}) end)
  {:noreply, state}
end

@impl true
def handle_info({:enriched, data}, call, state) do
  Guava.Call.add_info(call, "context", data)
  {:noreply, state}
end
```

## Attaching to a channel

An agent module does nothing until attached — see [Channels](channels.md):

```elixir
# supervised
{Guava.Channel, agent: MyAgent, listen: {:phone, "+14155550123"}}
# or blocking (scripts)
Guava.listen_phone(MyAgent, "+14155550123")
```

Next: [Calls](calls.md) · [Handlers](handlers.md).

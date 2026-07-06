# Channels

A channel connects an agent module to callers. `Guava.Channel` is a supervised
process you add to your own supervision tree; the blocking `Guava.*` helpers are
for scripts.

## Supervised (production)

```elixir
children = [
  {Guava.Channel, agent: SalesAgent, listen: {:phone, "+14155550100"}},
  {Guava.Channel, agent: SurveyAgent, campaign: "camp_abc"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Options:

  * `:agent` — the agent module (required)
  * one of `listen: {:phone, num} | {:webrtc, code | nil} | {:sip, code}`,
    `campaign: code`, or `outbound: {from, to, variables}`
  * `:client` — a `Guava.Client` (defaults to `Guava.Client.new!/0`)

The channel owns the listen/campaign socket and starts a supervised process per
live call. The listener restarts on crash; the WebSocket layer reconnects on its
own. This replaces hand-rolled listen/reconnect loops.

## Blocking helpers (scripts)

Each blocks the caller:

```elixir
Guava.listen_phone(MyAgent, "+14155550123")
Guava.listen_webrtc(MyAgent)                 # creates a temporary code
Guava.listen_sip(MyAgent, "guavasip-...")
Guava.attach_campaign(MyAgent, "camp_abc")
Guava.call_phone(MyAgent, from, to, %{"customer" => "Ada"})  # returns when the call ends
```

`Guava.run/1` starts one or more channel child specs under a supervisor and
blocks — handy for a `mix run` entrypoint:

```elixir
Guava.run([
  {Guava.Channel, agent: SalesAgent, listen: {:phone, "+14155550100"}},
  {Guava.Channel, agent: SurveyAgent, campaign: "camp_abc"}
])
```

## Inbound example: Q&A with RAG

```elixir
defmodule Nova do
  use Guava.Agent, name: "Nova", organization: "Clearfield Home"

  @impl true
  def handle_question(_call, question, state) do
    {:ok, qa} = {:ok, Process.get(:qa)}   # or hold it in state via init/1
    {:reply, Guava.DocumentQA.ask!(qa, question), state}
  end
end

Guava.listen_phone(Nova, "+14155550123")
```

## Outbound example: scheduling

```elixir
defmodule Scheduler do
  use Guava.Agent, name: "Nova", organization: "Acme"

  @impl true
  def handle_start(call, state) do
    Guava.Call.reach_person(call, Guava.Call.get_variable(call, "customer_name", "there"))
    {:noreply, state}
  end

  @impl true
  def handle_task_complete("reach_person", call, state) do
    if Guava.Call.get_field(call, "contact_availability") == "available" do
      Guava.Call.set_task(call, "schedule",
        objective: "Offer available times and book one.",
        checklist: [Guava.Field.new(key: "slot", field_type: "calendar_slot", searchable: true)]
      )
    else
      Guava.Call.hangup(call)
    end

    {:noreply, state}
  end

  @impl true
  def handle_search_query("slot", _call, query, state) do
    filter = Guava.DatetimeFilter.new(Process.get(:client), Scheduling.open_slots())
    {:reply, Guava.DatetimeFilter.filter!(filter, query), state}
  end

  @impl true
  def handle_task_complete("schedule", call, state) do
    Scheduling.book(Guava.Call.get_field(call, "slot"))
    Guava.Call.hangup(call, "You're all set — see you then!")
    {:noreply, state}
  end
end

Guava.call_phone(Scheduler, "+14155550100", "+16285550123", %{"customer_name" => "Ada"})
```

Next: [Campaigns](campaigns.md).
</content>

# Calls

A `Guava.Call` is a handle to one live call. It's passed into your handlers and
is how you steer the conversation. Every mutating function enqueues a command
on the call's WebSocket connection.

```elixir
%Guava.Call{id: session_id, call_info: call_info} = call
```

- `Guava.Call.id/1` — the session id.
- `Guava.Call.call_info/1` — a `Guava.CallInfo.PSTN` / `.WebRTC` / `.Sip`.

## Steering the conversation

```elixir
# Free-form guidance for the agent.
Call.send_instruction(call, "Confirm the caller's email before proceeding.")

# Read a script verbatim.
Call.read_script(call, "Calls may be recorded for quality assurance.")

# Give the agent contextual info about a topic.
Call.add_info(call, "order #4471", %{status: "shipped", eta: "Tuesday"})

# End the call.
Call.hangup(call)
Call.hangup(call, "Thanks for calling — have a great day!")
```

## Tasks

Assign an objective and/or a checklist. See [Tasks & Fields](tasks-and-fields.md)
for details.

```elixir
Call.set_task(call, "collect_details",
  objective: "Collect the caller's shipping details.",
  checklist: [
    Guava.Field.new(key: "name", description: "the caller's full name"),
    Guava.Field.new(key: "zip", field_type: "integer", question: "What's your ZIP code?"),
    "Confirm the details back to the caller."
  ]
)

Call.retry_task(call, "The ZIP code didn't validate; ask again.")
```

## Transferring

```elixir
Call.transfer(call, "+14155550100")
Call.transfer(call, "+14155550100", "Transferring you to billing now.")
Call.transfer(call, "sip:agent@pbx.example.com")
```

## Persona and language

```elixir
Call.set_persona(call, agent_name: "Max", organization_name: "Acme", voice: "verse")
Call.set_language_mode(call, "spanish", ["english"])
Call.set_agent_dtmf(call, true)   # allow the agent to press keypad digits
```

## DTMF

```elixir
Call.set_agent_dtmf(call, true)   # let the agent press digits when it decides to
Call.send_dtmf(call, "123")       # press a specific sequence now (string or list)
Call.send_dtmf(call, ["4", "#"])
```

`send_dtmf/2` presses a sequence immediately — useful for navigating an IVR. Each
digit must be a valid DTMF digit (`0`–`9`, `*`, `#`, `A`–`D`). Both functions
raise `ArgumentError` on WebRTC calls, which do not support sending DTMF.

## Fields and variables

Collected field values (from tasks) are readable at any time:

```elixir
Call.get_field(call, "name")
Call.get_field(call, "name", "unknown")   # with a default
Call.has_field?(call, "name")
```

Variables are call-scoped, JSON-serializable values you set and read:

```elixir
Call.set_variable(call, "customer_tier", "gold")
Call.get_variable(call, "customer_tier", "standard")
```

Outbound calls can be seeded with initial variables via
`Guava.call_phone/5`.

## Reaching a specific person (outbound)

`reach_person/3` is a tested pattern for the opening phase of an outbound call:
greet whoever answers, ask for the intended contact, and record their
availability in the `contact_availability` field. React in
[`handle_task_complete("reach_person", …)`](handlers.md#handle_task_complete)
by reading `Guava.Call.get_field(call, "contact_availability")`.

```elixir
Call.reach_person(call, "Ada Lovelace",
  greeting: "Hi, this is Nova calling from Acme.",
  voicemail_message: "Hi Ada, this is Acme — please call us back at your convenience.",
  # or: voicemail_hangup: true
  outcomes: Guava.Call.default_reach_person_outcomes()
)
```

Custom outcomes are a list of maps with `:key`, optional `:description`, and
optional `:next_action_preview`:

```elixir
Call.reach_person(call, "Ada Lovelace",
  outcomes: [
    %{key: "available", description: "Ada is on the line."},
    %{key: "callback", description: "Ada asked us to call back later.",
      next_action_preview: "note the callback time"},
    %{key: "wrong_number", description: "This number doesn't reach Ada."}
  ]
)
```

Next: [Tasks & Fields](tasks-and-fields.md).

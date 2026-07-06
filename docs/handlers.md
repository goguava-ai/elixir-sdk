# Handlers

Handlers are `Guava.Agent` behaviour callbacks. All are optional — implement only
what you need; the rest get sensible defaults. Each (except `init/1` and
`handle_call_received/1`) receives the `Guava.Call` handle and the per-call
`state`, and returns a tuple.

| Callback | Returns | Fires when |
| --- | --- | --- |
| `init(call_info)` | `{:ok, state}` | a call starts (build state) |
| `agent_info(call_info)` | keyword persona | to resolve persona (defaults to `use` opts) |
| `handle_call_received(call_info)` | `:accept` \| `:decline` | an inbound call is offered |
| `handle_start(call, state)` | `{:noreply, state}` | the call begins |
| `handle_caller_speech(call, event, state)` | `{:noreply, state}` | the caller speaks |
| `handle_agent_speech(call, event, state)` | `{:noreply, state}` | the agent speaks |
| `handle_question(call, question, state)` | `{:reply, answer, state}` | the agent needs an answer |
| `handle_action_request(call, request, state)` | `{:reply, suggestion, state}` | the caller requests an action |
| `handle_action(action_key, call, state)` | `{:noreply, state}` | an action executes (pattern-match the key) |
| `handle_task_complete(task_id, call, state)` | `{:noreply, state}` | a task finishes (pattern-match the id) |
| `handle_search_query(field_key, call, query, state)` | `{:reply, {matched, other}, state}` | a searchable field needs options |
| `handle_dtmf(call, event, state)` | `{:noreply, state}` | a keypad digit is pressed |
| `handle_escalate(call, state)` | `{:noreply, state}` | an escalation is requested |
| `handle_session_end(call, event, state)` | `{:noreply, state}` | the call ends |
| `handle_outbound_failed(call, event, state)` | `{:noreply, state}` | an outbound call fails to connect |
| `handle_info(msg, call, state)` | `{:noreply, state}` | an external message arrives (e.g. a spawned Task's result) |
| `terminate(reason, call, state)` | ignored | cleanup |

## handle_call_received

Screen an inbound call before answering. Return `:accept` or `:decline`.

```elixir
@impl true
def handle_call_received(%Guava.CallInfo.PSTN{from_number: nil}), do: :decline  # anonymous
def handle_call_received(_call_info), do: :accept
```

## handle_question

Return the answer string (often from RAG). Without this callback, the agent says
it doesn't have an answer and the server won't route questions to you.

```elixir
@impl true
def handle_question(_call, question, state), do: {:reply, DocumentQA.answer(question), state}
```

## handle_action_request / handle_action

Two-step intent handling. `handle_action_request` classifies the request and
replies with a `Guava.SuggestedAction`, a list of them (ambiguous), or `nil`.
When an action is chosen, its `handle_action` clause executes it.

```elixir
@impl true
def handle_action_request(_call, request, state),
  do: {:reply, Guava.IntentRecognizer.classify!(recognizer(), request), state}

@impl true
def handle_action("sales", call, state) do
  Guava.Call.transfer(call, "+14155550100")
  {:noreply, state}
end

def handle_action("support", call, state) do
  Guava.Call.transfer(call, "+14155550111")
  {:noreply, state}
end
```

## handle_task_complete

Fires when a task finishes; pattern-match the task id you gave `set_task`. A
`Guava.Call.reach_person/3` task completes here as `"reach_person"` — read the
`contact_availability` field:

```elixir
@impl true
def handle_task_complete("collect_details", call, state) do
  save(Guava.Call.get_field(call, "name"), Guava.Call.get_field(call, "zip"))
  {:noreply, state}
end

def handle_task_complete("reach_person", call, state) do
  case Guava.Call.get_field(call, "contact_availability") do
    "available" -> Guava.Call.set_task(call, "survey", objective: "Run the survey.")
    _ -> Guava.Call.hangup(call)
  end

  {:noreply, state}
end
```

## handle_search_query

Generate options for a `searchable: true` field. Return `{matched, other}`.

```elixir
@impl true
def handle_search_query("slot", _call, query, state) do
  {:reply, Scheduling.search(query), state}
end
```

## handle_escalate

The caller (or agent) asked to escalate. Without this callback, the agent
politely explains no one is available.

```elixir
@impl true
def handle_escalate(call, state) do
  Guava.Call.transfer(call, "+14155550100", "Connecting you to an agent.")
  {:noreply, state}
end
```

## handle_session_end

The call ended; the event's `termination_reason` is one of `"user-hangup"`,
`"bot-hangup"`, `"bot-failure"`, `"bot-transfer"`, `"voicemail"`.

```elixir
@impl true
def handle_session_end(call, event, state) do
  Analytics.record(Guava.Call.id(call), event.termination_reason)
  {:noreply, state}
end
```

Next: [Channels](channels.md).

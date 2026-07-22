# Tasks & Fields

## Tasks

A **task** gives the agent an objective and/or a checklist of things to do or
collect. You assign one with `Guava.Call.set_task/3`:

```elixir
Call.set_task(call, "book_table",
  objective: "Take a reservation.",
  checklist: [
    "Greet the caller.",
    Guava.Field.new(key: "party_size", field_type: "integer", question: "How many people?"),
    Guava.Field.new(key: "date_time", field_type: "calendar_slot", searchable: true),
    Guava.Say.new("Let me check availability."),
    "Confirm the booking details."
  ],
  completion_criteria: "A party size and a valid time slot have been collected."
)
```

- `task_id` (2nd arg) is your identifier for the task. Use it to route
  completion with [`handle_task_complete/3`](handlers.md#handle_task_complete).
- `:objective` — a natural-language goal.
- `:checklist` — an ordered list of items (see below). At least one of
  `:objective` or `:checklist` is required.
- `:completion_criteria` — optional explicit definition of "done".

### Checklist items

A checklist item can be:

| Item | Meaning |
| --- | --- |
| a string | a free-form to-do (`Guava.Todo`) for the agent |
| `Guava.Say.new("...")` | something to say verbatim |
| `Guava.Field.new(...)` | a piece of structured data to collect |

When a task finishes, its `handle_task_complete` clause fires — pattern-match the
task id you passed to `set_task`:

```elixir
@impl true
def handle_task_complete("book_table", call, state) do
  reserve(Guava.Call.get_field(call, "party_size"), Guava.Call.get_field(call, "date_time"))
  {:noreply, state}
end
```

## Fields

A `Guava.Field` tells the agent to collect one typed value. Build it with
`Guava.Field.new/1`, which validates the options.

```elixir
Guava.Field.new(
  key: "email",                     # retrieve later with Call.get_field(call, "email")
  description: "the caller's email address",
  question: "What's the best email to reach you?",  # optional exact phrasing
  field_type: "text",
  required: true
)
```

### Field types

| `field_type` | Collects |
| --- | --- |
| `"text"` | a string (default) |
| `"integer"` | a whole number |
| `"date"` | a calendar date |
| `"multiple_choice"` | one of a set of options |
| `"calendar_slot"` | an appointment time (ISO-8601 `YYYY-MM-DDTHH:MM`) |
| `"digit_sequence"` | a sequence of keypad digits (e.g. an account number) |
| `"cvv"` | a card security code (pair with `:sensitive`) |
| `"datetime"` | *(not yet implemented — raises)* |

### Options

- `:key` — required; the retrieval key.
- `:description` — natural-language guidance on what to collect.
- `:question` — exact phrasing to use instead of letting the agent decide.
- `:required` — if `false`, the agent may skip it when the caller declines.
- `:choices` — a small static option list (for `multiple_choice` /
  `calendar_slot`). Guava warns if you exceed ~10; prefer a searchable field.
- `:searchable` — set `true` and register a handler with
  [`handle_search_query/4`](handlers.md#handle_search_query) to generate options
  dynamically for large or data-driven option sets.
- `:sensitive` — set `true` to mark the value as sensitive (e.g. a `"cvv"` or
  `"digit_sequence"`) so the server redacts it from logs and transcripts.

### Validation

`Guava.Field.new/1` mirrors the Python SDK's validation and raises
`ArgumentError` for invalid combinations:

- `"datetime"` collection is not implemented.
- `:choices` are only valid for `multiple_choice` / `calendar_slot`.
- `calendar_slot` choices must be ISO-8601 (`YYYY-MM-DDTHH:MM`).

### Reading values

```elixir
Call.get_field(call, "email")            # nil if not collected
Call.get_field(call, "email", "n/a")     # with default
Call.has_field?(call, "email")
```

Fields are populated as the agent collects them; read them any time, most
commonly in a `handle_task_complete` handler.

### Searchable fields

For large or dynamic option sets, mark the field `searchable: true` and answer
queries with matching and fallback options:

```elixir
@impl true
def handle_search_query("date_time", _call, query, state) do
  filter = Guava.DatetimeFilter.new(client(), Scheduling.available_slots())
  {:reply, Guava.DatetimeFilter.filter!(filter, query), state}
end
```

The callback replies with `{matched, other}` — both lists of choice strings. See
[RAG & LLM helpers](rag-and-llm.md) for `DatetimeFilter`.

Next: [Handlers](handlers.md).

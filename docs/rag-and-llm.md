# RAG & LLM helpers

These helpers call Guava's server-side LLM and RAG endpoints — no third-party
API keys required. They pair naturally with the handlers in
[Handlers](handlers.md).

## DocumentQA (server mode)

Index documents on the Guava server and answer questions over them. Ideal for
[`on_question`](handlers.md#handle_question).

```elixir
client = Guava.Client.new()

qa = Guava.DocumentQA.new(client,
  documents: [policy_text, faq_text],
  # namespace: "policies",   # scope this instance's docs when running several
  # instructions: "Answer only from the documents; be concise."
)

{:ok, answer} = Guava.DocumentQA.ask(qa, "What is the return window?")
```

Documents are content-addressed, so re-running with the same set skips
re-uploading and prunes ones you dropped. Manage them incrementally:

```elixir
qa = Guava.DocumentQA.upsert_document(qa, "return-policy", new_text)
qa = Guava.DocumentQA.add_document(qa, some_text)   # content-addressed key
qa = Guava.DocumentQA.delete_document(qa, "return-policy")
qa = Guava.DocumentQA.clear(qa)
```

(Each returns an updated `DocumentQA` — thread it through, functional-style.)

Wire it up:

```elixir
@impl true
def handle_question(_call, question, state), do: {:reply, Guava.DocumentQA.ask!(qa(), question), state}
```

### Local mode (bring your own vector store)

Pass a `:store` implementing `Guava.RAG.VectorStore` and a
`:generation_model` implementing `Guava.RAG.GenerationModel`, each as a
`{module, state}` tuple. Server mode is the default and needs no setup.

## IntentRecognizer

Classify a caller request into one of a fixed set of choices — perfect for
[`on_action_request`](handlers.md#handle_action_request-handle_action).

```elixir
recognizer = Guava.IntentRecognizer.new(client, %{
  "sales" => "purchases, pricing, availability, order status",
  "support" => "problems, returns, warranty, account help",
  "other" => "anything else"
})

Guava.IntentRecognizer.classify!(recognizer, "my order arrived damaged")
# => [%Guava.SuggestedAction{key: "support", description: "problems, returns, ..."}]
```

Pass a plain list of strings instead of a map if you don't need descriptions.
Returns a list ordered by likelihood (multiple entries when ambiguous), or
`nil` when nothing matches.

## DatetimeFilter

Filter ISO-8601 datetime slots by a natural-language query — pairs with a
searchable `calendar_slot` field via [`on_search_query`](handlers.md#handle_search_query).

```elixir
filter = Guava.DatetimeFilter.new(client, ["2026-07-03T10:00", "2026-07-03T14:00", "2026-07-04T09:00"])
{matched, other} = Guava.DatetimeFilter.filter!(filter, "Friday afternoon", 5)
```

Returns `{matching, fallback}` slot lists (each capped at `max_results`), drawn
only from the source list.

## DateRangeParser

Turn phrases like "next Tuesday" or "the week of the 15th" into a concrete date
range, clamped to today..today+1yr.

```elixir
parser = Guava.DateRangeParser.new(client)
{start_date, end_date} = Guava.DateRangeParser.parse!(parser, "next week", 1)
```

## LLM.generate

The low-level primitive the helpers build on (tuple + `!` bang):

```elixir
{:ok, text} = Guava.LLM.generate(client, "Summarize: ...")
Guava.LLM.generate(client, prompt, %{"type" => "object", "properties" => %{...}})  # JSON-schema-constrained
```

Next: [Testing](testing.md).

# Parity with the Python SDK

Ground truth is the Python [`guava-sdk`](https://github.com/goguava-ai/python-sdk)
(v0.32.0). This Elixir port keeps the same
concepts and wire protocol but adapts the **public API to idiomatic Elixir**
(there are no users, so this was a deliberate design choice, not a constraint).

## Mapping

| Python | Elixir | Notes |
| --- | --- | --- |
| `guava.Client` | `Guava.Client` | `new/1`/`new!/1`; all ops return `{:ok, _} \| {:error, %Guava.Error{}}` with `!` bang variants |
| `guava.Agent` (decorators) | `Guava.Agent` **behaviour** | `use Guava.Agent`; implement `@impl` callbacks; per-call threaded state |
| `guava.Call` | `Guava.Call` | handle passed to callbacks; imperative actions (`set_task`, `transfer`, `get_field`, …); reads are ETS-backed |
| `guava.Runner` | `Guava.Channel` + `Guava.run/1` | supervised channel child specs; blocking helpers on `Guava` |
| decorators (`on_question`, `on_action`, …) | callbacks (`handle_question/3`, `handle_action/3`, …) | per-key handlers are one pattern-matched callback |
| `Agent.test` / `test_roleplay` | `Guava.Testing.session/3` / `roleplay/3` | module-based |
| `guava.Field`/`Say`/`Todo` | `Guava.Field`/`Guava.Say`/`Guava.Todo` | |
| `CallInfo`, `IncomingCallAction`, `SuggestedAction` | same under `Guava.*` | `handle_call_received` returns bare `:accept`/`:decline` |
| events / commands | `Guava.Events.*` / `Guava.Commands.*` | byte-identical wire format |
| `GuavaSocket` | `Guava.Socket` + `Guava.Socket.Reliable` (pure state machine) + `Conn` + `Protocol` | unchanged from the first port |
| `campaigns.py` | `Guava.Campaigns` / `Campaign` / `Contact` | tuple + bang |
| `helpers/llm.py` | `Guava.LLM`, `Guava.IntentRecognizer`, `Guava.DatetimeFilter`, `Guava.DateRangeParser` | tuple + bang |
| `helpers/rag.py` | `Guava.RAG`, `Guava.RAG.ServerRAG`, `Guava.DocumentQA` (+ behaviours) | `ask` tuple + bang; server mode default |
| `auth.py` | `Guava.Auth.{APIKey,Deploy,CLI}` | + `config :guava` resolution |
| `telemetry.py` (usage upload) | `Guava.Usage` | opt-in; renamed to free the name for `:telemetry` spans |

## Intentional deviations

- **Agent is a behaviour with threaded state.** The Python `Agent` registers
  callbacks on a mutable object; the Elixir `Guava.Agent` is a `use`-able
  behaviour whose callbacks thread a per-call `state` (like `GenServer`/LiveView).
  This is compile-time-checked, needs no external per-call store, and lets you
  implement only the callbacks you use.
- **Errors are `{:ok, _} | {:error, %Guava.Error{}}` with `!` variants** across
  the `Client`, campaigns, and LLM/RAG helpers — the Elixir norm.
- **Callbacks run serially per call, reads are ETS-backed.** Guarantees `state`
  can't race and lets a handler read fields without deadlocking. Long work is
  offloaded via a `Task` + `handle_info/3`.
- **Config via Application env** (`config :guava, api_key:/base_url:`) in addition
  to env vars.
- **`:telemetry` spans** (`[:guava, :http, :request, …]`, `[:guava, :command, :sent]`)
  for standard observability.
- **Usage telemetry is opt-in** (off unless `config :guava, usage_telemetry: true`).
- **Legacy `CallController` not ported** — deprecated in Python; `Guava.Agent`
  supersedes it (maintainers confirmed out of scope).
- **`call_local` / curses `chat` omitted** — platform-specific local-dev tools.
  Use `Guava.Testing`.
- **Local RAG vector-store backends** are expressed as the
  `Guava.RAG.VectorStore`/`GenerationModel` behaviours; server-mode RAG is fully
  ported.

## Keeping in sync with the Python SDK

The Python version this port currently matches is recorded in
[`.upstream-sync.json`](.upstream-sync.json). To see what has changed upstream
since then, run the **`check-upstream-parity`** Claude skill (in
`.claude/skills/`): it diffs the tracked version against the latest `guava-sdk`
on PyPI (handling being several releases behind), empirically checks for
wire-protocol drift by regenerating fixtures, and writes a prioritized,
read-only report under `sync/`. It never edits the SDK — reconciling the changes
is a deliberate follow-up. After reconciling, bump `.upstream-sync.json`.

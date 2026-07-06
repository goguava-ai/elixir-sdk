---
name: check-upstream-parity
description: Check the upstream Guava Python SDK (PyPI guava-sdk) for changes since this Elixir port last synced, and produce a read-only drift report mapping every upstream change to the Elixir files it affects. Use when asked to check for upstream updates, sync with the Python SDK, see what changed upstream, or how far behind the port is. Reports only — never edits the Elixir source.
---

# Check upstream parity with the Python SDK

This Elixir library is a port of the Guava **Python** SDK (`guava-sdk` on PyPI;
source of truth). It records the Python version it currently matches in
`.upstream-sync.json`. Over time the Python SDK moves ahead. This skill produces
a **drift report**: everything that changed upstream since the tracked version,
mapped to the Elixir code that needs updating, prioritized — so a developer (or
Claude, in a follow-up) can act on it.

**This skill is read-only with respect to the Elixir source.** It downloads
released sdists into a temp dir and writes a report under `sync/`. It must NOT
edit `lib/`, `test/`, `mix.exs`, etc. Applying changes is a separate, deliberate
step the developer initiates.

Assume the port may be **many releases behind**, not just one.

## Prerequisites
`python3`, `git`, and network access to PyPI. The wire check additionally needs
`python3 -m venv` and network for `pip`.

## Steps

Run from the repo root.

### 1. Scan upstream (versions + source diff)
```bash
python3 .claude/skills/check-upstream-parity/scripts/parity_scan.py \
  --repo-root . --out-dir sync/work
```
Read the printed JSON (also `sync/work/raw.json`). If `up_to_date` is true, stop
and report "in sync with Python vX.Y.Z" — no report needed. Otherwise note
`baseline`, `latest`, and `versions_behind` (the full list — the port may be
several releases behind).

### 2. Wire-protocol check (best-effort, highest signal)
```bash
bash .claude/skills/check-upstream-parity/scripts/wire_check.sh . "<latest>" sync/work
```
Read `sync/work/wire_status.txt`:
- `OK` — no serialization drift in the exercised fixtures.
- `CHANGED` — read `sync/work/wire.diff`; every hunk is a **CRITICAL** codec change.
- `BREAKING` — `gen_fixtures.py` couldn't import against the new SDK (renamed/moved/removed symbol). Read `sync/work/wire_err.txt`; treat the failing import as a concrete breaking-change lead.
- `SKIPPED` — record the reason; fall back to reading the source diff for wire changes.

### 3. Read the raw material
- `sync/work/source.stat` — which files changed across the span.
- `sync/work/source.diff` — the actual delta between the baseline and latest sdists.
- `sync/work/changelog.txt` — upstream changelog, if the package ships one (often the fastest way to understand intent; trust it, but verify against the diff).

### 4. Map each change to the Elixir port
For every meaningful upstream change, decide its impact here. Ground every claim
in the diff/changelog — do not speculate. Use the crosswalk and code search:
- `PARITY.md` — the Python→Elixir concept crosswalk and intentional deviations. Check here first; a change to something PARITY.md marks as deliberately dropped may be **N/A**.
- `grep`/search under `lib/guava/` for the corresponding module. Common mapping: Python `guava/commands.py` → `lib/guava/commands.ex`; `events.py` → `events.ex`; `socket/protocol.py` → `lib/guava/socket/protocol.ex`; `types/*` → `lib/guava/*` (field/say/todo/call_info/…); `agent.py` → `lib/guava/agent.ex` + `lib/guava/call/runtime.ex`; client/campaigns/llm/rag likewise.
- The wire fixtures the port tests against live in `test/fixtures/wire.json`.

Classify each item:
- **Category**: `wire-protocol` · `public-api` · `new-feature` · `removal/deprecation` · `behavior-change` · `dependency` · `docs`.
- **Priority**: `critical` (wire-protocol / breaking API the port already uses) · `high` (new public API a user would expect) · `medium` · `low` (docs, internal-only).
- **Elixir status**: `missing` · `partial` · `covered` · `n/a (see PARITY.md)`.
- **Affected Elixir files** and a one-line **suggested action**.

### 5. Write the report
Write two files (the `sync/` dir is gitignored):
- `sync/REPORT-<today>-v<latest>.md` — human-readable, using the template below.
- `sync/sync-report.json` — machine-readable, for a future auto-update step.

Do NOT bump `.upstream-sync.json` — that happens only after the changes are actually reconciled.

### 6. Summarize to the user
Give the headline (baseline → latest, N releases behind, count of critical/high
items, wire status), point to the report, and note next steps: they can work the
checklist manually or ask Claude to implement specific items (a separate action).
Do not start editing source unless explicitly asked.

## Report template (`REPORT-<date>-v<latest>.md`)
```markdown
# Upstream parity report — guava-sdk v<baseline> → v<latest>

Generated <date>. The Elixir port tracks Python **v<baseline>**; latest is
**v<latest>** (**<N> releases behind**: <list>).

## Summary
- Wire protocol: <OK | CHANGED (critical) | BREAKING | SKIPPED — reason>
- Critical: <n>   High: <n>   Medium: <n>   Low: <n>
- <one-paragraph gist of what changed upstream>

## Critical — wire protocol & breaking API
For each: **what changed** (upstream, with file/symbol) → **Elixir impact**
(status + affected files) → **suggested action**. Quote the relevant `wire.diff`
hunk or source-diff lines.

## High — new/changed public API
…

## Medium / Low
…

## Not applicable (intentional deviations)
Changes that don't apply to the Elixir port, with the PARITY.md rationale.

## Checklist
- [ ] <file> — <action>   (priority)
- …

## Per-release notes
Brief per-version highlights across <baseline>→<latest> so the sequence is
visible (a breaking change may have been introduced and later revised).
```

## `sync-report.json` shape
```json
{
  "baseline": "0.32.0",
  "latest": "0.37.0",
  "versions_behind": ["0.33.0", "..."],
  "wire_status": "OK | CHANGED | BREAKING | SKIPPED",
  "generated_at": "<date>",
  "changes": [
    {
      "id": "short-slug",
      "category": "wire-protocol|public-api|new-feature|removal|behavior-change|dependency|docs",
      "priority": "critical|high|medium|low",
      "elixir_status": "missing|partial|covered|n/a",
      "summary": "what changed upstream",
      "upstream_ref": "python file/symbol or changelog line",
      "elixir_files": ["lib/guava/..."],
      "suggested_action": "…"
    }
  ]
}
```

## Guardrails
- Read-only on the Elixir source. Only write under `sync/` (and only the report/JSON).
- Never overwrite `test/fixtures/wire.json` — the wire check writes elsewhere.
- Never bump `.upstream-sync.json` here (only after changes are reconciled).
- Ground every finding in the diff/changelog/wire output; if uncertain about Elixir coverage, mark it `partial` and say why rather than guessing.
- The date comes from the environment; don't fabricate it.

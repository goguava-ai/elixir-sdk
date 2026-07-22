---
name: release
description: Cut and publish a release of the Guava Elixir SDK to Hex and GitHub — version bump, fixture regen, verification gate, commit/tag/GitHub release, and a handoff for the interactive Hex publish. Use when asked to release, publish, cut a version, ship to Hex, or tag a release, AFTER upstream parity has been reconciled and the code changes are made and tested. Not for deciding what to change (that's check-upstream-parity).
---

# Release the Guava Elixir SDK

Turns a **reconciled working tree** into a **published version** on Hex and
GitHub. This skill picks up *after*:
1. `check-upstream-parity` produced a report under `sync/`, and
2. the actual SDK changes in `lib/` were made and tested.

It does **not** decide *what* to change (that's parity). It does: regenerate wire
fixtures, bump the version everywhere, run a blocking verification gate, commit +
push `main`, tag, cut the GitHub release, and hand off the Hex publish.

## Division of labor — the trust boundary

- **Claude does** (attempt directly, confirming outward-facing writes first):
  fixture regen, version bump, verification gate, the commit, push to `main`, the
  annotated tag, and the GitHub release.
- **The human does**, always: `mix hex.user auth` and `mix hex.publish` — Hex
  publishing prompts for a **2FA OTP** that cannot be automated.
- **If a git/gh write is blocked** by the harness permission classifier (this can
  happen even with valid GitHub perms — e.g. `gh release create`), do **not**
  route around it (no `gh api`/`curl` workaround). Hand the human that exact
  command and continue.

**Never publish if the verification gate (§3) is not green.** Hex releases are
effectively permanent.

## Background an agent must know

- **Hex package:** `guava`. **GitHub:** `goguava-ai/elixir-sdk` (remote `origin`,
  default branch `main`). This is an **Elixir port of the Python `guava-sdk`**
  (PyPI); Python is ground truth.
- **Version policy (critical):** the Elixir version **mirrors the Python
  `guava-sdk` version reconciled to** (stated in `PARITY.md`/`README.md`). It may
  **skip** Python versions. A **doc-only / Elixir-only** fix between upstream
  releases gets **no new version** — do a docs-only refresh (see below), never an
  Elixir-only `x.y.z+1`.
- **Immutability:** a Hex release is permanent (retire/short-window-unpublish
  only). Get it right before publishing.

## Prerequisites

Run from repo root. Tools: `mix` (or the Docker fallback `./emix`; set `MIX=./emix`
for the scripts), `uv` (manages the fixture venv — it has no pip), `gh`, `git`.

## Steps

### 0. Pre-flight
- **Version:** `NEW_VERSION` = the Python version reconciled to — read
  `sync/sync-report.json` (`latest`) or `.upstream-sync.json`. `OLD_VERSION` =
  `mix.exs` `@version`.
- **Auth, early** (so the human isn't surprised at the end): `mix hex.user whoami`
  and `gh auth status`. Note now if Hex is expired (needs `mix hex.user auth`) —
  the Hex publish needs auth + OTP regardless.
- Confirm the reconciled changes are present in the working tree.

### 1. Regenerate wire fixtures — only if the codec/wire changed
Skip if parity `wire_status: OK` with no `wire-protocol` items. Otherwise:
```bash
bash .claude/skills/release/scripts/regen_fixtures.sh "$NEW_VERSION"
```
Then **review the delta** (judgment): `git diff test/fixtures/wire.json` must be
**only** the changes you expect. Wrong delta → `git checkout -- test/fixtures/wire.json`.
If the script reports `gen_fixtures.py FAILED` (an import error), upstream renamed
or removed a symbol: fix `scripts/gen_fixtures.py` **and** the matching Elixir
command/event in `lib/` before retrying.

### 2. Bump the version everywhere
```bash
python3 .claude/skills/release/scripts/bump_version.py --new "$NEW_VERSION"
```
It edits `mix.exs`, `.upstream-sync.json`, `PARITY.md`, `README.md`,
`docs/getting-started.md`, `examples/help_desk.exs`, then sweeps. Must print
**`BUMP OK`**. `BUMP INCOMPLETE` means a file's format drifted or a stray
reference remains — resolve before continuing. (The script never touches the
ex_doc dep, the dynamic Hex badge, the path-dep example, or `skills/**`.)

### 3. Verification gate — blocking, do NOT skip
```bash
bash .claude/skills/release/scripts/release_check.sh      # MIX=./emix if no local mix
```
Must print **`GATE OK`**. It runs `compile --warnings-as-errors`, `test`,
`docs --warnings-as-errors`, `hex.build`.

**Docs is the one that catches what `hex.publish` won't.** If docs warns, it is
almost always a docstring referencing a **Python-SDK name that doesn't exist in
the Elixir port**. Fix the docstring to the idiomatic Elixir equivalent (this is
the agentic part): `on_*` → `handle_*` callbacks; `call_phone`/`Runner` →
`Guava.run/1` + `Guava.Channel`; `Agent.test`/`roleplay` → `Guava.Testing.*`.
Re-run until clean.

### 4. Commit, push, tag, GitHub release
**Mirror the previous release's conventions** — inspect it first:
```bash
git show -s --format='%B' "$(git rev-list -n1 --grep='^Sync to guava-sdk' HEAD)"
gh release view "v${OLD_VERSION}" --repo goguava-ai/elixir-sdk --json body,targetCommitish
```
The established pattern: **straight to `main`, linear history** (no merge commit);
**annotated tag on the sync commit**; **structured GitHub notes** (`## Wire
protocol` / `## New public API` / `## Housekeeping`) with a **`PARITY.md` link
pinned to the tag** and an install snippet; commit trailer `Co-Authored-By: Claude
Opus 4.8 (1M context) <noreply@anthropic.com>`.

1. **Commit** (write the message from the parity report + `git diff`): title
   `Sync to guava-sdk $NEW_VERSION`, a one-paragraph summary, then the trailer.
   Stage tracked changes with `git add -u` (add new files explicitly; don't sweep
   in untracked junk). If you worked on a branch, `git switch main && git merge
   --ff-only <branch>` to keep history linear.
2. **Push:** `git push origin main`.
3. **Tag:** `git tag -a "v$NEW_VERSION" -m "guava v$NEW_VERSION (tracks Python
   guava-sdk $NEW_VERSION)"` then `git push origin "v$NEW_VERSION"`.
4. **GitHub release:**
   ```bash
   gh release create "v$NEW_VERSION" --repo goguava-ai/elixir-sdk \
     --title "v$NEW_VERSION" --verify-tag --notes "<generated notes>"
   ```
   Pin the PARITY.md link to the tag:
   `https://github.com/goguava-ai/elixir-sdk/blob/v$NEW_VERSION/PARITY.md`.

If any of these is classifier-blocked, hand the human that exact command.

> **Idempotent:** if `v$NEW_VERSION` or the release already exists, skip — don't
> recreate. Backfill: if an older released version was never tagged, tag it
> retroactively at its commit so it stays pinnable.

### 5. Hand off the Hex publish (human — OTP)
Give the human these to run in **their** terminal (answer `Proceed?`/OTP there):
```bash
mix hex.user auth        # only if whoami showed expired/unauthenticated
mix hex.publish          # publishes PACKAGE + DOCS; --yes skips Proceed (OTP still prompts)
```
Notes: the **first** publish of `guava` makes that account the owner;
`mix hex.publish` ships docs too, so a normal release needs nothing extra.

### 6. Post-publish verification (after the human publishes)
```bash
curl -s -o /dev/null -w 'pkg %{http_code}\n' https://hex.pm/api/packages/guava
curl -s -o /dev/null -w 'rel %{http_code}\n' "https://hex.pm/api/packages/guava/releases/$NEW_VERSION"
curl -sL -o /dev/null -w 'doc %{http_code}\n' "https://hexdocs.pm/guava/$NEW_VERSION/"   # 200 (after a 301)
gh release view "v$NEW_VERSION" --repo goguava-ai/elixir-sdk --json tagName,isDraft
```
Also confirm Hex's `latest_stable_version` == `$NEW_VERSION` and local `main` ==
`origin/main`.

## Docs-only refresh (no version bump)
When only docs changed on an **already-published** version:
```bash
mix docs --warnings-as-errors    # must be clean first
mix hex.publish docs             # refreshes HexDocs for the CURRENT version only
```
This changes neither the tarball nor metadata (metadata changes take effect on the
next **package** publish).

## Rollback / fixing mistakes
- **Bad Hex release** — unpublish only within the short grace window
  (`mix help hex.publish`); otherwise **retire**:
  `mix hex.retire guava $NEW_VERSION invalid --message "…"`.
- **Bad tag** — `git push origin :v$NEW_VERSION` then `git tag -d v$NEW_VERSION`.
- **Bad GitHub release** — `gh release delete v$NEW_VERSION --repo goguava-ai/elixir-sdk`.
- **Bad HexDocs** — fix docs, re-run `mix hex.publish docs` (docs are mutable).

## Guardrails
- Never publish unless §3 is `GATE OK`.
- Never hand-edit `test/fixtures/wire.json` — regenerate via §1.
- Answer interactive prompts (`Proceed?`, OTP) in the **terminal**, not in chat.
- On a classifier denial for a git/gh write, hand off — never work around it.
- Idempotent: skip a tag/release that already exists.
- The version bump is scripted; don't hand-bump (you'll miss a file or touch a
  forbidden one).

## Lessons baked into this skill
- **Auth pre-flight is step 0**, not a surprise at the end (Hex auth expires).
- `mix hex.publish` **won't fail on doc warnings** → gate on `mix docs
  --warnings-as-errors` (§3). A prior release shipped, then patched doc warnings.
- **Stale Python-API names in docstrings** are the usual doc-warning cause; map
  them to idiomatic Elixir.
- **`.venv-guava` has no pip → use `uv`**; it may already exist (install into it).
- **Fixtures must be verified byte-reproducible** via the canonical venv, not
  trusted.
- **Outward-facing writes can be classifier-gated** even with valid creds → be
  ready with a clean, copy-pasteable human handoff.
- The Elixir version **mirrors** Python; doc-only fixes → docs-only refresh.

## Cheat sheet
```bash
OLD_VERSION=$(grep -oP '@version "\K[^"]+' mix.exs) ; NEW_VERSION=0.x.0

bash .claude/skills/release/scripts/regen_fixtures.sh "$NEW_VERSION"   # if wire changed; review diff
python3 .claude/skills/release/scripts/bump_version.py --new "$NEW_VERSION"   # -> BUMP OK
bash .claude/skills/release/scripts/release_check.sh                   # -> GATE OK

git add -u && git commit -F -   # "Sync to guava-sdk $NEW_VERSION" + Co-Authored-By trailer
git push origin main
git tag -a "v$NEW_VERSION" -m "guava v$NEW_VERSION (tracks Python guava-sdk $NEW_VERSION)"
git push origin "v$NEW_VERSION"
gh release create "v$NEW_VERSION" --repo goguava-ai/elixir-sdk --title "v$NEW_VERSION" --verify-tag --notes "…"

# HUMAN (OTP): mix hex.user auth ; mix hex.publish
```

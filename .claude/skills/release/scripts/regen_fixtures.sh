#!/usr/bin/env bash
# Regenerate test/fixtures/wire.json from the pinned Python guava-sdk (RELEASING.md
# §3). Run only when the codec/wire changed. Driven by the `release` skill.
#
# wire.json is a GENERATED artifact — never hand-edit it. It is produced by
# scripts/gen_fixtures.py running against the EXACT Python SDK version inside the
# gitignored .venv-guava. That venv has no pip, so we manage it with `uv`.
#
# Writes wire.json in place (revert with `git checkout` if the delta is wrong) and
# prints the diffstat for review — the delta must be ONLY the changes you expect.
#
# Usage: bash regen_fixtures.sh <guava-sdk-version>     e.g. bash regen_fixtures.sh 0.35.0
set -uo pipefail
VERSION="${1:?usage: regen_fixtures.sh <guava-sdk-version>}"
VENV=".venv-guava"

command -v uv >/dev/null || { echo "uv not found — install it (astral.sh) to manage .venv-guava"; exit 1; }

# Create the venv if missing; install/pin the exact SDK version either way.
[[ -x "$VENV/bin/python" ]] || uv venv "$VENV" || exit 1
uv pip install --python "$VENV/bin/python" -q "guava-sdk==${VERSION}" || {
  echo "failed to install guava-sdk==${VERSION} into $VENV"; exit 1; }

GOT="$("$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("guava-sdk"))')"
[[ "$GOT" == "$VERSION" ]] || { echo "venv has guava-sdk $GOT, expected $VERSION"; exit 1; }

# Regenerate. An ImportError here means upstream renamed/removed a symbol
# gen_fixtures.py imports — a real breaking change: update scripts/gen_fixtures.py
# AND the corresponding Elixir command/event in lib/ before this can succeed.
if ! "$VENV/bin/python" scripts/gen_fixtures.py > test/fixtures/wire.json; then
  echo "gen_fixtures.py FAILED against guava-sdk ${VERSION}."
  echo "Likely a renamed/removed symbol — update scripts/gen_fixtures.py + lib/ first."
  git checkout -- test/fixtures/wire.json 2>/dev/null || true
  exit 1
fi

echo "Regenerated test/fixtures/wire.json from guava-sdk ${VERSION}. Review the delta:"
git --no-pager diff --stat test/fixtures/wire.json
echo "(full diff: git diff test/fixtures/wire.json — the delta must be ONLY what you expect)"

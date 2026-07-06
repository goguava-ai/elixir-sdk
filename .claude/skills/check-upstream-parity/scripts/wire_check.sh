#!/usr/bin/env bash
# Best-effort wire-protocol drift check.
#
# Regenerates the wire fixtures from a target guava-sdk version (in a throwaway
# environment) and diffs them against the committed test/fixtures/wire.json.
# This is the highest-signal check for a wire-compatible port: any change here
# means the Elixir codec must change too. Degrades gracefully — always exits 0
# and records what happened in <out>/wire_status.txt.
#
# Isolates the install via whichever tool is present, in order of preference:
#   uv  →  virtualenv  →  python3 -m venv  →  pip install --target
#
# Usage: wire_check.sh <repo-root> <version> <out-dir>
set -uo pipefail

REPO="${1:?repo root}"
VERSION="${2:?guava-sdk version}"
OUT="${3:?out dir}"
mkdir -p "$OUT"
status="$OUT/wire_status.txt"
work="$(mktemp -d)"
pkg="guava-sdk==$VERSION"

# Print a command that runs python with guava-sdk importable, or nothing on failure.
setup_runner() {
  if command -v uv >/dev/null 2>&1 &&
     uv venv "$work/venv" >/dev/null 2>&1 &&
     uv pip install --python "$work/venv/bin/python" -q "$pkg" >"$OUT/pip.log" 2>&1; then
    echo "$work/venv/bin/python"; return 0
  fi
  if command -v virtualenv >/dev/null 2>&1 &&
     virtualenv -q "$work/venv" >/dev/null 2>&1 &&
     "$work/venv/bin/pip" install -q "$pkg" >"$OUT/pip.log" 2>&1; then
    echo "$work/venv/bin/python"; return 0
  fi
  if python3 -m venv "$work/venv" >/dev/null 2>&1; then
    "$work/venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1
    if "$work/venv/bin/pip" install -q "$pkg" >"$OUT/pip.log" 2>&1; then
      echo "$work/venv/bin/python"; return 0
    fi
  fi
  if python3 -m pip install -q --target "$work/pkgs" "$pkg" >"$OUT/pip.log" 2>&1; then
    echo "TARGET:$work/pkgs"; return 0
  fi
  return 1
}

runner="$(setup_runner)"
if [ -z "$runner" ]; then
  echo "SKIPPED: could not install $pkg (tried uv/virtualenv/venv/pip --target; see pip.log)" >"$status"
  exit 0
fi

if [ "${runner#TARGET:}" != "$runner" ]; then
  gen() { PYTHONPATH="${runner#TARGET:}" python3 "$@"; }
else
  gen() { "$runner" "$@"; }
fi

if gen "$REPO/scripts/gen_fixtures.py" >"$OUT/wire_latest.json" 2>"$OUT/wire_err.txt"; then
  if diff -u "$REPO/test/fixtures/wire.json" "$OUT/wire_latest.json" >"$OUT/wire.diff" 2>&1; then
    echo "OK: no wire-format changes vs test/fixtures/wire.json" >"$status"
  else
    echo "CHANGED: wire-format differs from test/fixtures/wire.json (see wire.diff) — CRITICAL for the codec" >"$status"
  fi
else
  echo "BREAKING: gen_fixtures.py failed against $pkg — likely a renamed/removed/moved symbol (see wire_err.txt). This itself signals a breaking API change; scripts/gen_fixtures.py may need updating before fixtures can be regenerated." >"$status"
fi
exit 0

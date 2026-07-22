#!/usr/bin/env bash
# Pre-flight verification gate for a release (RELEASING.md §6). Driven by the
# `release` skill. All four checks must pass with ZERO warnings/failures before
# anything is committed, tagged, or published.
#
# Why docs is here: `mix hex.publish` GENERATES docs but does NOT fail on doc
# warnings — that is how broken doc references once shipped to HexDocs. Gate on it.
#
# Set MIX=./emix to use the Docker toolchain instead of a local mix.
#
# Usage: bash release_check.sh
set -uo pipefail
MIX="${MIX:-mix}"

run() {
  echo "── ${MIX} $* ──"
  # shellcheck disable=SC2086
  if ! $MIX "$@"; then
    echo "GATE FAILED: ${MIX} $*"
    exit 1
  fi
}

run compile --warnings-as-errors   # code warnings
run test                           # full suite (:live excluded by default — expected)
run docs --warnings-as-errors      # broken doc refs/links (ExDoc >= 0.34)
run hex.build                      # validates package metadata + file list; prints the version

# Tidy the generated artifacts (both gitignored, but don't leave them lying around).
rm -rf doc guava-*.tar

echo "GATE OK — safe to commit/tag/release."

#!/usr/bin/env python3
"""Bump the SDK version across every file that must move together, then sweep for
stragglers. Deterministic — no judgment. Driven by the `release` skill (SKILL.md).

The Elixir package version MIRRORS the Python guava-sdk version it tracks, so
"the version" is whatever Python version was reconciled (see PARITY.md).

Edits exactly these files (nothing else — the do-NOT-touch list below is enforced
by only opening these paths):
  mix.exs                 @version "OLD" -> "NEW"        (NOT the ex_doc dep constraint)
  .upstream-sync.json     python_sdk_version -> NEW; synced_at -> today
  PARITY.md               intro "(vOLD)" -> "(vNEW)"
  README.md               Python-SDK badge vOLD, "Tracks vOLD", "~> OLD_MINOR", "OLD_MINOR.x"
  docs/getting-started.md install snippet "~> OLD_MINOR"
  examples/help_desk.exs  Mix.install "~> OLD_MINOR"

Never touched: the dynamic Hex.pm badge, {:ex_doc, "~> ..."}, mix.lock, deps/,
_build/, .venv*, .claude/skills/** (example text), and
examples/inbound_receptionist/mix.exs (depends via {:guava, path: "../.."}).

After editing, runs the two release-runbook sweeps for leftover OLD references and
fails if any remain (guava-scoped, so the ex_doc "~> OLD_MINOR" dep is ignored).

Usage:
  python3 bump_version.py --new 0.35.0 [--old 0.34.0] [--synced-at 2026-07-22]
  python3 bump_version.py --verify-only --old 0.34.0     # no edits; just sweep
"""
import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path


def read_current_version(root: Path) -> str:
    m = re.search(r'@version "([^"]+)"', (root / "mix.exs").read_text())
    if not m:
        sys.exit("could not read @version from mix.exs")
    return m.group(1)


def minor(v: str) -> str:
    return ".".join(v.split(".")[:2])


def edits_for(old: str, new: str, synced_at: str):
    om, nm = minor(old), minor(new)
    return {
        "mix.exs": [(f'@version "{old}"', f'@version "{new}"', True)],
        ".upstream-sync.json": [
            (f'"python_sdk_version": "{old}"', f'"python_sdk_version": "{new}"', True),
            (re.compile(r'"synced_at": "\d{4}-\d{2}-\d{2}"'), f'"synced_at": "{synced_at}"', True),
        ],
        "PARITY.md": [(f"(v{old})", f"(v{new})", True)],
        "README.md": [
            (old, new, True),                       # badge -vOLD- and "Tracks `vOLD`"
            (f"~> {om}", f"~> {nm}", True),          # prose + install constraint
            (f"{om}.x", f"{nm}.x", False),           # "OLD_MINOR.x" prose
        ],
        "docs/getting-started.md": [(f"~> {om}", f"~> {nm}", True)],
        "examples/help_desk.exs": [(f"~> {om}", f"~> {nm}", True)],
    }


def apply_edits(root: Path, old: str, new: str, synced_at: str) -> int:
    problems = 0
    for rel, reps in edits_for(old, new, synced_at).items():
        path = root / rel
        text = path.read_text()
        for pat, repl, required in reps:
            if isinstance(pat, re.Pattern):
                text, n = pat.subn(repl, text)
            else:
                n = text.count(pat)
                text = text.replace(pat, repl)
            label = pat.pattern if isinstance(pat, re.Pattern) else pat
            if n == 0 and required:
                print(f"  !! {rel}: expected to replace {label!r} but found 0 — format drift?")
                problems += 1
            else:
                print(f"  {rel}: {label!r} -> {n}x")
        path.write_text(text)
    return problems


def sweep(root: Path, old: str) -> int:
    """The two runbook sweeps; return count of stray SDK-version references."""
    om = minor(old)
    stray = 0
    # 1. literal old version, excluding generated/vendored trees and sync reports.
    r1 = subprocess.run(
        ["git", "grep", "-n", old, "--", ".", ":!sync", ":!mix.lock"],
        cwd=root, capture_output=True, text=True,
    )
    for line in r1.stdout.splitlines():
        if re.search(r"deps/|_build/|\.venv|skills/", line):
            continue
        print(f"  stray: {line}")
        stray += 1
    # 2. guava dep pinned to the old minor (ignores the ex_doc "~> OLD_MINOR" dep).
    r2 = subprocess.run(
        ["git", "grep", "-nE", rf"guava.*~> {re.escape(om)}"],
        cwd=root, capture_output=True, text=True,
    )
    for line in r2.stdout.splitlines():
        if re.search(r"deps/|_build/|\.venv", line):
            continue
        print(f"  stray: {line}")
        stray += 1
    return stray


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--new")
    ap.add_argument("--old")
    ap.add_argument("--synced-at", default=datetime.date.today().isoformat())
    ap.add_argument("--verify-only", action="store_true",
                    help="skip edits; only sweep for leftover --old references")
    args = ap.parse_args()

    root = Path(args.repo_root).resolve()
    old = args.old or read_current_version(root)

    if args.verify_only:
        print(f"Sweeping for leftover references to {old} ...")
        stray = sweep(root, old)
        print("SWEEP CLEAN" if stray == 0 else f"FOUND {stray} stray reference(s)")
        sys.exit(0 if stray == 0 else 1)

    if not args.new:
        sys.exit("--new is required unless --verify-only")
    if old == args.new:
        sys.exit(f"--old and --new are both {old}; nothing to bump")

    print(f"Bumping {old} -> {args.new} (synced_at {args.synced_at}) ...")
    problems = apply_edits(root, old, args.new, args.synced_at)
    print(f"Sweeping for leftover references to {old} ...")
    stray = sweep(root, old)
    ok = problems == 0 and stray == 0
    print("BUMP OK" if ok else f"BUMP INCOMPLETE ({problems} format issue(s), {stray} stray ref(s))")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

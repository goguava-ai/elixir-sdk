#!/usr/bin/env python3
"""Scan the upstream Guava Python SDK (PyPI: guava-sdk) for changes since the
version this Elixir port tracks, and emit raw diff material for a parity report.

Read-only. Touches nothing in the Elixir source tree — it downloads released
sdists into a temp dir and writes diff artifacts into --out-dir. The semantic
"what does this mean for the Elixir port" mapping is done by Claude per SKILL.md.

Outputs (in --out-dir):
  raw.json      summary: baseline, latest, versions_behind, artifact paths
  source.diff   full `git diff --no-index` between baseline and latest sdists
  source.stat   diffstat (changed files, per the guava package)
  changelog.txt latest sdist's CHANGELOG/HISTORY, if present

Usage:
  python3 parity_scan.py --repo-root . --out-dir sync/work [--baseline 0.32.0]
"""
import argparse
import json
import re
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

PYPI_PROJECT = "https://pypi.org/pypi/guava-sdk/json"
PYPI_VERSION = "https://pypi.org/pypi/guava-sdk/{}/json"
STABLE_RE = re.compile(r"^\d+(?:\.\d+){0,3}$")  # skip rc/dev/pre-releases


def http_json(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def parse_version(v):
    nums = [int(n) for n in re.findall(r"\d+", v)][:4]
    return tuple(nums + [0] * (4 - len(nums)))


def determine_baseline(repo, explicit):
    if explicit:
        return explicit
    sync = repo / ".upstream-sync.json"
    if sync.exists():
        return json.loads(sync.read_text())["python_sdk_version"]
    m = re.search(r'@version\s+"([^"]+)"', (repo / "mix.exs").read_text())
    if not m:
        raise SystemExit("Could not determine baseline: no .upstream-sync.json and no @version in mix.exs")
    return m.group(1)


def all_versions():
    data = http_json(PYPI_PROJECT)
    releases = data.get("releases", {})
    versions = [
        v
        for v, files in releases.items()
        if STABLE_RE.match(v) and any(not f.get("yanked") for f in files)
    ]
    versions.sort(key=parse_version)
    return versions, data["info"]["version"]


def sdist_url(version):
    for f in http_json(PYPI_VERSION.format(version))["urls"]:
        if f["packagetype"] == "sdist":
            return f["url"]
    return None


def download_extract(version, dest):
    url = sdist_url(version)
    if not url:
        raise SystemExit(f"No sdist on PyPI for guava-sdk=={version}")
    dest.mkdir(parents=True, exist_ok=True)
    tgz = dest / f"{version}.tar.gz"
    urllib.request.urlretrieve(url, tgz)
    with tarfile.open(tgz) as t:
        t.extractall(dest / "x")
    roots = [p for p in (dest / "x").iterdir() if p.is_dir()]
    return roots[0] if roots else dest / "x"


def git_no_index(*args):
    # `git diff --no-index` exits 1 when there are differences; that's expected.
    return subprocess.run(["git", "diff", "--no-index", *args], capture_output=True, text=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--baseline", help="override baseline version (else .upstream-sync.json / mix.exs)")
    args = ap.parse_args()

    repo = Path(args.repo_root).resolve()
    out = Path(args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)

    baseline = determine_baseline(repo, args.baseline)
    versions, latest = all_versions()

    if baseline not in versions:
        print(f"WARNING: baseline {baseline} not found on PyPI; known: {versions}")

    behind = [v for v in versions if parse_version(baseline) < parse_version(v) <= parse_version(latest)]

    summary = {
        "package": "guava-sdk",
        "baseline": baseline,
        "latest": latest,
        "versions_behind": behind,
        "count_behind": len(behind),
        "up_to_date": len(behind) == 0,
    }

    if behind:
        work = Path(tempfile.mkdtemp(prefix="parity-src-"))
        base_src = download_extract(baseline, work / baseline)
        latest_src = download_extract(latest, work / latest)

        (out / "source.diff").write_text(git_no_index("--", str(base_src), str(latest_src)))
        (out / "source.stat").write_text(git_no_index("--stat", "--", str(base_src), str(latest_src)))

        changelog = ""
        for name in ("CHANGELOG.md", "CHANGELOG.rst", "CHANGES.md", "HISTORY.md", "NEWS.md"):
            cl = latest_src / name
            if cl.exists():
                changelog = cl.read_text(errors="replace")
                break
        if changelog:
            (out / "changelog.txt").write_text(changelog)

        summary.update(
            {
                "baseline_src": str(base_src),
                "latest_src": str(latest_src),
                "source_diff": str(out / "source.diff"),
                "source_stat": str(out / "source.stat"),
                "changelog": str(out / "changelog.txt") if changelog else None,
            }
        )

    (out / "raw.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

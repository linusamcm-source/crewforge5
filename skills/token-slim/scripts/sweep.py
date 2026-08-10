#!/usr/bin/env python3
"""sweep.py — plan-level totals gate for a token-slim run.

Asserts, against the baseline snapshot and the live tree:
  1. no skill description exceeds --legacy-cap (default 500) normalized chars
  2. every trim-scope skill (baseline desc > legacy-cap) is ≤ --trim-cap (300)
  3. total normalized description chars ≤ --max-total (skipped if omitted)
  4. every skill in the ceilings file meets its body ceiling
  5. check.sh exits 0 for every touched skill (trim-scope ∪ ceilings)

Usage:
  sweep.py --skills-dir DIR --baseline FILE [--ceilings FILE]
           [--max-total N] [--trim-cap 300] [--legacy-cap 500]

--ceilings FILE is a JSON object mapping skill name → fraction of baseline
body_chars (e.g. {"my-skill": 0.75}). Exits 0 if all pass; one line per
failure and exit 1 otherwise.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", required=True, type=Path)
    ap.add_argument("--baseline", required=True, type=Path)
    ap.add_argument("--ceilings", type=Path)
    ap.add_argument("--max-total", type=int)
    ap.add_argument("--trim-cap", type=int, default=300)
    ap.add_argument("--legacy-cap", type=int, default=500)
    args = ap.parse_args()

    baseline = json.load(open(args.baseline))
    ceilings = json.load(open(args.ceilings)) if args.ceilings else {}
    report = subprocess.run(
        [sys.executable, str(HERE / "baseline.py"),
         "--skills-dir", str(args.skills_dir), "--report"],
        capture_output=True, text=True, check=True,
    )
    current = json.loads(report.stdout)
    failures = []

    trim_scope = sorted(
        s for s, e in baseline.items() if e["desc_chars"] > args.legacy_cap
    )
    touched = sorted(set(trim_scope) | set(ceilings))

    for s, e in sorted(current.items()):
        if e["desc_chars"] > args.legacy_cap:
            failures.append(f"{s}: desc {e['desc_chars']} > {args.legacy_cap}")
    for s in trim_scope:
        if s not in current:
            failures.append(f"{s}: in baseline but missing from live tree")
        elif current[s]["desc_chars"] > args.trim_cap:
            failures.append(
                f"{s}: trim-scope desc {current[s]['desc_chars']} > {args.trim_cap}"
            )

    total = sum(e["desc_chars"] for e in current.values())
    if args.max_total is not None and total > args.max_total:
        failures.append(f"total desc chars {total} > {args.max_total}")

    for s, cap in sorted(ceilings.items()):
        if s not in baseline or s not in current:
            failures.append(f"{s}: in ceilings but missing from baseline or live tree")
            continue
        limit = int(baseline[s]["body_chars"] * cap)
        if current[s]["body_chars"] > limit:
            failures.append(
                f"{s}: body {current[s]['body_chars']} > ceiling {limit} ({cap:.0%})"
            )

    for s in touched:
        r = subprocess.run(
            ["bash", str(HERE / "check.sh"), s, str(args.skills_dir),
             str(args.baseline), str(args.trim_cap)],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            failures.append(f"{s}: check.sh failed: {r.stdout.strip()}")

    for f in failures:
        print(f"FAIL: {f}")
    if not failures:
        base_total = sum(e["desc_chars"] for e in baseline.values())
        print(
            f"sweep OK: {len(touched)} touched skills clean; "
            f"total desc {total} chars (baseline {base_total})"
        )
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()

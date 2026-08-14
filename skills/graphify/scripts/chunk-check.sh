#!/usr/bin/env bash
# chunk-check.sh <expected-count> — Step B3 collection check, mechanised.
# Verifies each graphify-out/.graphify_chunk_*.json exists and parses with
# nodes+edges arrays. Prints per-chunk status and a verdict:
#   exit 0  all (or more than half) chunks valid — proceed, skipping invalid ones
#   exit 1  more than half failed/missing — stop, re-run with general-purpose agents
set -euo pipefail

EXPECTED="${1:?usage: chunk-check.sh <expected-chunk-count>}"

exec python3 - "$EXPECTED" <<'PY'
import glob, json, sys

expected = int(sys.argv[1])
found = sorted(glob.glob("graphify-out/.graphify_chunk_*.json"))
valid = 0
for f in found:
    try:
        d = json.load(open(f, encoding="utf-8"))
        if isinstance(d.get("nodes"), list) and isinstance(d.get("edges"), list):
            print(f"ok={f} nodes={len(d['nodes'])} edges={len(d['edges'])}")
            valid += 1
        else:
            print(f"invalid={f} (missing nodes/edges arrays)")
    except ValueError:
        print(f"invalid={f} (bad JSON)")

missing = expected - len(found)
if missing > 0:
    print(f"missing={missing} — subagent may have been dispatched read-only (Explore); use general-purpose")

failed = expected - valid
print(f"valid={valid}/{expected}")
if failed * 2 > expected:
    print("verdict=abort — more than half the chunks failed; re-run with subagent_type=general-purpose")
    sys.exit(1)
print("verdict=proceed" + (" (skipping invalid chunks)" if failed else ""))
PY

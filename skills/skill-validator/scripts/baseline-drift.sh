#!/usr/bin/env bash
# baseline-drift.sh <skill-path> — if the target skill has a token-slim baseline
# entry, run token-slim's check.sh against it and report drift as WARN findings.
# Drift is WARN not FAIL: it may be intentional feature evolution whose fix is
# refreshing the baseline entry, not reverting the skill. Always exits 0.
set -euo pipefail

DIR="${1:?usage: baseline-drift.sh <skill-path>}"
DIR="$(cd "$DIR" && pwd)"
SKILL="$(basename "$DIR")"
SKILLS_DIR="$(dirname "$DIR")"
BASELINE="$SKILLS_DIR/.token-slim/baseline.json"
CHECKER="$SKILLS_DIR/token-slim/scripts/check.sh"

if [ ! -f "$BASELINE" ] || [ ! -f "$CHECKER" ]; then
  echo "SKIPPED [baseline-drift]: no token-slim baseline/harness beside $SKILLS_DIR"
  exit 0
fi
if ! python3 -c "import json,sys; sys.exit(0 if '$SKILL' in json.load(open('$BASELINE')) else 1)"; then
  echo "SKIPPED [baseline-drift]: no baseline entry for $SKILL"
  exit 0
fi

if out="$(bash "$CHECKER" "$SKILL" "$SKILLS_DIR" "$BASELINE" 2>&1)"; then
  echo "OK [baseline-drift]: matches token-slim baseline"
else
  printf '%s\n' "$out" | sed 's/^FAIL/WARN/; s/^/[baseline-drift] /' | sed 's/^\[baseline-drift\] WARN/WARN [baseline-drift]:/'
  echo "WARN [baseline-drift]: drift vs token-slim baseline — if intentional, refresh the baseline entry"
fi

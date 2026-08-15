#!/usr/bin/env bash
# Mechanical debt-coverage check for /master-plan Phase 4.
# Usage: check_coverage.sh <GOAL_IMPACT.md> <plan-file>
# Compares finding IDs in the impact map's disposition table against the plan's
# debt-coverage table. Exit 0 + CLEAN when every ID appears exactly once in the plan.
set -euo pipefail

if [ $# -ne 2 ] || [ ! -f "$1" ] || [ ! -f "$2" ]; then
  echo "usage: check_coverage.sh <GOAL_IMPACT.md> <plan-file>" >&2
  exit 2
fi

impact="$1"
plan="$2"

# Finding IDs look like F001, C1, DEP1, SEC1... — uppercase prefix + digits,
# taken only from markdown table rows (lines starting with '|') so prose
# mentions don't count as coverage.
extract_ids() {
  grep -E '^\|' "$1" | grep -oE '\b[A-Z]{1,4}[0-9]{1,3}\b' | sort
}

impact_ids=$(extract_ids "$impact" | uniq)
# Plan tables also contain story IDs (S1, S2...) that match the same shape;
# only occurrences of IDs from the impact set count as coverage entries.
plan_ids=$(extract_ids "$plan" | grep -Fx -f <(echo "$impact_ids") || true)

status=0

missing=$(comm -23 <(echo "$impact_ids") <(echo "$plan_ids" | uniq))
if [ -n "$missing" ]; then
  echo "MISSING from plan coverage table:"
  # shellcheck disable=SC2001  # ${var//search/replace} cannot prefix EVERY line
  # of a multi-line value; sed is the right tool for a per-line prefix.
  echo "$missing" | sed 's/^/  - /'
  status=1
fi

dupes=$(echo "$plan_ids" | uniq -d)
if [ -n "$dupes" ]; then
  echo "DUPLICATED in plan coverage table:"
  # shellcheck disable=SC2001  # ${var//search/replace} cannot prefix EVERY line
  # of a multi-line value; sed is the right tool for a per-line prefix.
  echo "$dupes" | sed 's/^/  - /'
  status=1
fi

if [ "$status" -eq 0 ]; then
  count=$(echo "$impact_ids" | grep -c . || true)
  echo "CLEAN: all $count intersecting finding IDs accounted for exactly once."
fi

exit "$status"

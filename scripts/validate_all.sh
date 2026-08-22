#!/usr/bin/env bash
# validate_all.sh — run the plugin's own validators across everything it ships.
#
#   validate_all.sh [--unless <dir>]
#
# The pitch is that this toolchain keeps generated agents and skills from
# rotting. A bundle that cannot pass its own validators has no pitch, so this
# runs them over the whole tree and fails on any FAIL.
#
# --unless <dir> exits 0 with SKIPPED when <dir> IS this tree. `init` phase 4
# runs this sweep to prove the plugin is sound before it judges anything else,
# then gates on a per-component walk of INIT_TARGET — and INIT_TARGET defaults
# to the repo root. Auditing CrewForge5 with itself therefore ran the identical
# structural sweep over the identical components twice. When the two differ,
# both are still needed and both still run.
#
# STRUCTURAL ONLY, DELIBERATELY. The `skill-validator` and `agent-validator`
# skills grade behaviour as well, and behaviour needs a model — which CI does
# not have. Their non-spawning scripts are what runs here; the behavioural half
# stays a human-invoked gate, and this file does not pretend otherwise.
#
# Exits 0 when every component is structurally clean, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd -P)"

UNLESS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unless) [ $# -ge 2 ] || { echo "validate_all.sh: --unless needs a directory" >&2; exit 2; }
              UNLESS="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    *)        echo "validate_all.sh: unknown argument \"$1\"" >&2; exit 2 ;;
  esac
done

if [ -n "$UNLESS" ] && [ -d "$UNLESS" ] && [ "$(cd "$UNLESS" && pwd -P)" = "$ROOT" ]; then
  echo "SKIPPED: $UNLESS is this tree — the per-component walk already covers it"
  exit 0
fi
AGENT_V="$ROOT/skills/agent-validator/scripts/validate_agent.sh"
SKILL_V="$ROOT/skills/skill-validator/scripts/validate_structure.sh"
BUDGET_C="$ROOT/scripts/budget_check.sh"

fail=0
checked=0

report() { # $1 label  $2 output
  local fails
  fails="$(printf '%s' "$2" | grep -o '"status":"FAIL"' | wc -l | tr -d ' ')"
  if [ "${fails:-0}" -gt 0 ]; then
    echo "FAIL ($fails) $1"
    printf '%s\n' "$2" | grep '"status":"FAIL"' | sed 's/^/         /'
    fail=1
  else
    echo "ok       $1"
  fi
  checked=$((checked + 1))
}

if [ -x "$AGENT_V" ] || [ -f "$AGENT_V" ]; then
  for a in "$ROOT"/agents/*.md; do
    [ -f "$a" ] || continue
    report "agent  $(basename "$a")" "$(bash "$AGENT_V" "$a" 2>&1)"
  done
else
  echo "SKIP: no agent validator at $AGENT_V"
fi

if [ -x "$SKILL_V" ] || [ -f "$SKILL_V" ]; then
  for s in "$ROOT"/skills/*/; do
    [ -f "$s/SKILL.md" ] || continue
    report "skill  $(basename "$s")" "$(bash "$SKILL_V" "$s" 2>&1)"
  done
else
  echo "SKIP: no skill validator at $SKILL_V"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS: $checked components structurally clean"
else
  echo "FAIL: structural failures above, across $checked components"
fi

# Structural cleanliness says nothing about what the bundle costs before it is
# ever used, and the budget gate only ran as a separate CI step — so a local
# `validate_all.sh` run reported green on a tree that was over budget. It is
# folded in here so one command answers the whole release question.
echo
if [ -f "$BUDGET_C" ]; then
  budget_out="$(bash "$BUDGET_C" 2>&1)"
  budget_rc=$?
  printf '%s\n' "$budget_out" | sed 's/^/budget:  /'
  [ "$budget_rc" -eq 0 ] || fail=1
else
  echo "SKIP: no budget gate at $BUDGET_C"
fi

exit "$fail"

#!/usr/bin/env bash
# validate_all.sh — run the plugin's own validators across everything it ships.
#
#   validate_all.sh
#
# The pitch is that this toolchain keeps generated agents and skills from
# rotting. A bundle that cannot pass its own validators has no pitch, so this
# runs them over the whole tree and fails on any FAIL.
#
# STRUCTURAL ONLY, DELIBERATELY. The `skill-validator` and `agent-validator`
# skills grade behaviour as well, and behaviour needs a model — which CI does
# not have. Their non-spawning scripts are what runs here; the behavioural half
# stays a human-invoked gate, and this file does not pretend otherwise.
#
# Exits 0 when every component is structurally clean, 1 otherwise.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGENT_V="$ROOT/skills/agent-validator/scripts/validate_agent.sh"
SKILL_V="$ROOT/skills/skill-validator/scripts/validate_structure.sh"

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
exit "$fail"

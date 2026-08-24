#!/usr/bin/env bash
# round-gate.sh <findings-file> [round] [cap] — deterministic round-exit decision.
# The findings file has one finding per line, starting with its severity tag:
#   CRITICAL: <summary>   HIGH: ...   MEDIUM: ...   LOW: ...   NIT: ...
# Verdicts (never model-decided):
#   done-clean   zero findings of any severity
#   stop-early   zero CRITICAL/HIGH — batch remaining LOW/NIT into a polish pass
#   continue     CRITICAL/HIGH present — another round required
#   escalate     CRITICAL/HIGH present but [round] >= [cap] (default 6) —
#                stop looping, put the open findings to the user
# Always exits 0; the verdict is the output. Pass the round number so the cap
# is enforced here rather than remembered in prose.
set -euo pipefail

F="${1:?usage: round-gate.sh <findings-file> [round] [cap]}"
ROUND="${2:-}"
CAP="${3:-6}"
[ -f "$F" ] || { echo "verdict=error"; echo "reason=findings file missing"; exit 0; }

# Colon-anchored: a finding body beginning "CRITICAL path analysis" must not
# count as a CRITICAL finding.
c=$(grep -c '^CRITICAL:' "$F" || true)
h=$(grep -c '^HIGH:' "$F" || true)
m=$(grep -c '^MEDIUM:' "$F" || true)
l=$(grep -c '^LOW:' "$F" || true)
n=$(grep -c '^NIT:' "$F" || true)

echo "critical=$c"; echo "high=$h"; echo "medium=$m"; echo "low=$l"; echo "nit=$n"

total=$((c + h + m + l + n))
if [ "$total" -eq 0 ]; then
  echo "verdict=done-clean"
elif [ $((c + h)) -eq 0 ]; then
  echo "verdict=stop-early"
elif [ -n "$ROUND" ] && [ "$ROUND" -ge "$CAP" ] 2>/dev/null; then
  echo "verdict=escalate"
  echo "reason=round $ROUND reached cap $CAP with CRITICAL/HIGH open"
else
  echo "verdict=continue"
fi

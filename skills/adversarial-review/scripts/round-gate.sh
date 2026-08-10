#!/usr/bin/env bash
# round-gate.sh <findings-file> — deterministic round-exit decision.
# The findings file has one finding per line, starting with its severity tag:
#   CRITICAL: <summary>   HIGH: ...   MEDIUM: ...   LOW: ...   NIT: ...
# Verdicts (never model-decided):
#   done-clean   zero findings of any severity
#   stop-early   zero CRITICAL/HIGH — batch remaining LOW/NIT into a polish pass
#   continue     CRITICAL/HIGH present — another round required
# Always exits 0; the verdict is the output.
set -euo pipefail

F="${1:?usage: round-gate.sh <findings-file>}"
[ -f "$F" ] || { echo "verdict=error"; echo "reason=findings file missing"; exit 0; }

c=$(grep -c '^CRITICAL' "$F" || true)
h=$(grep -c '^HIGH' "$F" || true)
m=$(grep -c '^MEDIUM' "$F" || true)
l=$(grep -c '^LOW' "$F" || true)
n=$(grep -c '^NIT' "$F" || true)

echo "critical=$c"; echo "high=$h"; echo "medium=$m"; echo "low=$l"; echo "nit=$n"

total=$((c + h + m + l + n))
if [ "$total" -eq 0 ]; then
  echo "verdict=done-clean"
elif [ $((c + h)) -eq 0 ]; then
  echo "verdict=stop-early"
else
  echo "verdict=continue"
fi

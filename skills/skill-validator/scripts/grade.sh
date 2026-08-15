#!/usr/bin/env bash
# grade.sh <findings-file> — deterministic grade from the findings ledger.
#
# TWO SHAPES REACH THE LEDGER and both must count. The model appends prose lines:
#   FAIL [phase]: message
#   WARN [phase]: message
#   SKIPPED [phase]: message   (ignored for grading, listed next to the grade)
# The validator scripts are piped in with `tee -a` and speak JSON:
#   {"status":"FAIL","check":"...","detail":"..."}
# Counting only the prose form graded a skill A while its own structural script
# reported two warnings on the same file — the scripts are the mechanical half of
# the grade, so dropping them silently is the one failure this file cannot have.
#
# Scale: A = 0 FAIL, <=2 WARN   (production-ready)
#        B = 0 FAIL, <=5 WARN
#        C = 1-2 FAIL
#        D = 3-5 FAIL
#        F = >5 FAIL
# INFO and PASS never count. Prints grade= fails= warns= skipped=. Always exits 0.
set -euo pipefail

F="${1:?usage: grade.sh <findings-file>}"
[ -f "$F" ] || { echo "grade=F"; echo "fails=1"; echo "warns=0"; echo "skipped=0"; echo "FAIL [grade]: findings file missing"; exit 0; }

count() { # $1 status — prose lines plus JSON objects carrying that status
  local n1 n2
  n1=$(grep -c "^$1" "$F" || true)
  n2=$(grep -o "\"status\":\"$1\"" "$F" | wc -l | tr -d ' ')
  echo $((n1 + n2))
}

fails=$(count FAIL)
warns=$(count WARN)
skipped=$(count SKIPPED)

if   [ "$fails" -eq 0 ] && [ "$warns" -le 2 ]; then grade=A
elif [ "$fails" -eq 0 ] && [ "$warns" -le 5 ]; then grade=B
elif [ "$fails" -le 2 ]; then grade=C
elif [ "$fails" -le 5 ]; then grade=D
else grade=F
fi

echo "grade=$grade"
echo "fails=$fails"
echo "warns=$warns"
echo "skipped=$skipped"

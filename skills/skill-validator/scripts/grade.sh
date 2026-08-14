#!/usr/bin/env bash
# grade.sh <findings-file> — deterministic grade from the findings ledger.
# Ledger format, one finding per line (scripts and the model both append):
#   FAIL [phase]: message
#   WARN [phase]: message
#   SKIPPED [phase]: message   (ignored for grading, listed next to the grade)
# Scale: A = 0 FAIL, <=2 WARN   (production-ready)
#        B = 0 FAIL, <=5 WARN
#        C = 1-2 FAIL
#        D = 3-5 FAIL
#        F = >5 FAIL
# Prints grade= fails= warns= skipped=. Always exits 0.
set -euo pipefail

F="${1:?usage: grade.sh <findings-file>}"
[ -f "$F" ] || { echo "grade=F"; echo "fails=1"; echo "warns=0"; echo "skipped=0"; echo "FAIL [grade]: findings file missing"; exit 0; }

fails=$(grep -c '^FAIL' "$F" || true)
warns=$(grep -c '^WARN' "$F" || true)
skipped=$(grep -c '^SKIPPED' "$F" || true)

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

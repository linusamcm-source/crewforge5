#!/usr/bin/env bash
# verify_rule_scoping.sh — prove that a `paths:`-scoped rule loads ONLY when a
# matching file is read.
#
#   verify_rule_scoping.sh [--model <id>]
#
# WHY THIS IS A SCRIPT AND NOT A BATS CASE. The whole rules design rests on one
# claim: a scoped rule costs nothing until it is relevant. That claim is about
# harness behaviour, so nothing short of a real session can test it — which is
# why it is NOT in CI and why the plugin's other 664 tests cannot cover it. It
# is the one assertion that has to be run by hand, so it ships as a script
# rather than as a sentence in a README nobody can check.
#
# METHOD. Build a throwaway repo with one rule scoped to `**/*.go`, an
# `InstructionsLoaded` hook that appends every load event to a file, one .go
# file and one .txt file. Run two headless sessions:
#   1. read the .txt  → the rule must NOT load   (a false positive costs every
#                        unrelated session the rule's whole body)
#   2. read the .go   → the rule MUST load       (a false negative means the
#                        convention silently never reaches the model)
# Both directions matter; asserting only the second would pass for a rule that
# loads unconditionally, which is the exact failure being ruled out.
#
# Requires the `claude` CLI on PATH. Exits 0 when both directions hold, 1 if
# either fails, 2 if the environment cannot run the probe.
set -uo pipefail

MODEL="claude-haiku-4-5-20251001"
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="${2:?--model needs an id}"; shift 2 ;;
    *) echo "usage: verify_rule_scoping.sh [--model <id>]" >&2; exit 2 ;;
  esac
done

command -v claude >/dev/null 2>&1 || { echo "SKIP: no \`claude\` CLI on PATH — this probe needs a real session"; exit 2; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
EVENTS="$TMP/events.jsonl"
REPO="$TMP/repo"
mkdir -p "$REPO/.claude/rules"

cat > "$REPO/.claude/rules/gotest.md" <<'EOF'
---
description: Go conventions for this repo.
paths: ["**/*.go"]
---

CANARY_RULE_LOADED_MARKER
EOF

printf 'package main\n\nfunc main() {}\n' > "$REPO/main.go"
printf 'plain notes, not source\n'        > "$REPO/notes.txt"

cat > "$REPO/.claude/settings.json" <<EOF
{
  "hooks": {
    "InstructionsLoaded": [
      { "hooks": [ { "type": "command", "command": "cat >> $EVENTS" } ] }
    ]
  }
}
EOF

probe() { # $1 = file to read; echoes the number of gotest.md load events
  : > "$EVENTS"
  (cd "$REPO" && claude -p --model "$MODEL" --permission-mode bypassPermissions \
     "Read the file $1 and say what it contains. Do nothing else." ) >/dev/null 2>&1
  # `grep -c` PRINTS 0 and EXITS 1 on no match, so `|| echo 0` would emit "0\n0"
  # and every arithmetic test downstream breaks. Guard with `|| true` instead —
  # the count grep already printed is the answer.
  grep -c 'rules/gotest.md' "$EVENTS" 2>/dev/null || true
}

echo "probing with $MODEL …"
non_matching="$(probe notes.txt)"
matching="$(probe main.go)"

echo "  reading notes.txt (no glob match): $non_matching load event(s) — expected 0"
echo "  reading main.go   (**/*.go match): $matching load event(s) — expected >=1"

fail=0
[ "$non_matching" -eq 0 ] || { echo "FAIL: the rule loaded on a NON-matching read — scoping is not holding, and every session pays for it"; fail=1; }
[ "$matching" -ge 1 ]     || { echo "FAIL: the rule did NOT load on a matching read — the convention never reaches the model"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "PASS: paths:-scoped rules load only on a matching read"
fi
exit "$fail"

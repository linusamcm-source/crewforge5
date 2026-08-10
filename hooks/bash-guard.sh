#!/usr/bin/env bash
# bash-guard.sh — PreToolUse(Bash) deny guard for the shell rules in CLAUDE.md.
#
# CLAUDE.md states two shell rules that a model can read and still forget:
# stage explicit paths rather than `git add -A`, and never run `find` from /
# or ~. Prose asks; this enforces. The rules stay documented there for the
# reasoning; the denial happens here so a lapse costs a retry, not a mess.
#
# Contract: reads a PreToolUse payload on stdin, prints a permissionDecision
# of "deny" with a reason when the command matches, and prints nothing at all
# otherwise (silence = defer to normal permission flow).
#
# FAIL OPEN. A guard that cannot parse its input must not block the session:
# every unexpected condition exits 0 silently. A missed denial is recoverable,
# a wedged shell is not.
set -u

payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

cmd="$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    pass
' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

deny() {
  python3 -c '
import json,sys
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":sys.argv[1]}}))
' "$1" 2>/dev/null
  exit 0
}

# Strip quoted spans before matching so a filename or commit message that merely
# mentions a pattern cannot trip the guard.
bare="$(printf '%s' "$cmd" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g')"

# 1. Wholesale staging. `git add .gitignore` and `git add -Ax` must NOT match,
#    so `.` and `-A` are anchored to a word end.
if printf '%s' "$bare" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*git[[:space:]]+add[[:space:]]+([^;&|]*[[:space:]])?(-A|--all|\.)([[:space:]]|$)'; then
  deny 'CLAUDE.md: stage explicit paths — `git add <file>`, never `git add -A` / `git add .`. Name the files this change touched. If you genuinely want everything, the user has to ask for it.'
fi

# 2. Unscoped find. Scoped roots (., ./x, "$REPO", relative paths) are fine;
#    only / and the home directory are refused.
if printf '%s' "$bare" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+(/|~|\$HOME)([[:space:]]|$)'; then
  deny 'CLAUDE.md: never run `find` from / or ~ — scope it to the project tree. Use the repo root, or Glob, which is faster and already scoped.'
fi

exit 0

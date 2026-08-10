#!/usr/bin/env bash
# repo_preflight.sh — sprint-watchdog Pre-Sprint Gates 1 & 2 in one pass.
#
# Replaces the two inline Bash snippets in SKILL.md (Gate 1 — Clean Working
# Tree, Gate 2 — Branch Sanity) with a single deterministic, read-only check.
# Verifies the working tree is clean and the current branch is not a protected
# integration branch before a sprint starts. Touches nothing; safe to re-run.
#
# Usage:
#   repo_preflight.sh [--repo <dir>] [--protected a,b,c] [--log-oneline N] [--json]
#
# Options:
#   --repo <dir>       repo to check (default: current directory)
#   --protected a,b,c  comma-list of protected branches
#                      (default: main,master,dev,develop)
#   --log-oneline N    include N recent commits in the report (default: 5)
#   --json             emit a JSON object instead of the text report
#
# Bypass env (documented in SKILL.md "Optional: Hook-Based Enforcement"):
#   SPRINT_WATCHDOG_ALLOW_DIRTY=1      treat a dirty tree as non-blocking
#   SPRINT_WATCHDOG_ALLOW_PROTECTED=1  treat a protected branch as non-blocking
#
# Exit codes:
#   0  clean tree AND safe branch (or blocking condition bypassed via env)
#   1  working tree dirty (uncommitted/untracked changes)
#   2  on a protected branch (only when tree is clean; dirty takes precedence)
#   3  not a git repository / setup error
#   64 usage error

set -euo pipefail

REPO="."
PROTECTED="main,master,dev,develop"
LOG_N=5
AS_JSON=0

usage() {
  cat <<'USAGE' >&2
usage: repo_preflight.sh [--repo <dir>] [--protected a,b,c] [--log-oneline N] [--json]
  Checks Gate 1 (clean tree) and Gate 2 (branch sanity). Read-only.
USAGE
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)        REPO="${2:-}"; shift 2 ;;
    --protected)   PROTECTED="${2:-}"; shift 2 ;;
    --log-oneline) LOG_N="${2:-}"; shift 2 ;;
    --json)        AS_JSON=1; shift ;;
    -h|--help)     usage ;;
    *)             printf '[warn] repo_preflight.sh: unknown arg: %s\n' "$1" >&2; usage ;;
  esac
done

[[ "$LOG_N" =~ ^[0-9]+$ ]] || { printf '[warn] --log-oneline must be an integer\n' >&2; usage; }

git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf '[fail] repo_preflight.sh: not a git repository: %s\n' "$REPO" >&2
  exit 3
}

DIRTY_FILES="$(git -C "$REPO" status --porcelain)"
DIRTY_COUNT="$(printf '%s' "$DIRTY_FILES" | grep -c . || true)"
BRANCH="$(git -C "$REPO" branch --show-current)"
UPSTREAM="$(git -C "$REPO" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo 'none')"
AHEAD=0
if [[ "$UPSTREAM" != "none" ]]; then
  AHEAD="$(git -C "$REPO" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
fi

# Protected branch match (exact, comma-list membership).
IS_PROTECTED="no"
case ",$PROTECTED," in
  *,"$BRANCH",*) [[ -n "$BRANCH" ]] && IS_PROTECTED="yes" ;;
esac

# Resolve verdict + exit code. Dirty precedence over protected. Env bypasses
# downgrade a blocking condition to a warning without changing what is reported.
CODE=0
VERDICT="OK"
if [[ "$DIRTY_COUNT" -gt 0 && -z "${SPRINT_WATCHDOG_ALLOW_DIRTY:-}" ]]; then
  CODE=1; VERDICT="BLOCKED: working tree dirty ($DIRTY_COUNT changed)"
elif [[ "$IS_PROTECTED" == "yes" && -z "${SPRINT_WATCHDOG_ALLOW_PROTECTED:-}" ]]; then
  CODE=2; VERDICT="BLOCKED: on protected branch '$BRANCH'"
fi

if [[ "$AS_JSON" -eq 1 ]]; then
  DIRTY_FILES="$DIRTY_FILES" BRANCH="$BRANCH" UPSTREAM="$UPSTREAM" \
  AHEAD="$AHEAD" DIRTY_COUNT="$DIRTY_COUNT" IS_PROTECTED="$IS_PROTECTED" \
  VERDICT="$VERDICT" CODE="$CODE" python3 <<'PY'
import json, os
files = [l for l in os.environ["DIRTY_FILES"].splitlines() if l]
out = {
    "branch": os.environ["BRANCH"],
    "upstream": os.environ["UPSTREAM"],
    "ahead": int(os.environ["AHEAD"]),
    "dirty_count": int(os.environ["DIRTY_COUNT"]),
    "dirty_files": files,
    "protected": os.environ["IS_PROTECTED"] == "yes",
    "verdict": os.environ["VERDICT"],
    "exit_code": int(os.environ["CODE"]),
}
print(json.dumps(out, sort_keys=True))
PY
else
  printf 'branch=%s upstream=%s ahead=%s dirty=%s protected=%s\n' \
    "${BRANCH:-<detached>}" "$UPSTREAM" "$AHEAD" "$DIRTY_COUNT" "$IS_PROTECTED"
  if [[ "$DIRTY_COUNT" -gt 0 ]]; then
    printf 'dirty files:\n%s\n' "$DIRTY_FILES"
  fi
  if [[ "$LOG_N" -gt 0 ]]; then
    printf 'recent commits:\n'
    git -C "$REPO" log --oneline -n "$LOG_N" 2>/dev/null || true
  fi
  printf 'PREFLIGHT: %s\n' "$VERDICT"
fi

exit "$CODE"

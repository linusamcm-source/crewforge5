#!/usr/bin/env bash
# team-sprint task verification — one implementation, two entry points.
#
#   (stdin, PostToolUse)      automatic guard on TaskUpdate
#   --verify-task <cwd>       same predicates, callable by sprint-watchdog Step B
#   --activate / --deactivate arm/disarm the guard for a sprint
#
# Vocabularies come from the skill's data/vocab.json — never restate role or
# severity lists here. A baked-in fallback keeps the guard working when the
# skill is absent, since fail-open matters more than vocabulary freshness.
#
# Design constraints:
#   - A hook cannot call tools. It verifies only what is in the TaskUpdate call
#     plus the filesystem. Policy judgement stays with the watchdog.
#   - FAIL OPEN, ALWAYS. A broken guard must never stall a sprint.
#   - INERT OUTSIDE SPRINTS. No state file => exit before doing any work.

set -uo pipefail

STATE_REL=".claude/scripts/sprint-watchdog/.sprint-active.json"
VOCAB="${TEAM_SPRINT_VOCAB:-$HOME/.claude/skills/team-sprint/assets/data/vocab.json}"
MAX_VIOLATIONS=200

trap 'exit 0' ERR
exit_clean() { exit 0; }

# --- vocabulary -------------------------------------------------------------
IMPL_ROLES="go-engineer ui-engineer fullstack-eng test-writer engineer developer"
REVIEW_ROLES="reviewer perf-auditor security-check spec-reviewer ui-architect ui-designer code-reviewer"
NAME_RE='^QG:|review|audit|critique'
TEST_PATTERNS='*_test.go *.test.ts *.test.tsx *.spec.ts *.spec.tsx *_test.py test_*.py *.bats'
SPRINTS_ROOT=".team-sprint/sprints"

load_vocab() {
  [ -r "$VOCAB" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local v
  v="$(jq -r '.roles.implementation | join(" ")' "$VOCAB" 2>/dev/null)" && [ -n "$v" ] && IMPL_ROLES="$v"
  v="$(jq -r '.roles.review | join(" ")' "$VOCAB" 2>/dev/null)" && [ -n "$v" ] && REVIEW_ROLES="$v"
  v="$(jq -r '.review_task_name_pattern // empty' "$VOCAB" 2>/dev/null)" && [ -n "$v" ] && NAME_RE="$v"
  v="$(jq -r '.test_file_patterns | join(" ")' "$VOCAB" 2>/dev/null)" && [ -n "$v" ] && TEST_PATTERNS="$v"
  v="$(jq -r '.artifact_patterns.sprints_root // empty' "$VOCAB" 2>/dev/null)" && [ -n "$v" ] && SPRINTS_ROOT="$v"
  return 0
}

is_in() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

matches_test_pattern() {
  local f="$1" p
  for p in $TEST_PATTERNS; do
    # shellcheck disable=SC2254
    case "$f" in $p) return 0 ;; esac
    case "$f" in */__tests__/*|*/tests/*) return 0 ;; esac
  done
  return 1
}

# verify <cwd> <role> <name> <story> <files-newline-separated>
# Prints "kind<TAB>detail" on violation; prints nothing when clean.
verify() {
  local cwd="$1" role="$2" name="$3" story="$4" files="$5"

  if is_in "$role" "$IMPL_ROLES"; then
    if [ -z "$files" ]; then
      printf 'impl_no_source_files\tno metadata.sourceFiles declared on completion\n'
      return 0
    fi
    local missing="" nontest="" f p
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in /*) p="$f" ;; *) p="$cwd/$f" ;; esac
      [ -e "$p" ] || missing="$missing $f"
      if [ "$role" = "test-writer" ] && ! matches_test_pattern "$f"; then
        nontest="$nontest $f"
      fi
    done <<<"$files"
    if [ -n "$missing" ]; then
      printf 'impl_missing_source_files\tdeclared but absent on disk:%s\n' "$missing"
      return 0
    fi
    if [ -n "$nontest" ]; then
      printf 'impl_test_writer_scope_creep\tRED phase is test-only, but touched:%s\n' "$nontest"
      return 0
    fi
    return 0
  fi

  if is_in "$role" "$REVIEW_ROLES" || printf '%s' "$name" | grep -qiE "$NAME_RE"; then
    # The artifact is the audit record — never the message log.
    local pat found=""
    if [ -n "$story" ]; then pat="reviews-${story}-round-*.md"; else pat="reviews-*.md"; fi
    if [ -d "$cwd/$SPRINTS_ROOT" ]; then
      found="$(find "$cwd/$SPRINTS_ROOT" -name "$pat" -type f 2>/dev/null | head -1 || true)"
    fi
    [ -n "$found" ] || printf 'review_no_artifact\tno %s under %s/\n' "$pat" "$SPRINTS_ROOT"
  fi
  return 0
}

# --- entry points -----------------------------------------------------------
case "${1:-}" in
  --activate)
    mkdir -p "$(dirname "$STATE_REL")" || exit 1
    [ -f "$STATE_REL" ] || printf '{"active":true,"violations":[]}\n' > "$STATE_REL"
    echo "sprint-watchdog guard armed: $STATE_REL"
    exit 0
    ;;
  --deactivate)
    rm -f "$STATE_REL" 2>/dev/null
    echo "sprint-watchdog guard disarmed"
    exit 0
    ;;
  --verify-task)
    # Watchdog Step B: pipe one task's JSON ({role,name,storyId,sourceFiles}).
    command -v jq >/dev/null 2>&1 || { echo '{"error":"jq missing"}'; exit 0; }
    load_vocab
    t="$(cat)" || exit_clean
    c="${2:-$PWD}"
    r="$(jq -r '.role // .metadata.role // empty' <<<"$t" 2>/dev/null)"
    n="$(jq -r '.name // empty' <<<"$t" 2>/dev/null)"
    s="$(jq -r '.storyId // .metadata.storyId // empty' <<<"$t" 2>/dev/null)"
    fl="$(jq -r '[.sourceFiles // .metadata.sourceFiles // empty] | flatten | .[]?' <<<"$t" 2>/dev/null)"
    out="$(verify "$c" "$r" "$n" "$s" "$fl")"
    if [ -z "$out" ]; then
      echo '{"clean":true}'
    else
      jq -nc --arg k "${out%%$'\t'*}" --arg d "${out#*$'\t'}" '{clean:false,kind:$k,detail:$d}'
    fi
    exit 0
    ;;
esac

# --- PostToolUse path -------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit_clean

input="$(cat)" || exit_clean
[ -n "$input" ] || exit_clean

tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)" || exit_clean
[ "$tool" = "TaskUpdate" ] || exit_clean

cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit_clean

state="$cwd/$STATE_REL"
[ -f "$state" ] || exit_clean   # inert unless a sprint armed the guard

status="$(jq -r '.tool_input.status // empty' <<<"$input" 2>/dev/null)"
[ "$status" = "completed" ] || exit_clean

load_vocab

task_id="$(jq -r '.tool_input.id // .tool_input.taskId // "unknown"' <<<"$input" 2>/dev/null)"
role="$(jq -r '.tool_input.metadata.role // empty' <<<"$input" 2>/dev/null)"
name="$(jq -r '.tool_input.name // .tool_input.description // empty' <<<"$input" 2>/dev/null)"
story="$(jq -r '.tool_input.metadata.storyId // .tool_input.metadata.story_id // empty' <<<"$input" 2>/dev/null)"
files="$(jq -r '[.tool_input.metadata.sourceFiles // empty] | flatten | .[]?' <<<"$input" 2>/dev/null)"

# TaskUpdate may carry only {id,status}; fall back to the fuller task echoed
# back in tool_response.
if [ -z "$role" ] || [ -z "$name" ]; then
  resp="$(jq -r 'if (.tool_response|type)=="string" then .tool_response else (.tool_response|tostring) end' <<<"$input" 2>/dev/null)"
  [ -z "$role" ] && role="$(jq -r '.metadata.role // empty' <<<"$resp" 2>/dev/null)"
  [ -z "$name" ] && name="$(jq -r '.name // empty' <<<"$resp" 2>/dev/null)"
fi

result="$(verify "$cwd" "$role" "$name" "$story" "$files")"
[ -n "$result" ] || exit_clean
kind="${result%%$'\t'*}"
detail="${result#*$'\t'}"

# --- atomic append (parallel executors update tasks concurrently) -----------
lock="$state.lock"
acquired=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if mkdir "$lock" 2>/dev/null; then acquired=1; break; fi
  sleep 0.1
done
[ -n "$acquired" ] || exit_clean
trap 'rmdir "$lock" 2>/dev/null; exit 0' EXIT ERR

tmp="$state.tmp.$$"
if jq --arg id "$task_id" --arg kind "$kind" --arg detail "$detail" \
      --arg role "$role" --arg n "$MAX_VIOLATIONS" \
      '.violations = ((.violations // []) + [{
          task_id: $id, kind: $kind, detail: $detail, role: $role
       }] | .[-($n|tonumber):])' \
      "$state" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$state" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
  exit_clean
fi

jq -n --arg kind "$kind" --arg detail "$detail" --arg id "$task_id" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse",
    additionalContext: ("sprint-watchdog: task \($id) marked completed but failed verification (\($kind)): \($detail). Fix the gap and re-complete; the watchdog will otherwise reopen this task.")}}'
exit 0

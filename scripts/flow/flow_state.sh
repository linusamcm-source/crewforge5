#!/usr/bin/env bash
# flow_state.sh — locked read-modify-write over <repo>/.crewforge/<flow>/state.json.
#
# Usage:
#   flow_state.sh <flow> path                  absolute path to state.json
#   flow_state.sh <flow> manifest              absolute path to phases.json
#   flow_state.sh <flow> get <key>             print one dotted key's value
#   flow_state.sh <flow> set <key> <value>...  write dotted key(s), repeatable
# Keys are dotted paths (phase.0.status); every value is stored as a string.
#
# Lifted from skills/team-sprint/scripts/state.sh, which owns exactly this
# read-modify-write with exactly these hazards, so that `init`, `plan` and
# `execute` share one driver instead of carrying three copies of it. <flow> is
# the first argument because that is the only thing that differs between them.
# team-sprint's own state.sh is deliberately NOT re-pointed here: its schema is
# sprint-specific (plan_of_record, worktree_path, iterations) and this driver's
# is not.
#
# WHY VALUES ARE ALWAYS STRINGS. Everything the driver itself records — a phase
# status, a gate's captured stdout — is text, and a single type means a caller
# never has to quote JSON into an argv slot to write "ok". The schema below
# enforces it, so a typed field cannot appear by accident and rot the contract.
#
# The tmp/lock handling is the one part worth reading twice: the three write
# paths mktemp a "${state}.tmp.XXXXXX" and mv it into place, and an interrupt
# BETWEEN those two steps used to leave a 0-byte orphan next to state.json
# because the EXIT trap cleared only the lockdir. _FLOW_TMP is deliberately NOT
# `local`, so the trap can see it, and holds this process's path only — never a
# glob, which would race a concurrent writer's tmp.
#
# Exit codes: 0 success, 1 error (schema violation, unset key, jq missing),
# 2 usage.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$HERE/subskill_resolve.sh"

log()  { printf '%s\n' "$*" >&2; }
fail() { printf '[fail] %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Locations.
# ---------------------------------------------------------------------------

# repo_root — the MAIN repo root, absolute and symlink-resolved. Derived from
# --git-common-dir rather than --show-toplevel so a call from a worktree CWD
# still lands on the shared repo, instead of minting a second .crewforge tree
# per worktree (the dual-artifact bug team-sprint fought four times).
repo_root() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || fail "flow_state.sh: not inside a git repository"
  (cd "$common/.." && pwd -P)
}

state_path() {
  printf '%s/.crewforge/%s/state.json\n' "$(repo_root)" "$1"
}

# manifest_path — <flow>/phases.json, found beside the SKILL.md that the Story 1
# resolver resolves. A flow IS a skill, so its manifest inherits the resolver's
# search order and `-`/`_` normalisation for free rather than re-deriving both.
manifest_path() {
  local flow="$1" skill manifest
  skill="$("$RESOLVE" "$flow" 2>/dev/null)" || {
    log "flow_state.sh: no skill resolves for flow \"$flow\" (needs skills/$flow/SKILL.md)"
    return 1
  }
  manifest="$(dirname "$skill")/phases.json"
  [ -f "$manifest" ] || { log "flow_state.sh: no phases.json beside $skill"; return 1; }
  printf '%s\n' "$manifest"
}

# ---------------------------------------------------------------------------
# Locking: flock(1) when present, mkdir mutex otherwise (macOS base install has
# no flock). Both wrap the same read-modify-write.
# ---------------------------------------------------------------------------
_with_lock() {
  local lockfile="$1"; shift
  local lockdir="${lockfile}.d"
  mkdir -p "$(dirname "$lockfile")"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lockfile"
    flock 9
    "$@"
    local rc=$?
    exec 9>&-
    return $rc
  fi
  local waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -gt 300 ]; then
      fail "flow_state.sh: timed out waiting for lock $lockdir"
    fi
  done
  trap 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_FLOW_TMP:-}" ] && rm -f "$_FLOW_TMP"; true' EXIT
  "$@"
  local rc=$?
  rmdir "$lockdir" 2>/dev/null || true
  trap - EXIT
  return $rc
}

# ---------------------------------------------------------------------------
# Schema — pure jq, no external validator, same as state.sh. Only the fields
# the driver reads are constrained; a flow may park whatever else it needs
# alongside them.
# ---------------------------------------------------------------------------
_validate() {
  local f="$1" err
  err="$(
    jq -e '
      def must(cond; msg): if cond then . else error(msg) end;

      must(type == "object"; "root must be object")
      | must(.flow       | type == "string"; "flow must be string")
      | must(.started_at | type == "string"; "started_at must be string")
      | must(.phase      | type == "object"; "phase must be object")
      | must(.phase | to_entries | all(.value | type == "object"); "each phase.<id> must be an object")
      | must(.phase | to_entries | all(.value | to_entries | all(.value | type == "string"));
             "each phase.<id>.<field> must be a string")
      | true
    ' "$f" 2>&1 >/dev/null
  )" || {
    printf 'flow_state.sh: schema violation: %s\n' "$err" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# set — repeatable <key> <value> pairs, applied in one locked pass so a gate
# recording status AND stdout cannot be observed half-written.
# ---------------------------------------------------------------------------
_key_path_json() {
  local key="$1"
  case "$key" in
    .*|*.|*..*|"") fail "flow_state.sh set: unsupported key path '$key'" ;;
  esac
  local parts part out="[" first=1 IFS_save="$IFS"
  IFS=.
  # shellcheck disable=SC2206
  parts=( $key )
  IFS="$IFS_save"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || fail "flow_state.sh set: empty path component in '$key'"
    if [ "$first" -eq 1 ]; then out="${out}\"${part}\""; first=0
    else out="${out},\"${part}\""; fi
  done
  printf '%s]\n' "$out"
}

_set_apply() {
  local state="$1" flow="$2"; shift 2
  # One name for every write path's tmp, because the leak guard is a grep:
  # `mktemp … ; _FLOW_TMP="$tmp"` and `mv … ; _FLOW_TMP=""` are counted and
  # compared, so a path that spells its tmp differently silently opts out.
  local tmp

  # Seed and write share one lock acquisition, so a gate recording status AND
  # stdout is never observed half-applied by a concurrent reader.
  if [ ! -f "$state" ]; then
    tmp="$(mktemp "${state}.tmp.XXXXXX")"; _FLOW_TMP="$tmp"
    jq --sort-keys -n \
      --arg flow "$flow" \
      --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{flow: $flow, started_at: $started_at, phase: {}}' > "$tmp"
    mv "$tmp" "$state"; _FLOW_TMP=""
  fi

  local jq_filter='.'
  local jq_args=()
  local idx=0 pj
  while [ $# -gt 0 ]; do
    pj="$(_key_path_json "$1")"
    jq_args+=( --arg "v$idx" "$2" --argjson "p$idx" "$pj" )
    jq_filter="${jq_filter} | setpath(\$p${idx}; \$v${idx})"
    idx=$((idx + 1))
    shift 2
  done

  tmp="$(mktemp "${state}.tmp.XXXXXX")"; _FLOW_TMP="$tmp"
  jq --sort-keys "${jq_args[@]}" "$jq_filter" "$state" > "$tmp"

  if ! _validate "$tmp"; then
    rm -f "$tmp"; _FLOW_TMP=""
    fail "flow_state.sh set: schema violation, state.json unchanged"
  fi

  mv "$tmp" "$state"; _FLOW_TMP=""
}

_cmd_set() {
  local flow="$1"; shift
  { [ $# -ge 2 ] && [ $(($# % 2)) -eq 0 ]; } || usage
  local state dir
  state="$(state_path "$flow")"
  dir="$(dirname "$state")"
  mkdir -p "$dir"
  _with_lock "$dir/.state.lock" _set_apply "$state" "$flow" "$@"
}

_cmd_get() {
  local flow="$1" key="$2"
  local state pj value
  state="$(state_path "$flow")"
  [ -f "$state" ] || { log "flow_state.sh get: $state missing"; exit 1; }
  pj="$(_key_path_json "$key")"
  # jq -e exits 1 when the result is null, which is exactly "unset" here — an
  # empty string is a value and still exits 0.
  value="$(jq -er --argjson p "$pj" 'getpath($p)' "$state" 2>/dev/null)" || {
    log "flow_state.sh get: $key is unset in $state"
    exit 1
  }
  printf '%s\n' "$value"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  command -v jq >/dev/null 2>&1 || fail "jq missing — install: brew install jq"
  local flow="${1:-}" sub="${2:-}"
  [ -n "$flow" ] && [ -n "$sub" ] || usage
  shift 2
  case "$sub" in
    path)     [ $# -eq 0 ] || usage; state_path "$flow" ;;
    manifest) [ $# -eq 0 ] || usage; manifest_path "$flow" ;;
    get)      [ $# -eq 1 ] || usage; _cmd_get "$flow" "$1" ;;
    set)      _cmd_set "$flow" "$@" ;;
    *)        usage ;;
  esac
}

main "$@"

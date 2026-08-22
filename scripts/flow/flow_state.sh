#!/usr/bin/env bash
# flow_state.sh — locked read-modify-write over <repo>/.crewforge5/<flow>/state.json.
#
# Usage:
#   flow_state.sh <flow> path                  absolute path to state.json
#   flow_state.sh <flow> manifest              absolute path to phases.json
#   flow_state.sh <flow> get <key>             print one dotted key's value
#   flow_state.sh <flow> set <key> <value>...  write dotted key(s), repeatable
#   flow_state.sh <flow> subject               the subject state is keyed by now
#   flow_state.sh <flow> use <subject>         point later calls at <subject>
#   flow_state.sh <flow> use --from <text>     …at a slug derived from <text>
#   flow_state.sh <flow> list                  every subject this flow has state for
#   flow_state.sh <flow> reset [<subject>]     discard one subject's state
# Keys are dotted paths (phase.0.status); every value is stored as a string.
#
# STATE IS KEYED BY SUBJECT, NOT BY FLOW ALONE. A flow runs against a thing —
# a plan, a config root — and a repo holds more than one of those over time.
# Keyed by flow alone, a finished run made `flow_next.sh` answer STATUS=DONE
# for the next subject before it had started, and restarting meant deleting
# state.json by hand. The subject is a slug resolved in this order:
#   1. $CREWFORGE5_SUBJECT
#   2. <repo>/.crewforge5/<flow>/current, written by `use`
#   3. "default"
# team-sprint reached the same conclusion first: its $ART is derived per plan
# slug, and `state.sh resume-scan` exists precisely to enumerate the several
# in-flight sprints one repo can hold.
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
# The tmp/lock handling is the one part worth reading twice: the write paths
# mktemp a "${state}.tmp.XXXXXX" and mv it into place, and an interrupt BETWEEN
# those two steps leaves a 0-byte orphan next to state.json unless an EXIT trap
# clears it. The trap therefore goes in above the flock/mkdir branch — inside
# either branch it would cover only one of the two CI hosts. _FLOW_TMP is
# deliberately NOT `local`, so the trap can see it, and holds this process's
# path only — never a glob, which would race a concurrent writer's tmp.
#
# Exit codes: 0 success, 1 error (schema violation, unset key, jq missing),
# 2 usage.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$HERE/subskill_resolve.sh"

log()  { printf '%s\n' "$*" >&2; }
fail() { printf '[fail] %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '5,12p' "$0" | sed 's/^# //' >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Locations.
# ---------------------------------------------------------------------------

# repo_root — the MAIN repo root, absolute and symlink-resolved. Derived from
# --git-common-dir rather than --show-toplevel so a call from a worktree CWD
# still lands on the shared repo, instead of minting a second .crewforge5 tree
# per worktree (the dual-artifact bug team-sprint fought four times).
repo_root() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || fail "flow_state.sh: not inside a git repository"
  (cd "$common/.." && pwd -P)
}

# flow_dir — <repo>/.crewforge5/<flow>, the per-flow root holding one directory
# per subject plus the `current` pointer.
flow_dir() {
  printf '%s/.crewforge5/%s\n' "$(repo_root)" "$1"
}

# subject_slug — the subject later calls are keyed by. Validated rather than
# trusted: the slug becomes a path component, so a `/` or a `..` in it would
# write outside the flow directory.
subject_slug() {
  local flow="$1" slug=""
  if [ -n "${CREWFORGE5_SUBJECT:-}" ]; then
    slug="$CREWFORGE5_SUBJECT"
  else
    local pointer
    pointer="$(flow_dir "$flow")/current"
    [ -f "$pointer" ] && IFS= read -r slug < "$pointer"
  fi
  [ -n "$slug" ] || slug="default"
  case "$slug" in
    *[!A-Za-z0-9._-]*|.|..|.*) fail "flow_state.sh: unusable subject \"$slug\" (want [A-Za-z0-9][A-Za-z0-9._-]*)" ;;
  esac
  printf '%s\n' "$slug"
}

state_path() {
  printf '%s/%s/state.json\n' "$(flow_dir "$1")" "$(subject_slug "$1")"
}

# _migrate_legacy — move a pre-subject <flow>/state.json under default/ once.
# An in-flight run must not lose its place because the layout changed, and a
# permanent two-location read path would have to be honoured by `list`, `reset`
# and every future reader forever. One guarded `mv` is the smaller debt. Called
# from main() for every subcommand that resolves state, so no caller can reach
# the new layout without it having run.
_migrate_legacy() {
  local flow="$1" dir legacy target
  dir="$(flow_dir "$flow")"
  legacy="$dir/state.json"
  target="$dir/default/state.json"
  [ -f "$legacy" ] || return 0
  [ -e "$target" ] && return 0
  mkdir -p "$dir/default"
  mv "$legacy" "$target"
  log "flow_state.sh: moved pre-subject state to $target"
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
  # Installed ABOVE the branch, not inside one: both lock paths mktemp, so a
  # trap that only one of them reaches leaks a 0-byte orphan on the other host
  # (flock is Linux/CI, the mkdir mutex is macOS). `rmdir` on the lockdir the
  # flock path never creates is a silent no-op, so one trap body serves both.
  trap 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_FLOW_TMP:-}" ] && rm -f "$_FLOW_TMP"; true' EXIT
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lockfile"
    flock 9
    "$@"
    local rc=$?
    exec 9>&-
    trap - EXIT
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
# subject management — use / list / reset
# ---------------------------------------------------------------------------
# _slugify — free text (a goal, a plan path, a config root) to a subject slug.
# Callers have the thing the run is ABOUT, not a slug for it, and three flows
# hand-rolling the same tr/sed pipeline in three phase docs is how they drift.
# Truncated to 48 chars: the slug is a directory name, and a whole goal sentence
# makes an unreadable one without making it more unique in practice.
_slugify() {
  local out
  out="$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' \
    | cut -c1-48 \
    | sed -e 's/-*$//')"
  [ -n "$out" ] || out="default"
  printf '%s\n' "$out"
}

_cmd_use() {
  local flow="$1" slug="$2" dir
  if [ "$slug" = "--from" ]; then
    [ $# -eq 3 ] || fail "flow_state.sh use --from: needs the text to slugify"
    slug="$(_slugify "$3")"
  fi
  case "$slug" in
    ""|*[!A-Za-z0-9._-]*|.|..|.*) fail "flow_state.sh use: unusable subject \"$slug\" (want [A-Za-z0-9][A-Za-z0-9._-]*)" ;;
  esac
  dir="$(flow_dir "$flow")"
  mkdir -p "$dir"
  printf '%s\n' "$slug" > "$dir/current"
  printf 'SUBJECT=%s\n' "$slug"
}

# _cmd_list — one line per subject, so a caller resuming a repo with several
# in-flight runs can see them without opening any state file. PASSED counts the
# phases already recorded pass; the manifest total is deliberately not joined in
# here, because `list` must answer for a flow whose manifest no longer resolves.
_cmd_list() {
  local flow="$1" dir current d slug passed started
  dir="$(flow_dir "$flow")"
  [ -d "$dir" ] || return 0
  current="$(subject_slug "$flow")"
  for d in "$dir"/*/; do
    [ -f "$d/state.json" ] || continue
    slug="$(basename "$d")"
    passed="$(jq -r '[(.phase // {}) | to_entries[] | select((.value.status // "") | ascii_downcase == "pass")] | length' "$d/state.json" 2>/dev/null)"
    case "$passed" in ''|*[!0-9]*) passed=0 ;; esac
    started="$(jq -r '.started_at // ""' "$d/state.json" 2>/dev/null)"
    if [ "$slug" = "$current" ]; then
      printf 'SUBJECT=%s CURRENT=yes PASSED=%s STARTED=%s\n' "$slug" "$passed" "$started"
    else
      printf 'SUBJECT=%s CURRENT=no PASSED=%s STARTED=%s\n' "$slug" "$passed" "$started"
    fi
  done
}

# _cmd_reset — discard one subject's state so the flow can be run again against
# it. The subject is named or current; the `current` pointer is left alone,
# because resetting the run you are on should not also change which run you are
# on. Removing nothing is not an error: reset is how a caller makes sure.
_cmd_reset() {
  local flow="$1" slug="${2:-}" dir
  [ -n "$slug" ] || slug="$(subject_slug "$flow")"
  case "$slug" in
    *[!A-Za-z0-9._-]*|.|..|.*) fail "flow_state.sh reset: unusable subject \"$slug\"" ;;
  esac
  dir="$(flow_dir "$flow")/$slug"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    printf 'RESET=%s\n' "$slug"
  else
    printf 'RESET=%s NOTHING=1\n' "$slug"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  command -v jq >/dev/null 2>&1 || fail "jq missing — install: brew install jq"
  local flow="${1:-}" sub="${2:-}"
  if [ -z "$flow" ] || [ -z "$sub" ]; then usage; fi
  shift 2
  # Every subcommand that resolves state runs the one-time layout migration
  # first, so an in-flight pre-subject run keeps its place. `manifest` is exempt:
  # it reads the plugin tree, never the repo's state.
  case "$sub" in
    manifest) ;;
    *)        _migrate_legacy "$flow" ;;
  esac

  case "$sub" in
    path)     [ $# -eq 0 ] || usage; state_path "$flow" ;;
    manifest) [ $# -eq 0 ] || usage; manifest_path "$flow" ;;
    subject)  [ $# -eq 0 ] || usage; subject_slug "$flow" ;;
    use)      { [ $# -eq 1 ] || [ $# -eq 2 ]; } || usage; _cmd_use "$flow" "$@" ;;
    list)     [ $# -eq 0 ] || usage; _cmd_list "$flow" ;;
    reset)    [ $# -le 1 ] || usage; _cmd_reset "$flow" "${1:-}" ;;
    get)      [ $# -eq 1 ] || usage; _cmd_get "$flow" "$1" ;;
    set)      _cmd_set "$flow" "$@" ;;
    *)        usage ;;
  esac
}

main "$@"

#!/usr/bin/env bash
# state.sh — read/modify/write of $ART/state.json with locking + schema check.
#
# Plan-of-record gate (FL6 — the reviewed plan must provably be the executed
# plan; obs 18983/18988):
#   record-plan <plan_path> <file>  stores plan_of_record.path and
#     plan_of_record.sha256 (64-hex SHA-256 of <file>) into state.json.
#   check-plan  <plan_path> <file>  recomputes and compares path AND content:
#     stdout STATUS=OK (exit 0), or STATUS=FAIL (exit 1) with the reason on
#     stderr — recorded vs actual hashes, `path-mismatch` when <file> is not
#     the recorded plan_of_record.path, or `no-record` when nothing was
#     recorded. Missing state.json exits 2 with no STATUS line (phase-2.md
#     documents that branch as STOP).
# SHA-256 via `shasum -a 256` (macOS base install) with `sha256sum` fallback
# (GNU-only).
#
# Workflow-run recording (WA4):
#   record-workflow <plan_path> <phase> <run_id>  pins the Workflow run id that
#     executed <phase> into workflow_runs.<phase> (string; latest run wins).
#
# Exit codes: 0 success / STATUS=OK; 1 failure (schema violation, check-plan
# FAIL, jq missing); 2 usage error or state.json missing.

set -euo pipefail

_STATE_SH_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$_STATE_SH_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Locking: prefer flock(1) when present; fall back to mkdir-based mutex on
# macOS (no flock in base install). Both wrap the same read-modify-write.
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
    if [[ $waited -gt 300 ]]; then
      fail "state.sh: timed out waiting for lock $lockdir"
    fi
  done
  # Also clear this process's in-flight tmp. The three write paths mktemp a
  # "${state}.tmp.XXXXXX" and mv it into place; an interrupt BETWEEN those two
  # steps left a 0-byte orphan next to state.json, because this trap only ever
  # removed the lockdir. The schema-reject paths already rm -f explicitly; the
  # gap was signal/interrupt only. _STATE_TMP is deliberately NOT `local` so the
  # trap can see it, and holds only this process's path -- never a glob, which
  # would race a concurrent writer's tmp.
  trap 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_STATE_TMP:-}" ] && rm -f "$_STATE_TMP"; true' EXIT
  "$@"
  local rc=$?
  rmdir "$lockdir" 2>/dev/null || true
  trap - EXIT
  return $rc
}

# ---------------------------------------------------------------------------
# Schema validation — pure jq (no external validator). Returns 0 if valid.
# Error message on stderr describes which field broke.
# ---------------------------------------------------------------------------
_validate_state() {
  local f="$1"
  local err
  err="$(
    jq -e '
      def must(cond; msg): if cond then . else error(msg) end;

      must(type == "object"; "root must be object")
      | must(.plan_path     | type == "string"; "plan_path must be string")
      | must(.plan_slug     | type == "string"; "plan_slug must be string")
      | must(.worktree_name | type == "string"; "worktree_name must be string")
      | must(.target_branch | type == "string"; "target_branch must be string")
      | must(.worktree_path | type == "string"; "worktree_path must be string")
      | must(.artifact_dir  | type == "string"; "artifact_dir must be string")
      | must(.started_at    | type == "string"; "started_at must be string")
      | must((.current_phase | type == "number" and . == (. | floor)) or (.current_phase == "execute"); "current_phase must be integer or the string \"execute\"")
      | must(.repo_root     | type == "string"; "repo_root must be string")
      | must(.iterations    | type == "object"; "iterations must be object")
      | must(.iterations.adversarial | type == "number" and . == (. | floor); "iterations.adversarial must be integer")
      | must(.iterations.coverage    | type == "number" and . == (. | floor); "iterations.coverage must be integer")
      | must(.iterations.review_fix  | type == "number" and . == (. | floor); "iterations.review_fix must be integer")
      | must((has("plan_of_record") | not)
             or ((.plan_of_record | type == "object")
                 and (.plan_of_record.path | type == "string")
                 and (.plan_of_record.sha256 | type == "string" and test("^[0-9a-f]{64}$")));
             "plan_of_record must carry string path + 64-hex sha256")
      | must((.done // false)    | type == "boolean"; "done must be boolean")
      | must((.subskill_hooks // []) | type == "array"; "subskill_hooks must be array")
      | must((.story_commits // []) | type == "array"; "story_commits must be array")
      | must((.gates // []) | type == "array"; "gates must be array")
      | must((has("workflow_runs") | not) or ((.workflow_runs | type == "object") and (.workflow_runs | to_entries | all(.value | type == "string"))); "workflow_runs must be an object of string values")
      | must((.scheduling != "graph") or (.graph_path   | type == "string"); "graph_path must be a string when scheduling==graph")
      | must((.scheduling != "graph") or (.sprint_branch | type == "string"); "sprint_branch must be a string when scheduling==graph")
      | true
    ' "$f" 2>&1 >/dev/null
  )" || {
    printf 'state.sh: schema violation: %s\n' "$err" >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Per-plan paths.
# ---------------------------------------------------------------------------
_state_paths() {
  local plan_path="$1"
  local art
  art="$(art_dir "$plan_path")"
  STATE_JSON="$art/state.json"
  STATE_LOCK="$art/.state.lock"
}

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
_cmd_init() {
  local plan_path="$1"
  local target_branch="$2"
  local worktree_name="$3"

  local root
  # Main-repo root via lib.sh repo_root (NOT --show-toplevel): calls from a
  # worktree CWD must resolve to the shared main repo (CC-1). --show-toplevel
  # returns the worktree root and created dual artifact locations (bug recurred
  # 2026-05-20/27, 06-09/10).
  root="$(repo_root)"

  local sprint_dir
  sprint_dir="$("$SCRIPTS/validate_plan_path.sh" --slug-only "$plan_path" \
                 | awk -F= '$1=="SPRINT_DIR"{print $2}')"
  [[ -n "$sprint_dir" ]] || fail "state.sh init: could not derive SPRINT_DIR from $plan_path"

  local plan_slug
  plan_slug="$("$SCRIPTS/validate_plan_path.sh" --slug-only "$plan_path" \
                 | awk -F= '$1=="SLUG"{print $2}')"

  local art="$root/$sprint_dir"
  local state="$art/state.json"

  if [[ -f "$state" ]]; then
    local existing_done
    existing_done="$(jq -r '.done // false' "$state" 2>/dev/null || echo false)"
    [[ "$existing_done" == "true" ]] || \
      fail "state.sh init: $state exists with done != true (refusing to clobber)"
  fi

  mkdir -p "$art"

  local started_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local worktree_path
  worktree_path="../$(basename "$root")-$worktree_name"

  local tmp
  tmp="$(mktemp "${state}.tmp.XXXXXX")"; _STATE_TMP="$tmp"
  jq --sort-keys -n \
    --arg plan_path     "$plan_path" \
    --arg plan_slug     "$plan_slug" \
    --arg worktree_name "$worktree_name" \
    --arg target_branch "$target_branch" \
    --arg worktree_path "$worktree_path" \
    --arg artifact_dir  "$art" \
    --arg started_at    "$started_at" \
    --arg repo_root     "$root" \
    '{
      plan_path:     $plan_path,
      plan_slug:     $plan_slug,
      worktree_name: $worktree_name,
      target_branch: $target_branch,
      worktree_path: $worktree_path,
      artifact_dir:  $artifact_dir,
      started_at:    $started_at,
      current_phase: 0,
      iterations:    {adversarial: 0, coverage: 0, review_fix: 0},
      repo_root:     $repo_root
    }' > "$tmp"

  mv "$tmp" "$state"; _STATE_TMP=""

  if ! _validate_state "$state"; then
    rm -f "$state"
    fail "state.sh init: post-write schema validation failed, deleted half-written $state"
  fi

  printf '%s\n' "$state"
}

# ---------------------------------------------------------------------------
# read
# ---------------------------------------------------------------------------
_cmd_read() {
  local plan_path="$1"
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh read: $STATE_JSON missing"; exit 2; }
  cat "$STATE_JSON"
}

# ---------------------------------------------------------------------------
# update — repeatable <key>=<json-value> args
# ---------------------------------------------------------------------------
_update_apply() {
  local state="$1"; shift
  local tmp
  tmp="$(mktemp "${state}.tmp.XXXXXX")"; _STATE_TMP="$tmp"

  local jq_filter='.'
  local jq_args=()
  local idx=0
  local kv key json_value

  for kv in "$@"; do
    [[ "$kv" == *=* ]] || fail "state.sh update: bad pair '$kv' (need key=value)"
    key="${kv%%=*}"
    json_value="${kv#*=}"

    if printf '%s' "$key" | grep -qE '(^\.|\.$|\.\.|^$)'; then
      fail "state.sh update: unsupported character in key path '$key'"
    fi

    local parts part path_json="["
    local first=1
    local IFS_save="$IFS"
    IFS=.
    # shellcheck disable=SC2206
    parts=( $key )
    IFS="$IFS_save"

    for part in "${parts[@]}"; do
      [[ -n "$part" ]] || fail "state.sh update: empty path component in '$key'"
      if [[ "$first" -eq 1 ]]; then
        path_json="${path_json}\"${part}\""
        first=0
      else
        path_json="${path_json},\"${part}\""
      fi
    done
    path_json="${path_json}]"

    if ! printf '%s' "$json_value" | jq empty >/dev/null 2>&1; then
      fail "state.sh update: value for '$key' is not valid JSON: $json_value"
    fi

    jq_args+=( --argjson "v$idx" "$json_value" --argjson "p$idx" "$path_json" )
    jq_filter="${jq_filter} | setpath(\$p${idx}; \$v${idx})"
    idx=$((idx + 1))
  done

  jq --sort-keys "${jq_args[@]}" "$jq_filter" "$state" > "$tmp"

  if ! _validate_state "$tmp"; then
    rm -f "$tmp"
    fail "state.sh update: schema violation, state.json unchanged"
  fi

  mv "$tmp" "$state"; _STATE_TMP=""
}

_cmd_update() {
  local plan_path="$1"; shift
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh update: $STATE_JSON missing"; exit 2; }
  _with_lock "$STATE_LOCK" _update_apply "$STATE_JSON" "$@"
}

# ---------------------------------------------------------------------------
# record-plan / check-plan — plan-of-record gate (FL6).
# Phase 1 records plan-final.md at promotion; the Phase 2 entry gate checks it
# so the reviewed plan is provably the executed plan (obs 18983/18988).
# ---------------------------------------------------------------------------

# _sha256_file <file> — echo the 64-hex SHA-256 of <file>.
# `shasum -a 256` first (macOS base install; `sha256sum` is GNU-only).
_sha256_file() {
  local f="$1" out
  if command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$f")"
  elif command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$f")"
  else
    fail "state.sh: neither shasum nor sha256sum on PATH"
  fi
  printf '%s\n' "${out%% *}"
}

_cmd_record_plan() {
  local plan_path="$1" file="$2"
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh record-plan: $STATE_JSON missing"; exit 2; }
  [[ -f "$file" ]] || fail "state.sh record-plan: $file does not exist"

  local sha por
  sha="$(_sha256_file "$file")"
  por="$(jq -n --arg p "$file" --arg s "$sha" '{path: $p, sha256: $s}')"
  _with_lock "$STATE_LOCK" _update_apply "$STATE_JSON" "plan_of_record=$por"
}

# _canon_path <file> — echo <file> with its directory resolved to an absolute
# physical path (pwd -P: symlinks + relative segments collapsed), so the
# recorded-vs-argument path compare is not fooled by equivalent spellings of
# the same file. Echoes the raw path when the directory does not resolve
# (deleted/moved dir) — the caller then falls back to a literal compare.
_canon_path() {
  local p="$1" d
  if d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)"; then
    printf '%s/%s\n' "$d" "$(basename "$p")"
  else
    printf '%s\n' "$p"
  fi
}

_cmd_check_plan() {
  local plan_path="$1" file="$2"
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh check-plan: $STATE_JSON missing"; exit 2; }

  local recorded recorded_path
  recorded="$(jq -r '.plan_of_record.sha256 // ""' "$STATE_JSON")"
  recorded_path="$(jq -r '.plan_of_record.path // ""' "$STATE_JSON")"
  if [[ -z "$recorded" ]]; then
    log "state.sh check-plan: no-record — no plan_of_record in $STATE_JSON (an unrecorded plan is not a pass)"
    printf 'STATUS=FAIL\n'
    exit 1
  fi

  if [[ ! -f "$file" ]]; then
    log "state.sh check-plan: $file does not exist (recorded: $recorded)"
    printf 'STATUS=FAIL\n'
    exit 1
  fi

  # Path check: the gate's assurance is "same file", not merely "same bytes" —
  # a byte-identical copy at a different path is not the plan of record.
  if [[ "$(_canon_path "$file")" != "$(_canon_path "$recorded_path")" ]]; then
    log "state.sh check-plan: path-mismatch — $file is not the recorded plan_of_record.path"
    log "  recorded: $recorded_path"
    log "  checked:  $file"
    printf 'STATUS=FAIL\n'
    exit 1
  fi

  local actual
  actual="$(_sha256_file "$file")"
  if [[ "$actual" == "$recorded" ]]; then
    printf 'STATUS=OK\n'
    return 0
  fi
  log "state.sh check-plan: hash mismatch for $file"
  log "  recorded: $recorded"
  log "  actual:   $actual"
  printf 'STATUS=FAIL\n'
  exit 1
}

# ---------------------------------------------------------------------------
# record-workflow — workflow-run recording (WA4).
# Pins the Workflow run id that executed a phase into workflow_runs.<phase>,
# so a resumed sprint can find the run that produced its artifacts. Thin
# wrapper over the dotted update path; latest run for a phase wins.
# ---------------------------------------------------------------------------
_cmd_record_workflow() {
  local plan_path="$1" phase="$2" run_id="$3"
  # Validate run_id before touching any state: non-empty, and composed solely
  # of [A-Za-z0-9._-]. Deliberately no shape regex beyond the charset (plan-
  # pinned) — run-id formats are the Workflow tool's business, not ours.
  if [[ -z "$run_id" || "$run_id" == *[!A-Za-z0-9._-]* ]]; then
    log "usage: state.sh record-workflow <plan_path> <phase> <run_id>"
    fail "state.sh record-workflow: run_id must be non-empty and match [A-Za-z0-9._-]"
  fi
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh record-workflow: $STATE_JSON missing"; exit 2; }
  # _update_apply requires the value to parse as JSON; wrap the run id in
  # literal quotes so scalar-shaped ids (1.5, true) are stored as STRINGS.
  # Safe without jq encoding: the charset above excludes '"' and '\'.
  _with_lock "$STATE_LOCK" _update_apply "$STATE_JSON" "workflow_runs.${phase}=\"${run_id}\""
}

# ---------------------------------------------------------------------------
# advance-phase
# ---------------------------------------------------------------------------
_cmd_advance_phase() {
  local plan_path="$1"
  local n="$2"
  local force="${3:-}"
  _state_paths "$plan_path"
  [[ -f "$STATE_JSON" ]] || { log "state.sh advance-phase: $STATE_JSON missing"; exit 2; }

  _advance_apply() {
    local state="$1" target="$2" force="$3"
    local cur
    cur="$(jq -r '.current_phase' "$state")"
    local target_json
    if [[ "$target" == "execute" ]]; then
      # entering the graph-mode wave loop; no integer +1 invariant applies.
      target_json='"execute"'
    else
      target_json="$target"
      # Enforce the +1 invariant only when the current phase is numeric.
      # Coming out of "execute" (non-numeric) into an integer phase (e.g. 7)
      # has no arithmetic predecessor, so the invariant is skipped there.
      if [[ "$force" != "--force" && "$cur" =~ ^[0-9]+$ ]]; then
        if [[ "$target" != "$((cur + 1))" ]]; then
          fail "state.sh advance-phase: target $target != current+1 ($cur+1); pass --force to override"
        fi
      fi
    fi
    local tmp
    tmp="$(mktemp "${state}.tmp.XXXXXX")"; _STATE_TMP="$tmp"
    jq --sort-keys --argjson n "$target_json" '.current_phase = $n' "$state" > "$tmp"
    if ! _validate_state "$tmp"; then
      rm -f "$tmp"
      fail "state.sh advance-phase: schema violation"
    fi
    mv "$tmp" "$state"; _STATE_TMP=""
  }

  _with_lock "$STATE_LOCK" _advance_apply "$STATE_JSON" "$n" "$force"
}

# ---------------------------------------------------------------------------
# resume-scan
# ---------------------------------------------------------------------------
_cmd_resume_scan() {
  local root
  # Main-repo root via lib.sh repo_root (NOT --show-toplevel): calls from a
  # worktree CWD must resolve to the shared main repo (CC-1). --show-toplevel
  # returns the worktree root and created dual artifact locations (bug recurred
  # 2026-05-20/27, 06-09/10).
  root="$(repo_root)"
  local base="$root/.team-sprint/sprints"
  if [[ ! -d "$base" ]]; then
    printf '[]\n'
    return 0
  fi

  local files=()
  local f
  while IFS= read -r f; do
    files+=( "$f" )
  done < <(find "$base" -mindepth 2 -maxdepth 2 -name state.json -type f 2>/dev/null | sort)

  if [[ "${#files[@]}" -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi

  # Validate each file individually first. A single malformed state.json passed
  # into a `jq -s` slurp makes jq exit non-zero, which under `set -euo pipefail`
  # would abort discovery of EVERY in-flight sprint. Skip the bad file with a
  # warning and keep scanning; fall back to [] only when none remain valid.
  local valid=()
  for f in "${files[@]}"; do
    if jq -e . "$f" >/dev/null 2>&1; then
      valid+=( "$f" )
    else
      printf 'state.sh: skipping malformed state.json: %s\n' "$f" >&2
    fi
  done

  if [[ "${#valid[@]}" -eq 0 ]]; then
    printf '[]\n'
    return 0
  fi

  jq --sort-keys -s '
    map(select((.done // false) != true)
        | {slug:          .plan_slug,
           plan_path:     .plan_path,
           current_phase: .current_phase,
           started_at:    .started_at})
  ' "${valid[@]}"
}

# ---------------------------------------------------------------------------
# main dispatch
# ---------------------------------------------------------------------------
usage() {
  cat <<'USAGE' >&2
usage: state.sh <subcommand> [args]
  init  <plan_path> <target_branch> <worktree_name>
  read  <plan_path>
  update <plan_path> <key>=<json-value> [<key>=<json-value> ...]
  record-plan <plan_path> <file>
  check-plan  <plan_path> <file>
  record-workflow <plan_path> <phase> <run_id>
  advance-phase <plan_path> <N> [--force]
  resume-scan
  art-dir <plan_path>
USAGE
  exit 2
}

main() {
  # jq underpins every subcommand's read/validate path; probe once here (house
  # guard from lib.sh) instead of dying mid-subcommand with a raw 127.
  require_jq || exit 1
  local sub="${1:-}"
  [[ -n "$sub" ]] || usage
  shift
  case "$sub" in
    init)
      [[ $# -eq 3 ]] || usage
      _cmd_init "$@"
      ;;
    read)
      [[ $# -eq 1 ]] || usage
      _cmd_read "$@"
      ;;
    update)
      [[ $# -ge 2 ]] || usage
      _cmd_update "$@"
      ;;
    record-plan)
      [[ $# -eq 2 ]] || usage
      _cmd_record_plan "$@"
      ;;
    check-plan)
      [[ $# -eq 2 ]] || usage
      _cmd_check_plan "$@"
      ;;
    record-workflow)
      [[ $# -eq 3 ]] || usage
      _cmd_record_workflow "$@"
      ;;
    advance-phase)
      [[ $# -ge 2 && $# -le 3 ]] || usage
      _cmd_advance_phase "$@"
      ;;
    resume-scan)
      [[ $# -eq 0 ]] || usage
      _cmd_resume_scan
      ;;
    art-dir)
      # Echo $ART for a plan. Exists so the lead never has to `source lib.sh`
      # from its own shell (zsh has no BASH_SOURCE; sourcing lib.sh there
      # mis-resolves $SCRIPTS). Executed scripts always run under bash.
      [[ $# -eq 1 ]] || usage
      art_dir "$1"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"

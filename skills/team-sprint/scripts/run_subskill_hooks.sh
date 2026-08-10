#!/usr/bin/env bash
# shellcheck shell=bash
# run_subskill_hooks.sh — invoke user-declared sub-skill hooks for one phase.
#
# Reads the merged hook list from $ART/state.json.subskill_hooks (written by
# Phase 0 step 10), filters by the phase arg, and runs each entry's `command`
# in declaration order with the TS_* contract env vars set, in the worktree
# directory. Captured stdout+stderr is APPENDED to $ART/subskill-<phase>.log.
#
# Fail-soft: every hook command runs; non-zero exits are logged but never
# propagate. This script ALWAYS exits 0 unless its own args are malformed.
#
# Usage:
#   run_subskill_hooks.sh <phase> <plan_path>
#   run_subskill_hooks.sh --phase <phase> --plan-path <plan_path>
#
# <phase> is the integer 0|2|3|4|6|7 (or the string "phase-N"); the script
# normalises both forms. Phases 1 and 5 are RESERVED — invoking the script
# for those phases is a no-op (no commands run; log line emitted).
#
# Contract env vars exported to each hook command:
#   TS_PLAN_PATH  — absolute path to the plan file
#   TS_STORY_ID   — current story id (from state.json.current_story_id; "" if unset)
#   TS_TASK_ID    — phase-N task identifier (e.g. "phase-6")
#   TS_ART_DIR    — absolute $ART for this sprint
#   TS_WORKTREE   — absolute worktree path (from state.json.worktree_path)
#
# Namespace invariant: all hook env vars stay under TS_*. Adding a new one
# requires bumping state.schema.json + $REF/subskill-hooks.md.

set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_HERE/lib.sh"

usage() {
  cat <<'USAGE' >&2
usage: run_subskill_hooks.sh <phase> <plan_path>
       run_subskill_hooks.sh --phase <phase> --plan-path <plan_path>
USAGE
  exit 2
}

PHASE=""
PLAN_PATH=""

# Accept positional or flagged form (positional is the canonical contract;
# flagged form is kept so phase-6/phase-7 prose stays untouched).
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)     [[ $# -ge 2 ]] || usage; PHASE="$2"; shift 2 ;;
    --plan-path) [[ $# -ge 2 ]] || usage; PLAN_PATH="$2"; shift 2 ;;
    -h|--help)   usage ;;
    --*)         usage ;;
    *)
      if [[ -z "$PHASE" ]]; then
        PHASE="$1"; shift
      elif [[ -z "$PLAN_PATH" ]]; then
        PLAN_PATH="$1"; shift
      else
        usage
      fi
      ;;
  esac
done

[[ -n "$PHASE" && -n "$PLAN_PATH" ]] || usage

# Normalise PHASE: "6" → "phase-6"; "phase-6" → "phase-6"; reject anything else.
if [[ "$PHASE" =~ ^[0-9]+$ ]]; then
  PHASE_KEY="phase-$PHASE"
elif [[ "$PHASE" =~ ^phase-[0-9]+$ ]]; then
  PHASE_KEY="$PHASE"
else
  printf 'run_subskill_hooks.sh: bad --phase value %q (need integer or phase-N)\n' "$PHASE" >&2
  exit 2
fi

require_jq || exit 1

ART="$(art_dir "$PLAN_PATH")"
STATE="$ART/state.json"
LOG="$ART/subskill-${PHASE_KEY}.log"

mkdir -p "$ART"

# No state.json yet → nothing to do, exit clean.
if [[ ! -f "$STATE" ]]; then
  printf '[%s] %s: state.json not found at %s; skipping hooks\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY" "$STATE" >> "$LOG"
  exit 0
fi

# Filter to hooks for this phase, preserving declaration order.
HOOKS_JSON="$(jq -c --arg p "$PHASE_KEY" '
  (.subskill_hooks // []) | map(select(.phase == $p))
' "$STATE" 2>/dev/null || echo '[]')"

COUNT="$(printf '%s' "$HOOKS_JSON" | jq 'length')"

{
  printf '[%s] %s: %s hook(s) to run\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY" "$COUNT"
} >> "$LOG"

# Reserved phases never run anything.
case "$PHASE_KEY" in
  phase-1|phase-5)
    {
      printf '[%s] %s: reserved phase (no hooks run in v1.0)\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY"
    } >> "$LOG"
    exit 0
    ;;
esac

if [[ "$COUNT" -eq 0 ]]; then
  exit 0
fi

# Pull TS_* contract values out of state.json. Missing fields → empty string.
TS_PLAN_PATH_VAL="$PLAN_PATH"
TS_ART_DIR_VAL="$ART"
TS_STORY_ID_VAL="$(jq -r '.current_story_id // ""' "$STATE")"
TS_WORKTREE_VAL="$(jq -r '.worktree_path // ""' "$STATE")"
TS_TASK_ID_VAL="$PHASE_KEY"

# Resolve worktree to absolute (state may persist a relative path).
if [[ -n "$TS_WORKTREE_VAL" && "$TS_WORKTREE_VAL" != /* ]]; then
  REPO_ROOT="$(jq -r '.repo_root // ""' "$STATE")"
  if [[ -n "$REPO_ROOT" ]]; then
    TS_WORKTREE_VAL="$(cd "$REPO_ROOT" && cd "$TS_WORKTREE_VAL" 2>/dev/null && pwd -P || echo "$REPO_ROOT/$TS_WORKTREE_VAL")"
  fi
fi

# CWD for hook commands: worktree if available + reachable, otherwise $ART.
HOOK_CWD="$TS_WORKTREE_VAL"
if [[ -z "$HOOK_CWD" || ! -d "$HOOK_CWD" ]]; then
  HOOK_CWD="$ART"
fi

export TS_PLAN_PATH="$TS_PLAN_PATH_VAL"
export TS_STORY_ID="$TS_STORY_ID_VAL"
export TS_TASK_ID="$TS_TASK_ID_VAL"
export TS_ART_DIR="$TS_ART_DIR_VAL"
export TS_WORKTREE="$TS_WORKTREE_VAL"

# Iterate hooks: read one entry per line of jq -c output.
# We don't bail on a single failure — every hook runs.
idx=0
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  skill="$(printf '%s' "$entry"   | jq -r '.skill   // ""')"
  command_str="$(printf '%s' "$entry" | jq -r '.command // ""')"

  if [[ -z "$command_str" ]]; then
    {
      printf '[%s] %s hook[%d] skill=%s: empty command, skipping\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY" "$idx" "$skill"
    } >> "$LOG"
    idx=$((idx + 1))
    continue
  fi

  {
    printf '[%s] %s hook[%d] skill=%s START\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY" "$idx" "$skill"
  } >> "$LOG"

  # Run the command in a subshell, cd'd into HOOK_CWD, merging stderr→stdout
  # and appending to the log. Errexit is disabled inside so a hook failure
  # is captured, never propagated.
  (
    set +e
    cd "$HOOK_CWD" 2>/dev/null || cd "$ART" || exit 1
    bash -c "$command_str"
    exit $?
  ) >> "$LOG" 2>&1
  rc=$?

  {
    printf '[%s] %s hook[%d] skill=%s END rc=%d\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE_KEY" "$idx" "$skill" "$rc"
  } >> "$LOG"

  idx=$((idx + 1))
done < <(printf '%s' "$HOOKS_JSON" | jq -c '.[]')

exit 0

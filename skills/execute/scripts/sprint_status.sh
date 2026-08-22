#!/usr/bin/env bash
# sprint_status.sh — answer who owns `crewforge5:execute`'s phase progress.
#
# Usage:
#   sprint_status.sh              PHASE=<id> [DONE=1] for the sprint under way
#   sprint_status.sh --mode       graph | sequential — the scheduling this run walks
# stdout is KEY=VALUE; anything explanatory goes to stderr.
#
# WHY THIS EXISTS. `execute` wraps team-sprint, and team-sprint has tracked
# sprint progress since long before the shared flow driver did: current_phase,
# current_story_id, story_commits[], iterations{}, a `done` flag, and under
# `scheduling: graph` a whole node lifecycle in graph.json with its own resume.
# Keeping a second, coarser copy of that in .crewforge5/execute/state.json meant
# two sources of truth for one sprint, no story dimension at all (flow_next.sh
# filters on phase status, so nothing could send it back to Phase 3 for story 2),
# and a per-repo key where team-sprint's is per-plan. This script is the other
# direction: for the phases team-sprint owns, the driver ASKS it.
#
# The mapping onto flow_next.sh's `status_source` contract:
#   current_phase: <N>       -> PHASE=<N>          phases before N are passed
#   current_phase: "execute" -> PHASE=execute      the graph-mode wave loop
#   done: true               -> DONE=1             phase 7 is passed too
#
# NO OPINION IS A VALID ANSWER, and exiting non-zero is how it is given. Before
# Phase 0 records the plan and team-sprint inits its own state there is nothing
# to ask, and flow_next.sh then falls back to the driver's state alone — which
# is exactly right for phases 0 and 1, and for phases 8 and 9 that team-sprint
# has never heard of.
#
# Exit codes: 0 answered, 1 no opinion (no plan, no sprint state, unreadable).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${CREWFORGE5_ROOT:-$(cd "$HERE/../../.." && pwd -P)}"
RESOLVE="$ROOT/scripts/flow/subskill_resolve.sh"
FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"

usage() { sed -n '4,8p' "$0" | sed 's/^# //' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || exit 1

ts_dir() {
  local p
  p="$(bash "$RESOLVE" team-sprint 2>/dev/null)" || return 1
  dirname "$p"
}

# --mode — the scheduling this run walks. Resolution order matters:
#
#   1. `current_phase == "execute"` in the sprint's own state. team-sprint sets
#      that string in graph mode and nowhere else, so it is the strongest
#      evidence there is — and checking it first is what keeps the two probes
#      consistent: without it the status source can name the wave-loop phase
#      while `when` has excluded it, the driver reads that as "no opinion", and
#      a sprint mid-wave-loop gets offered Phase 0.
#   2. The sprint's recorded `scheduling`. Config is a request, not the verdict:
#      phase-0.md step 4a downgrades `graph` to `sequential` when the lead's
#      tool list has no `SendMessage`, and a mode probe that only ever read the
#      config would keep offering the graph phase list to a sprint that is
#      demonstrably running sequentially.
#   3. Otherwise the repo's config, through team-sprint's own reader, so a repo
#      that has tuned the key does not get a second private answer here.
#   4. Otherwise `sequential` — the mode whose phase list is a strict subset,
#      and therefore the safe thing to offer before anything has been decided.
#
# Re-read on every flow_next.sh call, so a pre-Phase-0 guess costs nothing: by
# the time the modes differ on which phase to offer, step 1 is answering.
if [ "${1:-}" = "--mode" ]; then
  [ $# -eq 1 ] || usage
  TS="$(ts_dir)" || { printf 'sequential\n'; exit 0; }

  mode=""
  PLAN="$(bash "$FLOW_STATE" execute get plan 2>/dev/null)" || PLAN=""
  if [ -n "$PLAN" ]; then
    STATE="$(bash "$TS/scripts/state.sh" art-dir "$PLAN" 2>/dev/null)/state.json"
    if [ -f "$STATE" ]; then
      if [ "$(jq -r '.current_phase // empty' "$STATE" 2>/dev/null)" = "execute" ]; then
        mode="graph"
      else
        mode="$(jq -r '.scheduling // empty' "$STATE" 2>/dev/null)"
      fi
    fi
  fi
  if [ -z "$mode" ]; then
    # shellcheck source=/dev/null
    mode="$(. "$TS/scripts/lib.sh" >/dev/null 2>&1
            read_config_scalar "${TEAM_SPRINT_CONFIG:-team-sprint.config.yaml}" scheduling 2>/dev/null)"
  fi
  case "$mode" in
    graph|sequential) printf '%s\n' "$mode" ;;
    *)                printf 'sequential\n' ;;
  esac
  exit 0
fi

[ $# -eq 0 ] || usage

PLAN="$(bash "$FLOW_STATE" execute get plan 2>/dev/null)" || exit 1
[ -n "$PLAN" ] || exit 1

TS="$(ts_dir)" || exit 1
STATE="$(bash "$TS/scripts/state.sh" art-dir "$PLAN" 2>/dev/null)/state.json"
[ -f "$STATE" ] || exit 1

CUR="$(jq -r '.current_phase // empty' "$STATE" 2>/dev/null)" || exit 1
[ -n "$CUR" ] || exit 1
DONE="$(jq -r 'if (.done // false) then "1" else "" end' "$STATE" 2>/dev/null)"

printf 'PHASE=%s\n' "$CUR"
[ -n "$DONE" ] && printf 'DONE=1\n'
exit 0

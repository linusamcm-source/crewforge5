#!/usr/bin/env bash
# phase_gate.sh — the mechanical gate behind one `crewforge:execute` phase.
#
# Usage:
#   phase_gate.sh <phase>
# Runs the check `phases.json` declares for <phase> and prints one KEY=VALUE
# line: STATUS=PASS | STATUS=SKIP REASON=<slug> | STATUS=FAIL REASON=<slug>.
# Only 0, 1, 8 and 9 carry a mechanical gate. Phases 2-7 are judgment gates
# stated by team-sprint's own phase docs, declare no gate in the manifest, and
# therefore never reach this script — asking for one is a usage error.
#
# execute WRAPS team-sprint, it does not fork it: phases 0 and 1 re-run
# team-sprint's own scripts (`validate_plan_path.sh`, `preflight_subskills.sh`,
# `findings_gate.sh`) rather than re-implementing their checks, so a wrapper
# cannot drift from the verdict the phase doc promises. Those scripts are found
# through the Story 1 resolver, because a sub-skill hidden from the catalogue is
# still on disk and must stay reachable without the `Skill` tool.
#
# WHY SKIP EXITS 0. flow_next.sh advances on a `pass` status and re-offers
# anything else, so a gate that exits non-zero to mean "not applicable" would
# park the flow on an optional phase forever. SKIP is therefore recorded in the
# verdict line — which flow_gate.sh stores in state.json — while the exit code
# says "do not stop here". A phase that is `required` in the manifest never
# skips: it fails, which is exactly what the retired `integration_diagram: on`
# toggle used to mean.
#
# Exit codes: 0 pass or skip, 1 the gate failed, 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CREWFORGE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
RESOLVE="$ROOT/scripts/flow/subskill_resolve.sh"
FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

pass() { printf 'STATUS=PASS\n'; exit 0; }
skip() { printf 'STATUS=SKIP REASON=%s\n' "$1"; exit 0; }
fail() { printf 'STATUS=FAIL REASON=%s\n' "$1"; exit 1; }

[ $# -eq 1 ] || usage
PHASE="$1"

command -v jq >/dev/null 2>&1 || { printf '[fail] jq missing — install: brew install jq\n' >&2; exit 1; }

# The sub-skill's directory, or nothing when it resolves in no root.
skill_dir() {
  local p
  p="$(bash "$RESOLVE" "$1" 2>/dev/null)" || return 1
  dirname "$p"
}

# The plan under sprint, recorded into state.json by phase 0's intake.
plan_path() { bash "$FLOW_STATE" execute get plan 2>/dev/null; }

# `required` for a phase, straight from the manifest — the flag that replaced
# team-sprint's `integration_diagram: off|auto|on` config toggle.
required_flag() {
  local m
  m="$(bash "$FLOW_STATE" execute manifest 2>/dev/null)" || return 1
  jq -r --arg id "$1" 'map(select(.id == $id)) | .[0].required // false' "$m"
}

gate_0() { # Pre-flight: a real plan, a valid plan path, every required sub-skill
  local plan ts s
  plan="$(plan_path)" || fail no-plan-recorded
  [ -n "$plan" ] || fail no-plan-recorded
  [ -f "$plan" ] || fail plan-missing
  ts="$(skill_dir team-sprint)" || fail no-team-sprint
  bash "$ts/scripts/validate_plan_path.sh" "$plan" >/dev/null || fail plan-path-contract
  for s in use-repo-code sprint-watchdog pre-commit-review-fleet; do
    bash "$ts/scripts/preflight_subskills.sh" --probe-only "$s" >/dev/null 2>&1 \
      || fail "subskill-missing:$s"
  done
  pass
}

gate_1() { # Plan-review provenance: stamped by the planner, and fold-clean
  local plan ts
  plan="$(plan_path)" || fail no-plan-recorded
  [ -n "$plan" ] || fail no-plan-recorded
  [ -f "$plan" ] || fail plan-missing
  grep -qm1 -E '^<!-- adversarial-review: status=(clean|user-override) ' "$plan" \
    || fail no-adversarial-stamp
  ts="$(skill_dir team-sprint)" || fail no-team-sprint
  bash "$ts/scripts/findings_gate.sh" "$plan" >/dev/null || fail unfolded-findings
  pass
}

gate_8() { # Integration diagram: the tool, then the artefact it should produce
  local required diagram
  required="$(required_flag 8)"
  if ! bash "$RESOLVE" --probe drawio; then
    [ "$required" = "true" ] && fail no-diagram-tool
    skip no-diagram-tool
  fi
  diagram="$(bash "$FLOW_STATE" execute get diagram_path 2>/dev/null)"
  if [ -n "$diagram" ] && [ -f "$diagram" ]; then
    pass
  fi
  [ "$required" = "true" ] && fail no-diagram
  skip no-diagram
}

gate_9() { # Distil the run's learnings, and pay for them
  local si count
  si="$(skill_dir self-improve)" || fail no-self-improve
  count="$(bash "$si/scripts/ledger.sh" count 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) fail ledger-unreadable ;; esac
  [ "$count" -eq 0 ] && skip ledger-empty
  bash "$si/scripts/ceiling.sh" check >/dev/null || fail ceiling-breach
  pass
}

case "$PHASE" in
  0) gate_0 ;;
  1) gate_1 ;;
  8) gate_8 ;;
  9) gate_9 ;;
  *) usage ;;
esac

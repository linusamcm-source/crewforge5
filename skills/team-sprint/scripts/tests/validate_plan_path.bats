#!/usr/bin/env bats
# validate_plan_path.bats — backfill fixtures for scripts/validate_plan_path.sh
# (mech-8 explicit deliverable). Covers FAIL/RESUME/OK branches of the
# pre-existing script without changing its interface.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  VPP_SH="$SCRIPTS/validate_plan_path.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# --- OK / slug derivation --------------------------------------------------

@test "valid mech-* plan path -> STATUS=OK with SLUG and SPRINT_DIR" {
  PLAN="$TMP/sprint-mech-8.md"
  printf '# plan\n' > "$PLAN"
  run "$VPP_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SLUG=sprint-mech-8"* ]]
  [[ "$output" == *"SPRINT_DIR=.team-sprint/sprints/sprint-sprint-mech-8"* ]]
  [[ "$output" == *"STATUS=OK"* ]]
}

@test "--slug-only short-circuits validation and emits OK" {
  PLAN="$TMP/sprint-mech-8.md"
  # Note: --slug-only does NOT require the file to exist.
  run "$VPP_SH" --slug-only "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SLUG=sprint-mech-8"* ]]
  [[ "$output" == *"SPRINT_DIR=.team-sprint/sprints/sprint-sprint-mech-8"* ]]
  [[ "$output" == *"STATUS=OK"* ]]
}

# --- usage error -----------------------------------------------------------

@test "missing arg -> exit 2 with usage on stderr" {
  run "$VPP_SH"
  [ "$status" -eq 2 ]
  # `run` merges stderr into output.
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"STATUS=FAIL"* ]]
}

# --- generic / digitless filenames -> FAIL ---------------------------------

@test "generic filename 'plan.md' -> STATUS=FAIL with rename hint" {
  PLAN="$TMP/plan.md"
  printf '# plan\n' > "$PLAN"
  run "$VPP_SH" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL"* ]]
  [[ "$output" == *"lacks a story id slug"* ]]
}

@test "filename without digit or recognised id-token -> STATUS=FAIL" {
  PLAN="$TMP/refactor-stuff.md"
  printf '# plan\n' > "$PLAN"
  run "$VPP_SH" "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL"* ]]
  [[ "$output" == *"does not include a story/epic id"* ]]
}

# --- collision: RESUME vs done vs different-plan ---------------------------

@test "existing sprint dir matching plan_path, not finalised -> STATUS=RESUME" {
  PLAN_REL="docs/plans/sprint-mech-8.md"
  mkdir -p "$TMP/docs/plans"
  printf '# plan\n' > "$TMP/$PLAN_REL"
  SDIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-8"
  mkdir -p "$SDIR"
  jq -n --arg p "$PLAN_REL" '{plan_path:$p, done:false}' > "$SDIR/state.json"

  run "$VPP_SH" "$PLAN_REL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=RESUME"* ]]
  [[ "$output" == *"resuming existing sprint"* ]]
}

@test "existing sprint dir with done=true -> STATUS=FAIL (already finalised)" {
  PLAN_REL="docs/plans/sprint-mech-8.md"
  mkdir -p "$TMP/docs/plans"
  printf '# plan\n' > "$TMP/$PLAN_REL"
  SDIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-8"
  mkdir -p "$SDIR"
  jq -n --arg p "$PLAN_REL" '{plan_path:$p, done:true}' > "$SDIR/state.json"

  run "$VPP_SH" "$PLAN_REL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL"* ]]
  [[ "$output" == *"already finalised"* ]]
}

@test "existing sprint dir for a DIFFERENT plan -> STATUS=FAIL (clobber)" {
  PLAN_REL="docs/plans/sprint-mech-8.md"
  mkdir -p "$TMP/docs/plans"
  printf '# plan\n' > "$TMP/$PLAN_REL"
  SDIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-8"
  mkdir -p "$SDIR"
  jq -n '{plan_path:"docs/plans/sprint-mech-other.md", done:false}' > "$SDIR/state.json"

  run "$VPP_SH" "$PLAN_REL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL"* ]]
  [[ "$output" == *"exists for a different plan"* ]]
}

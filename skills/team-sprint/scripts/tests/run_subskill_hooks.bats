#!/usr/bin/env bats
# run_subskill_hooks.bats — fixtures for scripts/run_subskill_hooks.sh

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  RUN_SH="$SCRIPTS/run_subskill_hooks.sh"
  STATE_SH="$SCRIPTS/state.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"

  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  PLAN="docs/plans/sprint-mech-15.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
  ART="$TMP/.team-sprint/sprints/sprint-sprint-mech-15"
  STATE="$ART/state.json"

  "$STATE_SH" init "$PLAN" develop sprint-mech-15 >/dev/null

  # Set worktree_path to TMP so hooks run in a real directory.
  "$STATE_SH" update "$PLAN" worktree_path="\"$TMP\""
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Helper: write hook list to state.json.subskill_hooks.
_set_hooks() {
  local json="$1"
  "$STATE_SH" update "$PLAN" subskill_hooks="$json"
}

# --- zero hooks (no-op) ----------------------------------------------------

@test "zero hooks: exits 0 and writes header-only log line" {
  _set_hooks '[]'
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  [ -f "$ART/subskill-phase-6.log" ]
  grep -q "0 hook(s) to run" "$ART/subskill-phase-6.log"
}

# --- one passing hook ------------------------------------------------------

@test "one passing hook: command runs, exit 0, log captures start/end" {
  marker="$TMP/hook-marker.txt"
  _set_hooks "[{\"skill\":\"ok\",\"command\":\"echo HOOK_OK > $marker\",\"required\":false,\"phase\":\"phase-6\",\"source\":\"user\"}]"
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  grep -q "HOOK_OK" "$marker"
  grep -q "skill=ok START" "$ART/subskill-phase-6.log"
  grep -q "skill=ok END rc=0" "$ART/subskill-phase-6.log"
}

# --- one failing hook (logged, exit 0) ------------------------------------

@test "one failing hook: rc captured, script still exits 0" {
  _set_hooks '[{"skill":"bad","command":"exit 3","required":false,"phase":"phase-6","source":"user"}]'
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  grep -q "skill=bad END rc=3" "$ART/subskill-phase-6.log"
}

# --- two hooks first fails (second still runs) ----------------------------

@test "two hooks: first fails, second still runs" {
  marker="$TMP/second-ran.txt"
  _set_hooks "[
    {\"skill\":\"first\",\"command\":\"exit 2\",\"required\":false,\"phase\":\"phase-6\",\"source\":\"user\"},
    {\"skill\":\"second\",\"command\":\"echo SECOND > $marker\",\"required\":false,\"phase\":\"phase-6\",\"source\":\"user\"}
  ]"
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  grep -q "skill=first END rc=2" "$ART/subskill-phase-6.log"
  grep -q "skill=second END rc=0" "$ART/subskill-phase-6.log"
}

# --- required: true at run time is IGNORED (run layer is always fail-soft) -

@test "required:true at run time does not abort (run is always fail-soft)" {
  _set_hooks '[{"skill":"req","command":"exit 1","required":true,"phase":"phase-6","source":"user"}]'
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  grep -q "skill=req END rc=1" "$ART/subskill-phase-6.log"
}

# --- only this phase's hooks fire -----------------------------------------

@test "hooks for other phases are skipped" {
  marker_6="$TMP/m6.txt"
  marker_7="$TMP/m7.txt"
  _set_hooks "[
    {\"skill\":\"six\",\"command\":\"echo 6 > $marker_6\",\"required\":false,\"phase\":\"phase-6\",\"source\":\"user\"},
    {\"skill\":\"seven\",\"command\":\"echo 7 > $marker_7\",\"required\":false,\"phase\":\"phase-7\",\"source\":\"user\"}
  ]"
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  [ -f "$marker_6" ]
  [ ! -f "$marker_7" ]
}

# --- log is APPENDED, not overwritten -------------------------------------

@test "log file is appended across invocations" {
  _set_hooks '[]'
  "$RUN_SH" 6 "$PLAN"
  before_lines="$(wc -l < "$ART/subskill-phase-6.log")"
  "$RUN_SH" 6 "$PLAN"
  after_lines="$(wc -l < "$ART/subskill-phase-6.log")"
  [ "$after_lines" -gt "$before_lines" ]
}

# --- TS_* env contract reaches the hook -----------------------------------

@test "TS_* env vars are exported to the hook command" {
  "$STATE_SH" update "$PLAN" current_story_id='"mech-15"'
  env_dump="$TMP/env-dump.txt"
  _set_hooks "[{\"skill\":\"env\",\"command\":\"env | grep ^TS_ | sort > $env_dump\",\"required\":false,\"phase\":\"phase-6\",\"source\":\"user\"}]"
  run "$RUN_SH" 6 "$PLAN"
  [ "$status" -eq 0 ]
  [ -f "$env_dump" ]
  grep -q "^TS_PLAN_PATH=" "$env_dump"
  grep -q "^TS_STORY_ID=mech-15$" "$env_dump"
  grep -q "^TS_TASK_ID=phase-6$" "$env_dump"
  grep -q "^TS_ART_DIR=" "$env_dump"
  grep -q "^TS_WORKTREE=" "$env_dump"
}

# --- positional and flagged invocations are equivalent --------------------

@test "flagged form --phase / --plan-path works (back-compat)" {
  _set_hooks '[]'
  run "$RUN_SH" --phase 6 --plan-path "$PLAN"
  [ "$status" -eq 0 ]
}

# --- reserved phases never run anything -----------------------------------

@test "reserved phase-1 is a no-op (does not run hooks)" {
  marker="$TMP/should-not-fire.txt"
  _set_hooks "[{\"skill\":\"x\",\"command\":\"echo X > $marker\",\"required\":false,\"phase\":\"phase-1\",\"source\":\"user\"}]"
  run "$RUN_SH" 1 "$PLAN"
  [ "$status" -eq 0 ]
  [ ! -f "$marker" ]
  grep -q "reserved phase" "$ART/subskill-phase-1.log"
}

# --- bad args ---

@test "missing args -> usage exit 2" {
  run "$RUN_SH"
  [ "$status" -eq 2 ]
}

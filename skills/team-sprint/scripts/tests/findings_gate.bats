#!/usr/bin/env bats
# findings_gate.bats — coverage for scripts/findings_gate.sh (Story FL3).
#
# The gate is the mechanical half of Phase 1's apply → fold → gate revise step:
# apply_findings.sh annotates the plan with `<!-- FINDING ... -->` markers, the
# lead folds each marker into revised prose, and this script proves zero
# markers remain before the next review round is spawned (or before promotion
# to plan-final.md). Without it the loop cannot converge —
# sprint-recon-harness-1 ended with 64 markers embedded in a 58.4KB plan.
#
# (The workflow-integration tests moved to team-sprint-planner with the loop.)
# the gate's integration: any remaining_markers other than exactly 0 (including
# a missing field — fail closed) stops the loop as fold_failed,
# and both the revise and finalise prompts instruct running the gate.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FG="$SCRIPTS/findings_gate.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

# --- invocation contract ----------------------------------------------------

@test "findings_gate.sh carries the executable bit like its sibling scripts" {
  [ -x "$FG" ]
}

# --- argument contract ------------------------------------------------------

@test "no args -> usage on stderr, exit 2" {
  run bash "$FG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "two args -> usage, exit 2" {
  run bash "$FG" "$TMP/a.md" "$TMP/b.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing plan file -> exit 2, names the path" {
  run bash "$FG" "$TMP/nope.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nope.md"* ]]
}

@test "unreadable plan -> exit 2, never STATUS=OK (gate must not fail open)" {
  printf '<!-- FINDING F-1 (HIGH): fix it -->\n' > "$TMP/noread.md"
  chmod 000 "$TMP/noread.md"
  run bash "$FG" "$TMP/noread.md"
  chmod 644 "$TMP/noread.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read"* ]]
  [[ "$output" != *"STATUS=OK"* ]]
}

@test "plan name starting with a dash is not parsed as a grep option" {
  printf '<!-- FINDING F-1 (HIGH): fix it -->\n' > "$TMP/-dash.md"
  run bash -c "cd '$TMP' && bash '$FG' -dash.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL COUNT=1"* ]]
}

# --- gate verdicts ----------------------------------------------------------

@test "marker-free plan -> STATUS=OK COUNT=0, exit 0" {
  cat > "$TMP/plan.md" <<'EOF'
# Plan

## Story A: does things

- an AC bullet
EOF
  run bash "$FG" "$TMP/plan.md"
  [ "$status" -eq 0 ]
  assert_output "STATUS=OK COUNT=0"
}

@test "plan with 3 markers -> STATUS=FAIL COUNT=3, exit 1, one line number each" {
  cat > "$TMP/plan.md" <<'EOF'
# Plan

<!-- FINDING F-1 (CRITICAL): fix the first thing -->
## Story A: does things

<!-- FINDING F-2 (HIGH): fix the second thing -->
- an AC bullet

<!-- FINDING F-3 (HIGH): fix the third thing -->
a prose paragraph
EOF
  run bash "$FG" "$TMP/plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL COUNT=3"* ]]
  # Markers sit on fixture lines 3, 6 and 9.
  [[ "$output" == *"line 3:"* ]]
  [[ "$output" == *"line 6:"* ]]
  [[ "$output" == *"line 9:"* ]]
}

@test "STATUS line is stdout-only; marker line numbers go to stderr" {
  printf '<!-- FINDING F-1 (HIGH): fix it -->\ntext\n' > "$TMP/plan.md"
  run bash -c "bash '$FG' '$TMP/plan.md' 2>/dev/null"
  [ "$status" -eq 1 ]
  assert_output "STATUS=FAIL COUNT=1"
  run bash -c "bash '$FG' '$TMP/plan.md' 2>&1 1>/dev/null"
  [[ "$output" == *"line 1:"* ]]
}

@test "non-FINDING html comments do not trip the gate" {
  cat > "$TMP/plan.md" <<'EOF'
# Plan
<!-- subskill-hooks:phase-1 -->
<!-- wf:revise -->
<!-- a stray comment mentioning FINDING mid-sentence is fine -->
prose
EOF
  run bash "$FG" "$TMP/plan.md"
  [ "$status" -eq 0 ]
  assert_output "STATUS=OK COUNT=0"
}

@test "the gate never mutates the plan" {
  printf '<!-- FINDING F-1 (HIGH): fix it -->\ntext\n' > "$TMP/plan.md"
  before="$(cat "$TMP/plan.md")"
  run bash "$FG" "$TMP/plan.md"
  [ "$status" -eq 1 ]
  [ "$(cat "$TMP/plan.md")" = "$before" ]
}

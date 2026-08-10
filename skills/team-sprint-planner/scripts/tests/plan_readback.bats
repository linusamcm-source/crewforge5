#!/usr/bin/env bats
# plan_readback.bats — fixtures for scripts/plan_readback.sh

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  PR_SH="$SCRIPTS/plan_readback.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP

  PLAN="$TMP/feature-x-1.md"
  cat > "$PLAN" <<'PLAN_EOF'
# Feature X
<!-- adversarial-review: status=clean rounds=2 date=2026-08-01 reviewer=team-sprint-planner -->

## Story x-1: build the widget

### Depends On: none
### Touches: src/widget/**

## Story x-2: wire the widget

### Depends On: x-1
### Touches: src/app/**
PLAN_EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "read-back emits stamp line first and one bullet per story with deps" {
  run "$PR_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "<!-- adversarial-review: status=clean"* ]]
  [[ "$output" == *"- x-1 — build the widget (depends on: none)"* ]]
  [[ "$output" == *"- x-2 — wire the widget (depends on: x-1)"* ]]
}

@test "unstamped plan reports STAMP: MISSING" {
  UNSTAMPED="$TMP/feature-y-2.md"
  printf '# Y\n\n## Story y-1: t\n\n### Depends On: none\n' > "$UNSTAMPED"
  run "$PR_SH" "$UNSTAMPED"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "STAMP: MISSING"* ]]
}

@test "single-story plan (no Story headings) emits one bullet keyed by filename stem" {
  SINGLE="$TMP/bugfix-3.md"
  printf '# Fix the thing\n\nbody text\n' > "$SINGLE"
  run "$PR_SH" "$SINGLE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- bugfix-3 — Fix the thing (depends on: none)"* ]]
}

@test "extra arguments are rejected with usage" {
  run "$PR_SH" "$PLAN" --drawio "$TMP/graph.drawio"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "reruns are byte-identical" {
  run "$PR_SH" "$PLAN"
  first="$output"
  run "$PR_SH" "$PLAN"
  [ "$output" = "$first" ]
}

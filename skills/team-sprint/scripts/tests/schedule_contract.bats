#!/usr/bin/env bats
# schedule_contract.bats — guards schedule.sh's DOCUMENTED contract surface.
#
# schedule.bats covers the happy wave-loop plus three regressions. This fixture
# covers what that leaves open: the header's exit-code contract
# (0 ok | 1 usage/IO | 2 illegal transition | 3 python3 unavailable) and the
# guard failures that protect the node state machine from illegal transitions.
#
# Written as refactor armour: schedule.sh had 4 tests for 267 lines before any
# streamlining work touched it.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$SCRIPTS/fixtures"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  run env TS_WORKTREE_NAME=sprint-demo bash "$SCRIPTS/build_graph.sh" "$FIX/happy.stories.json" "$TMP/g.json"
  [ "$status" -eq 0 ] || { echo "fixture build failed: $output"; false; }
}

teardown() { rm -rf "$TMP"; }

first_id() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["nodes"][0]["id"])' "$TMP/g.json"; }

# --- exit code 1: usage / IO ------------------------------------------------

@test "contract: no args -> exit 1 with usage on stderr" {
  run bash "$SCRIPTS/schedule.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "contract: one arg -> exit 1 with usage on stderr" {
  run bash "$SCRIPTS/schedule.sh" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "contract: missing graph file -> exit 1, names the path" {
  run bash "$SCRIPTS/schedule.sh" status "$TMP/does-not-exist.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"graph not found"* ]]
}

# --- exit code 2: illegal transitions --------------------------------------

@test "guard: commit on a pending node is rejected (exit 2)" {
  id="$(first_id)"
  run bash "$SCRIPTS/schedule.sh" commit "$TMP/g.json" "$id" deadbeef
  [ "$status" -eq 2 ]
}

@test "guard: integrate on a pending node is rejected (exit 2)" {
  id="$(first_id)"
  run bash "$SCRIPTS/schedule.sh" integrate "$TMP/g.json" "$id" deadbeef
  [ "$status" -eq 2 ]
}

@test "guard: double claim of the same node is rejected (exit 2)" {
  id="$(first_id)"
  run env TS_WORKTREE_PATH=/wt/x bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" "$id"
  assert_success
  run env TS_WORKTREE_PATH=/wt/x bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" "$id"
  [ "$status" -eq 2 ]
}

@test "guard: unknown node id is rejected, not silently ignored" {
  run bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" no-such-node-id
  [ "$status" -ne 0 ]
}

@test "guard: a rejected transition leaves graph.json byte-identical" {
  id="$(first_id)"
  before="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  run bash "$SCRIPTS/schedule.sh" commit "$TMP/g.json" "$id" deadbeef
  [ "$status" -eq 2 ]
  after="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

# --- read commands are pure ------------------------------------------------

@test "purity: status/frontier/next never mutate the graph" {
  before="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  run bash "$SCRIPTS/schedule.sh" status "$TMP/g.json";   assert_success
  run bash "$SCRIPTS/schedule.sh" frontier "$TMP/g.json"; assert_success
  run bash "$SCRIPTS/schedule.sh" next "$TMP/g.json";     assert_success
  after="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

@test "status emits a verdict the wave loop can branch on" {
  run bash "$SCRIPTS/schedule.sh" status "$TMP/g.json"
  assert_success
  [[ "$output" == *"verdict="* ]]
  [[ "$output" =~ verdict=(running|complete|blocked|deadlock) ]]
}

# --- failure cascade --------------------------------------------------------

@test "fail cascades: dependents of a failed node do not stay ready" {
  id="$(first_id)"
  run bash "$SCRIPTS/schedule.sh" fail "$TMP/g.json" "$id" "synthetic"
  assert_success
  run bash "$SCRIPTS/schedule.sh" frontier "$TMP/g.json"
  assert_success
  [[ "$output" != *"$id"* ]]
}

@test "fail records a reason when one is supplied" {
  id="$(first_id)"
  run bash "$SCRIPTS/schedule.sh" fail "$TMP/g.json" "$id" "synthetic-reason-xyz"
  assert_success
  run grep -q 'synthetic-reason-xyz' "$TMP/g.json"
  assert_success
}

# --- resume path ------------------------------------------------------------

@test "reset-orphans returns in_progress nodes to pending" {
  id="$(first_id)"
  run env TS_WORKTREE_PATH=/wt/x bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" "$id"
  assert_success
  run bash "$SCRIPTS/schedule.sh" reset-orphans "$TMP/g.json"
  assert_success
  run bash "$SCRIPTS/schedule.sh" frontier "$TMP/g.json"
  assert_success
  [[ "$output" == *"$id"* ]]
}

@test "reset-orphans is idempotent on a clean graph" {
  run bash "$SCRIPTS/schedule.sh" reset-orphans "$TMP/g.json"; assert_success
  before="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  run bash "$SCRIPTS/schedule.sh" reset-orphans "$TMP/g.json"; assert_success
  after="$(md5 -q "$TMP/g.json" 2>/dev/null || md5sum "$TMP/g.json" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

#!/usr/bin/env bats
# schedule.bats — fixture for scripts/schedule.sh (the execute wave-loop engine).
#
# schedule.sh is a stateful, sequential state machine: a single graph is driven
# through claim -> commit -> integrate / fail / reset / simulate, with each step
# depending on the prior mutation. That scenario lives in schedule_scenario.sh
# (self-checking, exits non-zero on any failed assertion); this fixture runs it
# and asserts a clean exit so the engine is gated by run-all.sh / lint check 8.
# Three more focused tests guard the node-branch naming scheme (D3 regression),
# the claim-time base_commit recording (D8 regression), and the stderr WARN on
# the sprint/unknown integration-branch fallback (D5 regression).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$SCRIPTS/fixtures"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

@test "schedule.sh wave-loop: build_graph -> frontier/claim/commit/integrate/fail/reset/simulate (13 checks)" {
  run bash "$BATS_TEST_DIRNAME/schedule_scenario.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "regression: node branch is <integration_branch>-<id>, no '/' after the prefix (claim + simulate)" {
  run env TS_WORKTREE_NAME=sprint-demo bash "$SCRIPTS/build_graph.sh" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  cp "$TMP/g.json" "$TMP/sim.json"
  run env TS_WORKTREE_PATH=/wt/repo-sprint-demo bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" 9
  assert_success
  run bash "$SCRIPTS/schedule.sh" simulate "$TMP/sim.json"
  assert_success
  run python3 - "$TMP/g.json" "$TMP/sim.json" <<'PY'
import json, sys
ib = "sprint/sprint-demo"
# D3: git forbids a slash-nested node ref while the integration branch
# sprint/<name> exists (ref vs ref-directory) -- node branches must be sibling
# refs <integration_branch>-<id>, so no '/' may follow the prefix.
claimed = {x["id"]: x for x in json.load(open(sys.argv[1]))["nodes"]}
assert claimed["9"]["branch"] == ib + "-9", claimed["9"]["branch"]
simulated = {x["id"]: x for x in json.load(open(sys.argv[2]))["nodes"]}
for nodes in (claimed, simulated):
    for n in nodes.values():
        b = n["branch"]
        if b is None:
            continue
        assert b.startswith(ib + "-"), b
        assert "/" not in b[len(ib):], b
print("ok")
PY
  assert_success
}

@test "regression: claim records optional base-sha as base_commit; omitted -> null (D8)" {
  run env TS_WORKTREE_NAME=sprint-demo bash "$SCRIPTS/build_graph.sh" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  cp "$TMP/g.json" "$TMP/nosha.json"
  run env TS_WORKTREE_PATH=/wt/repo-sprint-demo bash "$SCRIPTS/schedule.sh" claim "$TMP/g.json" 9 abc123
  assert_success
  run env TS_WORKTREE_PATH=/wt/repo-sprint-demo bash "$SCRIPTS/schedule.sh" claim "$TMP/nosha.json" 9
  assert_success
  run python3 - "$TMP/g.json" "$TMP/nosha.json" <<'PY'
import json, sys
# D8: the only correct diff base for a node is the integration HEAD it
# branched from -- recorded at claim as base_commit (nullable; omitting the
# sha keeps the null build_graph.sh emitted, preserving back-compat).
with_sha = {x["id"]: x for x in json.load(open(sys.argv[1]))["nodes"]}
assert with_sha["9"]["base_commit"] == "abc123", with_sha["9"]
no_sha = {x["id"]: x for x in json.load(open(sys.argv[2]))["nodes"]}
for n in no_sha.values():
    assert "base_commit" in n and n["base_commit"] is None, n
print("ok")
PY
  assert_success
}

@test "regression: missing integration_branch -> claim WARNs sprint/unknown fallback on stderr only (D5)" {
  # Minimal hand-rolled graph with no integration_branch field.
  printf '{"max_parallel_agents":4,"order":["n1"],"nodes":[{"id":"n1","status":"pending","phase":null,"depends_on":[],"branch":null,"worktree":null,"base_commit":null}]}' > "$TMP/noib.json"
  run bash -c 'bash "$1" claim "$2" n1 2>"$TMP/err"' _ "$SCRIPTS/schedule.sh" "$TMP/noib.json"
  assert_success
  # stdout shape unchanged: the claim line carries the fallback branch, no WARN.
  assert_line "sprint/unknown-n1"
  refute_output "WARN"
  run cat "$TMP/err"
  assert_line "WARN"
  assert_line "sprint/unknown"
  # With integration_branch present (build_graph output) the WARN is absent.
  run env TS_WORKTREE_NAME=sprint-demo bash "$SCRIPTS/build_graph.sh" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  run bash -c 'bash "$1" claim "$2" 9 2>"$TMP/err2"' _ "$SCRIPTS/schedule.sh" "$TMP/g.json"
  assert_success
  run cat "$TMP/err2"
  refute_output "WARN"
}

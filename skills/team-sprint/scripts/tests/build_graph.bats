#!/usr/bin/env bats
# build_graph.bats — fixtures for scripts/build_graph.sh (stories.json -> graph.json).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  BG="$SCRIPTS/build_graph.sh"
  PS="$SCRIPTS/parse_stories.sh"
  FIX="$SCRIPTS/fixtures"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

@test "happy.stories.json -> 4 pending nodes, derived integration_branch, valid topo order" {
  run env TS_WORKTREE_NAME=sprint-demo bash "$BG" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  run python3 - "$TMP/g.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
assert g["scheduling"] == "graph", g["scheduling"]
assert g["graph_version"] == 1
assert g["integration_branch"] == "sprint/sprint-demo", g["integration_branch"]
n = {x["id"]: x for x in g["nodes"]}
assert set(n) == {"9", "11", "12", "13"}, list(n)
assert all(x["status"] == "pending" for x in g["nodes"])
assert all(x["branch"] is None and x["worktree"] is None for x in g["nodes"])
assert n["9"]["depends_on"] == []
assert n["11"]["depends_on"] == ["9"]
assert n["12"]["depends_on"] == ["11"]
assert n["13"]["depends_on"] == ["9"]
o = g["order"]
assert set(o) == set(n)
assert o.index("9") < o.index("11") < o.index("12")
assert o.index("9") < o.index("13")
print("ok")
PY
  assert_success
}

@test "self-edge is rejected (exit 2)" {
  printf '[{"story_id":"a","depends_on":["a"]}]' > "$TMP/self.json"
  run bash "$BG" "$TMP/self.json" "$TMP/out.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"self-edge on node a"* ]]
}

@test "dangling depends_on ref is rejected (exit 2)" {
  printf '[{"story_id":"a","depends_on":["ghost"]}]' > "$TMP/d.json"
  run bash "$BG" "$TMP/d.json" "$TMP/out.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown node ghost"* ]]
}

@test "dependency cycle is rejected (exit 2) and names the cycle path" {
  printf '[{"story_id":"a","depends_on":["b"]},{"story_id":"b","depends_on":["a"]}]' > "$TMP/c.json"
  run bash "$BG" "$TMP/c.json" "$TMP/out.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cycle"* ]]
}

@test "hybrid mode infers a conflict-ordering edge from Touches overlap" {
  printf '[{"story_id":"10","touches":["src/cfg/**"]},{"story_id":"2","touches":["src/cfg/**"]}]' > "$TMP/pair.json"
  run env TS_WORKTREE_NAME=w bash "$BG" "$TMP/pair.json" "$TMP/g.json"
  assert_success
  run python3 - "$TMP/g.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
n = {x["id"]: x for x in g["nodes"]}
# No ordering path between 2 and 10 -> conflict edge, natural-key lower (2)
# first, recorded in the dependent's inferred_deps.
assert n["10"]["inferred_deps"] == ["2"], n["10"]["inferred_deps"]
assert n["10"]["depends_on"] == ["2"], n["10"]["depends_on"]
assert n["2"]["inferred_deps"] == [] and n["2"]["depends_on"] == []
o = g["order"]
assert o.index("2") < o.index("10"), o
print("ok")
PY
  assert_success
}

@test "hybrid: parse_stories fixture — ordered 9/12 overlap adds no phantom inferred edge" {
  bash "$PS" "$FIX/happy.plan-final.md" > "$TMP/stories.json"
  run env TS_WORKTREE_NAME=sprint-demo bash "$BG" "$TMP/stories.json" "$TMP/g.json"
  assert_success
  run python3 - "$TMP/g.json" <<'PY'
import json, sys
n = {x["id"]: x for x in json.load(open(sys.argv[1]))["nodes"]}
# Story 9 and 12 both touch src/mech/config/**, but the declared chain
# 12 -> 11 -> 9 already orders the pair -> the transitive-ordering rule skips
# the inferred edge and records no phantom dep (was ["9"] before GH1).
assert n["12"]["inferred_deps"] == [], n["12"]["inferred_deps"]
assert n["12"]["depends_on"] == ["11"], n["12"]["depends_on"]
assert n["12"]["declared_deps"] == ["11"], n["12"]["declared_deps"]
assert n["9"]["inferred_deps"] == [] and n["9"]["depends_on"] == []
print("ok")
PY
  assert_success
}

@test "hybrid: transitive declared ordering suppresses the inferred conflict edge" {
  printf '[{"story_id":"WT1","touches":["src/shared/**"]},{"story_id":"WT2","depends_on":["WT1"],"touches":["src/wt2/**"]},{"story_id":"DA4","depends_on":["WT2"],"touches":["src/shared/**"]}]' > "$TMP/chain.json"
  run env TS_WORKTREE_NAME=w bash "$BG" "$TMP/chain.json" "$TMP/g.json"
  assert_success
  run python3 - "$TMP/g.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
n = {x["id"]: x for x in g["nodes"]}
# WT1 -> WT2 -> DA4 declared chain already orders WT1 before DA4; the touches
# overlap between WT1 and DA4 must NOT add an inferred back-edge (DA4 sorts
# lower than WT1, so the old direct-edge-only guard fabricated a cycle here).
assert n["DA4"]["inferred_deps"] == [], n["DA4"]["inferred_deps"]
assert n["WT1"]["inferred_deps"] == [], n["WT1"]["inferred_deps"]
assert n["DA4"]["depends_on"] == ["WT2"], n["DA4"]["depends_on"]
o = g["order"]
assert o.index("WT1") < o.index("DA4"), o
print("ok")
PY
  assert_success
}

@test "hybrid: growing-graph check keeps inferred-chain + declared back-edge acyclic" {
  printf '[{"story_id":"A","depends_on":["Z"],"touches":["src/am/**"]},{"story_id":"M","touches":["src/am/**","src/mz/**"]},{"story_id":"Z","touches":["src/mz/**"]}]' > "$TMP/interplay.json"
  run env TS_WORKTREE_NAME=w bash "$BG" "$TMP/interplay.json" "$TMP/g.json"
  assert_success
  run python3 - "$TMP/g.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
n = {x["id"]: x for x in g["nodes"]}
# Declared Z-before-A plus overlaps (A,M) and (M,Z): the first inferred edge
# (M depends on A) transitively orders Z before M, so the (M,Z) pair must be
# skipped -- no phantom dep on Z, and the graph stays acyclic.
assert n["M"]["inferred_deps"] == ["A"], n["M"]["inferred_deps"]
assert n["Z"]["inferred_deps"] == [], n["Z"]["inferred_deps"]
o = g["order"]
assert o.index("Z") < o.index("A") < o.index("M"), o
print("ok")
PY
  assert_success
}

@test "max_parallel_agents is read from TS_MAX_PARALLEL_AGENTS" {
  run env TS_MAX_PARALLEL_AGENTS=2 TS_WORKTREE_NAME=w bash "$BG" "$FIX/wide.stories.json" "$TMP/w.json"
  assert_success
  run python3 - "$TMP/w.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
assert g["max_parallel_agents"] == 2, g["max_parallel_agents"]
assert len(g["nodes"]) == 6 and all(x["depends_on"] == [] for x in g["nodes"])
assert g["integration_branch"] == "sprint/w", g["integration_branch"]
print("ok")
PY
  assert_success
}

@test "D5: unset/empty TS_WORKTREE_NAME -> WARN on stderr only; stdout summary + exit 0 unchanged" {
  run bash -c 'env -u TS_WORKTREE_NAME bash "$1" "$2" "$3" 2>"$TMP/err"' _ "$BG" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  # The fallback is a warning, not an error: stdout keeps the one-line summary
  # (bats asserting stdout still pass) and no WARN leaks into it.
  assert_line "4 node(s)"
  refute_output "WARN"
  run cat "$TMP/err"
  assert_line "WARN"
  assert_line "sprint/sprint-unknown"
  assert_line "TS_WORKTREE_NAME"
  # Empty string falls back (and WARNs) identically to unset.
  run bash -c 'TS_WORKTREE_NAME= bash "$1" "$2" "$3" 2>"$TMP/err2"' _ "$BG" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  run cat "$TMP/err2"
  assert_line "WARN"
}

@test "D5: TS_WORKTREE_NAME set -> no WARN on stderr" {
  run bash -c 'TS_WORKTREE_NAME=w bash "$1" "$2" "$3" 2>"$TMP/err"' _ "$BG" "$FIX/happy.stories.json" "$TMP/g.json"
  assert_success
  run cat "$TMP/err"
  refute_output "WARN"
}

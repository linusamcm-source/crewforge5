#!/usr/bin/env bats
# plan_contract.bats — golden-template contract test.
#
# The team-sprint-planner skill documents a plan template
# (team-sprint-planner/references/plan-contract.md). This file locks that
# documented template to the real scripts by driving one canonical fixture
# (scripts/fixtures/golden-template-1.md) end-to-end through
# parse_stories.sh -> validate_plan_path.sh -> build_graph.sh. If a parser or
# graph change breaks the documented template, this suite fails at commit time.
#
# Scope: integrated round-trip only. Transitive-skip mechanics are
# unit-covered in build_graph.bats ("transitive declared ordering suppresses
# the inferred conflict edge", "growing-graph check") and are not re-proved
# here.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  FIX="$SCRIPTS/fixtures"
  GOLDEN="$FIX/golden-template-1.md"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

@test "golden template: parse_stories extracts 6 stories with documented field shapes" {
  run bash "$SCRIPTS/parse_stories.sh" "$GOLDEN"
  assert_success
  printf '%s' "$output" > "$TMP/stories.json"
  run python3 - "$TMP/stories.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
byid = {x["story_id"]: x for x in s}
assert [x["story_id"] for x in s] == ["1", "2", "3", "4", "5", "6"], [x["story_id"] for x in s]
# inline comma-separated Touches list splits into individual globs
assert byid["1"]["touches"] == ["src/config/**", "tests/test_config.py"], byid["1"]["touches"]
# brace-expansion glob on its own bullet line survives verbatim
assert byid["4"]["touches"] == ["tools/{fmt,lint}/**"], byid["4"]["touches"]
# inline Depends On list parses; "none" maps to []
assert byid["2"]["depends_on"] == ["1"], byid["2"]["depends_on"]
assert byid["1"]["depends_on"] == [], byid["1"]["depends_on"]
# story without a Touches section parses to []
assert byid["6"]["touches"] == [], byid["6"]["touches"]
# every story carries non-empty AC + DoD per the template
for x in s:
    assert x["acceptance_criteria"], x["story_id"]
    assert x["definition_of_done"], x["story_id"]
print("ok")
PY
  assert_success
}

@test "golden template: validate_plan_path accepts the fixture filename" {
  cd "$TMP"
  run bash "$SCRIPTS/validate_plan_path.sh" "$GOLDEN"
  assert_success
  [[ "$output" == *"STATUS=OK"* ]]
}

@test "cross-skill: team-feature documented default plan filename passes validate_plan_path" {
  TF="$SKILL_DIR/../team-feature/SKILL.md"
  [ -f "$TF" ] || skip "team-feature not installed"
  # Extract the documented default plan pattern from the peer skill — do not
  # hardcode the filename, so this case locks whatever the doc actually says.
  pattern="$(grep -oE 'docs/plans/<feature-slug>[a-z0-9<>-]*\.md' "$TF" | head -1)"
  [ -n "$pattern" ]
  example="${pattern//<feature-slug>/example-feature}"
  cd "$TMP"
  run bash "$SCRIPTS/validate_plan_path.sh" "$example"
  assert_success
  [[ "$output" == *"STATUS=OK"* ]]
}

@test "golden template: build_graph emits the expected integrated graph" {
  bash "$SCRIPTS/parse_stories.sh" "$GOLDEN" > "$TMP/stories.json"
  run env TS_WORKTREE_NAME=golden bash "$SCRIPTS/build_graph.sh" "$TMP/stories.json" "$TMP/graph.json"
  assert_success
  run python3 - "$TMP/graph.json" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
n = {x["id"]: x for x in g["nodes"]}
assert set(n) == {"1", "2", "3", "4", "5", "6"}, list(n)
# declared edges are authoritative
assert n["2"]["depends_on"] == ["1"] and n["2"]["declared_deps"] == ["1"]
assert n["3"]["depends_on"] == ["2"] and n["3"]["declared_deps"] == ["2"]
# transitively-ordered overlap pair (1,3) produced no inferred edge
assert n["3"]["inferred_deps"] == [], n["3"]["inferred_deps"]
# incomparable overlap pair (4,5): exactly one inferred edge, lower id first
assert n["5"]["inferred_deps"] == ["4"] and n["5"]["depends_on"] == ["4"]
# empty-Touches node receives no inferred edges
assert n["6"]["depends_on"] == [] and n["6"]["inferred_deps"] == []
# acyclic full topo order respecting the chain
o = g["order"]
assert set(o) == set(n)
assert o.index("1") < o.index("2") < o.index("3")
assert o.index("4") < o.index("5")
print("ok")
PY
  assert_success
}

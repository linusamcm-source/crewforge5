#!/usr/bin/env bats
# boundaries_dag_isolation.bats — post-mortem AC#2 (cross-boundary blindness).
#
# `### Boundaries:` is a REVIEW-SCOPE directive: it names cross-language,
# cross-repo and deployment artifacts a story's correctness depends on but does
# NOT edit. It must never reach the dependency DAG — `### Touches:` feeds
# inferred edges (SKILL.md:47-48, dependency_source: hybrid /
# infer_from_touches: true), so a boundary path landing in `touches[]` would
# invent phantom edges and corrupt Phase 2 scheduling.
#
# The post-mortem's acceptance criterion: adding a `### Boundaries:` section to a
# multi-story plan must leave graph output BYTE-IDENTICAL.
#
# Structural basis (verified in parse_stories.sh:128-146): every heading calls
# flush(); classify() returns kind=None for an unrecognised heading; buf resets;
# and body lines are only buffered while cur_kind is not None. These tests pin
# that behaviour so a future classify() pattern cannot silently capture it.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

write_plan() { # $1 = target path, $2 = "with" | "without"
  local extra=""
  [ "$2" = "with" ] && extra='### Boundaries: services/lambdas/auth/pre_token.py (produces custom:tier), packages/infra-consolidated/lib/config/dev.ts (decides which env runs this), ~/Development/surf-seer/src/services/spotConfigApiService.ts (the real caller)'
  cat > "$1" <<EOF
# Plan

## Story SP1-A: first story

### Acceptance Criteria
- AC1 does a thing

### Definition of Done
- DoD1 tests pass

### Touches: services/gateway/internal/server/a.go
$extra

## Story SP1-B: second story

### Depends On: SP1-A

### Acceptance Criteria
- AC1 does another thing

### Definition of Done
- DoD1 tests pass

### Touches: services/gateway/internal/server/b.go
$extra
EOF
}

@test "AC#2: Boundaries: leaves parse_stories.sh touches[] byte-identical" {
  write_plan "$TMP/without.md" without
  write_plan "$TMP/with.md" with
  a="$(bash "$SCRIPTS/parse_stories.sh" "$TMP/without.md" | jq -S '[.[]|{story_id,touches,depends_on}]')"
  b="$(bash "$SCRIPTS/parse_stories.sh" "$TMP/with.md"    | jq -S '[.[]|{story_id,touches,depends_on}]')"
  [ "$a" = "$b" ]
}

@test "AC#2: no boundary path leaks into touches[]" {
  write_plan "$TMP/with.md" with
  out="$(bash "$SCRIPTS/parse_stories.sh" "$TMP/with.md")"
  [[ "$out" != *"pre_token.py"* ]]
  [[ "$out" != *"spotConfigApiService"* ]]
  [[ "$out" != *"infra-consolidated"* ]]
}

@test "AC#2: the real Touches: entry still parses alongside Boundaries:" {
  write_plan "$TMP/with.md" with
  out="$(bash "$SCRIPTS/parse_stories.sh" "$TMP/with.md")"
  [[ "$out" == *"internal/server/a.go"* ]]
  [[ "$out" == *"internal/server/b.go"* ]]
}

@test "AC#2: declared Depends On: edge survives unchanged" {
  write_plan "$TMP/with.md" with
  dep="$(bash "$SCRIPTS/parse_stories.sh" "$TMP/with.md" | jq -r '[.[]|select(.story_id=="SP1-B")|.depends_on[]]|join(",")')"
  [ "$dep" = "SP1-A" ]
}

@test "AC#2: build_graph.sh output is byte-identical with and without Boundaries:" {
  write_plan "$TMP/without.md" without
  write_plan "$TMP/with.md" with
  bash "$SCRIPTS/parse_stories.sh" "$TMP/without.md" > "$TMP/s-without.json"
  bash "$SCRIPTS/parse_stories.sh" "$TMP/with.md"    > "$TMP/s-with.json"
  run env TS_WORKTREE_NAME=sprint-x bash "$SCRIPTS/build_graph.sh" "$TMP/s-without.json" "$TMP/g-without.json"
  assert_success
  run env TS_WORKTREE_NAME=sprint-x bash "$SCRIPTS/build_graph.sh" "$TMP/s-with.json" "$TMP/g-with.json"
  assert_success
  # Node ids + edges must match exactly; timestamps are the only permitted drift.
  a="$(jq -S '{nodes:[.nodes[]|{id,depends_on}],edges:(.edges//[])}' "$TMP/g-without.json")"
  b="$(jq -S '{nodes:[.nodes[]|{id,depends_on}],edges:(.edges//[])}' "$TMP/g-with.json")"
  [ "$a" = "$b" ]
}

@test "tripwire: classify() recognises exactly ac/dod/deps/touches" {
  # If someone adds a ("boundaries", r'boundaries') pattern to classify(), the
  # section starts feeding touches[] and corrupts the DAG. This fails loudly at
  # that moment rather than in production scheduling.
  # NB: a local variable literally named `boundaries` already exists at
  # parse_stories.sh:150 and is unrelated — so scope the check to classify().
  kinds="$(sed -n '/^def classify/,/^    return None, ""/p' "$SCRIPTS/parse_stories.sh" \
           | grep -oE '\("[a-z]+", r' | grep -oE '"[a-z]+"' | tr -d '"' | sort | paste -sd, -)"
  [ "$kinds" = "ac,deps,dod,touches" ]
}

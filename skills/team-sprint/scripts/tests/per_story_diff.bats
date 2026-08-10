#!/usr/bin/env bats
# per_story_diff.bats — fixtures for scripts/per_story_diff.sh (Story mech-6).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  PSD_SH="$SCRIPTS/per_story_diff.sh"
  STATE_SH="$SCRIPTS/state.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"

  # Init a target-branch repo and a sprint branch with two story commits.
  git init -q -b develop .
  git config user.email "test@example.com"
  git config user.name  "test"

  printf 'seed\n' > seed.txt
  git add -A && git commit -q -m "seed on develop"

  git checkout -q -b sprint/mech-1

  # Bootstrap a plan + state.json for state.sh read.
  PLAN="docs/plans/sprint-test.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
  git add -A && git commit -q -m "add plan"
  "$STATE_SH" init "$PLAN" develop sprint-test >/dev/null

  STATE_JSON="$TMP/.team-sprint/sprints/sprint-sprint-test/state.json"

  export TS_PLAN_PATH="$PLAN"
  export TS_SPRINT_BRANCH="sprint/mech-1"
  export TS_TARGET_BRANCH="develop"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# First story (no prior story_commits) -> diff against merge-base(sprint,target).
# ---------------------------------------------------------------------------
@test "first story: no prior story_commits -> diff vs merge-base(sprint,target)" {
  # Capture merge-base BEFORE we add the first story's changes.
  base_sha="$(git merge-base sprint/mech-1 develop)"

  # Story 1 introduces a new file on the sprint branch.
  printf 'story1 content\n' > story1.txt
  git add -A && git commit -q -m "story 1 changes"

  run "$PSD_SH" mech-1
  [ "$status" -eq 0 ]
  # The diff must show story1.txt as a brand-new file.
  [[ "$output" == *"diff --git"* ]]
  [[ "$output" == *"story1.txt"* ]]
  [[ "$output" == *"+story1 content"* ]]
  # Sanity: the same diff comes from invoking git directly against merge-base.
  expected="$(git diff "$base_sha"...HEAD)"
  [ "$output" = "$expected" ]
}

# ---------------------------------------------------------------------------
# Story 3 with two prior story_commits -> diff against story-2's recorded SHA.
# ---------------------------------------------------------------------------
@test "story 3: diff vs prior story (story 2's recorded SHA)" {
  # Commit story 1.
  printf 'story1\n' > a.txt
  git add -A && git commit -q -m "story 1"
  story1_sha="$(git rev-parse HEAD)"

  # Commit story 2.
  printf 'story2\n' > b.txt
  git add -A && git commit -q -m "story 2"
  story2_sha="$(git rev-parse HEAD)"

  # Commit story 3.
  printf 'story3\n' > c.txt
  git add -A && git commit -q -m "story 3"

  # Record story_commits[] for stories 1 and 2 only — story 3 is "in flight".
  "$STATE_SH" update "$PLAN" \
    story_commits="[{\"story_id\":\"mech-1\",\"sha\":\"$story1_sha\"},{\"story_id\":\"mech-2\",\"sha\":\"$story2_sha\"}]"

  run "$PSD_SH" mech-3
  [ "$status" -eq 0 ]
  # The diff must show c.txt (story 3's change) but NOT a.txt / b.txt.
  [[ "$output" == *"c.txt"* ]]
  [[ "$output" != *"+story1"* ]]
  [[ "$output" != *"+story2"* ]]
  # Equality with direct git invocation against story-2's SHA.
  expected="$(git diff "$story2_sha"...HEAD)"
  [ "$output" = "$expected" ]
}

# ---------------------------------------------------------------------------
# Story id already present in story_commits[] -> diff vs the entry BEFORE it.
# This is the "rerun for an already-recorded story" path.
# ---------------------------------------------------------------------------
@test "story already in story_commits -> diff vs the entry immediately before it" {
  printf 'a\n' > a.txt; git add -A && git commit -q -m "s1"
  s1_sha="$(git rev-parse HEAD)"
  printf 'b\n' > b.txt; git add -A && git commit -q -m "s2"
  s2_sha="$(git rev-parse HEAD)"
  printf 'c\n' > c.txt; git add -A && git commit -q -m "s3"
  s3_sha="$(git rev-parse HEAD)"

  "$STATE_SH" update "$PLAN" \
    story_commits="[{\"story_id\":\"mech-1\",\"sha\":\"$s1_sha\"},{\"story_id\":\"mech-2\",\"sha\":\"$s2_sha\"},{\"story_id\":\"mech-3\",\"sha\":\"$s3_sha\"}]"

  # Asking for mech-2 should diff against mech-1's SHA.
  run "$PSD_SH" mech-2
  [ "$status" -eq 0 ]
  expected="$(git diff "$s1_sha"...HEAD)"
  [ "$output" = "$expected" ]
}

# ---------------------------------------------------------------------------
# TS_DIFF_BASE short-circuit (graph mode, Story GH3 / D8): highest precedence,
# diffs from the given sha without consulting state.json at all.
# ---------------------------------------------------------------------------
@test "TS_DIFF_BASE set -> diff from that sha, story_commits and state.json ignored" {
  printf 'a\n' > a.txt; git add -A && git commit -q -m "s1"
  s1_sha="$(git rev-parse HEAD)"
  printf 'b\n' > b.txt; git add -A && git commit -q -m "s2"
  s2_sha="$(git rev-parse HEAD)"
  printf 'c\n' > c.txt; git add -A && git commit -q -m "s3"

  # story_commits would resolve mech-3's base to s2 (excluding b.txt); the
  # env override must win and diff from s1 instead (b.txt AND c.txt).
  "$STATE_SH" update "$PLAN" \
    story_commits="[{\"story_id\":\"mech-1\",\"sha\":\"$s1_sha\"},{\"story_id\":\"mech-2\",\"sha\":\"$s2_sha\"}]"

  # TS_PLAN_PATH emptied on purpose: the short-circuit must never read
  # state.json (without it, an empty TS_PLAN_PATH is a hard exit-1 failure).
  run env TS_PLAN_PATH= TS_DIFF_BASE="$s1_sha" "$PSD_SH" mech-3
  [ "$status" -eq 0 ]
  [[ "$output" == *"b.txt"* ]]
  [[ "$output" == *"c.txt"* ]]
  # Equality with direct git invocation against the overridden base.
  expected="$(git diff "$s1_sha"...HEAD)"
  [ "$output" = "$expected" ]
}

# ---------------------------------------------------------------------------
# Missing story id -> error (exit non-zero).
# ---------------------------------------------------------------------------
@test "missing story_id arg -> usage error (exit 2)" {
  run "$PSD_SH"
  [ "$status" -eq 2 ]
}

@test "empty story_id arg -> error (exit 1)" {
  run "$PSD_SH" ""
  [ "$status" -eq 1 ]
}

#!/usr/bin/env bats
# crew_copy.bats — contract for carrying a crew into every worktree.
#
# The bug being fenced off: a sprint generates its crew in Phase 0, after node
# worktrees were cut from a base ref that predates the crew commit. Every node
# then spawns against agents that do not exist in its tree.
#
# Two halves are asserted here. The script's behaviour — copies, refuses to
# clobber newer, reports an absent crew honestly — and the ORDER the phase docs
# put it in, because the copy is invoked by a model reading those docs and
# "before the first spawn of the sprint" is not the same guarantee as "before
# node N's first spawn".

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SKILL="$(cd "$SCRIPTS/.." && pwd -P)"
  COPY="$SCRIPTS/crew_copy.sh"
  PHASE2="$SKILL/phases/phase-2.md"
  PHASEX="$SKILL/phases/phase-execute.md"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  MAIN="$TMP/main"
  WT="$TMP/wt"
  mkdir -p "$MAIN/.claude/agents" "$MAIN/.claude/crews" "$WT"
  printf -- '---\nname: go-developer\n---\nbody\n' > "$MAIN/.claude/agents/go-developer.md"
  printf -- '---\nname: go-tester\n---\nbody\n'    > "$MAIN/.claude/agents/go-tester.md"
  printf '{"language":"go"}\n'                     > "$MAIN/.claude/crews/go.json"
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

@test "a crewless worktree gets every agent and the manifest" {
  run bash "$COPY" "$MAIN" "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=OK"* ]]
  [[ "$output" == *"COPIED=3"* ]]
  [ -f "$WT/.claude/agents/go-developer.md" ]
  [ -f "$WT/.claude/agents/go-tester.md" ]
  [ -f "$WT/.claude/crews/go.json" ]
}

@test "a repo with no crew reports NO_CREW rather than a successful copy of nothing" {
  rm -rf "$MAIN/.claude"
  run bash "$COPY" "$MAIN" "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=NO_CREW"* ]]
  [ ! -d "$WT/.claude/agents" ]
}

@test "a newer in-worktree agent is never clobbered" {
  bash "$COPY" "$MAIN" "$WT"
  printf -- '---\nname: go-developer\n---\nregenerated in this worktree\n' > "$WT/.claude/agents/go-developer.md"
  # `-nt` is mtime-based and the copy above is same-second; make the difference
  # unambiguous rather than racing the clock.
  touch -t 203001010000 "$WT/.claude/agents/go-developer.md"
  run bash "$COPY" "$MAIN" "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED_NEWER=1"* ]]
  grep -q 'regenerated in this worktree' "$WT/.claude/agents/go-developer.md"
}

@test "re-running is idempotent — the second pass copies the same files, not more" {
  bash "$COPY" "$MAIN" "$WT"
  run bash "$COPY" "$MAIN" "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"COPIED=3"* ]]
  [ "$(find "$WT/.claude" -type f | wc -l | tr -d ' ')" -eq 3 ]
}

@test "a missing worktree fails loudly instead of copying into thin air" {
  run bash "$COPY" "$MAIN" "$TMP/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REASON=worktree-missing"* ]]
}

@test "phase-2 copies the crew into the integration worktree" {
  grep -q 'crew_copy.sh' "$PHASE2"
}

@test "phase-execute copies the crew into node N's worktree BEFORE node N is spawned" {
  # Not "before the first spawn of the sprint" — per-node is the whole point,
  # so the ordering is asserted inside the claim-and-spawn step where the node
  # worktree is created.
  grep -q 'crew_copy.sh' "$PHASEX"
  local copy_line spawn_line
  copy_line="$(grep -n 'crew_copy.sh' "$PHASEX" | head -1 | cut -d: -f1)"
  spawn_line="$(grep -n 'spawn the teammate' "$PHASEX" | head -1 | cut -d: -f1)"
  [ -n "$copy_line" ]
  [ -n "$spawn_line" ]
  [ "$copy_line" -le "$spawn_line" ]
}

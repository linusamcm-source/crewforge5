#!/usr/bin/env bats
# art_dir.bats — regression fixtures for lib.sh::art_dir
#
# C-1: art_dir() must return a main-repo-absolute path even when invoked
# from a worktree CWD. Previously used `git rev-parse --show-toplevel`,
# which inside a worktree returns the worktree root (wrong).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  LIB_SH="$SCRIPTS/lib.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP

  # Main repo
  MAIN="$TMP/main"
  mkdir -p "$MAIN"
  cd "$MAIN"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  PLAN="docs/plans/sprint-mech-1.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
  SPRINT_REL=".team-sprint/sprints/sprint-sprint-mech-1"
  MAIN_ART="$MAIN/$SPRINT_REL"
  MAIN_STATE="$MAIN_ART/state.json"

  # Worktree (sibling)
  WT="$TMP/wt-mech-1"
  git worktree add -q -b sprint/mech-1 "$WT" main
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Helper to invoke art_dir() under controlled CWD.
_art_dir() {
  local cwd="$1"; shift
  cd "$cwd"
  /bin/bash -c "source '$LIB_SH' && art_dir '$1'"
}

@test "(a) state.json absent: art_dir from worktree CWD returns main-repo absolute path" {
  run _art_dir "$WT" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN_ART" ]
}

@test "(b) state.json present with absolute artifact_dir: art_dir returns stored path" {
  mkdir -p "$MAIN_ART"
  cat > "$MAIN_STATE" <<EOF
{ "artifact_dir": "$MAIN_ART" }
EOF
  run _art_dir "$WT" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN_ART" ]
}

@test "(c) state.json present but missing artifact_dir: fallback to main-repo path" {
  mkdir -p "$MAIN_ART"
  cat > "$MAIN_STATE" <<EOF
{ "plan_path": "$PLAN" }
EOF
  run _art_dir "$WT" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN_ART" ]
}

@test "(d) art_dir from worktree CWD never returns worktree-rooted path" {
  # Even with no state.json, the worktree-rooted path must NOT be returned.
  run _art_dir "$WT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != "$WT/"* ]]
  [ "$output" = "$MAIN_ART" ]
}

@test "(e) art_dir from main-repo CWD still works (no regression)" {
  run _art_dir "$MAIN" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN_ART" ]
}

# ---------------------------------------------------------------------------
# FL5: a plan that already lives DIRECTLY inside a sprint dir (a revision
# artifact like plan-v9.md) must resolve to THAT sprint dir, never to a fresh
# slug minted from its basename (obs 18980: sprint-plan-v4 was invented).
# ---------------------------------------------------------------------------

# Fixture: a sprint dir with a state.json, made in the MAIN repo.
_mk_sprint_foo_1() {
  FOO_ART="$MAIN/.team-sprint/sprints/sprint-foo-1"
  mkdir -p "$FOO_ART"
  printf '{}\n' > "$FOO_ART/state.json"
}

@test "(f) FL5: revision plan inside its sprint dir resolves there, not sprint-plan-v9" {
  _mk_sprint_foo_1
  printf '# plan v9\n' > "$FOO_ART/plan-v9.md"
  # Non-canonical path on purpose: the dir must be canonicalised before the
  # in-sprint-dir test.
  mkdir -p "$MAIN/sprints"
  run _art_dir "$MAIN" "sprints/../.team-sprint/sprints/sprint-foo-1/plan-v9.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$FOO_ART" ]
}

@test "(g) FL5: state.sh update on an in-sprint-dir plan lands in that sprint's state.json (obs 18980)" {
  _mk_sprint_foo_1
  cat > "$FOO_ART/state.json" <<EOF
{
  "plan_path": "docs/plans/foo-1.md",
  "plan_slug": "foo-1",
  "worktree_name": "foo-1",
  "target_branch": "main",
  "worktree_path": "../main-foo-1",
  "artifact_dir": "$FOO_ART",
  "started_at": "2026-07-28T00:00:00Z",
  "current_phase": 1,
  "repo_root": "$MAIN",
  "iterations": {"adversarial": 0, "coverage": 0, "review_fix": 0}
}
EOF
  printf '# plan v4\n' > "$FOO_ART/plan-v4.md"
  cd "$MAIN"
  run "$SCRIPTS/state.sh" update ".team-sprint/sprints/sprint-foo-1/plan-v4.md" 'iterations.adversarial=4'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.iterations.adversarial' "$FOO_ART/state.json")" = "4" ]
  [ ! -d "$MAIN/.team-sprint/sprints/sprint-plan-v4" ]
}

@test "(k) FL5: relative in-sprint-dir path from a worktree CWD maps to the MAIN repo sprint dir" {
  _mk_sprint_foo_1
  # A relative plan path resolved from a worktree CWD canonicalises under $WT,
  # not $MAIN, so an exact-root comparison misses it and mints sprint-plan-v4
  # from the basename (obs 18980 recurrence in the worktree call shape).
  mkdir -p "$WT/.team-sprint/sprints/sprint-foo-1"
  printf '# plan v4\n' > "$WT/.team-sprint/sprints/sprint-foo-1/plan-v4.md"
  run _art_dir "$WT" ".team-sprint/sprints/sprint-foo-1/plan-v4.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$FOO_ART" ]
}

@test "(h) FL5: plan at the repo root still resolves through slug derivation" {
  printf '# plan\n' > "$MAIN/docs/plans/foo-1.md"
  run _art_dir "$MAIN" "docs/plans/foo-1.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN/.team-sprint/sprints/sprint-foo-1" ]
}

@test "(i) FL5: plan in a non-sprint subdir of .team-sprint falls through to slug derivation" {
  mkdir -p "$MAIN/.team-sprint/notes"
  printf '# plan\n' > "$MAIN/.team-sprint/notes/foo-2.md"
  run _art_dir "$MAIN" ".team-sprint/notes/foo-2.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN/.team-sprint/sprints/sprint-foo-2" ]
}

@test "(j) FL5: deeper descendant of a sprint dir falls through (exact match, not prefix)" {
  _mk_sprint_foo_1
  mkdir -p "$FOO_ART/attachments"
  printf '# plan\n' > "$FOO_ART/attachments/foo-3.md"
  run _art_dir "$MAIN" ".team-sprint/sprints/sprint-foo-1/attachments/foo-3.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$MAIN/.team-sprint/sprints/sprint-foo-3" ]
}

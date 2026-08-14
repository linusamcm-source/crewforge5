#!/usr/bin/env bats
# subskill_resolve.bats — contract for the sub-skill resolver.
#
# The resolver exists because a skill carrying `disable-model-invocation: true`
# is unreachable through the `Skill` tool. Every "invoke the <X> skill" site has
# to become "resolve <X> to a path and load it", so the two things this file
# guards are the path answer and the *load mode*: a `context: fork` skill must be
# spawned through the `Agent` tool, never read inline, or its whole reason for
# forking (keeping its context out of the caller's window) is inverted.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  RESOLVE="$ROOT/scripts/flow/subskill_resolve.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  OUT="$TMP/out"
  ERR="$TMP/err"

  # A stray CREWFORGE5_ROOT in the ambient environment would silently retarget
  # root 1 and make every assertion below meaningless.
  unset CREWFORGE5_ROOT

  # Sandbox HOME so root 3 never reaches the developer's real catalogue.
  FAKE_HOME="$TMP/home"
  mkdir -p "$FAKE_HOME/.claude/skills"
  export HOME="$FAKE_HOME"

  # A throwaway git repo so root 2 (<repo-root>/.claude/skills) is well defined.
  mkdir -p "$TMP/repo"
  cd "$TMP/repo"
  git init -q -b main .
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Run the resolver with stdout and stderr kept apart — several ACs are about
# what does NOT appear on stdout, which bats' merged $output cannot express.
_split_run() {
  RC=0
  "$RESOLVE" "$@" >"$OUT" 2>"$ERR" || RC=$?
  STDOUT="$(cat "$OUT")"
  STDERR="$(cat "$ERR")"
}

# --- plain resolution -------------------------------------------------------

@test "resolves a plugin skill name to its absolute SKILL.md path" {
  _split_run token-slim
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$ROOT/skills/token-slim/SKILL.md" ]
}

# --- root precedence --------------------------------------------------------

@test "a name present in two roots resolves to the CREWFORGE5_ROOT copy" {
  mkdir -p "$TMP/repo/.claude/skills/token-slim"
  printf '# decoy\n' > "$TMP/repo/.claude/skills/token-slim/SKILL.md"
  _split_run token-slim
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$ROOT/skills/token-slim/SKILL.md" ]
}

@test "an exported CREWFORGE5_ROOT overrides the derived plugin root" {
  # The SessionStart hook publishes CREWFORGE5_ROOT as the plugin cache path,
  # which is nowhere near this checkout — root 1 has to follow it.
  mkdir -p "$TMP/plugin/skills/token-slim"
  printf '# installed copy\n' > "$TMP/plugin/skills/token-slim/SKILL.md"
  export CREWFORGE5_ROOT="$TMP/plugin"
  _split_run token-slim
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$TMP/plugin/skills/token-slim/SKILL.md" ]
}

@test "a name only in the repo .claude/skills resolves there" {
  mkdir -p "$TMP/repo/.claude/skills/repo-only"
  printf '# repo\n' > "$TMP/repo/.claude/skills/repo-only/SKILL.md"
  _split_run repo-only
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$TMP/repo/.claude/skills/repo-only/SKILL.md" ]
}

@test "a name only in \$HOME/.claude/skills resolves there" {
  mkdir -p "$FAKE_HOME/.claude/skills/home-only"
  printf '# home\n' > "$FAKE_HOME/.claude/skills/home-only/SKILL.md"
  _split_run home-only
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$FAKE_HOME/.claude/skills/home-only/SKILL.md" ]
}

# --- name normalisation -----------------------------------------------------

@test "master-plan and master_plan both resolve to skills/master_plan" {
  _split_run master-plan
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$ROOT/skills/master_plan/SKILL.md" ]

  _split_run master_plan
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$ROOT/skills/master_plan/SKILL.md" ]
}

@test "normalisation runs the other way too (use_repo_code -> use-repo-code)" {
  _split_run use_repo_code
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$ROOT/skills/use-repo-code/SKILL.md" ]
}

# --- misses -----------------------------------------------------------------

@test "an unknown name exits 1, names the searched roots on stderr, prints nothing" {
  _split_run no-such-skill-anywhere
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
  [[ "$STDERR" == *"$ROOT/skills"* ]]
  [[ "$STDERR" == *"$TMP/repo/.claude/skills"* ]]
  [[ "$STDERR" == *"$FAKE_HOME/.claude/skills"* ]]
}

# --- --probe ----------------------------------------------------------------

@test "--probe on a present skill exits 0 with no stdout" {
  _split_run --probe token-slim
  [ "$RC" -eq 0 ]
  [ -z "$STDOUT" ]
}

@test "--probe on an absent skill exits 1 with no stdout" {
  _split_run --probe no-such-skill-anywhere
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
}

# --- --load-mode ------------------------------------------------------------

@test "--load-mode: use-repo-code is Agent-spawned as Explore" {
  _split_run --load-mode use-repo-code
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "MODE=agent AGENT=Explore" ]
}

@test "--load-mode: the four general-purpose fork skills all report AGENT=general-purpose" {
  for s in agent-validator skill-validator tech-debt-audit ac-validate; do
    _split_run --load-mode "$s"
    [ "$RC" -eq 0 ]
    [ "$STDOUT" = "MODE=agent AGENT=general-purpose" ]
  done
}

@test "--load-mode: non-fork skills report MODE=inline" {
  # team-feature and claude-config both discuss `context: fork` in their prose
  # bodies without declaring it — a body-wide grep would misread both as forks
  # and start spawning agents for an interactive skill.
  for s in token-slim team-feature claude-config; do
    _split_run --load-mode "$s"
    [ "$RC" -eq 0 ]
    [ "$STDOUT" = "MODE=inline" ]
  done
}

@test "--load-mode on an unknown name exits 1 with no stdout" {
  _split_run --load-mode no-such-skill-anywhere
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
}

# --- usage ------------------------------------------------------------------

@test "no arguments exits 2 with usage on stderr and nothing on stdout" {
  _split_run
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
  [[ "$STDERR" == *"Usage:"* ]]
}

@test "--probe with no name exits 2" {
  _split_run --probe
  [ "$RC" -eq 2 ]
}

@test "an unknown flag exits 2" {
  _split_run --nonsense token-slim
  [ "$RC" -eq 2 ]
}

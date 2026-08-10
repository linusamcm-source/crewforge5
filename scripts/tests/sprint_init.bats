#!/usr/bin/env bats
# sprint_init.bats — contract for the rules installer.
#
# WHY THIS FILE EXISTS. `sprint_init.sh` is the first script a stranger runs after installing the
# plugin, it writes into their repo, and it shipped with three acceptance criteria — idempotence,
# uninstall-leaves-nothing, and refusal over a contradiction — asserted by inspection only. An
# installer verified by reading it is an installer nobody has verified.
#
# The contradiction check is the interesting one: it is a regex table, and a regex that is too
# greedy blocks an install nobody should have been stopped from doing, while one too narrow lets
# the plugin silently install a rule that contradicts the user's own. Both directions are tested.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  INIT="$ROOT/scripts/sprint_init.sh"
  RULES="$ROOT/rules"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  REPO="$TMP/repo"
  mkdir -p "$REPO"
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

_rule_count() { find "$RULES" -maxdepth 1 -name '*.md' | wc -l | tr -d ' '; }

@test "install links every rule file into the project" {
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 0 ]
  [ "$(find "$REPO/.claude/rules" -maxdepth 1 -type l | wc -l | tr -d ' ')" -eq "$(_rule_count)" ]
  [ -L "$REPO/.claude/rules/recon-ladder.md" ]
  # A link is only useful if it resolves — a dangling symlink passes -L and fails -f.
  [ -f "$REPO/.claude/rules/recon-ladder.md" ]
}

@test "install is idempotent — a second run changes nothing" {
  bash "$INIT" install --project "$REPO" --yes
  local before after
  before="$(find "$REPO/.claude/rules" | sort)"
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 0 ]
  after="$(find "$REPO/.claude/rules" | sort)"
  [ "$before" = "$after" ]
}

@test "uninstall removes our links and the emptied directory" {
  bash "$INIT" install --project "$REPO" --yes
  run bash "$INIT" uninstall --project "$REPO"
  [ "$status" -eq 0 ]
  [ ! -d "$REPO/.claude/rules" ]
}

@test "uninstall leaves a file that is not ours alone" {
  bash "$INIT" install --project "$REPO" --yes
  printf 'my own rule\n' > "$REPO/.claude/rules/house-style.md"
  run bash "$INIT" uninstall --project "$REPO"
  [ "$status" -eq 0 ]
  [ -f "$REPO/.claude/rules/house-style.md" ]
  grep -q 'my own rule' "$REPO/.claude/rules/house-style.md"
}

@test "a real file where a link would go is never clobbered" {
  mkdir -p "$REPO/.claude/rules"
  printf 'hand-written, not a link\n' > "$REPO/.claude/rules/git-hygiene.md"
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 0 ]
  [ ! -L "$REPO/.claude/rules/git-hygiene.md" ]
  grep -q 'hand-written, not a link' "$REPO/.claude/rules/git-hygiene.md"
  # …and the report says so rather than staying silent about the one it skipped.
  run bash "$INIT" report --project "$REPO"
  [[ "$output" == *"BLOCKED"* ]]
}

@test "install refuses over a CLAUDE.md that contradicts a shipped rule" {
  printf '# House rules\n\nStage everything with `git add -A` before committing.\n' > "$REPO/CLAUDE.md"
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"* ]]
  # Refusing means refusing: nothing may be written on the way to the refusal.
  [ ! -d "$REPO/.claude/rules" ]
}

@test "the find rule is caught too, not just the staging one" {
  printf '# House rules\n\nSearch with `find ~ -name "*.ts"` when you need to.\n' > "$REPO/CLAUDE.md"
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"* ]]
}

@test "a CLAUDE.md that AGREES with us does not trip the check" {
  # The false-positive direction. "git add src/main.py" and prose that merely mentions staging
  # must install cleanly, or the guard blocks the people who already do the right thing.
  printf '# House rules\n\nStage explicit paths, e.g. `git add src/main.py`. Never stage wholesale.\nScope every `find` to the project tree.\n' > "$REPO/CLAUDE.md"
  run bash "$INIT" install --project "$REPO" --yes
  [ "$status" -eq 0 ]
  [ -L "$REPO/.claude/rules/git-hygiene.md" ]
}

@test "report on a clean target names every rule as new and finds no conflict" {
  run bash "$INIT" report --project "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new       recon-ladder.md"* ]]
  [[ "$output" == *"(none)"* ]]
}

@test "an unknown mode is a usage error, not a silent no-op" {
  run bash "$INIT" frobnicate --project "$REPO"
  [ "$status" -eq 2 ]
}

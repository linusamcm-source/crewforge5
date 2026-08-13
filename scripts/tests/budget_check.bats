#!/usr/bin/env bats
# budget_check.bats — contract for the always-loaded context gate.
#
# The gate measured cost and nothing else, which left a hole: a fourth entry
# point whose description happened to be cheap paid its tokens and walked
# straight through. Cost and shape are separate claims, so the count assertion
# is tested with a budget deliberately set far above the fixture's cost — if it
# only fired because the fixture went over budget, it would prove nothing.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  GATE="$ROOT/scripts/budget_check.sh"
  VALIDATE="$ROOT/scripts/validate_all.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  FX="$TMP/fx"
  mkdir -p "$FX/scripts" "$FX/agents" "$FX/commands"
  cp "$GATE" "$FX/scripts/budget_check.sh"
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

# mkskill <name> <description> [hidden]
mkskill() {
  mkdir -p "$FX/skills/$1"
  {
    echo "---"
    echo "name: $1"
    echo "description: $2"
    if [ "${3:-}" = "hidden" ]; then echo "disable-model-invocation: true"; fi
    echo "---"
    echo
    echo "# $1"
  } > "$FX/skills/$1/SKILL.md"
}

three_entry_points() {
  mkskill init "Start a crew."
  mkskill plan "Plan a sprint."
  mkskill execute "Run a sprint."
  mkskill team-sprint "Hidden worker." hidden
}

# --- AC: the real tree passes and lists exactly the three entry points -------

@test "the post-condensation tree passes --verbose and prints its total" {
  run bash "$GATE" --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"always-loaded:"* ]]
  [[ "$output" == *"PASS:"* ]]
}

@test "init, plan and execute are the only non-hidden skills in the table" {
  run bash "$GATE" --verbose
  [ "$status" -eq 0 ]
  local listed
  listed="$(printf '%s\n' "$output" \
    | awk '$2 == "skill" && $0 !~ /\(hidden\)/ { print $3 }' | sort | tr '\n' ' ')"
  [ "$listed" = "execute init plan " ]
}

# --- AC: a fourth listed skill fails even when it is cheap ------------------

@test "a fourth listed skill fails the gate under a budget it never approaches" {
  three_entry_points
  mkskill extra "Tiny."
  run bash "$FX/scripts/budget_check.sh" --budget 5000
  [ "$status" -eq 1 ]
  [[ "$output" == *"extra"* ]]
}

@test "the same fixture without the fourth skill passes" {
  three_entry_points
  run bash "$FX/scripts/budget_check.sh" --budget 5000
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS:"* ]]
}

@test "a missing entry point fails too — the shape is asserted both ways" {
  mkskill init "Start a crew."
  mkskill plan "Plan a sprint."
  run bash "$FX/scripts/budget_check.sh" --budget 5000
  [ "$status" -eq 1 ]
  [[ "$output" == *"execute"* ]]
}

@test "hiding a would-be fourth entry point clears it" {
  three_entry_points
  mkskill extra "Tiny." hidden
  run bash "$FX/scripts/budget_check.sh" --budget 5000
  [ "$status" -eq 0 ]
}

# --- AC: --budget still overrides, and the default is the measured value ----

@test "--budget still overrides in both directions" {
  run bash "$GATE" --budget 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"over budget"* ]]

  run bash "$GATE" --budget 5000
  [ "$status" -eq 0 ]
}

@test "the recorded default is the measured value, with no slack" {
  run bash "$GATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: 0 tok of headroom"* ]]
}

@test "a bad flag is a usage error on stderr" {
  run bash "$GATE" --nonsense
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

# --- AC: validate_all.sh invokes it and fails when it fails -----------------

@test "validate_all.sh prints the budget verdict" {
  run bash "$VALIDATE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"always-loaded:"* ]]
  [[ "$output" == *"components structurally clean"* ]]
}

@test "validate_all.sh fails when the budget gate fails" {
  cp "$VALIDATE" "$FX/scripts/validate_all.sh"
  printf '#!/usr/bin/env bash\necho "FAIL: over budget by 9 tok"\nexit 1\n' \
    > "$FX/scripts/budget_check.sh"
  run bash "$FX/scripts/validate_all.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"over budget by 9 tok"* ]]
}

@test "validate_all.sh passes when the budget gate passes" {
  cp "$VALIDATE" "$FX/scripts/validate_all.sh"
  printf '#!/usr/bin/env bash\necho "PASS: 0 tok of headroom"\nexit 0\n' \
    > "$FX/scripts/budget_check.sh"
  run bash "$FX/scripts/validate_all.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 tok of headroom"* ]]
}

# --- AC: runs in under 2 seconds -------------------------------------------

@test "the gate runs in under 2 seconds on this tree" {
  local start=$SECONDS
  bash "$GATE" --verbose >/dev/null 2>&1
  [ $((SECONDS - start)) -lt 2 ]
}

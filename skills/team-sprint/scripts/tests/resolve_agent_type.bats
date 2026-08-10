#!/usr/bin/env bats
# resolve_agent_type.bats — the ONE canonical agent-type precedence.
#
#   explicit non-`auto` config <config_key>  >  state.json .crew.<crew_key>  >  default
#
# The rule was restated in prose in SKILL.md, phase-3.md (x2) and phase-4.md.
# These tests are what makes the single implementation trustworthy enough for
# those four prose copies to be replaced by a call.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  CFG="$TMP/cfg.yaml"
  ST="$TMP/state.json"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib.sh"
}

teardown() { rm -rf "$TMP"; }

R() { resolve_agent_type "$CFG" "$ST" test_writer_agent tester rn-test; }

# --- tier 3: default --------------------------------------------------------

@test "no config, no state -> static default" {
  [ "$(R)" = "rn-test" ]
}

@test "empty config + empty crew -> static default" {
  echo "" > "$CFG"; echo '{}' > "$ST"
  [ "$(R)" = "rn-test" ]
}

@test "crew present but this role absent -> static default" {
  echo '{"crew":{"developer":"go-developer"}}' > "$ST"
  [ "$(R)" = "rn-test" ]
}

@test "crew value null -> falls through to default" {
  echo '{"crew":{"tester":null}}' > "$ST"
  [ "$(R)" = "rn-test" ]
}

# --- tier 2: crew manifest --------------------------------------------------

@test "crew manifest beats the static default" {
  echo '{"crew":{"tester":"go-tester"}}' > "$ST"
  [ "$(R)" = "go-tester" ]
}

@test "crew manifest used when config says auto" {
  printf 'test_writer_agent: auto\n' > "$CFG"
  echo '{"crew":{"tester":"go-tester"}}' > "$ST"
  [ "$(R)" = "go-tester" ]
}

@test "malformed state.json falls through, does not crash" {
  echo 'NOT JSON {' > "$ST"
  [ "$(R)" = "rn-test" ]
}

# --- tier 1: explicit config override ---------------------------------------

@test "explicit config beats the crew manifest" {
  printf 'test_writer_agent: python-tester\n' > "$CFG"
  echo '{"crew":{"tester":"go-tester"}}' > "$ST"
  [ "$(R)" = "python-tester" ]
}

@test "explicit config beats the default with no crew at all" {
  printf 'test_writer_agent: python-tester\n' > "$CFG"
  [ "$(R)" = "python-tester" ]
}

@test "literal 'auto' is a sentinel, never resolves to itself" {
  printf 'test_writer_agent: auto\n' > "$CFG"
  [ "$(R)" != "auto" ]
  [ "$(R)" = "rn-test" ]
}

@test "quoted config value is unquoted" {
  printf 'test_writer_agent: "python-tester"\n' > "$CFG"
  [ "$(R)" = "python-tester" ]
}

@test "commented-out config key does not count as set" {
  printf '# test_writer_agent: python-tester\n' > "$CFG"
  echo '{"crew":{"tester":"go-tester"}}' > "$ST"
  [ "$(R)" = "go-tester" ]
}

# --- shape ------------------------------------------------------------------

@test "always echoes exactly one line" {
  echo '{"crew":{"tester":"go-tester"}}' > "$ST"
  [ "$(R | wc -l | tr -d ' ')" = "1" ]
  rm -f "$ST"
  [ "$(R | wc -l | tr -d ' ')" = "1" ]
}

@test "distinct roles resolve independently from one crew manifest" {
  echo '{"crew":{"tester":"go-tester","developer":"go-developer"}}' > "$ST"
  [ "$(resolve_agent_type "$CFG" "$ST" test_writer_agent tester rn-test)" = "go-tester" ]
  [ "$(resolve_agent_type "$CFG" "$ST" engineer_agent developer rn-engineer)" = "go-developer" ]
}

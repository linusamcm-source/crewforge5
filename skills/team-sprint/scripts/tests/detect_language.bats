#!/usr/bin/env bats
# detect_language.bats — the ONE canonical language-marker table.
#
# The marker list was restated in prose in crew-factory Phase 0 and
# team-sprint phase-0 step 10a.1, and the two copies drifted (powershell in
# one, missing in the other; bash in neither). These tests are what makes the
# single implementation trustworthy enough for both prose copies to be
# replaced by a call.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown() { rm -rf "$TMP"; }

D() { bash "$SCRIPTS/detect_language.sh" "$TMP"; }

@test "pyproject.toml -> python" {
  touch "$TMP/pyproject.toml"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=python')" ]
}

@test "setup.py -> python" {
  touch "$TMP/setup.py"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=python')" ]
}

@test "package.json with react-native dep -> react-native" {
  echo '{"dependencies":{"react-native":"0.75.0"}}' > "$TMP/package.json"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=react-native')" ]
}

@test "package.json with react-native devDependency -> react-native" {
  echo '{"devDependencies":{"react-native":"0.75.0"}}' > "$TMP/package.json"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=react-native')" ]
}

@test "package.json without react-native -> typescript" {
  echo '{"dependencies":{"express":"4.0.0"}}' > "$TMP/package.json"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=typescript')" ]
}

@test "go.mod -> go" {
  touch "$TMP/go.mod"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=go')" ]
}

@test "Cargo.toml -> rust" {
  touch "$TMP/Cargo.toml"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=rust')" ]
}

@test "psd1 module file -> powershell" {
  touch "$TMP/module.psd1"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=powershell')" ]
}

@test "sh-dominant tree with no manifest marker -> bash" {
  touch "$TMP/a.sh" "$TMP/b.sh"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=bash')" ]
}

@test "sh files do NOT win when another marker is present" {
  touch "$TMP/a.sh" "$TMP/go.mod"
  [ "$(D)" = "$(printf 'STATUS=OK\nLANG=go')" ]
}

@test "sh outnumbered by other sources -> UNKNOWN, not bash" {
  touch "$TMP/a.sh" "$TMP/b.py" "$TMP/c.py"
  [ "$(D)" = "STATUS=UNKNOWN" ]
}

@test "two marker families -> AMBIGUOUS with both candidates" {
  touch "$TMP/pyproject.toml" "$TMP/go.mod"
  out="$(D)"
  [ "$(printf '%s' "$out" | head -1)" = "STATUS=AMBIGUOUS" ]
  printf '%s' "$out" | grep -q 'CANDIDATES=python,go'
}

@test "empty dir -> UNKNOWN" {
  [ "$(D)" = "STATUS=UNKNOWN" ]
}

@test "nonexistent dir -> exit 1" {
  run bash "$SCRIPTS/detect_language.sh" "$TMP/nope"
  [ "$status" -ne 0 ]
}

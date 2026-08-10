#!/usr/bin/env bats
# graphify_ensure.bats — first coverage for scripts/graphify_ensure.sh.
#
# The script had 232 lines and ZERO tests. --ensure/--verify shell out to
# uv/pip/graphify and are not hermetically testable here, so this fixture pins
# the surface that IS pure: argument parsing, target-dir resolution, and the
# --graph-status freshness state machine (MISSING/FRESH/STALE) that Phase 0 and
# Phase 2 branch on. No network, no installs.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GE="$SCRIPTS/graphify_ensure.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

# --- argument parsing -------------------------------------------------------

@test "unknown flag -> exit 1 with usage" {
  run bash "$GE" --not-a-real-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "-h / --help -> exit 1 with usage" {
  run bash "$GE" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "--max-age-minutes with no value -> usage" {
  run bash "$GE" --graph-status --max-age-minutes
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "--max-age-minutes non-integer -> fails loudly, names the bad value" {
  run bash "$GE" --graph-status --max-age-minutes abc --target-dir "$TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"abc"* ]]
}

@test "--max-age-minutes negative -> rejected (regex is non-negative only)" {
  run bash "$GE" --graph-status --max-age-minutes -5 --target-dir "$TMP"
  [ "$status" -ne 0 ]
}

@test "--target-dir that is not a directory -> fails, names the path" {
  run bash "$GE" --graph-status --target-dir "$TMP/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nope"* ]]
}

# --- --graph-status state machine ------------------------------------------

@test "graph-status: no graphify-out/graph.json -> STATUS=MISSING" {
  run bash "$GE" --graph-status --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=MISSING"* ]]
}

@test "graph-status: graphify-out exists but no graph.json -> STATUS=MISSING" {
  mkdir -p "$TMP/graphify-out"
  run bash "$GE" --graph-status --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=MISSING"* ]]
}

@test "graph-status: freshly written graph.json -> STATUS=FRESH" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  run bash "$GE" --graph-status --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

@test "graph-status: old graph.json -> STATUS=STALE" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  touch -t 202001010000 "$TMP/graphify-out/graph.json"
  run bash "$GE" --graph-status --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=STALE"* ]]
}

@test "graph-status: --max-age-minutes 0 makes any existing graph STALE (boundary)" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  touch -t 202001010000 "$TMP/graphify-out/graph.json"
  run bash "$GE" --graph-status --max-age-minutes 0 --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=STALE"* ]]
}

@test "graph-status: a huge max-age keeps an ancient graph FRESH" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  touch -t 202001010000 "$TMP/graphify-out/graph.json"
  run bash "$GE" --graph-status --max-age-minutes 99999999 --target-dir "$TMP"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

@test "graph-status never mutates the target dir" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  before="$(find "$TMP" | sort | md5 -q 2>/dev/null || find "$TMP" | sort | md5sum | cut -d' ' -f1)"
  run bash "$GE" --graph-status --target-dir "$TMP"
  assert_success
  after="$(find "$TMP" | sort | md5 -q 2>/dev/null || find "$TMP" | sort | md5sum | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

# --- target-dir resolution --------------------------------------------------

@test "relative --target-dir binds to the caller's CWD" {
  mkdir -p "$TMP/sub/graphify-out"; echo '{}' > "$TMP/sub/graphify-out/graph.json"
  run bash -c "cd '$TMP' && bash '$GE' --graph-status --target-dir sub"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

@test "omitted --target-dir defaults to CWD" {
  mkdir -p "$TMP/graphify-out"; echo '{}' > "$TMP/graphify-out/graph.json"
  run bash -c "cd '$TMP' && bash '$GE' --graph-status"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

# --- path robustness (regression: raw interpolation into python source) ------

@test "a target dir containing an apostrophe does not break --graph-status" {
  d="$TMP/it's a project"
  mkdir -p "$d/graphify-out"; echo '{"nodes":[1]}' > "$d/graphify-out/graph.json"
  run bash "$GE" --graph-status --target-dir "$d"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

@test "a target dir containing a space resolves correctly" {
  d="$TMP/two words"
  mkdir -p "$d/graphify-out"; echo '{}' > "$d/graphify-out/graph.json"
  run bash "$GE" --graph-status --target-dir "$d"
  assert_success
  [[ "$output" == *"STATUS=FRESH"* ]]
}

# --- resolve_python / uv invocation shape -----------------------------------

@test "uv branch passes --from (bare 'uv tool run graphifyy python' never resolves)" {
  # The package is graphifyy; its only executable is `graphify`. Without --from,
  # uv is asked for an executable named graphifyy and returns empty, so the
  # branch silently never fired and --check reported MISSING on healthy installs.
  run grep -n 'uv tool run' "$GE"
  assert_success
  [[ "$output" == *"--from graphifyy"* ]]
}

@test "shebang parsing allows '@' (Homebrew versioned python) and anchors the strip" {
  # /opt/homebrew/opt/python@3.13/... is the common macOS layout; the old
  # allowlist rejected it, and `tr -d '#!'` stripped those chars anywhere.
  run grep -n 'a-zA-Z0-9/_.@' "$GE"
  assert_success
  # Comment lines legitimately mention the old form when explaining the fix, so
  # assert on CODE lines only.
  run bash -c "grep -vE '^[[:space:]]*#' '$GE' | grep -c \"tr -d '#!'\" || true"
  [ "$output" = "0" ]
}

@test "no python -c source is a double-quoted string (shell cannot interpolate a single-quoted one)" {
  # Every python -c must take paths via argv. The bug class is a DOUBLE-quoted
  # source, where the shell expands \$VAR straight into python source text and an
  # apostrophe in a path yields SyntaxError -> a false STATUS=FAIL. A
  # single-quoted source is inert by construction, so the precise check is
  # "no -c followed by a double quote", not "no \$ near a -c".
  run bash -c "grep -cE -- '-c \"' '$GE' || true"
  [ "$output" = "0" ]
}

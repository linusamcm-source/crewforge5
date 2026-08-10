#!/usr/bin/env bats
# run_gate.bats — fixtures for scripts/run_gate.sh.
# Uses fake gate commands (true/false/echo) via the --typecheck/--lint/--test
# flags so the suite is fast and deterministic (no real tsc/eslint/jest).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

# run --separate-stderr (below) keeps $output = stdout-only JSON, unpolluted by
# the script's [info] stderr lines. That flag needs bats >= 1.5.
bats_require_minimum_version 1.5.0

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  RG_SH="$SCRIPTS/run_gate.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  LOGS="$TMP/logs"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# gate_status <json> <gate> — echo the status string for one gate.
gate_status() {
  printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin)['gates']['$2']['status'])"
}

@test "all gates pass -> exit 0, passed true, three ran" {
  run --separate-stderr "$RG_SH" --project "$TMP" --log-dir "$LOGS" \
    --typecheck true --lint true --test "echo ok"
  assert_success
  assert_equal "$(gate_status "$output" typecheck)" passed
  assert_equal "$(gate_status "$output" lint)" passed
  assert_equal "$(gate_status "$output" test)" passed
  printf '%s' "$output" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["passed"] is True;assert d["ran"]==["typecheck","lint","test"]'
}

@test "a failing gate -> exit 1, passed false, that gate failed" {
  run --separate-stderr "$RG_SH" --project "$TMP" --log-dir "$LOGS" \
    --typecheck true --lint false --test true
  assert_failure
  assert_equal "$(gate_status "$output" lint)" failed
  printf '%s' "$output" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["passed"] is False;assert d["gates"]["lint"]["exit"]!=0'
}

@test "--skip skips a gate -> status skipped, absent from ran" {
  run --separate-stderr "$RG_SH" --project "$TMP" --log-dir "$LOGS" \
    --typecheck true --lint true --test true --skip test
  assert_success
  assert_equal "$(gate_status "$output" test)" skipped
  printf '%s' "$output" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert "test" not in d["ran"]'
}

@test "empty command with no detection -> skipped" {
  # $TMP has no project markers, so detect_commands.sh yields no test command.
  run --separate-stderr "$RG_SH" --project "$TMP" --log-dir "$LOGS" --typecheck true --lint true
  assert_success
  assert_equal "$(gate_status "$output" test)" skipped
}

@test "gate output is teed to the log file" {
  run --separate-stderr "$RG_SH" --project "$TMP" --log-dir "$LOGS" \
    --typecheck "echo TYPECHECK_MARKER" --lint true --test true
  assert_success
  grep -q TYPECHECK_MARKER "$LOGS/typecheck.log"
}

@test "re-run is idempotent: same verdict, log overwritten not appended" {
  "$RG_SH" --project "$TMP" --log-dir "$LOGS" --typecheck "echo ONCE" --lint true --test true >/dev/null
  "$RG_SH" --project "$TMP" --log-dir "$LOGS" --typecheck "echo ONCE" --lint true --test true >/dev/null
  assert_equal "$(grep -c ONCE "$LOGS/typecheck.log")" 1
}

@test "bad --project dir -> exit 3" {
  run --separate-stderr "$RG_SH" --project "$TMP/does-not-exist"
  assert_equal "$status" 3
}

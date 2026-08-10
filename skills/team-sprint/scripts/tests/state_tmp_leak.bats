#!/usr/bin/env bats
# state_tmp_leak.bats — state.sh must not leak a tmp when interrupted.
#
# Reported by the sprint-recon-harness-1 harness agent: a 0-byte
# `state.json.tmp.Vc08yi` orphaned next to state.json. The three write paths
# mktemp "${state}.tmp.XXXXXX" and mv it into place; the EXIT trap cleared only
# the lockdir, so an interrupt BETWEEN mktemp and mv left the tmp behind. The
# schema-reject paths already `rm -f` explicitly — the gap was signal-only,
# which is why 25 existing state.bats tests never saw it.
#
# HONEST LIMITATION — READ BEFORE ADDING A "BETTER" TEST HERE.
# There is deliberately NO end-to-end signal-race test. One was written and
# discarded: a full `update` takes ~24ms and the mktemp..mv window is ~1-5ms, so
# a backgrounded process plus `kill` either dies before mktemp or after mv. It
# passed identically against the PRE-FIX script, which makes it decoration —
# a regression test that cannot fail on the broken code proves nothing and
# manufactures confidence. Widening the window with a slow `jq` PATH shim was
# also tried and did not reproduce it either.
#
# So this file tests the two things that ARE deterministic:
#   1. the trap's cleanup LOGIC, exercised directly
#   2. the WIRING — every mktemp registers, every mv deregisters — so a new
#      write path cannot silently forget to participate
# plus the normal-path and concurrency invariants.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ST="$SCRIPTS/state.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"
  PLAN="docs/plans/sprint-leak-1.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
}

teardown() { cd /; rm -rf "$TMP"; }

init_state() { bash "$ST" init "$PLAN" main sprint-leak-1 >/dev/null 2>&1; }
orphans() { find "$TMP" -name 'state.json.tmp.*' 2>/dev/null | wc -l | tr -d ' '; }

# --- normal paths -----------------------------------------------------------

@test "a normal init leaves no tmp behind" {
  run bash "$ST" init "$PLAN" main sprint-leak-1
  assert_success
  [ "$(orphans)" = "0" ]
}

@test "a normal update leaves no tmp behind" {
  init_state
  run bash "$ST" update "$PLAN" current_phase=1
  assert_success
  [ "$(orphans)" = "0" ]
}

@test "repeated updates never accumulate tmps" {
  init_state
  for n in 1 2 3 4 5; do bash "$ST" update "$PLAN" current_phase=$n >/dev/null 2>&1; done
  [ "$(orphans)" = "0" ]
}

# --- the trap's cleanup logic, exercised directly ---------------------------

@test "trap logic: an in-flight tmp registered in _STATE_TMP is removed" {
  lockdir="$TMP/l.lock"; mkdir -p "$lockdir"
  _STATE_TMP="$TMP/state.json.tmp.INFLIGHT"; printf 'partial' > "$_STATE_TMP"
  # Verbatim body of the EXIT trap installed by state.sh's lock wrapper.
  eval 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_STATE_TMP:-}" ] && rm -f "$_STATE_TMP"; true'
  [ ! -f "$TMP/state.json.tmp.INFLIGHT" ]
  [ ! -d "$lockdir" ]
}

@test "trap logic: with no tmp in flight it is a clean no-op, not an error" {
  lockdir="$TMP/l.lock"; mkdir -p "$lockdir"
  _STATE_TMP=""
  run eval 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_STATE_TMP:-}" ] && rm -f "$_STATE_TMP"; true'
  assert_success
  [ ! -d "$lockdir" ]
}

@test "trap logic: removes only the registered path, never a glob" {
  # A glob would race a parallel node executor's in-flight write.
  _STATE_TMP="$TMP/state.json.tmp.MINE"; printf 'mine'  > "$_STATE_TMP"
  decoy="$TMP/state.json.tmp.OTHERPROC";  printf 'other' > "$decoy"
  eval '[ -n "${_STATE_TMP:-}" ] && rm -f "$_STATE_TMP"; true'
  [ ! -f "$TMP/state.json.tmp.MINE" ]
  [ -f "$decoy" ]
  [ "$(cat "$decoy")" = "other" ]
}

# --- wiring: a new write path cannot forget to participate ------------------

@test "wiring: every mktemp of a state tmp registers _STATE_TMP" {
  mk="$(grep -cE 'mktemp "\$\{state\}\.tmp\.XXXXXX"' "$ST")"
  reg="$(grep -cE 'mktemp "\$\{state\}\.tmp\.XXXXXX"\)"; _STATE_TMP="\$tmp"' "$ST")"
  [ "$mk" -gt 0 ]
  [ "$mk" = "$reg" ]
}

@test "wiring: every mv of a state tmp deregisters _STATE_TMP" {
  mv="$(grep -cE 'mv "\$tmp" "\$state"' "$ST")"
  dereg="$(grep -cE 'mv "\$tmp" "\$state"; _STATE_TMP=""' "$ST")"
  [ "$mv" -gt 0 ]
  [ "$mv" = "$dereg" ]
}

@test "wiring: the lock trap clears both the lockdir and the tmp" {
  run grep -cE "trap 'rmdir \"\\\$lockdir\".*_STATE_TMP" "$ST"
  assert_success
  [ "$output" = "1" ]
}

@test "wiring: _STATE_TMP is not declared local (the trap must see it)" {
  [ "$(grep -c 'local _STATE_TMP' "$ST")" = "0" ]
}

# --- concurrency ------------------------------------------------------------

@test "a concurrent writer's tmp survives a normal update" {
  init_state
  found="$(find "$TMP" -name state.json | head -1)"
  decoy="$(dirname "$found")/state.json.tmp.OTHERPROC"
  printf '{"decoy":true}\n' > "$decoy"
  run bash "$ST" update "$PLAN" current_phase=5
  assert_success
  [ -f "$decoy" ]
  [ "$(jq -r '.decoy' "$decoy")" = "true" ]
}

@test "state.json remains valid JSON after a sequence of updates" {
  init_state
  for n in 1 2 3; do bash "$ST" update "$PLAN" current_phase=$n >/dev/null 2>&1; done
  found="$(find "$TMP" -name state.json | head -1)"
  run jq -e . "$found"
  assert_success
}

#!/usr/bin/env bats
# flow_driver.bats — contract for the shared flow driver (flow_state / flow_next
# / flow_gate).
#
# The driver generalises team-sprint's state machine so `init`, `plan` and
# `execute` share one implementation instead of three copies. What this file
# guards is the machine contract the three entry skills will be written against:
# where state lives, that a concurrent write does not lose the other writer's
# key, that the next-phase answer is a pure function of state + manifest, and
# that a failing gate is recorded rather than swallowed — a gate whose FAIL does
# not stick would let a flow walk past its own quality bar.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"
  FLOW_NEXT="$ROOT/scripts/flow/flow_next.sh"
  FLOW_GATE="$ROOT/scripts/flow/flow_gate.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  OUT="$TMP/out"
  ERR="$TMP/err"

  # A fake plugin root, so the flow manifest under test is the fixture's and
  # never this checkout's. The flow's manifest sits beside its SKILL.md, which
  # is what the Story 1 resolver finds.
  export CREWFORGE_ROOT="$TMP/plugin"
  FLOW_DIR="$CREWFORGE_ROOT/skills/init"
  mkdir -p "$FLOW_DIR/phases"
  printf -- '---\nname: init\ndescription: fixture\n---\n# init\n' > "$FLOW_DIR/SKILL.md"
  printf '# phase 0\n' > "$FLOW_DIR/phases/phase-0.md"
  printf '# phase 1\n' > "$FLOW_DIR/phases/phase-1.md"
  cat > "$FLOW_DIR/phases.json" <<'JSON'
[
  {"id": "0", "title": "Survey",  "doc": "phases/phase-0.md", "gate": "echo gate-0 ok",            "required": true},
  {"id": "1", "title": "Repair",  "doc": "phases/phase-1.md", "gate": "echo gate-1 boom; exit 3",  "required": true}
]
JSON

  # Sandbox HOME so the resolver's third root never reaches the developer's
  # real catalogue.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/skills"

  # State lives under the repo root, so the fixture needs a repo.
  mkdir -p "$TMP/repo"
  cd "$TMP/repo"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  STATE="$TMP/repo/.crewforge/init/state.json"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Several assertions are about what does NOT reach stdout, which bats' merged
# $output cannot express.
_split_run() {
  RC=0
  "$@" >"$OUT" 2>"$ERR" || RC=$?
  STDOUT="$(cat "$OUT")"
  STDERR="$(cat "$ERR")"
}

orphans() { find "$TMP" -name 'state.json.tmp.*' 2>/dev/null | wc -l | tr -d ' '; }

# --- flow_state: round-trip --------------------------------------------------

@test "set then get round-trips through .crewforge/<flow>/state.json" {
  _split_run bash "$FLOW_STATE" init set phase.0.status ok
  [ "$RC" -eq 0 ]
  [ -f "$STATE" ]

  _split_run bash "$FLOW_STATE" init get phase.0.status
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "ok" ]

  [ "$(jq -r '.phase["0"].status' "$STATE")" = "ok" ]
  [ "$(jq -r '.flow' "$STATE")" = "init" ]
}

@test "path names the repo-rooted state file without creating it" {
  _split_run bash "$FLOW_STATE" init path
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "$STATE" ]
  [ ! -e "$STATE" ]
}

@test "state lands under the repo root, not the calling directory" {
  mkdir -p "$TMP/repo/sub/dir"
  cd "$TMP/repo/sub/dir"
  bash "$FLOW_STATE" init set phase.0.status ok
  [ -f "$STATE" ]
  [ ! -e "$TMP/repo/sub/dir/.crewforge" ]
}

@test "set writes several dotted keys in one locked pass" {
  bash "$FLOW_STATE" init set phase.0.status PASS phase.0.stdout 'two words'
  [ "$(jq -r '.phase["0"].status' "$STATE")" = "PASS" ]
  [ "$(jq -r '.phase["0"].stdout' "$STATE")" = "two words" ]
}

@test "get on an unset key exits 1 with nothing on stdout" {
  bash "$FLOW_STATE" init set phase.0.status ok
  _split_run bash "$FLOW_STATE" init get phase.9.status
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
}

@test "a write that would violate the schema leaves state.json unchanged" {
  bash "$FLOW_STATE" init set phase.0.status ok
  tmp="$(mktemp)"
  jq '.phase = "not-an-object"' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  before="$(cat "$STATE")"
  _split_run bash "$FLOW_STATE" init set phase.1.status ok
  [ "$RC" -ne 0 ]
  [ "$(cat "$STATE")" = "$before" ]
}

# --- flow_state: concurrency -------------------------------------------------

# Mirrors state.bats "concurrent updates of distinct keys both survive",
# re-pointed at the shared driver. Same-key contention is deliberately NOT
# covered: last-writer-wins is the accepted semantics there too.
@test "concurrent writes of distinct keys both survive" {
  bash "$FLOW_STATE" init set phase.0.status seed
  bash "$FLOW_STATE" init set phase.0.status ok        & pid1=$!
  bash "$FLOW_STATE" init set phase.1.status pass      & pid2=$!
  bash "$FLOW_STATE" init set note 'hello there'       & pid3=$!
  wait $pid1 $pid2 $pid3

  run jq -e . "$STATE"; [ "$status" -eq 0 ]
  [ "$(jq -r '.phase["0"].status' "$STATE")" = "ok" ]
  [ "$(jq -r '.phase["1"].status' "$STATE")" = "pass" ]
  [ "$(jq -r '.note' "$STATE")" = "hello there" ]
}

# --- flow_state: tmp hygiene (the trap case pinned for state.sh) -------------

@test "a normal set leaves no orphan state.json.tmp.*" {
  bash "$FLOW_STATE" init set phase.0.status ok
  for n in 1 2 3; do bash "$FLOW_STATE" init set phase.0.status "s$n"; done
  [ "$(orphans)" = "0" ]
}

@test "trap logic: an in-flight tmp registered in _FLOW_TMP is removed" {
  lockdir="$TMP/l.lock"; mkdir -p "$lockdir"
  _FLOW_TMP="$TMP/state.json.tmp.INFLIGHT"; printf 'partial' > "$_FLOW_TMP"
  # Verbatim body of the EXIT trap installed by flow_state.sh's lock wrapper.
  eval 'rmdir "$lockdir" 2>/dev/null || true; [ -n "${_FLOW_TMP:-}" ] && rm -f "$_FLOW_TMP"; true'
  [ ! -f "$TMP/state.json.tmp.INFLIGHT" ]
  [ ! -d "$lockdir" ]
}

@test "trap logic: removes only the registered path, never a glob" {
  # A glob would race a concurrent writer's in-flight tmp.
  _FLOW_TMP="$TMP/state.json.tmp.MINE"; printf 'mine'  > "$_FLOW_TMP"
  decoy="$TMP/state.json.tmp.OTHERPROC";  printf 'other' > "$decoy"
  eval '[ -n "${_FLOW_TMP:-}" ] && rm -f "$_FLOW_TMP"; true'
  [ ! -f "$TMP/state.json.tmp.MINE" ]
  [ "$(cat "$decoy")" = "other" ]
}

@test "wiring: every mktemp registers _FLOW_TMP and every mv deregisters it" {
  mk="$(grep -cE 'mktemp "\$\{state\}\.tmp\.XXXXXX"' "$FLOW_STATE")"
  reg="$(grep -cE 'mktemp "\$\{state\}\.tmp\.XXXXXX"\)"; _FLOW_TMP="\$tmp"' "$FLOW_STATE")"
  [ "$mk" -gt 0 ]
  [ "$mk" = "$reg" ]
  mv="$(grep -cE 'mv "\$tmp" "\$state"' "$FLOW_STATE")"
  dereg="$(grep -cE 'mv "\$tmp" "\$state"; _FLOW_TMP=""' "$FLOW_STATE")"
  [ "$mv" -gt 0 ]
  [ "$mv" = "$dereg" ]
  [ "$(grep -c 'local _FLOW_TMP' "$FLOW_STATE")" = "0" ]
}

@test "a concurrent writer's tmp survives a normal set" {
  bash "$FLOW_STATE" init set phase.0.status ok
  decoy="$(dirname "$STATE")/state.json.tmp.OTHERPROC"
  printf '{"decoy":true}\n' > "$decoy"
  _split_run bash "$FLOW_STATE" init set phase.1.status ok
  [ "$RC" -eq 0 ]
  [ "$(jq -r '.decoy' "$decoy")" = "true" ]
}

# --- flow_next ---------------------------------------------------------------

@test "flow_next on a fresh state offers the first phase from phases.json" {
  _split_run bash "$FLOW_NEXT" init
  [ "$RC" -eq 0 ]
  [[ "$STDOUT" == *"STATUS=NEXT"* ]]
  [[ "$STDOUT" == *"PHASE=0"* ]]
  [[ "$STDOUT" == *"DOC=$FLOW_DIR/phases/phase-0.md"* ]]
}

@test "flow_next skips a passed phase and offers the next one" {
  bash "$FLOW_STATE" init set phase.0.status PASS
  _split_run bash "$FLOW_NEXT" init
  [ "$RC" -eq 0 ]
  [[ "$STDOUT" == *"PHASE=1"* ]]
  [[ "$STDOUT" == *"DOC=$FLOW_DIR/phases/phase-1.md"* ]]
}

@test "flow_next prints STATUS=DONE once every phase is marked pass" {
  bash "$FLOW_STATE" init set phase.0.status pass phase.1.status pass
  _split_run bash "$FLOW_NEXT" init
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=DONE" ]
}

@test "flow_next on a flow with no manifest exits 1 with nothing on stdout" {
  _split_run bash "$FLOW_NEXT" no-such-flow
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
  [ -n "$STDERR" ]
}

# --- flow_gate ---------------------------------------------------------------

@test "a passing gate records PASS plus its stdout and exits 0" {
  _split_run bash "$FLOW_GATE" init 0
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [ "$(jq -r '.phase["0"].status' "$STATE")" = "PASS" ]
  [ "$(jq -r '.phase["0"].stdout' "$STATE")" = "gate-0 ok" ]
}

@test "a passing gate lets flow_next advance to the following phase" {
  bash "$FLOW_GATE" init 0
  _split_run bash "$FLOW_NEXT" init
  [[ "$STDOUT" == *"PHASE=1"* ]]
}

@test "a failing gate records FAIL and its stdout, and exits the gate's code" {
  _split_run bash "$FLOW_GATE" init 1
  [ "$RC" -eq 3 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
  [ "$(jq -r '.phase["1"].status' "$STATE")" = "FAIL" ]
  [ "$(jq -r '.phase["1"].stdout' "$STATE")" = "gate-1 boom" ]
}

@test "after a failing gate flow_next re-offers the same phase" {
  bash "$FLOW_STATE" init set phase.0.status PASS
  bash "$FLOW_GATE" init 1 || true
  _split_run bash "$FLOW_NEXT" init
  [ "$RC" -eq 0 ]
  [[ "$STDOUT" == *"PHASE=1"* ]]
  [[ "$STDOUT" != *"STATUS=DONE"* ]]
}

@test "a gate runs from the repo root, whatever the caller's directory" {
  cat > "$FLOW_DIR/phases.json" <<'JSON'
[{"id": "0", "title": "Where", "doc": "phases/phase-0.md", "gate": "pwd", "required": true}]
JSON
  mkdir -p "$TMP/repo/sub"
  cd "$TMP/repo/sub"
  bash "$FLOW_GATE" init 0
  [ "$(jq -r '.phase["0"].stdout' "$STATE")" = "$TMP/repo" ]
}

@test "a phase absent from the manifest exits 1 with nothing on stdout" {
  _split_run bash "$FLOW_GATE" init 9
  [ "$RC" -eq 1 ]
  [ -z "$STDOUT" ]
  [ -n "$STDERR" ]
}

@test "a phase declaring no gate records PASS without running anything" {
  cat > "$FLOW_DIR/phases.json" <<'JSON'
[{"id": "0", "title": "Prose only", "doc": "phases/phase-0.md", "gate": "", "required": false}]
JSON
  _split_run bash "$FLOW_GATE" init 0
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [ "$(jq -r '.phase["0"].status' "$STATE")" = "PASS" ]
}

# --- usage -------------------------------------------------------------------

@test "flow_state with no arguments exits 2 with usage on stderr" {
  _split_run bash "$FLOW_STATE"
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
  [[ "$STDERR" == *"flow_state.sh <flow>"* ]]
}

@test "flow_state with an unknown subcommand exits 2" {
  _split_run bash "$FLOW_STATE" init frobnicate
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
}

@test "flow_next with no flow exits 2 with usage on stderr" {
  _split_run bash "$FLOW_NEXT"
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
  [[ "$STDERR" == *"flow_next.sh <flow>"* ]]
}

@test "flow_gate without a phase exits 2 with usage on stderr" {
  _split_run bash "$FLOW_GATE" init
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
  [[ "$STDERR" == *"flow_gate.sh <flow> <phase>"* ]]
}

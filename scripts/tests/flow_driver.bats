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
  export CREWFORGE5_ROOT="$TMP/plugin"
  FLOW_DIR="$CREWFORGE5_ROOT/skills/init"
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

  # Subject-keyed: <flow>/<subject>/state.json, subject defaulting to "default".
  # A test that switches subject re-derives its own path.
  STATE="$TMP/repo/.crewforge5/init/default/state.json"
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

@test "set then get round-trips through .crewforge5/<flow>/state.json" {
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
  [ ! -e "$TMP/repo/sub/dir/.crewforge5" ]
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

# The AC is "an interrupt between mktemp and mv leaves no orphan
# state.json.tmp.*", so the proof has to interrupt the real script at exactly
# that point rather than re-enact the trap body in the test file. A `jq` shim on
# PATH SIGTERMs its parent — flow_state.sh — on the write pass, which is the one
# jq call that happens after mktemp and before mv.
#
# Both lock branches get their own case, because they are different code paths
# and CI runs both hosts: ubuntu-latest takes the flock branch, macos-latest the
# mkdir mutex. A trap installed on only one of them is a leak on the other, and
# that is the shape of the bug this pins.

_killer_jq_dir() {
  local d="$TMP/shim" real
  real="$(command -v jq)"
  mkdir -p "$d"
  cat > "$d/jq" <<SHIM
#!/usr/bin/env bash
# Real jq everywhere except the write pass — the only call carrying setpath —
# where it kills flow_state.sh while its tmp is in flight.
for a in "\$@"; do
  case "\$a" in
    *setpath*) kill -TERM "\$PPID"; exit 1 ;;
  esac
done
exec "$real" "\$@"
SHIM
  chmod +x "$d/jq"
  printf '%s\n' "$d"
}

# A PATH carrying every command flow_state.sh shells out to, minus flock, so a
# host that has flock still exercises the mkdir-mutex branch.
_path_without_flock() {
  local d="$TMP/noflock" t p
  mkdir -p "$d"
  for t in bash git date mktemp mv rm rmdir sleep dirname mkdir sed; do
    p="$(command -v "$t")" || return 1
    ln -sf "$p" "$d/$t"
  done
  printf '%s\n' "$d"
}

# The decoy stands in for a concurrent writer's in-flight tmp: cleanup must
# remove this process's registered path and never a glob.
_interrupted_set() { # $1 = PATH to run the interrupted write under
  bash "$FLOW_STATE" init set phase.0.status seed
  DECOY="$(dirname "$STATE")/state.json.tmp.OTHERPROC"
  printf 'other' > "$DECOY"
  RC=0
  PATH="$1" bash "$FLOW_STATE" init set phase.1.status boom >"$OUT" 2>"$ERR" || RC=$?
}

_orphans_beside_decoy() {
  find "$TMP" -name 'state.json.tmp.*' ! -name '*OTHERPROC' 2>/dev/null | wc -l | tr -d ' '
}

@test "an interrupt between mktemp and mv leaves no orphan on the flock path" {
  command -v flock >/dev/null 2>&1 || skip "no flock here; the mkdir-mutex case covers this host"
  _interrupted_set "$(_killer_jq_dir):$PATH"
  [ "$RC" -ne 0 ]
  [ "$(_orphans_beside_decoy)" = "0" ]
  [ "$(cat "$DECOY")" = "other" ]
}

@test "an interrupt between mktemp and mv leaves no orphan on the mkdir-mutex path" {
  nf="$(_path_without_flock)" || skip "cannot build a flock-free PATH on this host"
  # Guard the guard: if flock were still reachable this would silently be a
  # second copy of the test above. Spelled as an if/return rather than `! cmd`,
  # which under bats does not fail a test (SC2314).
  if PATH="$nf" command -v flock >/dev/null 2>&1; then
    printf 'flock is still reachable on the sandboxed PATH\n' >&2
    return 1
  fi
  _interrupted_set "$(_killer_jq_dir):$nf"
  [ "$RC" -ne 0 ]
  [ "$(_orphans_beside_decoy)" = "0" ]
  [ "$(cat "$DECOY")" = "other" ]
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

# --- subject keying ----------------------------------------------------------
#
# State keyed by flow alone made a finished run answer STATUS=DONE for the next
# subject before it had started, and restarting meant deleting state.json by
# hand. These guard the key, the pointer, and the one-time migration that keeps
# an in-flight pre-subject run from losing its place.

@test "state lands under .crewforge5/<flow>/<subject>/state.json" {
  run "$FLOW_STATE" init path
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/repo/.crewforge5/init/default/state.json" ]
}

@test "use points later calls at another subject" {
  "$FLOW_STATE" init use other
  run "$FLOW_STATE" init subject
  [ "$output" = "other" ]
  run "$FLOW_STATE" init path
  [ "$output" = "$TMP/repo/.crewforge5/init/other/state.json" ]
}

@test "two subjects keep separate phase status" {
  "$FLOW_STATE" init set phase.0.status PASS phase.1.status PASS
  "$FLOW_STATE" init use second
  run "$FLOW_NEXT" init
  [ "$status" -eq 0 ]
  # The first subject passed every phase; the second must still start at 0.
  printf '%s\n' "$output" | grep -q '^STATUS=NEXT$'
  printf '%s\n' "$output" | grep -q '^PHASE=0$'
}

@test "a finished subject does not make a fresh one report DONE" {
  "$FLOW_STATE" init set phase.0.status PASS phase.1.status PASS
  run "$FLOW_NEXT" init
  [ "$output" = "STATUS=DONE" ]
  "$FLOW_STATE" init use another
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=0$'
}

@test "use --from slugifies free text into a subject" {
  run "$FLOW_STATE" init use --from "Add OAuth2 login to the API Gateway!"
  [ "$status" -eq 0 ]
  [ "$output" = "SUBJECT=add-oauth2-login-to-the-api-gateway" ]
}

@test "a subject that would escape the flow directory is refused" {
  run "$FLOW_STATE" init use ../escape
  [ "$status" -eq 1 ]
  run "$FLOW_STATE" init use "a/b"
  [ "$status" -eq 1 ]
}

@test "list names every subject and marks the current one" {
  "$FLOW_STATE" init set phase.0.status PASS
  "$FLOW_STATE" init use other
  "$FLOW_STATE" init set phase.0.status PASS
  run "$FLOW_STATE" init list
  printf '%s\n' "$output" | grep -q '^SUBJECT=default CURRENT=no PASSED=1 '
  printf '%s\n' "$output" | grep -q '^SUBJECT=other CURRENT=yes PASSED=1 '
}

@test "reset discards one subject's state and leaves the other" {
  "$FLOW_STATE" init set phase.0.status PASS
  "$FLOW_STATE" init use other
  "$FLOW_STATE" init set phase.0.status PASS
  run "$FLOW_STATE" init reset other
  [ "$output" = "RESET=other" ]
  [ ! -e "$TMP/repo/.crewforge5/init/other" ]
  [ -f "$TMP/repo/.crewforge5/init/default/state.json" ]
}

@test "reset on a subject with no state says so rather than failing" {
  run "$FLOW_STATE" init reset never-started
  [ "$status" -eq 0 ]
  [ "$output" = "RESET=never-started NOTHING=1" ]
}

@test "a pre-subject state.json is migrated under default/ rather than stranded" {
  mkdir -p "$TMP/repo/.crewforge5/init"
  printf '{"flow":"init","started_at":"x","phase":{"0":{"status":"PASS"}}}\n' \
    > "$TMP/repo/.crewforge5/init/state.json"
  # _split_run, not `run`: the migration announces itself on stderr, and the
  # whole point of this assertion is that the announcement does NOT reach
  # stdout — a caller reading `v="$(flow_state.sh init get k)"` must get the
  # value alone. bats' merged $output cannot express that.
  _split_run "$FLOW_STATE" init get phase.0.status
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "PASS" ]
  case "$STDERR" in *"moved pre-subject state"*) ;; *) return 1 ;; esac
  [ -f "$TMP/repo/.crewforge5/init/default/state.json" ]
  [ ! -f "$TMP/repo/.crewforge5/init/state.json" ]
}

@test "CREWFORGE5_SUBJECT overrides the recorded pointer" {
  "$FLOW_STATE" init use pointed-at
  CREWFORGE5_SUBJECT=env-wins run "$FLOW_STATE" init subject
  [ "$output" = "env-wins" ]
}

# --- when / status_source ----------------------------------------------------
#
# Two manifest fields that let a flow whose phases are owned elsewhere stop
# keeping a second copy of their progress. `when` decides whether a phase is in
# this run at all; `status_source` names who answers how far the run has got.
# Both exist for `execute`, which wraps team-sprint — but the driver stays
# flow-agnostic, so they are tested here against a fixture manifest.

_object_manifest() { # $1 status_source cmd  $2 `when` for phase 1
  cat > "$FLOW_DIR/phases.json" <<JSON
{
  "status_source": "$1",
  "phases": [
    {"id": "0", "title": "A", "doc": "phases/phase-0.md", "gate": "true", "required": true},
    {"id": "1", "title": "B", "doc": "phases/phase-1.md", "gate": "true", "required": true, "when": "$2"},
    {"id": "2", "title": "C", "doc": "phases/phase-0.md", "gate": "true", "required": true}
  ]
}
JSON
}

@test "the object manifest form is read the same as the bare array" {
  _object_manifest "" "true"
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=0$'
}

@test "a phase whose when fails is dropped from the run" {
  _object_manifest "" "false"
  "$FLOW_STATE" init set phase.0.status PASS
  run "$FLOW_NEXT" init
  # Phase 1 is excluded, so phase 2 is next rather than 1.
  printf '%s\n' "$output" | grep -q '^PHASE=2$'
}

@test "a when-excluded phase cannot be gated" {
  _object_manifest "" "false"
  run "$FLOW_GATE" init 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'excluded from this run'
}

@test "status_source passes every phase before the one it names" {
  _object_manifest "echo PHASE=2" "true"
  run "$FLOW_NEXT" init
  # Phases 0 and 1 are passed by the source alone — nothing recorded them.
  printf '%s\n' "$output" | grep -q '^PHASE=2$'
  run "$FLOW_STATE" init get phase.0.status
  [ "$status" -eq 1 ]
}

@test "status_source with DONE=1 passes the phase it names too" {
  _object_manifest "printf 'PHASE=2\nDONE=1\n'" "true"
  run "$FLOW_NEXT" init
  [ "$output" = "STATUS=DONE" ]
}

@test "a status_source that exits non-zero leaves state.json deciding" {
  _object_manifest "exit 1" "true"
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=0$'
}

@test "a status_source naming a phase not in the manifest has no opinion" {
  _object_manifest "echo PHASE=99" "true"
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=0$'
}

@test "state.json still passes a phase the status_source has not reached" {
  _object_manifest "echo PHASE=0" "true"
  "$FLOW_STATE" init set phase.0.status PASS phase.1.status PASS
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=2$'
}

@test "when and status_source run from the repo root, not the caller's cwd" {
  _object_manifest "test -f .crewforge5/marker && echo PHASE=2" "true"
  mkdir -p "$TMP/repo/.crewforge5" && touch "$TMP/repo/.crewforge5/marker"
  mkdir -p "$TMP/repo/deep/dir" && cd "$TMP/repo/deep/dir"
  run "$FLOW_NEXT" init
  printf '%s\n' "$output" | grep -q '^PHASE=2$'
}

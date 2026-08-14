#!/usr/bin/env bats
# state.bats — fixtures for scripts/state.sh
#
# LS1 (schema reconciliation): the machine schema state.schema.json is the
# single source of truth. The final section below pins two contracts — the
# graph-mode keys (crew, crew_commands, scheduling, graph_path,
# worktree_strategy) round-trip through update+read today, and the machine
# schema must NAME those keys, drop the dead `subskills` map, and stop
# claiming in its $comment that lint_skill.sh MUST validate against it.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  STATE_SH="$SCRIPTS/state.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"

  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  PLAN="docs/plans/sprint-mech-1.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
  STATE="$TMP/.team-sprint/sprints/sprint-sprint-mech-1/state.json"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# --- init / read / update --------------------------------------------------

@test "init creates state.json with required fields" {
  run "$STATE_SH" init "$PLAN" develop sprint-mech-1
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]

  run jq -r '.plan_path'     "$STATE"; [ "$output" = "$PLAN" ]
  run jq -r '.target_branch' "$STATE"; [ "$output" = "develop" ]
  run jq -r '.current_phase' "$STATE"; [ "$output" = "0" ]
  run jq -r '.iterations.adversarial' "$STATE"; [ "$output" = "0" ]
  run jq -r '.iterations.coverage'    "$STATE"; [ "$output" = "0" ]
  run jq -r '.iterations.review_fix'  "$STATE"; [ "$output" = "0" ]
  run jq -r '.repo_root'     "$STATE"; [ "$output" = "$TMP" ]
  run jq -r '.artifact_dir'  "$STATE"; [ "$output" = "$TMP/.team-sprint/sprints/sprint-sprint-mech-1" ]
}

@test "init refuses to clobber existing non-finalised state" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" init "$PLAN" develop sprint-mech-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to clobber"* ]]
}

@test "init allows re-init when prior state is done=true" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  tmp="$(mktemp)"
  jq '.done = true' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  run "$STATE_SH" init "$PLAN" develop sprint-mech-1
  [ "$status" -eq 0 ]
  run jq -r '.done // false' "$STATE"
  [ "$output" = "false" ]
}

@test "read prints state.json" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" read "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan_path"* ]]
}

@test "read exits 2 when missing" {
  run "$STATE_SH" read "$PLAN"
  [ "$status" -eq 2 ]
}

@test "update sets three keys top-level" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" update "$PLAN" \
    current_story_id='"mech-1"' \
    sprint_branch='"sprint/mech-1"' \
    plan_final='"plan-final.md"'
  [ "$status" -eq 0 ]

  run jq -r '.current_story_id' "$STATE"; [ "$output" = "mech-1" ]
  run jq -r '.sprint_branch'    "$STATE"; [ "$output" = "sprint/mech-1" ]
  run jq -r '.plan_final'       "$STATE"; [ "$output" = "plan-final.md" ]
}

@test "update with nested key containing '-' in component" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  "$STATE_SH" update "$PLAN" subskills='{}'
  run "$STATE_SH" update "$PLAN" subskills.integration-diagram.last_event_id='"evt-42"'
  [ "$status" -eq 0 ]
  run jq -r '.subskills."integration-diagram".last_event_id' "$STATE"
  [ "$output" = "evt-42" ]
}

@test "update rejects key whose component contains '.'" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" update "$PLAN" 'subskills..bad=42'
  [ "$status" -ne 0 ]
  # M-1: error wording is contract per plan-final AC ("Path-separator escape").
  [[ "$output" == *"unsupported character in key path"* ]]
}

# --- advance-phase ---------------------------------------------------------

@test "advance-phase valid (current+1) succeeds" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" advance-phase "$PLAN" 1
  [ "$status" -eq 0 ]
  run jq -r '.current_phase' "$STATE"; [ "$output" = "1" ]
}

@test "advance-phase invalid skips fail without --force" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" advance-phase "$PLAN" 3
  [ "$status" -ne 0 ]
  run jq -r '.current_phase' "$STATE"; [ "$output" = "0" ]
}

@test "advance-phase --force allows skip" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" advance-phase "$PLAN" 3 --force
  [ "$status" -eq 0 ]
  run jq -r '.current_phase' "$STATE"; [ "$output" = "3" ]
}

# --- resume-scan -----------------------------------------------------------

@test "resume-scan empty -> []" {
  run "$STATE_SH" resume-scan
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "resume-scan 1 active sprint" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" resume-scan
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq 'length'"
  [ "$output" = "1" ]
}

@test "resume-scan 2 active sprints" {
  P1="docs/plans/sprint-mech-1.md"
  P2="docs/plans/sprint-mech-2.md"
  printf '# p\n' > "$P2"
  "$STATE_SH" init "$P1" develop sprint-mech-1
  "$STATE_SH" init "$P2" develop sprint-mech-2
  json="$("$STATE_SH" resume-scan)"
  [ "$(echo "$json" | jq 'length')" -eq 2 ]
}

@test "resume-scan: 1 finalised + 1 active surfaces only active" {
  P1="docs/plans/sprint-mech-1.md"
  P2="docs/plans/sprint-mech-2.md"
  printf '# p\n' > "$P2"
  "$STATE_SH" init "$P1" develop sprint-mech-1
  "$STATE_SH" init "$P2" develop sprint-mech-2
  S1="$TMP/.team-sprint/sprints/sprint-sprint-mech-1/state.json"
  tmp="$(mktemp)"
  jq '.done = true' "$S1" > "$tmp" && mv "$tmp" "$S1"
  json="$("$STATE_SH" resume-scan)"
  [ "$(echo "$json" | jq 'length')" -eq 1 ]
  [ "$(echo "$json" | jq -r '.[0].plan_path')" = "$P2" ]
}

@test "resume-scan (P1-4): one malformed state.json is skipped, valid sprints still discovered" {
  P1="docs/plans/sprint-mech-1.md"
  P2="docs/plans/sprint-mech-2.md"
  printf '# p\n' > "$P2"
  "$STATE_SH" init "$P1" develop sprint-mech-1
  "$STATE_SH" init "$P2" develop sprint-mech-2
  # Inject a third sprint whose state.json is syntactically invalid. Before P1-4
  # the single `jq -s` slurp aborts under set -euo pipefail and NO sprint is
  # discovered.
  mkdir -p "$TMP/.team-sprint/sprints/sprint-bad"
  printf '{ this is not valid json ' > "$TMP/.team-sprint/sprints/sprint-bad/state.json"

  # stdout: the two valid in-flight sprints are still discovered.
  json="$("$STATE_SH" resume-scan 2>/dev/null)"
  [ "$(echo "$json" | jq 'length')" -eq 2 ]

  # stderr: the malformed file is reported as skipped.
  err="$("$STATE_SH" resume-scan 2>&1 >/dev/null)"
  [[ "$err" == *"skipping malformed state.json"* ]]
}

# --- concurrency -----------------------------------------------------------

@test "concurrent updates of distinct keys both survive" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  "$STATE_SH" update "$PLAN" current_phase='0' &
  pid1=$!
  "$STATE_SH" update "$PLAN" current_story_id='"mech-1"' &
  pid2=$!
  "$STATE_SH" update "$PLAN" sprint_branch='"sprint/mech-1"' &
  pid3=$!
  wait $pid1 $pid2 $pid3
  run jq -r '.current_story_id' "$STATE"; [ "$output" = "mech-1" ]
  run jq -r '.sprint_branch'    "$STATE"; [ "$output" = "sprint/mech-1" ]
}

# --- schema rollback -------------------------------------------------------

@test "schema-violating update leaves state.json unchanged" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  before="$(cat "$STATE")"
  run "$STATE_SH" update "$PLAN" current_phase='"not-an-int"'
  [ "$status" -ne 0 ]
  after="$(cat "$STATE")"
  [ "$before" = "$after" ]
}

# --- array replacement -----------------------------------------------------

@test "array replacement [A]+[A,B] -> [A,B]" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  "$STATE_SH" update "$PLAN" story_commits='[{"story_id":"A","sha":"aaa"}]'
  "$STATE_SH" update "$PLAN" story_commits='[{"story_id":"A","sha":"aaa"},{"story_id":"B","sha":"bbb"}]'
  run jq -r '.story_commits | length' "$STATE"; [ "$output" = "2" ]
  run jq -r '.story_commits[0].story_id' "$STATE"; [ "$output" = "A" ]
  run jq -r '.story_commits[1].story_id' "$STATE"; [ "$output" = "B" ]
}

@test "array replacement [A]+[B] -> [B]" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  "$STATE_SH" update "$PLAN" story_commits='[{"story_id":"A","sha":"aaa"}]'
  "$STATE_SH" update "$PLAN" story_commits='[{"story_id":"B","sha":"bbb"}]'
  run jq -r '.story_commits | length' "$STATE"; [ "$output" = "1" ]
  run jq -r '.story_commits[0].story_id' "$STATE"; [ "$output" = "B" ]
}

# --- init write-then-validate-then-delete-on-failure -----------------------

@test "init delete-on-failure when post-write validation breaks" {
  REAL_JQ="$(command -v jq)"
  STUBDIR="$TMP/stub"
  mkdir -p "$STUBDIR"
  cat > "$STUBDIR/jq" <<STUB
#!/usr/bin/env bash
# When the init script generates state.json (detected by -n flag in args),
# strip the required repo_root field so post-write validation fails.
strip=0
for a in "\$@"; do
  if [ "\$a" = "-n" ]; then strip=1; break; fi
done
if [ "\$strip" -eq 1 ]; then
  "$REAL_JQ" "\$@" | "$REAL_JQ" 'del(.repo_root)'
  exit \${PIPESTATUS[1]}
fi
exec "$REAL_JQ" "\$@"
STUB
  chmod +x "$STUBDIR/jq"
  PATH="$STUBDIR:$PATH" run "$STATE_SH" init "$PLAN" develop sprint-mech-1
  [ "$status" -ne 0 ]
  [ ! -f "$STATE" ]
}

# --- LS1: schema reconciliation (machine schema = source of truth) ---------

@test "LS1: crew/scheduling survive an update+read round-trip" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1

  # These keys live only in the prose schema today; the update must still
  # succeed because state.sh's validator round-trips unknown keys via
  # additionalProperties. This half characterises behaviour that already works
  # and must keep working after LS1 names the keys in the machine schema.
  # graph mode additionally requires graph_path + sprint_branch (P3-2), so a
  # valid graph state supplies them alongside scheduling.
  run "$STATE_SH" update "$PLAN" \
    crew='{"developer":"x"}' \
    scheduling='"graph"' \
    graph_path='"docs/graph.json"' \
    sprint_branch='"sprint/mech-1"'
  [ "$status" -eq 0 ]

  # `read` re-emits them, proving they survived _validate_state on write.
  run "$STATE_SH" read "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scheduling"* ]]

  run jq -r '.crew.developer' "$STATE"; [ "$output" = "x" ]
  run jq -r '.scheduling'     "$STATE"; [ "$output" = "graph" ]
}

@test "P3-2: scheduling==graph without graph_path/sprint_branch is rejected on write" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1

  # Setting scheduling=graph alone violates the graph-mode conditional-required
  # invariant (graph_path + sprint_branch). _validate_state must reject the write.
  run "$STATE_SH" update "$PLAN" scheduling='"graph"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"graph_path must be a string when scheduling==graph"* ]] \
    || [[ "$output" == *"sprint_branch must be a string when scheduling==graph"* ]]

  # Sequential mode has no such requirement.
  run "$STATE_SH" update "$PLAN" scheduling='"sequential"'
  [ "$status" -eq 0 ]
}

@test "P3-2: schema encodes the graph-mode if/then conditional-required" {
  SCHEMA="$SCRIPTS/schemas/state.schema.json"
  run jq -e '.["if"].properties.scheduling.const == "graph"
    and (.["then"].required | index("graph_path") != null)
    and (.["then"].required | index("sprint_branch") != null)' "$SCHEMA"
  [ "$status" -eq 0 ]
}

# --- FL6: plan-of-record gate ----------------------------------------------
# The reviewed plan must provably be the executed plan (obs 18983/18988: four
# review rounds ran against plan-v4 while the config pointed at the original
# plan). record-plan pins {path, sha256}; check-plan recomputes and compares.

@test "FL6: record-plan stores path + 64-hex sha256, state still schema-valid" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  ART_DIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-1"
  printf '# final plan\n' > "$ART_DIR/plan-final.md"

  run "$STATE_SH" record-plan "$PLAN" "$ART_DIR/plan-final.md"
  [ "$status" -eq 0 ]

  run jq -r '.plan_of_record.path' "$STATE"
  [ "$output" = "$ART_DIR/plan-final.md" ]
  sha="$(jq -r '.plan_of_record.sha256' "$STATE")"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]]

  # A later update re-runs _validate_state over the whole file: the recorded
  # plan_of_record must survive it (schema-valid, not merely tolerated).
  run "$STATE_SH" update "$PLAN" current_story_id='"mech-1"'
  [ "$status" -eq 0 ]
  run jq -r '.plan_of_record.sha256' "$STATE"
  [ "$output" = "$sha" ]
}

@test "FL6: check-plan on unmodified file prints STATUS=OK and exits 0" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  ART_DIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-1"
  printf '# final plan\n' > "$ART_DIR/plan-final.md"
  "$STATE_SH" record-plan "$PLAN" "$ART_DIR/plan-final.md"

  run "$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md"
  [ "$status" -eq 0 ]
  # Pin the stdout channel: STATUS goes to stdout, nothing else.
  out="$("$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md" 2>/dev/null)"
  [ "$out" = "STATUS=OK" ]
}

@test "FL6: check-plan after single-byte edit fails with both hashes on stderr" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  ART_DIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-1"
  printf '# final plan\n' > "$ART_DIR/plan-final.md"
  "$STATE_SH" record-plan "$PLAN" "$ART_DIR/plan-final.md"
  printf 'x' >> "$ART_DIR/plan-final.md"

  run "$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STATUS=FAIL"* ]]
  # stderr carries recorded vs actual hashes (stdout discarded to isolate it).
  err="$("$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md" 2>&1 >/dev/null || true)"
  [[ "$err" == *"recorded:"* ]]
  [[ "$err" == *"actual:"* ]]
}

@test "FL6: check-plan with no recorded plan_of_record fails with reason no-record" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  ART_DIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-1"
  printf '# final plan\n' > "$ART_DIR/plan-final.md"

  run "$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md"
  [ "$status" -eq 1 ]
  # Pin the channels like the sibling tests: STATUS on stdout, reason on
  # stderr ($output alone merges both and would mask a channel swap).
  out="$("$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md" 2>/dev/null || true)"
  [ "$out" = "STATUS=FAIL" ]
  err="$("$STATE_SH" check-plan "$PLAN" "$ART_DIR/plan-final.md" 2>&1 >/dev/null || true)"
  [[ "$err" == *"no-record"* ]]
}

@test "FL6: check-plan fails with reason path-mismatch on a byte-identical copy elsewhere" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  ART_DIR="$TMP/.team-sprint/sprints/sprint-sprint-mech-1"
  printf '# final plan\n' > "$ART_DIR/plan-final.md"
  "$STATE_SH" record-plan "$PLAN" "$ART_DIR/plan-final.md"
  mkdir -p "$TMP/elsewhere"
  cp "$ART_DIR/plan-final.md" "$TMP/elsewhere/plan-final.md"

  # Same bytes, different path: the gate's assurance is "same file", not
  # merely "same bytes" — a copy is not the plan of record.
  run "$STATE_SH" check-plan "$PLAN" "$TMP/elsewhere/plan-final.md"
  [ "$status" -eq 1 ]
  out="$("$STATE_SH" check-plan "$PLAN" "$TMP/elsewhere/plan-final.md" 2>/dev/null || true)"
  [ "$out" = "STATUS=FAIL" ]
  err="$("$STATE_SH" check-plan "$PLAN" "$TMP/elsewhere/plan-final.md" 2>&1 >/dev/null || true)"
  [[ "$err" == *"path-mismatch"* ]]
}

@test "FL6: check-plan with missing state.json exits 2 with no STATUS line" {
  # No init: state.json was lost or the sprint dir was never created.
  # phase-2.md documents this third branch (exit 2, no STATUS token) as STOP.
  run "$STATE_SH" check-plan "$PLAN" "$PLAN"
  [ "$status" -eq 2 ]
  out="$("$STATE_SH" check-plan "$PLAN" "$PLAN" 2>/dev/null || true)"
  [ -z "$out" ]
  err="$("$STATE_SH" check-plan "$PLAN" "$PLAN" 2>&1 >/dev/null || true)"
  [[ "$err" == *"missing"* ]]
}

@test "FL6: update with explicit plan_of_record null is rejected on write" {
  # state.schema.json declares plan_of_record "type": "object"; the write-time
  # jq validator must agree — absent is fine, explicit null is not.
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" update "$PLAN" plan_of_record='null'
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_of_record"* ]]
}

@test "state.sh fails with the jq install hint when jq is missing from PATH" {
  # Stub PATH carrying only what state.sh needs BEFORE the jq probe: bash for
  # the env shebang, dirname for the lib.sh SCRIPTS resolution.
  stub="$TMP/nojq-bin"
  mkdir -p "$stub"
  ln -s "$(command -v bash)" "$stub/bash"
  ln -s "$(command -v dirname)" "$stub/dirname"
  run env PATH="$stub" "$STATE_SH" read "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq missing"* ]]
}

@test "FL6: update with malformed plan_of_record sha256 is rejected on write" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" update "$PLAN" plan_of_record='{"path":"x","sha256":"nothex"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_of_record"* ]]
}

@test "FL6: phase-2.md entry gate STOPs on check-plan FAIL and on sprint-dir mismatch" {
  # AC: phase-2.md instructs the STOP branch on STATUS=FAIL and on sprint-dir
  # mismatch, in the STATUS-branch style of phase-0.md's graphify steps.
  doc="$SKILL_DIR/references/phases/phase-2.md"
  grep -qF 'check-plan "$plan_path" "$ART/plan-final.md"' "$doc"
  grep -qF 'STATUS=FAIL` → STOP' "$doc"
  grep -qF 'no-record' "$doc"
  grep -qF 'path-mismatch' "$doc"
  # Third branch: missing state.json → exit 2 with no STATUS line, also STOP.
  grep -qF 'exit 2 with no `STATUS=` line' "$doc"
  grep -qF 'Mismatch → STOP' "$doc"
  grep -qF 'art_dir' "$doc"
}

@test "FL6: machine schema names plan_of_record with required path + 64-hex sha256" {
  SCHEMA="$SCRIPTS/schemas/state.schema.json"
  run jq -e '.properties.plan_of_record
    | (.required == ["path", "sha256"])
      and (.properties.path.type == "string")
      and (.properties.sha256.pattern == "^[0-9a-f]{64}$")' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "LS1: machine schema names five graph keys, drops dead subskills, comment stops overclaiming" {
  SCHEMA="$SCRIPTS/schemas/state.schema.json"
  [ -f "$SCHEMA" ]

  # (1) The five keys the prose already declares must become NAMED properties in
  #     the machine schema (today they survive only via additionalProperties).
  run jq -e '.properties
    | has("crew") and has("crew_commands")
      and has("scheduling") and has("graph_path") and has("worktree_strategy")' "$SCHEMA"
  [ "$status" -eq 0 ]

  # (2) The `subskills` map nothing writes must be gone.
  run jq -e '.properties | has("subskills") | not' "$SCHEMA"
  [ "$status" -eq 0 ]

  # (3) The schema's $comment must no longer claim lint_skill.sh MUST validate
  #     against this file (grep -c prints the match count; target is 0).
  run grep -c 'MUST validate' "$SCHEMA"
  [ "$output" -eq 0 ]
}

# --- WA4: workflow-run recording -------------------------------------------
# record-workflow <plan_path> <phase> <run_id> pins the workflow run id that
# executed a phase into .workflow_runs.<phase>, so a resumed sprint can find
# the run that produced its artifacts. Thin wrapper over the dotted update
# path: the run_id is JSON-encoded as a STRING before delegating, and
# validated to be non-empty + composed solely of [A-Za-z0-9._-]. _validate_state
# gains a must(...) clause: workflow_runs, when present, must be an object
# whose values are all strings.

@test "WA4: record-workflow writes .workflow_runs.<phase> and state stays valid" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" record-workflow "$PLAN" phase-3 wf_abc123
  [ "$status" -eq 0 ]
  run jq -r '.workflow_runs["phase-3"]' "$STATE"
  [ "$output" = "wf_abc123" ]

  # A later update re-runs _validate_state over the whole file: the recorded
  # workflow_runs must survive it (schema-valid, not merely tolerated).
  # `read` only cats the file, so it is NOT the validation gate here.
  run "$STATE_SH" update "$PLAN" current_phase='3'
  [ "$status" -eq 0 ]
}

@test "WA4: second record-workflow for the same phase overwrites" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  "$STATE_SH" record-workflow "$PLAN" phase-3 wf_first
  run "$STATE_SH" record-workflow "$PLAN" phase-3 wf_second
  [ "$status" -eq 0 ]
  run jq -r '.workflow_runs["phase-3"]' "$STATE"
  [ "$output" = "wf_second" ]
}

@test "WA4: record-workflow rejects empty run_id with usage, writes nothing" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" record-workflow "$PLAN" phase-3 ""
  [ "$status" -ne 0 ]
  # `|| false`: bats here runs under macOS system bash 3.2, whose errexit does
  # NOT fire on a failing bare `[[ ]]` compound command mid-test; the || false
  # converts the failure into a simple-command failure errexit does catch.
  [[ "$output" == *"record-workflow"* ]] || false
  run jq 'has("workflow_runs")' "$STATE"
  [ "$output" = "false" ]
}

@test "WA4: record-workflow rejects run_id outside [A-Za-z0-9._-], state unchanged" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  before="$(cat "$STATE")"

  for bad in 'wf/abc' 'wf abc' 'wf;rm'; do
    run "$STATE_SH" record-workflow "$PLAN" phase-3 "$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"record-workflow"* ]] || false
  done

  after="$(cat "$STATE")"
  [ "$before" = "$after" ]
}

@test "WA4: record-workflow with missing state.json exits 2 without usage text" {
  # No init. Matches the update/read convention: missing state.json is exit 2
  # with a "missing" log line — NOT the usage() text an unknown subcommand
  # produces (also exit 2), so the negative assertion keeps this RED until the
  # subcommand exists.
  run "$STATE_SH" record-workflow "$PLAN" phase-3 wf_abc123
  [ "$status" -eq 2 ]
  [[ "$output" != *"usage: state.sh"* ]] || false
  [[ "$output" == *"missing"* ]] || false
}

@test "WA4: JSON-scalar-shaped run_ids are stored as strings" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1

  run "$STATE_SH" record-workflow "$PLAN" phase-3 1.5
  [ "$status" -eq 0 ]
  run jq -r '.workflow_runs["phase-3"] | type' "$STATE"
  [ "$output" = "string" ]
  run jq -r '.workflow_runs["phase-3"]' "$STATE"
  [ "$output" = "1.5" ]

  run "$STATE_SH" record-workflow "$PLAN" phase-3 true
  [ "$status" -eq 0 ]
  run jq -r '.workflow_runs["phase-3"] | type' "$STATE"
  [ "$output" = "string" ]
  run jq -r '.workflow_runs["phase-3"]' "$STATE"
  [ "$output" = "true" ]
}

@test "WA4: non-object workflow_runs is rejected by _validate_state on write" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  # Hand-inject a bare string, bypassing state.sh entirely.
  tmp="$(mktemp)"
  jq '.workflow_runs = "oops"' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
  run "$STATE_SH" update "$PLAN" current_phase='1'
  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow_runs"* ]] || false
}

@test "WA4: non-string workflow_runs value is rejected through the generic update path" {
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  before="$(cat "$STATE")"
  run "$STATE_SH" update "$PLAN" 'workflow_runs.phase-3=15'
  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow_runs"* ]] || false
  after="$(cat "$STATE")"
  [ "$before" = "$after" ]
}

@test "WA4: dotted update creates the missing workflow_runs parent (regression pin)" {
  # Pins existing setpath behaviour record-workflow delegates to: the missing
  # parent object is created on the fly. Expected to pass pre-implementation.
  "$STATE_SH" init "$PLAN" develop sprint-mech-1
  run "$STATE_SH" update "$PLAN" 'workflow_runs.phase-3="wf_x"'
  [ "$status" -eq 0 ]
  run jq -r '.workflow_runs["phase-3"]' "$STATE"
  [ "$output" = "wf_x" ]
}

@test "WA4: machine schema names workflow_runs as an object" {
  SCHEMA="$SCRIPTS/schemas/state.schema.json"
  run jq -e '.properties.workflow_runs' "$SCHEMA"
  [ "$status" -eq 0 ]
  run jq -r '.properties.workflow_runs.type' "$SCHEMA"
  [ "$output" = "object" ]
}

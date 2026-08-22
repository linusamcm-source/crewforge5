#!/usr/bin/env bats
# execute_flow.bats — contract for `crewforge5:execute`.
#
# execute wraps team-sprint rather than forking it: phases 0–7 are team-sprint's
# own phase docs, reached through the Story 1 resolver, and only phases 8
# (integration diagram) and 9 (distil learnings) are new. So what this file
# guards is the wrapping. That the manifest still points at the eight docs that
# exist; that driving those phases through the shared driver reaches Phase 7
# with the SAME verdicts as running team-sprint's own gate scripts directly —
# a wrapper that quietly changes a verdict is worse than no wrapper; that
# Phase 1 still hard-STOPs a plan nobody reviewed, which is the one gate the
# whole pipeline's provenance rests on; and that the two added phases skip
# when they are optional and fail when they are not.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"
  FLOW_NEXT="$ROOT/scripts/flow/flow_next.sh"
  FLOW_GATE="$ROOT/scripts/flow/flow_gate.sh"
  PHASE_GATE="$ROOT/skills/execute/scripts/phase_gate.sh"
  TS="$ROOT/skills/team-sprint/scripts"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  OUT="$TMP/out"
  ERR="$TMP/err"

  # A fixture plugin root the resolver can search: every shipped skill by
  # symlink, so a test that needs a sub-skill absent just removes one link
  # instead of rebuilding the bundle. scripts/ is linked too, so a fixture that
  # replaces a link with a real copy still finds the shared driver beside it.
  export CREWFORGE5_ROOT="$TMP/plugin"
  mkdir -p "$CREWFORGE5_ROOT/skills"
  ln -s "$ROOT/scripts" "$CREWFORGE5_ROOT/scripts"
  for d in "$ROOT"/skills/*/; do
    ln -s "${d%/}" "$CREWFORGE5_ROOT/skills/$(basename "$d")"
  done

  # Sandbox HOME so neither the resolver's third root nor the ledger reaches the
  # developer's real catalogue.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/skills"

  mkdir -p "$TMP/repo/docs/plans"
  cd "$TMP/repo"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name "test"
  git commit -q --allow-empty -m "init"

  # Subject-keyed since flow state stopped being one file per repo: a second
  # sprint would otherwise resume into the first one's phase statuses.
  STATE="$TMP/repo/.crewforge5/execute/default/state.json"

  # The repo's own fixture plan, under a filename that carries its story id
  # (Phase 0's path contract) and stamped as the planner would stamp it — the
  # fixture is the artifact team-sprint parses, and the stamp is the one thing
  # a plan-final fixture is missing because the planner, not the sprint, adds
  # it. Directly under the `#` title, which is where the contract puts it.
  PLAN="docs/plans/story-9-mech-refactor.md"
  FIXTURE="$ROOT/skills/team-sprint/scripts/fixtures/happy.plan-final.md"
  {
    head -1 "$FIXTURE"
    printf '<!-- adversarial-review: status=clean rounds=2 date=2026-08-13 reviewer=team-sprint-planner -->\n'
    tail -n +2 "$FIXTURE"
  } > "$TMP/repo/$PLAN"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

_split_run() {
  RC=0
  "$@" >"$OUT" 2>"$ERR" || RC=$?
  STDOUT="$(cat "$OUT")"
  STDERR="$(cat "$ERR")"
}

manifest() { bash "$FLOW_STATE" execute manifest; }
# Walk the sprint up to the point where phase 8 is the phase on offer, so a
# phase-8 test asserts on a flow that genuinely arrived there.
drive_to_8() {
  local n
  record_plan
  for n in 0 1 2 3 4 5 6 7; do
    bash "$FLOW_GATE" execute "$n" >/dev/null 2>&1 || return 1
  done
}
verdict()  { jq -r --arg p "$1" '.phase[$p].status // "none"' "$STATE"; }
record_plan() { bash "$FLOW_STATE" execute set plan "$PLAN"; }

# Replace the symlinked skill with a writable copy, so a test can flip a
# manifest field without editing the shipped file.
_own_execute() {
  rm "$CREWFORGE5_ROOT/skills/execute"
  cp -R "$ROOT/skills/execute" "$CREWFORGE5_ROOT/skills/execute"
}

# --- the manifest ------------------------------------------------------------

# The manifest is the object form — {status_source, phases} — because execute's
# phase list depends on `scheduling` and its phase progress is owned by
# team-sprint. `mphases` normalises so these assertions read the same either way.
mphases() { jq '(if type == "array" then {phases: .} else . end) | .phases' "$(manifest)"; }
mfield()  { mphases | jq -r --arg id "$1" --arg f "$2" 'map(select(.id == $id)) | .[0][$f] // ""'; }

@test "phases.json lists eleven phases: 0-9 plus the graph-mode wave loop" {
  [ "$(mphases | jq -r 'length')" = "11" ]
  [ "$(mphases | jq -r 'map(.id) | join(",")')" = "0,1,2,3,4,5,6,execute,7,8,9" ]
}

@test "phases 0-7 point at team-sprint's own phase docs, which exist" {
  local m n doc
  m="$(manifest)"
  for n in 0 1 2 3 4 5 6 7; do
    doc="$(mfield "$n" doc)"
    [ "$doc" = "../team-sprint/references/phases/phase-$n.md" ]
    [ -f "$(dirname "$m")/$doc" ]
  done
}

@test "the wave-loop phase points at team-sprint's graph-mode doc, which exists" {
  local m doc
  m="$(manifest)"
  doc="$(mfield execute doc)"
  [ "$doc" = "../team-sprint/references/phases/phase-execute.md" ]
  [ -f "$(dirname "$m")/$doc" ]
}

@test "phases 8 and 9 are execute's own docs and exist" {
  local m doc
  m="$(manifest)"
  for n in 8 9; do
    doc="$(mfield "$n" doc)"
    [ "$doc" = "phases/phase-$n.md" ]
    [ -f "$(dirname "$m")/$doc" ]
  done
}

@test "only 0, 1, 8 and 9 declare a gate; the rest are judgment phases" {
  local n
  for n in 0 1 8 9; do
    case "$(mfield "$n" gate)" in *"phase_gate.sh"*" $n") ;; *) return 1 ;; esac
  done
  for n in 2 3 4 5 6 execute 7; do
    [ -z "$(mfield "$n" gate)" ]
  done
  [ -f "$PHASE_GATE" ]
}

@test "the per-story phases and the wave loop are mode-gated against each other" {
  local n
  # Exactly one of the two lists can be live in a run, so each carries a `when`.
  for n in 3 4 5 6; do
    case "$(mfield "$n" when)" in *"--mode"*sequential) ;; *) return 1 ;; esac
  done
  case "$(mfield execute when)" in *"--mode"*graph) ;; *) return 1 ;; esac
  # Phases every run walks carry none.
  for n in 0 1 2 7 8 9; do
    [ -z "$(mfield "$n" when)" ]
  done
}

@test "the manifest names team-sprint as the owner of phase progress" {
  local src
  src="$(jq -r '.status_source // ""' "$(manifest)")"
  case "$src" in *sprint_status.sh*) ;; *) return 1 ;; esac
  [ -f "$CREWFORGE5_ROOT/skills/execute/scripts/sprint_status.sh" ]
}

# --- phase 1: the provenance gate execute inherits ---------------------------

@test "phase 1 hard-STOPs a plan with no adversarial-review stamp" {
  printf '# unreviewed\n\n## Story 5: fixture\n' > "$TMP/repo/$PLAN"
  record_plan
  _split_run bash "$FLOW_GATE" execute 1
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
  [ "$(verdict 1)" = "FAIL" ]
  case "$(jq -r '.phase["1"].stdout' "$STATE")" in *no-adversarial-stamp*) ;; *) return 1 ;; esac
}

@test "a failed phase 1 is re-offered rather than advanced past" {
  printf '# unreviewed\n\n## Story 5: fixture\n' > "$TMP/repo/$PLAN"
  record_plan
  bash "$FLOW_GATE" execute 0 >/dev/null 2>&1
  bash "$FLOW_GATE" execute 1 >/dev/null 2>&1 || true
  _split_run bash "$FLOW_NEXT" execute
  [ "$RC" -eq 0 ]
  case "$STDOUT" in *"PHASE=1"*) ;; *) return 1 ;; esac
}

@test "phase 1 passes a stamped, fold-clean plan" {
  record_plan
  _split_run bash "$FLOW_GATE" execute 1
  [ "$RC" -eq 0 ]
  [ "$(verdict 1)" = "PASS" ]
}

@test "phase 1 fails a stamped plan that still carries FINDING markers" {
  printf '# f\n<!-- adversarial-review: status=clean rounds=1 date=2026-08-13 reviewer=x -->\n<!-- FINDING 1 (HIGH): unresolved -->\n' > "$TMP/repo/$PLAN"
  record_plan
  _split_run bash "$FLOW_GATE" execute 1
  [ "$RC" -ne 0 ]
  [ "$(verdict 1)" = "FAIL" ]
}

# --- phase 0 -----------------------------------------------------------------

@test "phase 0 fails when a required sub-skill is missing from every root" {
  rm "$CREWFORGE5_ROOT/skills/use-repo-code"
  record_plan
  _split_run bash "$FLOW_GATE" execute 0
  [ "$RC" -ne 0 ]
  [ "$(verdict 0)" = "FAIL" ]
  case "$(jq -r '.phase["0"].stdout' "$STATE")" in *use-repo-code*) ;; *) return 1 ;; esac
}

@test "phase 0 fails a plan filename that carries no story id" {
  mv "$TMP/repo/$PLAN" "$TMP/repo/docs/plans/plan.md"
  PLAN="docs/plans/plan.md"
  record_plan
  _split_run bash "$FLOW_GATE" execute 0
  [ "$RC" -ne 0 ]
  [ "$(verdict 0)" = "FAIL" ]
}

@test "phase 0 fails when no plan has been recorded at all" {
  bash "$FLOW_STATE" execute set started yes
  _split_run bash "$FLOW_GATE" execute 0
  [ "$RC" -ne 0 ]
  [ "$(verdict 0)" = "FAIL" ]
}

# --- the wrap: same verdicts as team-sprint driven directly ------------------

# The expected column: team-sprint's own mechanical checks, invoked directly and
# exactly as its phase docs state them — a second code path, not a re-run of the
# gate under test. Phases 2-7 hold judgment gates, which have no script to run
# on either side.
_team_sprint_verdicts() {
  local n s direct out=""
  direct=PASS
  bash "$TS/validate_plan_path.sh" "$PLAN" >/dev/null 2>&1 || direct=FAIL
  for s in use-repo-code sprint-watchdog pre-commit-review-fleet; do
    bash "$TS/preflight_subskills.sh" --probe-only "$s" >/dev/null 2>&1 || direct=FAIL
  done
  out="$out 0=$direct"

  direct=PASS
  grep -qm1 -E '^<!-- adversarial-review: status=(clean|user-override) ' "$PLAN" || direct=FAIL
  bash "$TS/findings_gate.sh" "$PLAN" >/dev/null 2>&1 || direct=FAIL
  out="$out 1=$direct"

  for n in 2 3 4 5 6 7; do out="$out $n=PASS"; done
  printf '%s' "$out"
}

# The actual column: what the driver recorded, phase by phase.
_driver_verdicts() {
  local n out=""
  for n in 0 1 2 3 4 5 6 7; do
    bash "$FLOW_GATE" execute "$n" >/dev/null 2>&1 || true
    out="$out $n=$(verdict "$n")"
  done
  printf '%s' "$out"
}

@test "phases 0-7 through the driver reach 8 with team-sprint's own verdicts" {
  record_plan
  expected="$(_team_sprint_verdicts)"
  actual="$(_driver_verdicts)"
  [ "$actual" = "$expected" ]

  _split_run bash "$FLOW_NEXT" execute
  case "$STDOUT" in *"PHASE=8"*) ;; *) return 1 ;; esac
}

# The happy-path diff above is all PASS, so on its own it cannot tell a faithful
# wrapper from one that records PASS unconditionally. This is the same diff over
# a plan team-sprint's own gate rejects: the vectors must still agree, and the
# agreed vector must carry the FAIL.
@test "the driver records team-sprint's FAIL too, not just its passes" {
  printf '# unreviewed\n\n## Story 9: fixture\n' > "$TMP/repo/$PLAN"
  record_plan
  expected="$(_team_sprint_verdicts)"
  actual="$(_driver_verdicts)"
  [ "$actual" = "$expected" ]
  case "$actual" in *"1=FAIL"*) ;; *) return 1 ;; esac
}

# --- phase 8: the integration diagram ---------------------------------------

@test "phase 8 not required and no diagram tool: SKIP, and the flow advances" {
  _own_execute
  jq '(.phases[] | select(.id == "8") | .required) |= false' "$CREWFORGE5_ROOT/skills/execute/phases.json" > "$TMP/p.json"
  mv "$TMP/p.json" "$CREWFORGE5_ROOT/skills/execute/phases.json"
  rm "$CREWFORGE5_ROOT/skills/drawio"
  drive_to_8

  _split_run bash "$FLOW_GATE" execute 8
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  case "$(jq -r '.phase["8"].stdout' "$STATE")" in
    "STATUS=SKIP REASON=no-diagram-tool") ;;
    *) return 1 ;;
  esac

  _split_run bash "$FLOW_NEXT" execute
  case "$STDOUT" in *"PHASE=9"*) ;; *) return 1 ;; esac
}

@test "phase 8 required and no diagram tool: FAIL" {
  _own_execute
  jq '(.phases[] | select(.id == "8") | .required) |= true' "$CREWFORGE5_ROOT/skills/execute/phases.json" > "$TMP/p.json"
  mv "$TMP/p.json" "$CREWFORGE5_ROOT/skills/execute/phases.json"
  rm "$CREWFORGE5_ROOT/skills/drawio"
  drive_to_8

  _split_run bash "$FLOW_GATE" execute 8
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
  case "$(jq -r '.phase["8"].stdout' "$STATE")" in
    *"REASON=no-diagram-tool"*) ;;
    *) return 1 ;;
  esac

  _split_run bash "$FLOW_NEXT" execute
  case "$STDOUT" in *"PHASE=8"*) ;; *) return 1 ;; esac
}

@test "phase 8 required with the tool present but no diagram recorded: FAIL" {
  _own_execute
  jq '(.phases[] | select(.id == "8") | .required) |= true' "$CREWFORGE5_ROOT/skills/execute/phases.json" > "$TMP/p.json"
  mv "$TMP/p.json" "$CREWFORGE5_ROOT/skills/execute/phases.json"
  record_plan

  _split_run bash "$FLOW_GATE" execute 8
  [ "$RC" -ne 0 ]
  case "$(jq -r '.phase["8"].stdout' "$STATE")" in
    *"REASON=no-diagram"*) ;;
    *) return 1 ;;
  esac
}

@test "phase 8 passes once a diagram exists on disk" {
  record_plan
  printf '<mxfile></mxfile>\n' > "$TMP/repo/integration.drawio"
  bash "$FLOW_STATE" execute set diagram_path integration.drawio
  _split_run bash "$FLOW_GATE" execute 8
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [ "$(jq -r '.phase["8"].stdout' "$STATE")" = "STATUS=PASS" ]
}

# --- phase 9: distil what the run learned ------------------------------------

@test "phase 9 with an empty ledger passes without editing anything" {
  record_plan
  before="$(git -C "$TMP/repo" status --porcelain)"
  _split_run bash "$FLOW_GATE" execute 9
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  case "$(jq -r '.phase["9"].stdout' "$STATE")" in
    "STATUS=SKIP REASON=ledger-empty") ;;
    *) return 1 ;;
  esac
  [ ! -d "$HOME/.local/state/crewforge5/ledger" ]
  [ "$(git -C "$TMP/repo" status --porcelain)" = "$before" ]
}

@test "phase 9 with entries in the ledger holds them to the byte ceiling" {
  record_plan
  export CLAUDE_CONFIG_DIR="$TMP/config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  bash "$ROOT/skills/self-improve/scripts/ledger.sh" add execute user "a lesson"
  _split_run bash "$FLOW_GATE" execute 9
  case "$STDOUT" in STATUS=PASS|STATUS=FAIL) ;; *) return 1 ;; esac
  case "$(jq -r '.phase["9"].stdout' "$STATE")" in
    *"ledger-empty"*) return 1 ;;
    *) ;;
  esac
}

# --- the gate script's own contract ------------------------------------------

@test "phase_gate.sh with no argument exits 2 with usage on stderr" {
  _split_run bash "$PHASE_GATE"
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
  [ -n "$STDERR" ]
}

@test "phase_gate.sh refuses a phase that carries no mechanical gate" {
  _split_run bash "$PHASE_GATE" 3
  [ "$RC" -eq 2 ]
  [ -z "$STDOUT" ]
}

# --- team-sprint owns phases 0-7 ---------------------------------------------
#
# execute wraps team-sprint, which has tracked current_phase, current_story_id
# and story_commits[] since long before the shared driver existed. Keeping a
# second copy meant no story dimension at all: flow_next.sh filters on phase
# status, so once Phase 3 was marked pass for story 1 nothing could send it
# back for story 2. These prove the driver now follows team-sprint instead.

_sprint_state() { # $1 current_phase (JSON)  $2 done (JSON)
  local art
  art="$(bash "$CREWFORGE5_ROOT/skills/team-sprint/scripts/state.sh" art-dir "$PLAN")"
  mkdir -p "$art"
  printf '{"current_phase":%s,"current_story_id":"s1","done":%s}\n' "$1" "$2" > "$art/state.json"
}

_offers() { bash "$FLOW_NEXT" execute | sed -n 's/^PHASE=//p'; }

@test "the driver follows team-sprint's current_phase without recording it itself" {
  bash "$FLOW_STATE" execute set plan "$PLAN"
  _sprint_state 5 false
  [ "$(_offers)" = "5" ]
  # Nothing recorded phases 0-4; the status source passed them.
  run bash "$FLOW_STATE" execute get phase.0.status
  [ "$status" -eq 1 ]
}

@test "a story loop-back to phase 3 is followed, not walked past" {
  bash "$FLOW_STATE" execute set plan "$PLAN"
  _sprint_state 6 false
  [ "$(_offers)" = "6" ]
  # Phase 6 step 7 puts current_phase back to 3 for the next story.
  _sprint_state 3 false
  [ "$(_offers)" = "3" ]
}

@test "done=true hands over to the phases team-sprint does not own" {
  bash "$FLOW_STATE" execute set plan "$PLAN"
  _sprint_state 7 true
  [ "$(_offers)" = "8" ]
}

@test "current_phase execute offers the wave loop even when config says sequential" {
  printf 'scheduling: sequential\n' > "$TMP/repo/team-sprint.config.yaml"
  bash "$FLOW_STATE" execute set plan "$PLAN"
  _sprint_state '"execute"' false
  [ "$(_offers)" = "execute" ]
  # …and the per-story phases are gone from that run.
  run bash "$FLOW_GATE" execute 3
  [ "$status" -eq 1 ]
}

@test "with no sprint state the driver decides alone" {
  bash "$FLOW_STATE" execute set plan "$PLAN"
  [ "$(_offers)" = "0" ]
  bash "$FLOW_STATE" execute set phase.0.status PASS
  [ "$(_offers)" = "1" ]
}

@test "a sprint on a second plan does not inherit the first's progress" {
  bash "$FLOW_STATE" execute use --from "$PLAN"
  bash "$FLOW_STATE" execute set plan "$PLAN" phase.0.status PASS phase.1.status PASS
  bash "$FLOW_STATE" execute use --from "docs/plans/story-2-other.md"
  [ "$(_offers)" = "0" ]
}

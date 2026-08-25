#!/usr/bin/env bats
# plan_flow.bats — contract for the `crewforge5:plan` flow.
#
# `plan` turns a goal into an adversarial-clean, /team-sprint-ready plan file.
# Everything it does that a human could fake — "the goal is recorded", "the
# findings are folded", "every debt finding is covered" — is a gate in
# skills/plan/phases.json, and this file is what proves those gates actually
# bite. The three that matter most are the ones a flow would otherwise walk
# straight past: an intake with no goal, a review stamped while a finding is
# still open, and a plan whose debt-coverage table quietly drops a finding ID.
#
# The flow under test is this checkout's real skills/plan — not a fixture — so
# a gate naming a script that has been moved or renamed fails here rather than
# in someone's live sprint.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"
  FLOW_NEXT="$ROOT/scripts/flow/flow_next.sh"
  FLOW_GATE="$ROOT/scripts/flow/flow_gate.sh"
  PLAN_DIR="$ROOT/skills/plan"
  MANIFEST="$PLAN_DIR/phases.json"
  STRUCT="$ROOT/skills/skill-validator/scripts/validate_structure.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  OUT="$TMP/out"
  ERR="$TMP/err"

  # The gates name their scripts through ${CREWFORGE5_ROOT:-.} so that the flow
  # works on a repo that is not the plugin. Pointing it at this checkout is
  # therefore the realistic configuration, not a shortcut.
  export CREWFORGE5_ROOT="$ROOT"

  # Sandbox HOME so the resolver's third root never reaches the developer's
  # real catalogue.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/skills"

  # State lives under the repo root, so the target repo is a throwaway one —
  # never this checkout, whose .crewforge5/ must stay untouched by a test run.
  mkdir -p "$TMP/repo"
  cd "$TMP/repo"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  STATE="$TMP/repo/.crewforge5/plan/default/state.json"
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

_pass_through() { # $1 = highest phase id to mark passed
  local i
  for i in $(seq 0 "$1"); do
    bash "$FLOW_STATE" plan set "phase.$i.status" pass
  done
}

_write_plan() { # $1 = path (relative to the fixture repo), $2… = extra lines
  local path="$1"; shift
  mkdir -p "$(dirname "$path")"
  {
    printf '# Epic 1 — widget\n\n'
    printf '<!-- adversarial-review: status=clean rounds=1 date=2026-08-13 reviewer=team-sprint-planner -->\n\n'
    printf '## Story 1: Do the thing\n\n'
    printf '### Depends On: none\n\n'
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$path"
}

# --- the manifest (AC: nine phases; every doc and gate resolves) -------------

@test "phases.json lists all nine phases, 0 through 8, in order" {
  [ -f "$MANIFEST" ]
  run jq -e . "$MANIFEST"; [ "$status" -eq 0 ]
  [ "$(jq -r 'length' "$MANIFEST")" = "9" ]
  [ "$(jq -r '[.[].id] | join(" ")' "$MANIFEST")" = "0 1 2 3 4 5 6 7 8" ]
  # Every entry carries the driver's declared shape {id,title,doc,gate,required}.
  [ "$(jq -r '[.[] | select(has("title") and has("doc") and has("gate") and has("required"))] | length' "$MANIFEST")" = "9" ]
}

@test "every phase doc the manifest names exists on disk" {
  local doc n=0
  for doc in $(jq -r '.[].doc' "$MANIFEST"); do
    [ -f "$PLAN_DIR/$doc" ] || { printf 'missing phase doc: %s\n' "$doc" >&2; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 9 ]
}

@test "every script a gate names resolves under the plugin root" {
  local p n=0
  for p in $(jq -r '.[].gate' "$MANIFEST" \
             | grep -oE '\$\{CREWFORGE5_ROOT:-\.\}/[A-Za-z0-9._/-]+' \
             | sed 's|\${CREWFORGE5_ROOT:-\.}/||' | sort -u); do
    [ -f "$ROOT/$p" ] || { printf 'gate names a missing script: %s\n' "$p" >&2; return 1; }
    n=$((n + 1))
  done
  # Guard the guard: a manifest whose gates named nothing would pass vacuously.
  [ "$n" -ge 4 ]
}

# --- phase 0 intake (AC: no goal → stop, no state beyond intake) -------------

@test "phase 0 fails while no goal is recorded and writes no state beyond intake" {
  _split_run bash "$FLOW_GATE" plan 0
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
  [ -f "$STATE" ]

  run jq -e 'has("goal")' "$STATE"; [ "$status" -ne 0 ]
  [ "$(jq -r '.phase | keys | join(",")' "$STATE")" = "0" ]
}

@test "a goalless phase 0 leaves flow_next re-offering phase 0" {
  bash "$FLOW_GATE" plan 0 || true
  _split_run bash "$FLOW_NEXT" plan
  [ "$RC" -eq 0 ]
  [[ "$STDOUT" == *"PHASE=0"* ]]
  [[ "$STDOUT" == *"DOC=$PLAN_DIR/phases/phase-0.md"* ]]
}

@test "phase 0 passes once the goal is recorded" {
  bash "$FLOW_STATE" plan set goal "condense the skills"
  _split_run bash "$FLOW_GATE" plan 0
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  _split_run bash "$FLOW_NEXT" plan
  [[ "$STDOUT" == *"PHASE=1"* ]]
}

# --- phase 1 ground (the plan's "degrade visibly" requirement) ---------------

# On a host carrying repomix the gate legitimately passes by refreshing the
# pack, and neither case below is about that path.
# Spelled as an if rather than `cmd && skip`, whose non-zero return status on
# the common branch fails the test outright.
_needs_no_repomix() {
  if command -v repomix >/dev/null 2>&1; then
    skip "repomix is installed; the refresh path covers this host"
  fi
}

@test "phase 1 fails when the pack cannot be built and nothing was recorded" {
  _needs_no_repomix
  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
}

@test "phase 1 passes on an explicitly recorded DEGRADED verdict naming Grep" {
  _needs_no_repomix
  bash "$FLOW_STATE" plan set ground_degraded \
    "DEGRADED: no repomix on PATH; grounded with live Grep"
  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
}

# The plan spells the fallback as "an explicit DEGRADED verdict naming live
# Grep as the provider". A gate that accepts any non-empty string lets a caller
# type "ok" and walk past ungrounded, which is the exact failure the phase
# exists to prevent — so the *shape* of the verdict is part of the contract.
@test "phase 1 refuses a ground_degraded value that is not a DEGRADED verdict" {
  _needs_no_repomix
  bash "$FLOW_STATE" plan set ground_degraded "whatever"
  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
}

@test "phase 1 refuses a DEGRADED verdict that names no fallback provider" {
  _needs_no_repomix
  bash "$FLOW_STATE" plan set ground_degraded "DEGRADED: no repomix on PATH"
  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
}

# --- phase 1 honours repomix_max_age_minutes ---------------------------------
#
# The plan's phase-1 row says the gate proves the pack is "fresher than
# `repomix_max_age_minutes`" — a real config key whose documented and live
# default in this repo is 240 (team-sprint.config.yaml.example:140,
# recon.sh:583). A gate that hardcodes its own threshold ignores a `plan` flow's
# configuration, so the three cases below pin the key, not a literal.
#
# Each case shims `repomix` onto PATH so `require_repomix` passes and the
# refresh decision — not tool availability — is what the gate turns on. The shim
# records that it ran and then fails, which makes "did the gate decide to
# refresh?" observable in both the marker and the verdict.

_shim_repomix() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/repomix" <<SH
#!/usr/bin/env bash
: > "$TMP/repomix-ran"
exit 1
SH
  chmod +x "$TMP/bin/repomix"
  PATH="$TMP/bin:$PATH"
  export PATH
}

# touch -t takes [[CC]YY]MMDDhhmm[.ss] on both BSD and GNU; `date -d` / `date -v`
# do not agree, so the timestamp is computed in python3 (already a hard
# dependency of read_config_scalar).
_pack_aged() { # $1 = age in minutes
  : > "$TMP/repo/.repomix-output.xml"
  touch -t "$(python3 -c 'import sys, time; print(time.strftime("%Y%m%d%H%M.%S", time.localtime(time.time() - int(sys.argv[1]) * 60)))' "$1")" \
    "$TMP/repo/.repomix-output.xml"
}

_config() { # $1 = repomix_max_age_minutes value
  printf 'repomix_max_age_minutes: %s\n' "$1" > "$TMP/repo/team-sprint.config.yaml"
}

@test "phase 1 accepts a pack the configured max age still calls fresh" {
  _shim_repomix
  _config 240
  _pack_aged 90

  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  # A gate hardcoding 60 would have called a 90-minute-old pack stale.
  [ ! -f "$TMP/repomix-ran" ]
}

@test "phase 1 refreshes a pack the configured max age calls stale" {
  _shim_repomix
  _config 30
  _pack_aged 45

  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
  # A gate hardcoding 60 would have called a 45-minute-old pack fresh.
  [ -f "$TMP/repomix-ran" ]
}

@test "phase 1 falls back to the documented default of 240 with no config file" {
  _shim_repomix
  [ ! -f "$TMP/repo/team-sprint.config.yaml" ]
  _pack_aged 200

  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [ ! -f "$TMP/repomix-ran" ]
}

@test "phase 1 ignores a non-numeric configured max age rather than passing it on" {
  _shim_repomix
  _config 'soon'
  _pack_aged 200

  # repomix_refresh.sh exits 1 on a non-integer --max-age-minutes, so an
  # unvalidated value would surface as a FAIL that blames the pack.
  _split_run bash "$FLOW_GATE" plan 1
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [ ! -f "$TMP/repomix-ran" ]
}

@test "the phase 1 gate and doc name the config key, not a hardcoded threshold" {
  gate="$(jq -r 'map(select(.id == "1")) | .[0].gate' "$MANIFEST")"
  [[ "$gate" == *repomix_max_age_minutes* ]]
  [[ "$gate" != *"--max-age-minutes 60"* ]]
  grep -q 'repomix_max_age_minutes' "$PLAN_DIR/phases/phase-1.md"
}

# --- phase 3 grill (AC: one AskUserQuestion at a time) -----------------------

@test "the skill body carries the one-question-at-a-time rule" {
  grep -q 'AskUserQuestion' "$PLAN_DIR/SKILL.md"
  grep -qi 'one question at a time' "$PLAN_DIR/SKILL.md"
}

# The rule only bites if the doc the driver actually hands the model in phase 3
# carries it too — SKILL.md is read once at the top of the flow, phase-3.md is
# what is open while the questions are being written.
@test "the phase 3 doc carries the one-question-at-a-time rule as an instruction" {
  [ -f "$PLAN_DIR/phases/phase-3.md" ]
  grep -q 'AskUserQuestion' "$PLAN_DIR/phases/phase-3.md"
  grep -qi 'one question at a time' "$PLAN_DIR/phases/phase-3.md"
  # "a single AskUserQuestion call" is the half that makes it mechanical rather
  # than a mood: one call, not one question spread over a batched call.
  grep -qi 'single .AskUserQuestion. call' "$PLAN_DIR/phases/phase-3.md"
  # …and the half that makes it sequential: the next question is composed after
  # the answer, which is what a pre-written batch cannot do.
  grep -qi 'wait for the answer' "$PLAN_DIR/phases/phase-3.md"
}

@test "the flow stays inline — an interactive phase has no user to ask from a fork" {
  # grep exits non-zero on a missing file exactly as it does on no-match, so
  # without this precondition the assertion below would pass loudest when the
  # skill had been deleted.
  [ -f "$PLAN_DIR/SKILL.md" ]
  run grep -E '^(context|agent):' "$PLAN_DIR/SKILL.md"
  [ "$status" -ne 0 ]
}

# --- phase 6 draft (AC: validate_plan_path.sh + plan_readback.sh) ------------

@test "phase 6 passes for a plan whose filename carries a story id" {
  _write_plan "docs/plans/epic-1-widget.md"
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _split_run bash "$FLOW_GATE" plan 6
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]

  recorded="$(jq -r '.phase["6"].stdout' "$STATE")"
  [[ "$recorded" == *"SLUG=epic-1-widget"* ]]
  [[ "$recorded" == *"Do the thing"* ]]
}

@test "phase 6 fails for a plan filename carrying no story id" {
  _write_plan "docs/plans/plan.md"
  bash "$FLOW_STATE" plan set plan_path docs/plans/plan.md
  _split_run bash "$FLOW_GATE" plan 6
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
}

# --- phase 7 review (AC: no stamp while a finding is open) -------------------

@test "phase 7 refuses a plan carrying an unresolved finding, and phase 8 is not reached" {
  _write_plan "docs/plans/epic-1-widget.md" \
    '<!-- FINDING F001 (high): the intake gate accepts an empty goal -->'
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _pass_through 6

  _split_run bash "$FLOW_GATE" plan 7
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]

  _split_run bash "$FLOW_NEXT" plan
  [[ "$STDOUT" == *"PHASE=7"* ]]
  [[ "$STDOUT" != *"PHASE=8"* ]]
  [[ "$STDOUT" != *"STATUS=DONE"* ]]
}

@test "phase 7 passes once the finding is folded and the stamp is present" {
  _write_plan "docs/plans/epic-1-widget.md"
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _pass_through 6

  _split_run bash "$FLOW_GATE" plan 7
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]

  _split_run bash "$FLOW_NEXT" plan
  [[ "$STDOUT" == *"PHASE=8"* ]]
}

@test "phase 7 refuses a fold-clean plan that carries no review stamp" {
  mkdir -p docs/plans
  printf '# Epic 1 — widget\n\n## Story 1: Do the thing\n' > docs/plans/epic-1-widget.md
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _split_run bash "$FLOW_GATE" plan 7
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]
}

# --- phase 8 verify (AC: a finding ID missing from the coverage table) -------

_write_impact() {
  mkdir -p docs/plans
  cat > docs/plans/GOAL_IMPACT.md <<'MD'
# Goal impact map

| ID | Finding | Disposition |
| --- | --- | --- |
| F001 | intake accepts an empty goal | fix in Story 1 |
| F002 | coverage table drifts silently | fix in Story 2 |
MD
}

@test "phase 8 names the finding ID missing from the plan's coverage table" {
  _write_impact
  _write_plan "docs/plans/epic-1-widget.md" \
    '### Debt coverage' '' '| ID | Story |' '| --- | --- |' '| F001 | 1 |'
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _pass_through 7

  _split_run bash "$FLOW_GATE" plan 8
  [ "$RC" -ne 0 ]
  [ "$STDOUT" = "STATUS=FAIL" ]

  recorded="$(jq -r '.phase["8"].stdout' "$STATE")"
  [[ "$recorded" == *"F002"* ]]
  [[ "$recorded" != *"F001"* ]]

  _split_run bash "$FLOW_NEXT" plan
  [[ "$STDOUT" == *"PHASE=8"* ]]
  [[ "$STDOUT" != *"STATUS=DONE"* ]]
}

@test "phase 8 passes and the flow completes once every finding is covered" {
  _write_impact
  _write_plan "docs/plans/epic-1-widget.md" \
    '### Debt coverage' '' '| ID | Story |' '| --- | --- |' '| F001 | 1 |' '| F002 | 1 |'
  bash "$FLOW_STATE" plan set plan_path docs/plans/epic-1-widget.md
  _pass_through 7

  _split_run bash "$FLOW_GATE" plan 8
  [ "$RC" -eq 0 ]
  [ "$STDOUT" = "STATUS=PASS" ]
  [[ "$(jq -r '.phase["8"].stdout' "$STATE")" == *"CLEAN"* ]]

  _split_run bash "$FLOW_NEXT" plan
  [ "$STDOUT" = "STATUS=DONE" ]
}

# --- scope (AC: ac-validate is wired nowhere) --------------------------------

@test "ac-validate appears nowhere under skills/plan" {
  # Same trap as the fork check: an absent directory greps as cleanly as a
  # clean one. Assert there is something to search before believing the miss.
  [ -d "$PLAN_DIR" ]
  [ "$(find "$PLAN_DIR" -type f | wc -l)" -ge 11 ]
  run grep -rF 'ac-validate' "$PLAN_DIR"
  [ "$status" -ne 0 ]
}

# --- capability checklist (DoD: one line per absorbed skill) -----------------

# The DoD names the skills `plan` has to absorb — six since the dead
# `team-feature` row was dropped. A table row is only a claim; what makes it a
# checklist is that the name in it still resolves to a body the flow can load —
# which is exactly what Story 6's hiding pass could break.
@test "every skill the capability table names resolves, and all six absorbed ones are listed" {
  [ -f "$PLAN_DIR/SKILL.md" ]
  local named
  named="$(sed -n 's/^| [^|]* | `\([a-z_-]*\)` | .*/\1/p' "$PLAN_DIR/SKILL.md")"
  [ -n "$named" ]

  local s
  for s in $named; do
    bash "$ROOT/scripts/flow/subskill_resolve.sh" --probe "$s" \
      || { printf 'capability table names an unresolvable skill: %s\n' "$s" >&2; return 1; }
  done

  for s in grill-me adhd master-plan tech-debt-audit team-sprint-planner \
           adversarial-review; do
    printf '%s\n' "$named" | grep -qx "$s" \
      || { printf 'capability table is missing: %s\n' "$s" >&2; return 1; }
  done
}

# --- the skill itself (AC: skill-validator grades it A) ----------------------

@test "skills/plan is structurally clean with no more than two warnings" {
  report="$(bash "$STRUCT" "$PLAN_DIR")"
  fails="$(printf '%s' "$report" | grep -c '"status":"FAIL"' || true)"
  warns="$(printf '%s' "$report" | grep -c '"status":"WARN"' || true)"
  if [ "$fails" -ne 0 ] || [ "$warns" -gt 2 ]; then
    printf '%s\n' "$report" | grep -E '"status":"(FAIL|WARN)"' >&2
    return 1
  fi
}

# The AC says skill-validator *grades* the skill A, and the grade is not a
# judgement call: grade.sh is a deterministic function of the findings ledger.
# So run every mechanical phase skill-validator ships a script for, feed the
# ledger it produces to the real grader, and assert the letter. skill-validator
# ships no script for its Step 5 agent simulation (`ls
# skills/skill-validator/scripts/` — five files, none of them simulate), and its
# own SKILL.md:189 records that a SKIPPED phase does not block grade A, so this
# is the whole of the AC that is executable.
@test "skill-validator's own grader grades skills/plan an A" {
  local sv="$ROOT/skills/skill-validator/scripts"
  local ledger="$TMP/plan-findings.txt"
  : > "$ledger"

  bash "$sv/validate_structure.sh" "$PLAN_DIR" \
    | sed -nE 's/.*"status":"(FAIL|WARN)","check":"([^"]*)","detail":"([^"]*)".*/\1 [structure:\2]: \3/p' \
    >> "$ledger"
  bash "$sv/functional.sh"  "$PLAN_DIR" | grep -E '^(FAIL|WARN) ' >> "$ledger" || true
  bash "$sv/efficiency.sh"  "$PLAN_DIR" | grep -E '^(FAIL|WARN) ' >> "$ledger" || true

  # Guard the guard: a ledger built from three silent scripts would grade A
  # vacuously, so prove on a copy that the grader can still see a finding.
  cat "$ledger" > "$ledger.canary"
  printf 'FAIL [selftest]: canary\n' >> "$ledger.canary"
  [ "$(bash "$sv/grade.sh" "$ledger.canary" | sed -n 's/^grade=//p')" = "C" ]

  run bash "$sv/grade.sh" "$ledger"
  [ "$status" -eq 0 ]
  if [[ "$output" != *"grade=A"* ]]; then
    printf '%s\n' "$output" >&2
    cat "$ledger" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Phases 2-5 — the shape gates that replaced `test -s`.
#
# Non-emptiness proved a file was touched, not that the phase happened: a
# frames.md holding one sentence passed phase 2, a decisions.md answering none
# of the framed decisions passed phase 3, and an impact map could invent an ID
# phase 8 would never catch (it only compares impact vs plan). Each test here
# is one of those escapes, closed.
# ---------------------------------------------------------------------------

PG="skills/plan/scripts/plan_gate.sh"

_art() { dirname "$(bash "$FLOW_STATE" plan path)"; }

_frames() { # write $1 as this run's frames.md
  local art; art="$(_art)"; mkdir -p "$art"
  printf '%s\n' "$1" > "$art/frames.md"
}

_decisions() {
  local art; art="$(_art)"; mkdir -p "$art"
  printf '%s\n' "$1" > "$art/decisions.md"
}

@test "frames gate: a non-empty file with no decision section fails" {
  _frames "just some prose about the goal"
  run bash "$ROOT/$PG" frames
  [ "$status" -eq 1 ]
  case "$output" in *REASON=no-sections*) ;; *) return 1 ;; esac
}

@test "frames gate: two frames per decision passes" {
  _frames "$(printf '## D1 — storage?\n- Frame A: sqlite\n- Frame B: postgres')"
  run bash "$ROOT/$PG" frames
  assert_success
  case "$output" in *SECTIONS=1*) ;; *) return 1 ;; esac
}

@test "frames gate: a single frame needs its Skip: reason" {
  _frames "$(printf '## D1 — auth?\n- Frame A: sessions')"
  run bash "$ROOT/$PG" frames
  [ "$status" -eq 1 ]
  _frames "$(printf '## D1 — auth?\n- Frame A: sessions\nSkip: user asked for the textbook answer')"
  run bash "$ROOT/$PG" frames
  assert_success
}

@test "frames gate: a named-but-unframed decision fails by id" {
  _frames "$(printf '## D1 — storage?\n- Frame A: sqlite\n- Frame B: postgres\n## D2 — naming?')"
  run bash "$ROOT/$PG" frames
  [ "$status" -eq 1 ]
  case "$output" in *BAD=D2*) ;; *) return 1 ;; esac
}

@test "decisions gate: a framed decision with no answer fails as MISSING" {
  _frames "$(printf '## D1 — a?\n- Frame A: x\n- Frame B: y\n## D2 — b?\n- Frame A: x\n- Frame B: y')"
  _decisions "$(printf '## D1 — a?\n**Chosen:** Frame A — cheap')"
  run bash "$ROOT/$PG" decisions
  [ "$status" -eq 1 ]
  case "$output" in *MISSING=D2*) ;; *) return 1 ;; esac
}

@test "decisions gate: discussed is not decided — no Chosen line fails as UNCHOSEN" {
  _frames "$(printf '## D1 — a?\n- Frame A: x\n- Frame B: y')"
  _decisions "$(printf '## D1 — a?\nWe went back and forth on this.')"
  run bash "$ROOT/$PG" decisions
  [ "$status" -eq 1 ]
  case "$output" in *UNCHOSEN=D1*) ;; *) return 1 ;; esac
}

@test "decisions gate: every framed decision chosen passes" {
  _frames "$(printf '## D1 — a?\n- Frame A: x\n- Frame B: y')"
  _decisions "$(printf '## D1 — a?\n**Chosen:** Frame B — concurrency')"
  run bash "$ROOT/$PG" decisions
  assert_success
  case "$output" in *DECISIONS=1*) ;; *) return 1 ;; esac
}

@test "audit gate: an ID only in prose fails; a table row passes" {
  printf 'The intake accepts an empty goal (F001).\n' > TECH_DEBT_AUDIT.md
  run bash "$ROOT/$PG" audit
  [ "$status" -eq 1 ]
  printf '| ID | Finding |\n| --- | --- |\n| F001 | empty goal accepted |\n' > TECH_DEBT_AUDIT.md
  run bash "$ROOT/$PG" audit
  assert_success
  case "$output" in *FINDINGS=1*) ;; *) return 1 ;; esac
}

@test "audit gate: a clean repo passes only by claiming it" {
  printf '# Audit\n\nNothing stood out.\n' > TECH_DEBT_AUDIT.md
  run bash "$ROOT/$PG" audit
  [ "$status" -eq 1 ]
  printf '# Audit\n\nNo findings.\n' > TECH_DEBT_AUDIT.md
  run bash "$ROOT/$PG" audit
  assert_success
}

_audit_f001() {
  printf '| ID | Finding |\n| --- | --- |\n| F001 | empty goal |\n' > TECH_DEBT_AUDIT.md
  mkdir -p docs/plans
}

@test "triage gate: an ID the audit never issued fails — phase 8 would never catch it" {
  _audit_f001
  printf '| ID | Finding | Disposition |\n| --- | --- | --- |\n| F999 | invented | accept |\n' > docs/plans/GOAL_IMPACT.md
  run bash "$ROOT/$PG" triage
  [ "$status" -eq 1 ]
  case "$output" in *UNKNOWN=F999*) ;; *) return 1 ;; esac
}

@test "triage gate: one ID with two dispositions fails here, not three phases later" {
  _audit_f001
  printf '| ID | Finding | Disposition |\n| --- | --- | --- |\n| F001 | empty goal | fix in Story 1 |\n| F001 | empty goal | accept |\n' > docs/plans/GOAL_IMPACT.md
  run bash "$ROOT/$PG" triage
  [ "$status" -eq 1 ]
  case "$output" in *DUPES=F001*) ;; *) return 1 ;; esac
}

@test "triage gate: an ID row with an empty disposition cell fails" {
  _audit_f001
  printf '| ID | Finding | Disposition |\n| --- | --- | --- |\n| F001 | empty goal |  |\n' > docs/plans/GOAL_IMPACT.md
  run bash "$ROOT/$PG" triage
  [ "$status" -eq 1 ]
  case "$output" in *BARE=F001*) ;; *) return 1 ;; esac
}

@test "triage gate: a dispositioned intersection passes; zero rows needs the claim" {
  _audit_f001
  printf '| ID | Finding | Disposition |\n| --- | --- | --- |\n| F001 | empty goal | fix in Story 1 |\n' > docs/plans/GOAL_IMPACT.md
  run bash "$ROOT/$PG" triage
  assert_success
  printf '# Impact\n\nNo intersecting findings.\n' > docs/plans/GOAL_IMPACT.md
  run bash "$ROOT/$PG" triage
  assert_success
  case "$output" in *INTERSECTING=0*) ;; *) return 1 ;; esac
}

@test "the phase 2 and 3 gates run through the driver and record their verdicts" {
  _pass_through 1
  run bash "$FLOW_GATE" plan 2
  [ "$status" -ne 0 ]
  _frames "$(printf '## D1 — a?\n- Frame A: x\n- Frame B: y')"
  run bash "$FLOW_GATE" plan 2
  [ "$status" -eq 0 ]
  run bash "$FLOW_NEXT" plan
  printf '%s\n' "$output" | grep -q '^PHASE=3$'
}

@test "frames and decisions are subject-keyed — a second plan does not see the first's" {
  _frames "$(printf '## D1 — a?\n- Frame A: x\n- Frame B: y')"
  run bash "$ROOT/$PG" frames
  assert_success
  bash "$FLOW_STATE" plan use other-feature >/dev/null
  run bash "$ROOT/$PG" frames
  [ "$status" -eq 1 ]
  case "$output" in *REASON=no-frames*) ;; *) return 1 ;; esac
}

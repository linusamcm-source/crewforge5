#!/usr/bin/env bats
# init_flow.bats — the contract for `crewforge5:init`: its phase manifest, the
# gate script behind every phase, and the two flow-level behaviours the story
# cares about (a rejected proposal must not advance the flow; a clean tree must).
#
# Everything here runs against a throwaway config root and a throwaway git repo,
# never this checkout, so a gate that silently measured the developer's own tree
# would fail rather than pass by accident.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  INIT_DIR="$ROOT/skills/init"
  MANIFEST="$INIT_DIR/phases.json"
  SKILL_MD="$INIT_DIR/SKILL.md"
  GATE_SH="$INIT_DIR/scripts/init_gate.sh"
  FLOW_NEXT="$ROOT/scripts/flow/flow_next.sh"
  FLOW_GATE="$ROOT/scripts/flow/flow_gate.sh"
  FLOW_STATE="$ROOT/scripts/flow/flow_state.sh"
  BASELINE_PY="$ROOT/skills/token-slim/scripts/baseline.py"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"

  # Sandbox every ambient root the gates read, so no test can reach the
  # developer's real catalogue, ledger or ceilings file.
  export HOME="$TMP/home"
  export XDG_STATE_HOME="$TMP/state"
  mkdir -p "$HOME/.claude/skills" "$XDG_STATE_HOME"
  unset CLAUDE_CONFIG_DIR || true

  # The plugin under test is this checkout: gates are declared against
  # ${CREWFORGE5_ROOT}, which is how a phase command reaches the plugin from
  # inside whatever repo the flow is being run on.
  export CREWFORGE5_ROOT="$ROOT"

  REPO="$TMP/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name "test"
  git commit -q --allow-empty -m "init"

  STATE_DIR="$REPO/.crewforge5/init"
  mkdir -p "$STATE_DIR"
  export INIT_STATE="$STATE_DIR"
  export INIT_TARGET="$TMP/config"
  mkdir -p "$INIT_TARGET"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# --- fixture builders -------------------------------------------------------

# A skill whose description is over the 300-char trim cap. Its two quoted
# trigger phrases are short on purpose: the padding is what a trim removes, and
# the phrases are what check.sh proves survived.
fixture_bloated_skill() {
  mkdir -p "$INIT_TARGET/skills/fixture-skill"
  cat > "$INIT_TARGET/skills/fixture-skill/SKILL.md" <<'EOF'
---
name: fixture-skill
description: Fixture skill used by the init phase-3 slim gate test. Padding sentence one exists to push this description well past the three hundred character trim cap so that the gate has something real to reject. Padding sentence two adds still more length to it. Padding sentence three finishes the job. Trigger on "slim the fixture" and "fixture trim demo".
---

# Fixture skill

## What it does

Nothing. It exists so the slim gate has a description to measure.

## When to use

Never outside this test.
EOF
}

fixture_trim_skill() {
  cat > "$INIT_TARGET/skills/fixture-skill/SKILL.md" <<'EOF'
---
name: fixture-skill
description: Fixture skill for the init slim gate. Trigger on "slim the fixture" and "fixture trim demo".
---

# Fixture skill

## What it does

Nothing. It exists so the slim gate has a description to measure.

## When to use

Never outside this test.
EOF
}

# A skill that validates structurally clean AND grades A (0 FAIL, <=2 WARN),
# so the only defect in the phase-4 fixture is the agent's.
fixture_clean_skill() {
  mkdir -p "$INIT_TARGET/skills/fixture-clean"
  cat > "$INIT_TARGET/skills/fixture-clean/SKILL.md" <<'EOF'
---
name: fixture-clean
description: An unremarkable fixture skill the validate and rectify gates walk past. Use when a fixture run needs one clean component.
---

# Fixture clean skill

## What it does

Nothing at all. It is here to be validated.

## When to use

Never outside this test suite.
EOF
}

fixture_broken_agent() {
  mkdir -p "$INIT_TARGET/agents"
  cat > "$INIT_TARGET/agents/fixture-reviewer.md" <<'EOF'
---
name: fixture-reviewer
tools: Grep
color: blue
---

# Fixture reviewer

You are a fixture reviewer agent used only by the init gate tests.

## Completion gate

Before reporting done, confirm the fixture was inspected.
EOF
}

fixture_fixed_agent() {
  mkdir -p "$INIT_TARGET/agents"
  cat > "$INIT_TARGET/agents/fixture-reviewer.md" <<'EOF'
---
name: fixture-reviewer
description: Fixture reviewer for the init phase-4 and phase-5 gate tests. Use when the init flow needs one clean agent to validate against.
tools: Grep
color: blue
---

# Fixture reviewer

You are a fixture reviewer agent used only by the init gate tests.

## Completion gate

Before reporting done, confirm the fixture config root was inspected.
EOF
}

record_baseline() {
  python3 "$BASELINE_PY" --skills-dir "$INIT_TARGET/skills" --out "$INIT_STATE/baseline.json" >/dev/null
}

# ---------------------------------------------------------------------------
# AC: phases.json lists all 8 phases; every doc and gate resolves on disk.
# ---------------------------------------------------------------------------

@test "manifest declares exactly the 8 init phases, ids 0-7 in order" {
  [ -f "$MANIFEST" ]
  run jq -r 'length' "$MANIFEST"
  assert_success
  assert_output "8"
  run jq -r '[.[].id] | join(",")' "$MANIFEST"
  assert_output "0,1,2,3,4,5,6,7"
}

@test "manifest: every phase carries a title, doc, gate and required flag" {
  run jq -e 'all(.[]; (.title | type == "string" and length > 0)
                   and (.doc   | type == "string" and length > 0)
                   and (.gate  | type == "string" and length > 0)
                   and (.required | type == "boolean"))' "$MANIFEST"
  assert_success
}

@test "manifest: every doc path resolves on disk" {
  [ -f "$MANIFEST" ]
  local doc
  while IFS= read -r doc; do
    [ -n "$doc" ]
    [ -f "$INIT_DIR/$doc" ] || {
      echo "missing phase doc: $INIT_DIR/$doc" >&2
      return 1
    }
  done < <(jq -r '.[].doc' "$MANIFEST")
}

@test "manifest: every gate command names a script that exists and answers to that check" {
  [ -f "$MANIFEST" ]
  [ -x "$GATE_SH" ]
  local gate p rel sub
  while IFS= read -r gate; do
    [ -n "$gate" ]
    # Gates address the plugin through ${CREWFORGE5_ROOT} — no machine paths.
    for p in $(printf '%s\n' "$gate" | grep -o '\${CREWFORGE5_ROOT}[^" ]*'); do
      rel="${p#\$\{CREWFORGE5_ROOT\}/}"
      [ -f "$ROOT/$rel" ] || { echo "gate names a missing file: $rel" >&2; return 1; }
      [ -x "$ROOT/$rel" ] || { echo "gate names a non-executable file: $rel" >&2; return 1; }
    done
    sub="${gate##* }"
    bash "$GATE_SH" --list | grep -qx "$sub" || {
      echo "init_gate.sh does not answer to check '$sub'" >&2
      return 1
    }
  done < <(jq -r '.[].gate' "$MANIFEST")
}

@test "init_gate.sh rejects an unknown check with exit 2 and usage on stderr" {
  run bash "$GATE_SH" not-a-check
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# AC: SKILL.md body <= 120 lines, description <= 300 normalised chars.
# ---------------------------------------------------------------------------

@test "SKILL.md body is at most 120 lines" {
  [ -f "$SKILL_MD" ]
  local total close body
  total="$(wc -l < "$SKILL_MD" | tr -d ' ')"
  close="$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_MD")"
  [ -n "$close" ]
  body=$((total - close))
  echo "body lines: $body" >&2
  [ "$body" -le 120 ]
}

@test "SKILL.md description is at most 300 normalised chars" {
  run python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fm = re.match(r"\A---\n(.*?\n)---\n", text, re.DOTALL).group(1)
m = re.search(r"^description:[ \t]*(.*(?:\n[ \t]+\S.*)*)", fm, re.MULTILINE)
print(len(re.sub(r"\s+", " ", m.group(1)).strip()))
' "$SKILL_MD"
  assert_success
  [ "$output" -le 300 ]
  [ "$output" -gt 0 ]
}

@test "SKILL.md names every bundled file, so nothing in the skill is an orphan" {
  local f base
  while IFS= read -r f; do
    base="$(basename "$f")"
    grep -qF "$base" "$SKILL_MD" || { echo "unmentioned file: $f" >&2; return 1; }
  done < <(find "$INIT_DIR" -type f ! -name 'SKILL.md')
}

@test "SKILL.md and phase docs use the namespaced /crewforge5:init form" {
  grep -q '/crewforge5:init' "$SKILL_MD"
  # A bare `/init` reaches Claude Code's built-in CLAUDE.md initializer.
  run grep -rn '[^:a-z0-9]/init\b' "$SKILL_MD" "$INIT_DIR/phases"
  [ "$status" -ne 0 ]
}

# The plan's phase-4 row names `validate_all.sh` as the structural sweep before
# the per-component pass. The gate cannot run it — it is hardcoded to the
# plugin's own root, not INIT_TARGET — so the phase doc is the only place that
# sweep is carried, and dropping it there would drop it entirely.
@test "phase-4 doc still carries the validate_all.sh structural sweep" {
  grep -q 'validate_all.sh' "$INIT_DIR/phases/phase-4.md"
}

# ---------------------------------------------------------------------------
# Phase 0 step 0 — dependencies.
#
# The point of this check is the machine that has nothing on it, so the tests
# build that machine rather than describing it: _shim makes a PATH holding only
# the named tools, and every case below runs the gate against one.
# ---------------------------------------------------------------------------

# _shim <dir> <tool>… — a PATH containing only the tools named, symlinked to
# wherever they really live. Anything not named is genuinely unreachable.
_shim() {
  local dir="$1" t p
  shift
  mkdir -p "$dir"
  for t in "$@"; do
    p="$(command -v "$t")" || continue
    ln -sf "$p" "$dir/$t"
  done
  printf '%s\n' "$dir"
}

@test "deps passes on this machine and reports no required tool missing" {
  run bash "$GATE_SH" deps
  assert_success
  case "$output" in *STATUS=OK*) : ;; *) return 1 ;; esac
  case "$output" in *CHECK=deps*) : ;; *) return 1 ;; esac
  case "$output" in *"REQUIRED_MISSING="$'\n'*) : ;; *) return 1 ;; esac
}

@test "deps fails and names the required tool that is missing" {
  local p
  p="$(_shim "$TMP/shim-nojq" bash git dirname python3)"
  run env PATH="$p" bash "$GATE_SH" deps
  [ "$status" -eq 1 ]
  case "$output" in *STATUS=FAIL*) : ;; *) return 1 ;; esac
  case "$output" in *REQUIRED_MISSING=jq*) : ;; *) return 1 ;; esac
  case "$output" in *REASON=missing-required*) : ;; *) return 1 ;; esac
}

# The whole reason deps is exempt from the script's jq precondition. Without
# the exemption this run would print "[fail] jq missing" and exit before ever
# reaching the scan — reporting one missing tool and hiding the rest.
@test "deps answers on a machine without jq instead of hitting the jq guard" {
  local p
  p="$(_shim "$TMP/shim-guard" bash git dirname python3)"
  run env PATH="$p" bash "$GATE_SH" deps
  case "$output" in *"[fail] jq missing"*) return 1 ;; esac
  case "$output" in *CHECK=deps*) : ;; *) return 1 ;; esac
}

# …and the exemption is scoped to deps alone. Every other check reads state
# through jq, so it must still refuse rather than measure with a broken tool.
@test "a non-deps check still refuses when jq is missing" {
  local p
  p="$(_shim "$TMP/shim-measure" bash git dirname python3)"
  run env PATH="$p" bash "$GATE_SH" measure
  [ "$status" -eq 1 ]
  case "$output" in *"jq missing"*) : ;; *) return 1 ;; esac
}

# Optional tooling absent is a documented degradation, not a stop — the README
# says the bundle degrades visibly, and a gate that failed here would make that
# sentence false.
@test "deps passes when only optional tools are missing, and names them" {
  local p
  p="$(_shim "$TMP/shim-noopt" bash git dirname python3 jq)"
  run env PATH="$p" bash "$GATE_SH" deps
  assert_success
  case "$output" in *STATUS=OK*) : ;; *) return 1 ;; esac
  case "$output" in *OPTIONAL_MISSING=*repomix*) : ;; *) return 1 ;; esac
}

# The block is what the user pastes into another terminal, so its markers are
# part of the contract the phase doc tells the model to relay.
@test "deps emits a delimited copy-paste block when something is missing" {
  local p
  p="$(_shim "$TMP/shim-block" bash git dirname python3)"
  run env PATH="$p" bash "$GATE_SH" deps
  case "$output" in *"copy-paste into another terminal"*) : ;; *) return 1 ;; esac
  case "$output" in *"deps: ----- end -----"*) : ;; *) return 1 ;; esac
}

# A tool with no install command this repo can vouch for is admitted, never
# guessed at — the user is about to paste the block into a root shell. The shim
# carries no package manager, so MANAGER=none and the tools that only have a
# manager-specific line land in the unknown list on every platform.
@test "deps admits the tools it knows no install command for" {
  local p
  p="$(_shim "$TMP/shim-unknown" bash git dirname python3 jq)"
  run env PATH="$p" bash "$GATE_SH" deps
  case "$output" in *"no packaged install known here for:"*) : ;; *) return 1 ;; esac
}

# The three manager-independent tools carry their own install line whatever the
# platform, so MANAGER=none must not empty the block out entirely. codegraph's
# line was verified against the live registry (@colbymchenry/codegraph, MIT),
# not inferred from the name.
@test "deps emits manager-independent install lines even with no package manager" {
  local p
  p="$(_shim "$TMP/shim-nomgr" bash git dirname python3 jq)"
  run env PATH="$p" bash "$GATE_SH" deps
  case "$output" in *"npm install -g repomix"*) : ;; *) return 1 ;; esac
  case "$output" in *"uv tool install graphifyy"*) : ;; *) return 1 ;; esac
  case "$output" in *"codegraph/main/install.sh | sh"*) : ;; *) return 1 ;; esac
  case "$output" in *"npm install -g @colbymchenry/codegraph"*) : ;; *) return 1 ;; esac
}

# A piped-remote-script install is the one line the model must never run for
# the user: it needs no sudo, so the "install what needs no sudo" rule would
# otherwise wave it through. The doc has to say so, and an alternative has to
# be offered rather than the line simply being withheld.
@test "the phase-0 doc refuses to run a piped remote installer on the user's behalf" {
  grep -q 'Never run a line that pipes a remote script into a shell' \
    "$INIT_DIR/phases/phase-0.md"
}

@test "a piped installer is offered with a non-piped alternative beside it" {
  local p
  p="$(_shim "$TMP/shim-piped" bash git dirname python3 jq)"
  run env PATH="$p" bash "$GATE_SH" deps
  # The alternative is a comment line, so the block stays safe to paste whole.
  case "$output" in
    *"install.sh | sh"*"# or, without piping a remote script to a shell:"*) : ;;
    *) return 1 ;;
  esac
}

@test "the phase-0 doc drives the wait-and-loop, not just the check" {
  local doc="$INIT_DIR/phases/phase-0.md"
  grep -q 'init_gate.sh" deps' "$doc"
  grep -qi 'loop' "$doc"
  grep -qi 'wait' "$doc"
  # Installing without asking is the failure mode worth pinning: the doc must
  # keep sudo off the table and put the decision to the user.
  grep -q 'sudo' "$doc"
}

# ---------------------------------------------------------------------------
# Phase 0 — preflight.
# ---------------------------------------------------------------------------

@test "preflight refuses when a required tool is missing, before the tree check" {
  local p
  p="$(_shim "$TMP/shim-pre" bash git dirname python3)"
  run env PATH="$p" bash "$GATE_SH" preflight
  [ "$status" -eq 1 ]
  case "$output" in *REASON=missing-deps*) : ;; *) return 1 ;; esac
}

@test "preflight passes on a clean tree and reports the target" {
  run bash "$GATE_SH" preflight
  assert_success
  case "$output" in *STATUS=OK*) : ;; *) return 1 ;; esac
  case "$output" in *CHECK=preflight*) : ;; *) return 1 ;; esac
}

@test "preflight fails on a dirty tree" {
  echo "stray" > "$REPO/untracked.txt"
  run bash "$GATE_SH" preflight
  [ "$status" -eq 1 ]
  case "$output" in *STATUS=FAIL*) : ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Phase 1 — measure.
# ---------------------------------------------------------------------------

@test "measure fails when baseline.json is missing or empty" {
  run bash "$GATE_SH" measure
  [ "$status" -eq 1 ]
  : > "$INIT_STATE/baseline.json"
  run bash "$GATE_SH" measure
  [ "$status" -eq 1 ]
}

@test "measure passes on a baseline.json holding at least one skill" {
  fixture_bloated_skill
  record_baseline
  run bash "$GATE_SH" measure
  assert_success
  case "$output" in *SKILLS=1*) : ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Phase 2 — hygiene, gated by retention_gate.sh.
# ---------------------------------------------------------------------------

write_proposal_pair() { # $1 slug  $2 original text  $3 proposed text
  mkdir -p "$INIT_STATE/proposals"
  printf '%s\n' "$2" > "$INIT_STATE/proposals/$1.orig"
  printf '%s\n' "$3" > "$INIT_STATE/proposals/$1.proposed"
}

@test "hygiene rejects a proposal that drops a never directive" {
  write_proposal_pair claude-md \
"# House rules

Never run find from the filesystem root; scope it to the project tree.
Always stage explicit paths rather than the whole tree." \
"# House rules

Keep searches scoped and stage changes carefully."
  run bash "$GATE_SH" hygiene
  [ "$status" -eq 1 ]
  case "$output" in *"directive lost"*) : ;; *) return 1 ;; esac
}

@test "hygiene passes a proposal that reorganises without losing a directive" {
  write_proposal_pair claude-md \
"# House rules

Never run find from the filesystem root; scope it to the project tree.
Always stage explicit paths rather than the whole tree." \
"# House rules

- Always stage explicit paths rather than the whole tree.
- Never run find from the filesystem root; scope it to the project tree."
  run bash "$GATE_SH" hygiene
  assert_success
  case "$output" in *PROPOSALS=1*) : ;; *) return 1 ;; esac
}

@test "hygiene fails a proposal with no recorded original" {
  mkdir -p "$INIT_STATE/proposals"
  printf 'anything\n' > "$INIT_STATE/proposals/orphan.proposed"
  run bash "$GATE_SH" hygiene
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Phase 3 — slim, gated by token-slim's check.sh and sweep.py.
# ---------------------------------------------------------------------------

@test "slim fails while a description is over the trim cap" {
  fixture_bloated_skill
  record_baseline
  run bash "$GATE_SH" slim
  [ "$status" -eq 1 ]
  case "$output" in *"fixture-skill"*) : ;; *) return 1 ;; esac
}

@test "slim passes once the description is trimmed and the trigger phrases survive" {
  fixture_bloated_skill
  record_baseline
  fixture_trim_skill
  run bash "$GATE_SH" slim
  assert_success
  case "$output" in *STATUS=OK*) : ;; *) return 1 ;; esac
}

@test "slim still fails when a trim loses a baseline trigger phrase" {
  fixture_bloated_skill
  record_baseline
  cat > "$INIT_TARGET/skills/fixture-skill/SKILL.md" <<'EOF'
---
name: fixture-skill
description: Fixture skill for the init slim gate.
---

# Fixture skill

## What it does

Nothing.

## When to use

Never outside this test.
EOF
  run bash "$GATE_SH" slim
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Phases 4 and 5 — validate, then rectify to grade A.
# ---------------------------------------------------------------------------

@test "validate reports FAIL for an agent with a structural defect" {
  fixture_clean_skill
  fixture_broken_agent
  run bash "$GATE_SH" validate
  [ "$status" -eq 1 ]
  case "$output" in *STATUS=FAIL*) : ;; *) return 1 ;; esac
  case "$output" in *"fixture-reviewer"*) : ;; *) return 1 ;; esac
}

@test "validate passes once the defect is repaired" {
  fixture_clean_skill
  fixture_fixed_agent
  run bash "$GATE_SH" validate
  assert_success
  case "$output" in *FAILURES=0*) : ;; *) return 1 ;; esac
}

@test "rectify demands grade A and refuses the unrepaired component" {
  fixture_clean_skill
  fixture_broken_agent
  run bash "$GATE_SH" rectify
  [ "$status" -eq 1 ]
}

@test "rectify passes when every component grades A" {
  fixture_clean_skill
  fixture_fixed_agent
  run bash "$GATE_SH" rectify
  assert_success
  case "$output" in *GRADE=A*) : ;; *) return 1 ;; esac
}

# A config root with nothing to walk is a mis-pointed INIT_TARGET, not a clean
# bill of health. "Zero FAIL across zero components" is the shape of a gate that
# passes because it looked at nothing.
@test "validate refuses a config root holding neither skills nor agents" {
  run bash "$GATE_SH" validate
  [ "$status" -eq 1 ]
  case "$output" in *REASON=no-components*) : ;; *) return 1 ;; esac
}

@test "rectify refuses a config root holding neither skills nor agents" {
  run bash "$GATE_SH" rectify
  [ "$status" -eq 1 ]
  case "$output" in *REASON=no-components*) : ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Phase 6 — distil.
# ---------------------------------------------------------------------------

@test "distil with an empty ledger reports nothing to distil and passes" {
  run bash "$GATE_SH" distil
  assert_success
  case "$output" in *"nothing to distil"*) : ;; *) return 1 ;; esac
  case "$output" in *LEDGER=0*) : ;; *) return 1 ;; esac
}

@test "distil with a populated ledger runs the ceiling gate instead" {
  export CLAUDE_CONFIG_DIR="$INIT_TARGET"
  fixture_clean_skill
  bash "$ROOT/skills/self-improve/scripts/ledger.sh" add fixture-clean user "a lesson" >/dev/null
  bash "$ROOT/skills/self-improve/scripts/ceiling.sh" record fixture-clean >/dev/null
  run bash "$GATE_SH" distil
  assert_success
  case "$output" in *LEDGER=1*) : ;; *) return 1 ;; esac
}

# The pass above cannot tell a ceiling gate that ran from one that was never
# called: both look like exit 0. This is the case that can — the ledger is
# populated, so the empty-ledger shortcut is closed, and the only thing left
# that can fail the phase is the ceiling itself.
@test "distil fails when a distilled target has outgrown its recorded ceiling" {
  export CLAUDE_CONFIG_DIR="$INIT_TARGET"
  fixture_clean_skill
  bash "$ROOT/skills/self-improve/scripts/ledger.sh" add fixture-clean user "a lesson" >/dev/null
  bash "$ROOT/skills/self-improve/scripts/ceiling.sh" record fixture-clean >/dev/null
  # Descriptions get no slack at all in ceiling.sh, so one padded sentence past
  # the recorded budget is a breach. The body is left byte-identical.
  # No `sed -i`: the BSD and GNU spellings differ, so write beside and move.
  local skill="$INIT_TARGET/skills/fixture-clean/SKILL.md"
  sed 's/^\(description: .*\)$/\1 It has since grown one more sentence that nobody paid for by cutting elsewhere./' \
    "$skill" > "$skill.grown"
  mv "$skill.grown" "$skill"
  run bash "$GATE_SH" distil
  [ "$status" -eq 1 ]
  case "$output" in *REASON=ceiling-breach*) : ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Phase 7 — report, which must carry the measured char delta.
# ---------------------------------------------------------------------------

@test "report fails when report.md is missing" {
  fixture_bloated_skill
  record_baseline
  run bash "$GATE_SH" report
  [ "$status" -eq 1 ]
}

@test "report fails when report.md omits the measured char delta" {
  fixture_bloated_skill
  record_baseline
  fixture_trim_skill
  printf '# init report\n\nWe slimmed some things.\n' > "$INIT_STATE/report.md"
  run bash "$GATE_SH" report
  [ "$status" -eq 1 ]
}

@test "report passes when report.md records the before, after and delta chars" {
  fixture_bloated_skill
  record_baseline
  fixture_trim_skill
  local before after delta
  before="$(jq -r '[.[].desc_chars] | add' "$INIT_STATE/baseline.json")"
  after="$(python3 "$BASELINE_PY" --skills-dir "$INIT_TARGET/skills" --report | jq -r '[.[].desc_chars] | add')"
  delta=$((before - after))
  [ "$delta" -gt 0 ]
  {
    printf '# init report\n\n'
    printf 'DESC_CHARS_BEFORE=%s\n' "$before"
    printf 'DESC_CHARS_AFTER=%s\n' "$after"
    printf 'DESC_CHARS_DELTA=%s\n' "$delta"
  } > "$INIT_STATE/report.md"
  run bash "$GATE_SH" report
  assert_success
  case "$output" in *"DESC_CHARS_DELTA=$delta"*) : ;; *) return 1 ;; esac
}

@test "report fails when report.md claims a delta the tree does not support" {
  fixture_bloated_skill
  record_baseline
  fixture_trim_skill
  {
    printf 'DESC_CHARS_BEFORE=999\n'
    printf 'DESC_CHARS_AFTER=1\n'
    printf 'DESC_CHARS_DELTA=998\n'
  } > "$INIT_STATE/report.md"
  run bash "$GATE_SH" report
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Flow level — a rejected phase-2 proposal must not advance the flow.
# ---------------------------------------------------------------------------

@test "a rejected phase-2 proposal records FAIL and flow_next re-offers phase 2" {
  bash "$FLOW_STATE" init set phase.0.status pass phase.1.status pass

  write_proposal_pair claude-md \
"# House rules

Never run find from the filesystem root; scope it to the project tree." \
"# House rules

Search carefully."

  run bash "$FLOW_GATE" init 2
  [ "$status" -eq 1 ]
  case "$output" in *STATUS=FAIL*) : ;; *) return 1 ;; esac

  run bash "$FLOW_STATE" init get phase.2.status
  assert_success
  assert_output "FAIL"

  run bash "$FLOW_NEXT" init
  assert_success
  case "$output" in *PHASE=2*) : ;; *) return 1 ;; esac
}

@test "a retention-safe phase-2 proposal records PASS and the flow advances to phase 3" {
  bash "$FLOW_STATE" init set phase.0.status pass phase.1.status pass

  write_proposal_pair claude-md \
"# House rules

Never run find from the filesystem root; scope it to the project tree." \
"# House rules

- Never run find from the filesystem root; scope it to the project tree."

  run bash "$FLOW_GATE" init 2
  assert_success

  run bash "$FLOW_NEXT" init
  assert_success
  case "$output" in *PHASE=3*) : ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# AC: skill-validator grades the new skill A.
# ---------------------------------------------------------------------------

@test "skill-validator grades skills/init A: 0 failures and at most 2 warnings" {
  local out fails warns findings
  out="$(bash "$ROOT/skills/skill-validator/scripts/validate_structure.sh" "$INIT_DIR" 2>&1)"
  fails="$(printf '%s' "$out" | grep -c '"status":"FAIL"' || true)"
  warns="$(printf '%s' "$out" | grep -c '"status":"WARN"' || true)"
  printf '%s\n' "$out" | grep -E '"status":"(FAIL|WARN)"' >&2 || true

  findings="$TMP/findings.txt"
  : > "$findings"
  local i=0
  while [ "$i" -lt "$fails" ]; do printf 'FAIL [structure]: see above\n' >> "$findings"; i=$((i + 1)); done
  i=0
  while [ "$i" -lt "$warns" ]; do printf 'WARN [structure]: see above\n' >> "$findings"; i=$((i + 1)); done

  run bash "$ROOT/skills/skill-validator/scripts/grade.sh" "$findings"
  assert_success
  case "$output" in *"grade=A"*) : ;; *) return 1 ;; esac
}

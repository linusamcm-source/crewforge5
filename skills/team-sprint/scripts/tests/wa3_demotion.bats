#!/usr/bin/env bats
# wa3_demotion.bats — WA3: phase-3/4/5/7 prose demoted to a fallback contract.
#
# The story rewrites phase-3.md, phase-4.md, phase-5.md and phase-7.md so that
# each opens with a `> **Workflow path.**` guard block naming its workflow
# (story-executor.workflow.js for 3/4/5, phase-7.workflow.js for 7) with the
# full args signature, and the remaining prose becomes the FALLBACK contract —
# never "the reference implementation". SKILL.md's phase sections must name the
# same workflow paths. These tests pin the mechanically checkable acceptance
# criteria and are written RED: today only phase-1/phase-5 carry a guard, the
# phase-5 guard still names the renamed workflow, and the docs are too long.
#
# SELF-MATCH NOTE: a story gate greps this whole tree for the renamed
# workflow's dotted name, so this file only ever spells it with a bracketed
# dot — "phase-4-5[.]workflow" — which the gate's pattern does not match.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# Extract the contiguous blockquote starting at the `> **Workflow path.**` line.
wf_guard() { awk '/^> \*\*Workflow path\.\*\*/{f=1} f && !/^>/{exit} f' "$1"; }

# _guard_has <doc> <token>... — the doc's guard block exists and contains
# every token as a literal substring. Prints one line per miss.
_guard_has() {
  local doc="$1" g t bad=0
  shift
  g="$(wf_guard "$doc")"
  [ -n "$g" ] || { echo "$(basename "$doc"): no Workflow-path guard block"; return 1; }
  for t in "$@"; do
    case "$g" in
      *"$t"*) : ;;
      *) echo "$(basename "$doc"): guard missing '$t'"; bad=1 ;;
    esac
  done
  [ "$bad" -eq 0 ]
}

# Fallback-runner semantics: only the terminal command's status is enforcing
# under plain `bash <file>`, so every multi-check test below accumulates into
# `bad` and ends on a single `[ "$bad" -eq 0 ]`.

@test "phase-3/4/5/7 each carry a Workflow-path guard with the fact-check phrase" {
  bad=0
  for f in phase-3.md phase-4.md phase-5.md phase-7.md; do
    _guard_has "$SKILL/phases/$f" 'a fact to check, not a preference to weigh' || bad=1
  done
  [ "$bad" -eq 0 ]
}

@test "phase-3 and phase-4 guards name story-executor.workflow.js with the full args signature" {
  bad=0
  for f in phase-3.md phase-4.md; do
    _guard_has "$SKILL/phases/$f" story-executor.workflow.js \
      storyId artDir scriptsDir planPath testWriterAgent engineerAgent coverageMode || bad=1
  done
  [ "$bad" -eq 0 ]
}

@test "phase-5 guard names story-executor.workflow.js; the renamed workflow is gone from phase-5.md" {
  bad=0
  _guard_has "$SKILL/phases/phase-5.md" story-executor.workflow.js \
    storyId artDir scriptsDir planPath testWriterAgent engineerAgent coverageMode || bad=1
  run grep -E "phase-4-5[.]workflow" "$SKILL/phases/phase-5.md"
  [ "$status" -ne 0 ] || { echo "phase-5.md still names the renamed workflow:"; echo "$output"; bad=1; }
  [ "$bad" -eq 0 ]
}

@test "phase-7 guard names phase-7.workflow.js with the full args signature" {
  _guard_has "$SKILL/phases/phase-7.md" phase-7.workflow.js \
    artDir scriptsDir planPath targetBranch worktree \
    testCommand typecheckCommand lintCommand coverageCommand coverageThreshold
}

@test "no phase doc calls the prose the reference implementation" {
  run grep -r "reference implementation" "$SKILL/phases/"
  [ "$status" -eq 1 ] || { echo "grep status=$status"; echo "$output"; false; }
}

@test "zero references to the renamed workflow outside docs/plans" {
  out="$(grep -rlE "phase-4-5[.]workflow" "$SKILL" | grep -v docs/plans || true)"
  [ -z "$out" ] || { echo "$out"; false; }
}

@test "guard blocks document lead-side workflow-run recording" {
  bad=0
  # WA4 keys workflow_runs by `phase-<n>` (state-schema.md:53, state.schema.json,
  # state.bats:501-503) — a bare-digit key would satisfy `workflow_runs.` yet
  # write a key space the resume contract never reads.
  for p in 3 4 5 7; do
    _guard_has "$SKILL/phases/phase-$p.md" "workflow_runs.phase-$p" "phase-$p <run_id>" || bad=1
  done
  for f in phase-3.md phase-4.md phase-5.md; do
    _guard_has "$SKILL/phases/$f" 'sequential mode' || bad=1
  done
  _guard_has "$SKILL/phases/phase-7.md" 'both scheduling modes' 'iterations.review_fix' || bad=1
  [ "$bad" -eq 0 ]
}

@test "per-story guards list the lead-side steps around the workflow call" {
  # plan-final.md: hooks, mid-audit, state advance are listed explicitly as
  # "lead before/after the call" — the workflow runs none of them, so a lead
  # on the Workflow path needs the reminder inside the guard block itself.
  bad=0
  for f in phase-3.md phase-4.md phase-5.md; do
    _guard_has "$SKILL/phases/$f" 'Lead before/after the call' || bad=1
  done
  [ "$bad" -eq 0 ]
}

@test "journal recording is not documented (WA4 reduced branch)" {
  run grep -il "journal" \
    "$SKILL/phases/phase-3.md" "$SKILL/phases/phase-4.md" \
    "$SKILL/phases/phase-5.md" "$SKILL/phases/phase-7.md"
  [ "$status" -eq 1 ] || { echo "grep status=$status"; echo "$output"; false; }
}

@test "combined line count of the four demoted docs is <= 306" {
  total=0
  for f in phase-3.md phase-4.md phase-5.md phase-7.md; do
    n="$(wc -l < "$SKILL/phases/$f" | tr -d ' ')"
    total=$((total + n))
  done
  [ "$total" -le 306 ] || { echo "combined=$total"; false; }
}

@test "no demoted phase doc instructs AskUserQuestion" {
  run grep -l "AskUserQuestion" \
    "$SKILL/phases/phase-3.md" "$SKILL/phases/phase-4.md" \
    "$SKILL/phases/phase-5.md" "$SKILL/phases/phase-7.md"
  [ "$status" -eq 1 ] || { echo "grep status=$status"; echo "$output"; false; }
}

@test "SKILL.md phase sections name the workflow path" {
  bad=0
  for p in 3 4 5; do
    sec="$(awk -v p="$p" '$0 ~ "^### Phase " p " " {f=1;next} /^### /{f=0} f' "$SKILL/SKILL.md")"
    case "$sec" in
      *story-executor.workflow.js*) : ;;
      *) echo "SKILL.md Phase $p section lacks story-executor.workflow.js"; bad=1 ;;
    esac
  done
  sec="$(awk '/^### Phase 7 /{f=1;next} /^### /{f=0} f' "$SKILL/SKILL.md")"
  case "$sec" in
    *phase-7.workflow.js*) : ;;
    *) echo "SKILL.md Phase 7 section lacks phase-7.workflow.js"; bad=1 ;;
  esac
  [ "$bad" -eq 0 ]
}

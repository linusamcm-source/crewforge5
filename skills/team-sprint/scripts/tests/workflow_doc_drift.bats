#!/usr/bin/env bats
# workflow_doc_drift.bats — the phase doc and its workflow must not drift.
#
# WHY: six defects reached a live run, and FIVE shared one shape — the workflow
# silently omitted a step its own phase doc requires. Step 3a's boundary-reviewer,
# the persisted round counter, prompt_user_with_residuals(). Every one was caught
# by a human reading both files, because the smoke tests only asserted what the
# workflow DOES, never that it does everything the doc SAYS.
#
# The doc itself warns "Keep the two in sync or delete one — do not let them
# drift", which is prose: a sentence someone must notice. This makes it a check.
#
# MECHANISM: each requirement the workflow must implement is tagged `<!-- wf:id -->`
# in the phase doc (same HTML-comment convention as `<!-- subskill-hooks:phase-N -->`)
# and `// wf:id` at its implementation site. The sets must match EXACTLY, both
# directions:
#   doc marker with no code marker  -> the workflow silently dropped a step
#   code marker with no doc marker  -> the doc dropped a step still implemented
#
# Adding a step to either file without the other now fails here, loudly, at the
# moment of the change rather than on a live sprint.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() { rm -rf "$TMP"; }

# Marker ids may carry digits (wf:p3-red, wf:p4-verify): [a-z0-9-], not [a-z-],
# which silently truncated "wf:p3-red" to "wf:p" on the code side and matched
# nothing at all on the doc side.
doc_markers()  { grep -oE '<!-- wf:[a-z0-9-]+ -->' "$1" | sed 's|<!-- ||; s| -->||' | sort -u; }
code_markers() { grep -oE '// wf:[a-z0-9-]+'      "$1" | sed 's|// ||'             | sort -u; }

check_drift() { # $1..$(n-1) = phase docs (doc side is their UNION), $n = workflow
  # story-executor implements phases 3+4+5 in one workflow, so the doc side of
  # the parity check is the union of several docs' marker sets. Existing
  # 2-arg (one doc, one workflow) calls behave exactly as before.
  local n=$#
  local wf="${!n}"
  local docs=("${@:1:n-1}")
  local doclabel="" d
  for d in "${docs[@]}"; do doclabel="${doclabel:+$doclabel+}$(basename "$d")"; done
  for d in "${docs[@]}"; do doc_markers "$d"; done | sort -u > "$TMP/doc.txt"
  code_markers "$wf" > "$TMP/code.txt"
  missing="$(comm -23 "$TMP/doc.txt" "$TMP/code.txt")"
  orphan="$(comm -13 "$TMP/doc.txt" "$TMP/code.txt")"
  if [ -n "$missing" ]; then
    echo "DRIFT — required by $doclabel but NOT implemented in $(basename "$wf"):"
    echo "$missing" | sed 's/^/    /'
  fi
  if [ -n "$orphan" ]; then
    echo "DRIFT — implemented in $(basename "$wf") but no longer required by $doclabel:"
    echo "$orphan" | sed 's/^/    /'
  fi
  [ -z "$missing" ] && [ -z "$orphan" ]
}

# The phase-1 (adversarial review) drift checks moved planner-side with the
# workflow: team-sprint-planner/scripts/tests/workflow_doc_drift.bats pairs
# adversarial-review-loop.md with plan-review.workflow.js.

# --- phases 3/4/5: story-executor -------------------------------------------
# WA1: the old phase-4/5 workflow becomes story-executor.workflow.js and absorbs the
# Phase-3 stages, so its code markers must equal the UNION of the three docs.

@test "phase-3/4/5 docs and story-executor.workflow.js declare the same requirements (union)" {
  run check_drift "$SKILL/phases/phase-3.md" "$SKILL/phases/phase-4.md" "$SKILL/phases/phase-5.md" "$SKILL/workflows/story-executor.workflow.js"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "phase-5 has a non-trivial number of tagged requirements" {
  n="$(doc_markers "$SKILL/phases/phase-5.md" | wc -l | tr -d ' ')"
  [ "$n" -ge 4 ]
}

@test "phase-4 has a non-trivial number of tagged requirements" {
  n="$(doc_markers "$SKILL/phases/phase-4.md" | wc -l | tr -d ' ')"
  [ "$n" -ge 2 ]
}

@test "phase-3 tags every executor stage: RED/RED-verify/GREEN/GREEN-verify/wip/coverage-loop" {
  m="$(doc_markers "$SKILL/phases/phase-3.md")"
  for required in wf:p3-red wf:p3-red-verify wf:p3-green wf:p3-green-verify wf:p3-wip-commit wf:p3-coverage-loop; do
    grep -qx "$required" <<<"$m" || { echo "phase-3.md lost the $required marker"; false; }
  done
}

@test "phase-4 tags verify and re-review under its own p4- namespace" {
  m="$(doc_markers "$SKILL/phases/phase-4.md")"
  for required in wf:p4-verify wf:p4-re-review; do
    grep -qx "$required" <<<"$m" || { echo "phase-4.md lost the $required marker"; false; }
  done
}

@test "phase-4 tags the per-story diff producer (CONS-1: the reviewer's patch must be computed in-workflow)" {
  # phase-4.md step 1 lists $ART/diff-<story-id>.patch under Artifacts produced
  # and feeds it to the reviewer, but the workflow path ran nothing before the
  # call ("Before: nothing") — the patch had no producer. The marker makes the
  # union drift check enforce an implementation site in story-executor.
  m="$(doc_markers "$SKILL/phases/phase-4.md")"
  grep -qx "wf:p4-diff" <<<"$m" || { echo "phase-4.md lost the wf:p4-diff marker"; false; }
}

@test "phase-5 tags fix/coverage/triage/persist-counter; re-review no longer lives here" {
  m="$(doc_markers "$SKILL/phases/phase-5.md")"
  for required in wf:p5-fix wf:p5-coverage wf:p5-triage wf:p5-persist-counter; do
    grep -qx "$required" <<<"$m" || { echo "phase-5.md lost the $required marker"; false; }
  done
  run grep -qx "wf:re-review" <<<"$m"
  [ "$status" -ne 0 ]
}

# --- phase 7: regression gate + review fleet --------------------------------
# WA2: phase-7.workflow.js covers phase-7.md steps 1/1b/2/3 (regression gate,
# diff regeneration, four-lane fleet, bounded fix loop); steps 4-10 stay
# lead-side.

@test "phase-7.md and phase-7.workflow.js declare the same requirements" {
  wf="$SKILL/workflows/phase-7.workflow.js"
  # Existence first: check_drift on two marker-less sides passes vacuously,
  # which would hide a missing workflow file entirely.
  [ -f "$wf" ] || { echo "missing $wf"; false; }
  run check_drift "$SKILL/phases/phase-7.md" "$wf"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "phase-7 tags the fleet/simplifier/cap/regression requirements" {
  m="$(doc_markers "$SKILL/phases/phase-7.md")"
  for required in wf:regression-first wf:fleet-completeness wf:simplifier-mandatory wf:cap-residuals; do
    grep -qx "$required" <<<"$m" || { echo "phase-7.md lost the $required marker"; false; }
  done
}

@test "phase-7.md Gate section names the unavailable-coverage exception verbatim" {
  # Scoped to the Gate section: a whole-file grep would stay green if a later
  # rewrite relocated the sentence out of the Gate bullet — the exact drift
  # this check exists to block. The words match the workflow's result note
  # byte-for-byte (em dash included).
  awk '/^## Gate/{f=1;next} /^## /{f=0} f' "$SKILL/phases/phase-7.md" | grep -qF 'unavailable — no coverage command resolved'
}

# --- the marker grammar itself ----------------------------------------------

@test "marker grammar round-trips digit-bearing ids (wf:p3-red), no truncation" {
  # The old [a-z-] classes truncated wf:p3-red to wf:p in code and dropped it
  # entirely in docs — a drift check that cannot SEE the p3/p4/p5 markers
  # passes vacuously. Pin the extraction end to end.
  printf 'prose\n<!-- wf:p3-red -->\nprose\n' > "$TMP/rt-doc.md"
  printf '// wf:p3-red\nconst x = 1\n' > "$TMP/rt-wf.js"
  [ "$(doc_markers "$TMP/rt-doc.md")" = "wf:p3-red" ]
  [ "$(code_markers "$TMP/rt-wf.js")" = "wf:p3-red" ]
  run check_drift "$TMP/rt-doc.md" "$TMP/rt-wf.js"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# --- the check itself must be able to fail ---------------------------------

@test "the drift check DETECTS a workflow that dropped a required step" {
  cp "$SKILL/phases/phase-7.md" "$TMP/doc.md"
  sed 's|// wf:regression-first||' "$SKILL/workflows/phase-7.workflow.js" > "$TMP/wf.js"
  run check_drift "$TMP/doc.md" "$TMP/wf.js"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT implemented"* ]]
  [[ "$output" == *"wf:regression-first"* ]]
}

@test "the drift check DETECTS a doc that dropped a still-implemented step" {
  sed 's|<!-- wf:cap-residuals -->||' "$SKILL/phases/phase-7.md" > "$TMP/doc.md"
  cp "$SKILL/workflows/phase-7.workflow.js" "$TMP/wf.js"
  run check_drift "$TMP/doc.md" "$TMP/wf.js"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no longer required"* ]]
  [[ "$output" == *"wf:cap-residuals"* ]]
}

@test "every workflow in workflows/ has a paired phase doc under the check" {
  # A new workflow added with no drift coverage is itself drift.
  for wf in "$SKILL"/workflows/*.workflow.js; do
    base="$(basename "$wf")"
    case "$base" in
      story-executor.workflow.js|phase-7.workflow.js) ;;
      *) echo "workflow $base has no drift-check pairing in this fixture"; false ;;
    esac
  done
}

#!/usr/bin/env bats
# workflow_smoke.bats — functional smoke tests for workflows/*.workflow.js.
#
# WHY THIS EXISTS: both workflows shipped unrunnable. `args` arrives as a JSON
# STRING, `const cfg = args || {}` yielded a string whose .planPath was undefined,
# and the required-args guard threw on every launch. 269 green bats and a clean
# `node --check` said nothing, because nothing EXECUTED the scripts — bats covers
# bash, and --check only proves the file parses.
#
# lib/workflow-harness.mjs runs each script with agent/parallel/pipeline/phase/log
# stubbed, so these assert real behaviour: the args contract, the required-args
# guard, loop bounds, which agents are spawned, and what the prompts instruct.
# Every test here maps to a bug that reached a live run.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  H="$BATS_TEST_DIRNAME/lib/workflow-harness.mjs"
  # The phase-1 (adversarial review) workflow moved planner-side as
  # team-sprint-planner/workflows/plan-review.workflow.js; its smoke tests live
  # in that skill's tests/ now.
  # WA1: the old phase-4/5 workflow is git-mv'd to story-executor.workflow.js and
  # grows the Phase-3 stages (RED/RED-verify/GREEN/GREEN-verify/wip-commit)
  # ahead of Verify/Review/Fix, plus a bounded coverage loop.
  SE="$SKILL/workflows/story-executor.workflow.js"
  # story-executor: the SEVEN required args. testWriterAgent/engineerAgent use
  # distinctive values so agentType assertions cannot pass on a hardcoded default.
  SE_ARGS='{"storyId":"RH1","artDir":"/a","scriptsDir":"/s","planPath":"/p/plan.md","testWriterAgent":"my-tester","engineerAgent":"my-eng","coverageMode":"new"}'
  # All-green stubs for every stage label prefix; per-test overrides via _se_resp.
  SE_RESP='{"red-":{"test_files":["t.bats"],"evidence":"e"},"redverify-":{"failing_right_reason":true,"non_test_files":[],"evidence":"e"},"green-":{"source_files":["src.sh"],"evidence":"e"},"greenverify-":{"all_exist":true,"missing":[]},"wipcommit-":{"committed":true},"verify:":{"tests_pass":true,"typecheck_pass":true,"lint_pass":true,"evidence":"ok"},"diff:":{"patch_written":true},"review:":{"artifact_path":"/a/r.md","per_ac_checklist_present":true,"findings":[]},"artifactcheck-":{"exists":true},"fix:":{"finding_id":"F1","resolved":true,"source_files":["s.sh"]},"coverage:":{"pass":true,"gate_status":"measured"}}'
  # WA2: phase-7 workflow — regression gate, review fleet, bounded fix loop.
  P7="$SKILL/workflows/phase-7.workflow.js"
  # The TEN required args; the four command strings use distinctive literals so
  # verbatim-in-prompt assertions cannot pass on a hardcoded or re-derived
  # command. No lane-agent args and no reviewFixIterations: defaults exercised.
  P7_ARGS='{"artDir":"/a","scriptsDir":"/s","planPath":"/p/plan.md","targetBranch":"main","worktree":"/w","testCommand":"pytest -x --tb=short","typecheckCommand":"mypy --strict srcpkg","lintCommand":"ruff check srcpkg","coverageCommand":"coverage run -m pytest","coverageThreshold":85}'
  # All-green stubs: gate passes, every fleet lane delivers zero findings WITH
  # an artifact_path ("delivered, zero findings" != "never delivered").
  P7_RESP='{"regression-gate":{"tests_pass":true,"typecheck_pass":true,"lint_pass":true,"coverage_pass":true,"evidence":"all green"},"diff:":{"patch_written":true},"fleet:security":{"artifact_path":"/a/reviews-sprint-round-1-security.md","findings":[]},"fleet:performance":{"artifact_path":"/a/reviews-sprint-round-1-performance.md","findings":[]},"fleet:consistency":{"artifact_path":"/a/reviews-sprint-round-1-consistency.md","findings":[]},"fleet:simplifier":{"artifact_path":"/a/reviews-sprint-round-1-simplifier.md","findings":[]},"fix:":{"finding_id":"SEC-1","resolved":true,"source_files":["s.sh"]}}'
  # A reusable HIGH finding for the gating/fix-loop cases.
  P7_HIGH='{"id":"SEC-1","severity":"HIGH","issue":"cmd injection","evidence":"e","recommendation":"quote it"}'
  # Stuck-HIGH override: fleet reports the HIGH, every fix attempt fails.
  P7_STUCK="{\"fleet:security\":{\"artifact_path\":\"/a/reviews-sprint-round-1-security.md\",\"findings\":[$P7_HIGH]},\"fix:\":{\"finding_id\":\"SEC-1\",\"resolved\":false,\"source_files\":[]}}"
  # Stuck-CRITICAL override: review reports the CRITICAL, every fix attempt fails.
  SE_STUCK='{"review:":{"artifact_path":"/a/r.md","per_ac_checklist_present":true,"findings":[{"id":"F1","severity":"CRITICAL","ac_id":"AC1","issue":"i","evidence":"e","recommendation":"r"}]},"fix:":{"finding_id":"F1","resolved":false,"source_files":[]}}'
}

run_wf() { node "$H" "$@"; }

# Merge a JSON override object into the base args / response map.
_se_args() { jq -c ". + $1" <<<"$SE_ARGS"; }
_se_resp() { jq -c ". + $1" <<<"$SE_RESP"; }
_p7_args() { jq -c ". + $1" <<<"$P7_ARGS"; }
_p7_resp() { jq -c ". + $1" <<<"$P7_RESP"; }
# PREPEND override keys instead: the harness pick() matches label prefixes in
# key insertion order, so a MORE specific key (fleet:security:r1:a1) must sit
# BEFORE the general one (fleet:security) — `. + $1` would append it after,
# and the general key would steal the match. New keys only; on a key collision
# the base value wins here.
_p7_resp_pre() { jq -c "$1 + ." <<<"$P7_RESP"; }
# Index of an exact label in .calls (null when absent).
_idx() { jq --arg l "$1" '[.calls[].label]|index($l)' <<<"$2"; }
# A wipcommit-* call sits STRICTLY between call indices $1 and $2 in output $3.
_wip_between() {
  jq -e --argjson a "$1" --argjson b "$2" \
    '[.calls[].label]|to_entries|map(select(.value|startswith("wipcommit-"))|.key)|any(. > $a and . < $b)' <<<"$3" >/dev/null
}

# --- args contract (the bug that made both workflows unlaunchable) ----------

@test "REGRESSION story-executor: runs with both object and stringified args" {
  a="$(_se_args '{"maxVerify":1,"reviewFixIterations":1}')"
  out="$(run_wf "$SE" "$a" "$SE_RESP")"; [ "$(jq -r '.ok' <<<"$out")" = "true" ]
  str="$(jq -Rn --arg s "$a" '$s')"
  out="$(run_wf "$SE" "$str" "$SE_RESP")"; [ "$(jq -r '.ok' <<<"$out")" = "true" ]
}

# --- required-args guards ---------------------------------------------------

@test "story-executor: missing storyId fails loudly" {
  a="$(jq -c 'del(.storyId)' <<<"$SE_ARGS")"
  out="$(run_wf "$SE" "$a" '{}')"
  [ "$(jq -r '.ok' <<<"$out")" = "false" ]
  [[ "$(jq -r '.error' <<<"$out")" == *"requires args"* ]]
  [[ "$(jq -r '.error' <<<"$out")" == *"storyId"* ]]
}

@test "malformed JSON string args throws with context, not a silent empty object" {
  out="$(run_wf "$SE" '"{not valid json"' '{}')"
  [ "$(jq -r '.ok' <<<"$out")" = "false" ]
  [[ "$(jq -r '.error' <<<"$out")" == *"not valid JSON"* ]]
}

# --- script interface contracts (bugs that hit the live run) ---------------

@test "REGRESSION story-executor: --threshold is numeric, never a literal placeholder" {
  a="$(_se_args '{"maxVerify":1,"reviewFixIterations":1,"coverageThreshold":0}')"
  r="$(_se_resp '{"coverage:":{"pass":null,"gate_status":"disabled"}}')"
  out="$(run_wf "$SE" "$a" "$r")"
  p="$(jq -r '.calls[]|select(.label|startswith("coverage:"))|.prompt' <<<"$out")"
  [[ "$p" == *"--threshold 0"* ]]
  [[ "$p" != *"<configured>"* ]]
}

# --- bounded loops: the reason story-executor exists ------------------------

@test "BOUND story-executor: verify never green -> blocked_verify at the cap, no spin" {
  a="$(_se_args '{"maxVerify":3}')"
  r="$(_se_resp '{"verify:":{"tests_pass":false,"typecheck_pass":true,"lint_pass":true,"evidence":"red"}}')"
  out="$(run_wf "$SE" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_verify" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("verify:RH1:"))]|length' <<<"$out")" = "3" ]
}

@test "BOUND story-executor: checklist-less reviewer is capped, does not respawn forever" {
  a="$(_se_args '{"maxVerify":1,"maxReviewRespawn":2,"reviewFixIterations":1}')"
  r="$(_se_resp '{"review:":{"artifact_path":"/a/r.md","per_ac_checklist_present":false,"findings":[]}}')"
  out="$(run_wf "$SE" "$a" "$r")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("review:RH1:"))]|length' <<<"$out")" = "2" ]
}

@test "BOUND story-executor: gating findings that never resolve stop at reviewFixIterations" {
  a="$(_se_args '{"maxVerify":1,"reviewFixIterations":2,"maxInnerFix":1}')"
  r="$(_se_resp "$SE_STUCK")"
  out="$(run_wf "$SE" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds|length' <<<"$out")" = "2" ]
}

# --- schema contract --------------------------------------------------------

@test "every findings-bearing agent call carries a schema (prose is a non-delivery)" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  [ "$(jq -r '[.calls[]|select(.label|startswith("review:"))|select(.hasSchema|not)]|length' <<<"$out")" = "0" ]
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))|select(.hasSchema|not)]|length' <<<"$out")" = "0" ]
}

# --- WA1: story-executor grows the Phase-3 stages ---------------------------
# The old phase-4/5 workflow becomes story-executor.workflow.js with RED / RED-verify
# / GREEN / GREEN-verify / wip-commit stages ahead of Verify/Review/Fix, plus a
# bounded coverage loop. Everything below is the RED contract for that move.

@test "story-executor: file exists (git mv), parses, and phase-4-5 is gone" {
  node --check "$SKILL/workflows/story-executor.workflow.js"
  # Built from a var so WA1's zero-references grep never matches this test file.
  old_wf="phase-4-5"
  [ ! -e "$SKILL/workflows/${old_wf}.workflow.js" ]
}

@test "story-executor: the no-args guard names ALL seven required args" {
  out="$(run_wf "$SE" '' '{}')"
  [ "$(jq -r '.ok' <<<"$out")" = "false" ]
  err="$(jq -r '.error' <<<"$out")"
  for req in storyId artDir scriptsDir planPath testWriterAgent engineerAgent coverageMode; do
    [[ "$err" == *"$req"* ]] || { echo "guard does not name required arg $req: $err"; false; }
  done
}

@test "story-executor: object and stringified args produce the same first call (red-1)" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  [ "$(jq -r '.calls[0].label' <<<"$out")" = "red-1" ]
  str="$(jq -Rn --arg s "$SE_ARGS" '$s')"
  out="$(run_wf "$SE" "$str" "$SE_RESP")"
  [ "$(jq -r '.calls[0].label' <<<"$out")" = "red-1" ]
}

@test "story-executor: happy path is ready_to_commit, RED->GREEN->wip->verify in order" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  # "ready_to_commit" REPLACES the old "clean" status.
  [ "$(jq -r '.result.status' <<<"$out")" = "ready_to_commit" ]
  i_red="$(_idx red-1 "$out")"
  i_redv="$(_idx redverify-1 "$out")"
  i_green="$(_idx green-1 "$out")"
  i_greenv="$(_idx greenverify-1 "$out")"
  i_wip="$(_idx wipcommit-1 "$out")"
  i_verify="$(jq '[.calls[].label|startswith("verify:")]|index(true)' <<<"$out")"
  for i in "$i_red" "$i_redv" "$i_green" "$i_greenv" "$i_wip" "$i_verify"; do
    [ "$i" != "null" ] || { echo "missing stage call: red=$i_red redverify=$i_redv green=$i_green greenverify=$i_greenv wip=$i_wip verify=$i_verify"; false; }
  done
  [ "$i_red" -lt "$i_redv" ]
  [ "$i_redv" -lt "$i_green" ]
  [ "$i_green" -lt "$i_greenv" ]
  [ "$i_greenv" -lt "$i_wip" ]
  [ "$i_wip" -lt "$i_verify" ]
}

@test "BOUND story-executor: phantom GREEN files -> blocked_green, and NO wip commit ever" {
  # greenverify reports a declared file that does not exist on disk, both attempts.
  r="$(_se_resp '{"greenverify-":{"all_exist":false,"missing":["src.sh"]}}')"
  out="$(run_wf "$SE" "$SE_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_green" ]
  [ "$(jq -r '[.calls[].label|select(startswith("green-"))]|length' <<<"$out")" = "2" ]
  # A phantom declared file must never reach the wip commit.
  [ "$(jq -r '[.calls[].label|select(startswith("wipcommit-"))]|length' <<<"$out")" = "0" ]
}

@test "BOUND story-executor: tests failing for the WRONG reason -> blocked_red at maxRedAttempts" {
  r="$(_se_resp '{"redverify-":{"failing_right_reason":false,"non_test_files":[],"evidence":"e"}}')"
  out="$(run_wf "$SE" "$SE_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_red" ]
  [ "$(jq -r '[.calls[].label|select(startswith("red-"))]|length' <<<"$out")" = "2" ]
}

@test "BOUND story-executor: RED touching non-test files -> blocked_red identically" {
  # Both redverify trigger conditions behave the same; this one fails RIGHT
  # reason but declares a source file written during the RED phase.
  r="$(_se_resp '{"redverify-":{"failing_right_reason":true,"non_test_files":["src.sh"],"evidence":"e"}}')"
  out="$(run_wf "$SE" "$SE_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_red" ]
  [ "$(jq -r '[.calls[].label|select(startswith("red-"))]|length' <<<"$out")" = "2" ]
}

@test "story-executor: redverify prompt demands failure for the right reason" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  p="$(jq -r '.calls[]|select(.label=="redverify-1")|.prompt' <<<"$out")"
  [[ "$p" == *"right reason"* ]]
}

@test "BOUND story-executor: a review whose artifact is missing on disk is re-spawned, bounded" {
  # artifactcheck exists:false = the review is a lost return; re-spawn within
  # the same maxReviewRespawn bound, never forever.
  a="$(_se_args '{"maxVerify":1,"maxReviewRespawn":2,"reviewFixIterations":1}')"
  r="$(_se_resp '{"artifactcheck-":{"exists":false}}')"
  out="$(run_wf "$SE" "$a" "$r")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("review:RH1:"))]|length' <<<"$out")" = "2" ]
}

@test "story-executor: red/green stages spawn the INJECTED agent types" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  [ "$(jq -r '.calls[]|select(.label=="red-1")|.agentType' <<<"$out")" = "my-tester" ]
  [ "$(jq -r '.calls[]|select(.label=="green-1")|.agentType' <<<"$out")" = "my-eng" ]
}

@test "story-executor: wipcommit prompt is a wip( commit and precedes the coverage gate" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  p="$(jq -r '.calls[]|select(.label=="wipcommit-1")|.prompt' <<<"$out")"
  [[ "$p" == *"wip("* ]]
  i_wip="$(_idx wipcommit-1 "$out")"
  i_cov="$(_idx 'coverage:RH1:1' "$out")"
  [ "$i_wip" != "null" ]
  [ "$i_cov" != "null" ]
  [ "$i_wip" -lt "$i_cov" ]
}

@test "BOUND story-executor: coverage never passes -> coverage_cap_reached, wip between iters" {
  r="$(_se_resp '{"coverage:":{"pass":false,"gate_status":"measured","uncovered_files":["u.sh"]},"covfix-test-":{"test_files":["t2.bats"],"evidence":"e"},"covfix-eng-":{"source_files":["s2.sh"],"evidence":"e"}}')"
  out="$(run_wf "$SE" "$SE_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "coverage_cap_reached" ]
  [ "$(jq -r '[.calls[].label|select(startswith("coverage:"))]|length' <<<"$out")" = "3" ]
  # covfix agents inherit the injected agent types too.
  [ "$(jq -r '.calls[]|select(.label=="covfix-test-1")|.agentType' <<<"$out")" = "my-tester" ]
  [ "$(jq -r '.calls[]|select(.label=="covfix-eng-1")|.agentType' <<<"$out")" = "my-eng" ]
  # residuals carry the stubbed uncovered files up to the caller.
  [[ "$(jq -c '.result.residuals' <<<"$out")" == *"u.sh"* ]]
  # a wip commit sits STRICTLY between each pair of consecutive coverage calls.
  c1="$(_idx 'coverage:RH1:1' "$out")"
  c2="$(_idx 'coverage:RH1:2' "$out")"
  c3="$(_idx 'coverage:RH1:3' "$out")"
  for c in "$c1" "$c2" "$c3"; do
    [ "$c" != "null" ] || { echo "coverage iters not attempt-indexed: $c1 $c2 $c3"; false; }
  done
  _wip_between "$c1" "$c2" "$out"
  _wip_between "$c2" "$c3" "$out"
}

@test "story-executor: coverageMode is threaded into the gate; happy path counts one iteration" {
  a="$(jq -c '.coverageMode="whole"' <<<"$SE_ARGS")"
  out="$(run_wf "$SE" "$a" "$SE_RESP")"
  p="$(jq -r '.calls[]|select(.label=="coverage:RH1:1")|.prompt' <<<"$out")"
  [[ "$p" == *"--mode 'whole'"* ]]
  [ "$(jq -r '.result.coverage_iterations' <<<"$out")" = "1" ]
}

@test "story-executor: no call label is a strict prefix of another" {
  # The harness pick() — and any response router — matches stubs by label
  # PREFIX; a label that prefixes another silently steals its stub.
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  # bash-3.2 floor: mapfile is a bash-4 builtin, accumulate with read instead.
  labels=(); while IFS= read -r l; do labels+=("$l"); done < <(jq -r '.calls[].label' <<<"$out")
  [ "${#labels[@]}" -gt 0 ]
  for a in "${labels[@]}"; do
    for b in "${labels[@]}"; do
      if [ "$a" != "$b" ] && [[ "$b" == "$a"* ]]; then
        echo "label '$a' is a strict prefix of '$b'"
        false
      fi
    done
  done
}

# --- S1: plan-derived storyId / config coverageMode reach shell command text -
# parse_stories.sh's STORY_RE ([^:\s]+) admits $(...), backticks, semicolons and
# pipes, and story-executor interpolates STORY unquoted into command text agents
# run verbatim (git commit -m, coverage_check.sh --story-id). A malicious plan
# heading `## Story $(id):Title` is arbitrary command execution in the worktree.

@test "S1 story-executor: storyId with shell metacharacters is rejected before any agent call" {
  for bad in '$(id)' 'RH1;id' 'RH1`id`' 'RH1|id' 'RH1 id' "RH1'id"; do
    a="$(jq -c --arg s "$bad" '.storyId=$s' <<<"$SE_ARGS")"
    out="$(run_wf "$SE" "$a" "$SE_RESP")"
    [ "$(jq -r '.ok' <<<"$out")" = "false" ] || { echo "storyId '$bad' was accepted"; false; }
    [[ "$(jq -r '.error' <<<"$out")" == *"storyId"* ]]
    [ "$(jq -r '.calls|length' <<<"$out")" = "0" ] || { echo "agent call made with storyId '$bad'"; false; }
  done
}

@test "S1 story-executor: coverageMode outside new|whole is rejected before any agent call" {
  for bad in 'new;id' 'whole$(id)' 'partial'; do
    a="$(jq -c --arg m "$bad" '.coverageMode=$m' <<<"$SE_ARGS")"
    out="$(run_wf "$SE" "$a" "$SE_RESP")"
    [ "$(jq -r '.ok' <<<"$out")" = "false" ] || { echo "coverageMode '$bad' was accepted"; false; }
    [[ "$(jq -r '.error' <<<"$out")" == *"coverageMode"* ]]
    [ "$(jq -r '.calls|length' <<<"$out")" = "0" ] || { echo "agent call made with coverageMode '$bad'"; false; }
  done
}

@test "S1 story-executor: emitted command text single-quotes story-id, mode and the wip message" {
  # Defence in depth on top of the shape guard: the values sit inside single
  # quotes wherever they appear in a command an agent is told to run.
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  p="$(jq -r '.calls[]|select(.label=="coverage:RH1:1")|.prompt' <<<"$out")"
  [[ "$p" == *"--mode 'new'"* ]]
  [[ "$p" == *"--story-id 'RH1'"* ]]
  w="$(jq -r '.calls[]|select(.label=="wipcommit-1")|.prompt' <<<"$out")"
  [[ "$w" == *"git commit -m 'wip(RH1): phase-3 green'"* ]]
}

# --- CONS-1: the reviewer's per-story diff must have an in-workflow producer -
# phase-4.md step 1 makes $ART/diff-<story-id>.patch the reviewer's input ("the
# reviewer never re-flags work approved in earlier stories"), but the workflow
# path had no producer for it: the lead guard says "Before: nothing", and the
# workflow never ran per_story_diff.sh — so the reviewer was pointed at a file
# nobody wrote. phase-7.workflow.js sets the house convention by regenerating
# its own diff in-workflow, each round.

@test "CONS-1 story-executor: per-story diff is produced before the reviewer and passed into its prompt" {
  out="$(run_wf "$SE" "$SE_ARGS" "$SE_RESP")"
  i_diff="$(_idx 'diff:RH1:r1' "$out")"
  [ "$i_diff" != "null" ] || { echo "no diff:RH1:r1 call — the per-story diff has no producer"; false; }
  i_review="$(jq '[.calls[].label|startswith("review:RH1:")]|index(true)' <<<"$out")"
  [ "$i_review" != "null" ]
  [ "$i_diff" -lt "$i_review" ]
  p="$(jq -r '.calls[]|select(.label=="diff:RH1:r1")|.prompt' <<<"$out")"
  [[ "$p" == *"per_story_diff.sh"* ]]
  [[ "$p" == *"/a/diff-RH1.patch"* ]]
  # per_story_diff.sh resolves state.json via TS_PLAN_PATH; without it the
  # script exits 1 and the patch is empty.
  [[ "$p" == *'TS_PLAN_PATH="/p/plan.md"'* ]]
  # S1: the story id sits single-quoted in the emitted command text.
  [[ "$p" == *"per_story_diff.sh 'RH1'"* ]]
  rp="$(jq -r '.calls[]|select(.label|startswith("review:RH1:r1"))|.prompt' <<<"$out")"
  [[ "$rp" == *"/a/diff-RH1.patch"* ]]
}

@test "CONS-1 story-executor: each round regenerates the diff, with fixes wip-committed first" {
  # Round 2's reviewer must not re-review a stale pre-fix patch: the diff is
  # regenerated per round, and the fix work is landed in HEAD first because
  # per_story_diff.sh reads committed BASE...HEAD only.
  a="$(_se_args '{"maxVerify":1,"reviewFixIterations":2,"maxInnerFix":1}')"
  r="$(_se_resp "$SE_STUCK")"
  out="$(run_wf "$SE" "$a" "$r")"
  [ "$(jq -r '[.calls[].label|select(startswith("diff:RH1:r"))]|length' <<<"$out")" = "2" ]
  i_fix="$(_idx 'fix:RH1:F1:1' "$out")"
  i_d2="$(_idx 'diff:RH1:r2' "$out")"
  [ "$i_fix" != "null" ]
  [ "$i_d2" != "null" ]
  # a wip commit sits STRICTLY between the round-1 fix batch and the round-2 diff.
  _wip_between "$i_fix" "$i_d2" "$out"
}

# --- WA2: phase-7 workflow --------------------------------------------------
# New phase-7.workflow.js covers phase-7.md steps 1/1b/2/3: full-suite
# regression gate FIRST, diff regeneration, four-lane review fleet, bounded
# fix loop. Merge/push/cleanup (steps 4-10) stay lead-side. Everything below
# is the RED contract for that workflow.

# rounds must be an integer >= 0 on EVERY status: the lead's
# `state.sh update ... iterations.review_fix=<rounds>` write aborts on an
# empty value (state.sh:252 --argjson bind) or a non-integer (state.sh:89).
_p7_rounds_ok() {
  jq -e '.result.rounds|(type=="number") and (. == floor) and (. >= 0)' <<<"$1" >/dev/null \
    || { echo "rounds is not an integer >= 0: $(jq -c '.result' <<<"$1")"; false; }
}

# AC: `node --check` exits 0.
@test "phase-7: workflow file exists and parses" {
  node --check "$SKILL/workflows/phase-7.workflow.js"
}

# AC: guard names the TEN required args; the four lane-agent args are NOT
# required (optional, static default general-purpose).
@test "phase-7: the no-args guard names ALL ten required args; lane agents stay optional" {
  out="$(run_wf "$P7" '' '{}')"
  [ "$(jq -r '.ok' <<<"$out")" = "false" ]
  err="$(jq -r '.error' <<<"$out")"
  [[ "$err" == *"requires args"* ]]
  for req in artDir scriptsDir planPath targetBranch worktree testCommand typecheckCommand lintCommand coverageCommand coverageThreshold; do
    [[ "$err" == *"$req"* ]] || { echo "guard does not name required arg $req: $err"; false; }
  done
  for opt in securityAgent performanceAgent consistencyAgent simplifierAgent; do
    [[ "$err" != *"$opt"* ]] || { echo "optional lane arg $opt appears in the required list: $err"; false; }
  done
}

# AC: stringified args behave as objects.
@test "phase-7: runs with both object and stringified args" {
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
  str="$(jq -Rn --arg s "$P7_ARGS" '$s')"
  out="$(run_wf "$P7" "$str" "$P7_RESP")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
}

# AC: the command-string guard is a null/undefined check, NEVER truthiness —
# coverageCommand "" is a legitimate detect_commands.sh value (:292).
@test "phase-7: coverageCommand empty-string passes the args guard" {
  a="$(_p7_args '{"coverageCommand":""}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
}

# AC: coverageThreshold 0 is the documented disable value and falsy in JS —
# it must reach the regression gate, not fail a truthiness guard.
@test "phase-7: coverageThreshold 0 reaches the regression gate" {
  a="$(_p7_args '{"coverageThreshold":0}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.ok' <<<"$out")" = "true" ]
  [ "$(jq -r '[.calls[]|select(.label=="regression-gate")]|length' <<<"$out")" = "1" ]
}

# AC: a non-numeric threshold fails at the boundary (coverage_check.sh would
# exit 2 mid-run), BEFORE any agent call.
@test "phase-7: non-numeric coverageThreshold fails the guard before any agent call" {
  a="$(_p7_args '{"coverageThreshold":"eighty"}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.ok' <<<"$out")" = "false" ]
  [[ "$(jq -r '.error' <<<"$out")" == *"coverageThreshold"* ]]
  [ "$(jq -r '.calls|length' <<<"$out")" = "0" ]
}

# AC: crew: off — no lane args passed, the fleet still launches and every
# lane falls to the documented static default.
@test "phase-7: omitted lane args default every fleet agentType to general-purpose" {
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "4" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))|.agentType]|unique|join(",")' <<<"$out")" = "general-purpose" ]
}

# AC: each fleet call carries agentType equal to ITS lane's arg when passed.
@test "phase-7: passed lane args land on their own fleet calls' agentType" {
  a="$(_p7_args '{"securityAgent":"my-sec-lane","performanceAgent":"my-perf-lane","consistencyAgent":"my-cons-lane","simplifierAgent":"my-simp-lane"}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.calls[]|select(.label|startswith("fleet:security:"))|.agentType' <<<"$out")" = "my-sec-lane" ]
  [ "$(jq -r '.calls[]|select(.label|startswith("fleet:performance:"))|.agentType' <<<"$out")" = "my-perf-lane" ]
  [ "$(jq -r '.calls[]|select(.label|startswith("fleet:consistency:"))|.agentType' <<<"$out")" = "my-cons-lane" ]
  [ "$(jq -r '.calls[]|select(.label|startswith("fleet:simplifier:"))|.agentType' <<<"$out")" = "my-simp-lane" ]
}

# AC: the config example gains the four lane-agent keys (auto, mirroring
# test_writer_agent) plus the profiler-mapping / crew-off consequence notes.
@test "phase-7: config example gains the four lane-agent keys defaulting to auto" {
  cfg="$SKILL/team-sprint.config.yaml.example"
  grep -qF 'security_agent: auto' "$cfg"
  grep -qF 'performance_agent: auto' "$cfg"
  grep -qF 'simplifier_agent: auto' "$cfg"
  grep -qF 'consistency_agent: auto' "$cfg"
  grep -qF 'profiler' "$cfg"
  grep -qF 'general-purpose' "$cfg"
}

# AC: the gate prompt carries the four command literals VERBATIM (the agent
# never re-derives commands), and the coverage sequence is run-then-score.
@test "phase-7: regression prompt carries the command literals; run precedes the score" {
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  p="$(jq -r '.calls[]|select(.label=="regression-gate")|.prompt' <<<"$out")"
  [[ "$p" == *"pytest -x --tb=short"* ]]
  [[ "$p" == *"mypy --strict srcpkg"* ]]
  [[ "$p" == *"ruff check srcpkg"* ]]
  [[ "$p" == *"coverage run -m pytest"* ]]
  [[ "$p" == *"coverage_check.sh --mode whole"* ]]
  [[ "$p" == *"--threshold 85"* ]]
  # non-empty coverageCommand -> the scoring call carries the env prefix.
  [[ "$p" == *"TS_COMMANDS_COVERAGE="* ]]
  # run-then-score: the coverageCommand literal appears BEFORE coverage_check.sh.
  [[ "${p%%coverage_check.sh*}" == *"coverage run -m pytest"* ]]
}

# AC: empty coverageCommand -> the WHOLE coverage sequence is skipped (still
# one gate call, no coverage instruction at all, no set-but-empty env prefix
# that would clobber config through coverage_check.sh:133), the note is
# byte-exact, and the run still reaches the fleet.
@test "phase-7: empty coverageCommand skips the whole coverage leg, never blocks" {
  a="$(_p7_args '{"coverageCommand":""}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '[.calls[]|select(.label=="regression-gate")]|length' <<<"$out")" = "1" ]
  P="$(jq -r '.calls[]|select(.label=="regression-gate")|.prompt' <<<"$out")"
  [[ "$P" != *"TS_COMMANDS_COVERAGE="* ]]
  p="$(tr '[:upper:]' '[:lower:]' <<<"$P")"
  [[ "$p" != *"coverage_check.sh"* ]]
  [[ "$p" != *"coverage"* ]]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "4" ]
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '.result.regression.coverage' <<<"$out")" = "unavailable — no coverage command resolved" ]
}

# AC: the skip-leg contract applies symmetrically to lint — empty lintCommand
# is skipped with the exact note, never blocked_regression.
@test "phase-7: empty lintCommand skips the lint leg with the exact note, fleet still runs" {
  a="$(_p7_args '{"lintCommand":""}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "4" ]
  p="$(tr '[:upper:]' '[:lower:]' <<<"$(jq -r '.calls[]|select(.label=="regression-gate")|.prompt' <<<"$out")")"
  [[ "$p" != *"ruff check srcpkg"* ]]
  [[ "$p" != *"lint"* ]]
  [ "$(jq -r '.result.regression.lint' <<<"$out")" = "unavailable — no lint command resolved" ]
}

# AC: mirror case — empty typecheckCommand.
@test "phase-7: empty typecheckCommand skips the typecheck leg with the exact note" {
  a="$(_p7_args '{"typecheckCommand":""}')"
  out="$(run_wf "$P7" "$a" "$P7_RESP")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "4" ]
  p="$(tr '[:upper:]' '[:lower:]' <<<"$(jq -r '.calls[]|select(.label=="regression-gate")|.prompt' <<<"$out")")"
  [[ "$p" != *"mypy --strict srcpkg"* ]]
  [[ "$p" != *"typecheck"* ]]
  [ "$(jq -r '.result.regression.typecheck' <<<"$out")" = "unavailable — no typecheck command resolved" ]
}

# AC: happy path — clean, exactly one regression-gate call, then one
# diff-generation call, then the four fleet calls naming the four lanes.
@test "phase-7: happy path is clean — one gate, one diff, then the four lanes" {
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '.calls|length' <<<"$out")" = "6" ]
  [ "$(jq -r '.calls[0].label' <<<"$out")" = "regression-gate" ]
  [ "$(jq -r '.calls[1].label' <<<"$out")" = "diff:r1" ]
  for lane in security performance consistency simplifier; do
    i="$(_idx "fleet:$lane:r1:a1" "$out")"
    [ "$i" != "null" ] || { echo "missing fleet lane call fleet:$lane:r1:a1"; false; }
    [ "$i" -ge 2 ]
  done
  # the diff step regenerates the sprint patch from the worktree; the patch
  # has no other producer inside the workflow.
  dp="$(jq -r '.calls[1].prompt' <<<"$out")"
  [[ "$dp" == *"main...HEAD"* ]]
  [[ "$dp" == *"/a/diff-sprint.patch"* ]]
}

# AC: a fix round regenerates the diff between consecutive fleet rounds —
# after the fix calls, before the re-run's fleet calls (never a stale patch).
@test "phase-7: a fix round regenerates the diff BEFORE the re-run fleet reviews it" {
  r="$(_p7_resp_pre "{\"fleet:security:r1\":{\"artifact_path\":\"/a/reviews-sprint-round-1-security.md\",\"findings\":[$P7_HIGH]}}")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "1" ]
  i_fix="$(_idx "fix:security:SEC-1:r1" "$out")"
  i_diff2="$(_idx "diff:r2" "$out")"
  i_fleet2="$(_idx "fleet:security:r2:a1" "$out")"
  for i in "$i_fix" "$i_diff2" "$i_fleet2"; do
    [ "$i" != "null" ] || { echo "missing call: fix=$i_fix diff2=$i_diff2 fleet2=$i_fleet2"; false; }
  done
  [ "$i_fix" -lt "$i_diff2" ]
  [ "$i_diff2" -lt "$i_fleet2" ]
}

# AC: a null lane (agent died) -> exactly one re-spawn; still null ->
# blocked_fleet naming the missing lane, never a silent green.
@test "phase-7: a null lane is re-spawned exactly once; twice-null is blocked_fleet" {
  # attempt 1 dies, attempt 2 delivers -> the run completes clean.
  r="$(_p7_resp_pre '{"fleet:security:r1:a1":null}')"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:security:r1:"))]|length' <<<"$out")" = "2" ]
  # both attempts null -> blocked_fleet, the result names the lane, no third spawn.
  r="$(_p7_resp '{"fleet:security":null}')"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_fleet" ]
  [ "$(jq -r '.result.missing_lane' <<<"$out")" = "security" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:security:r1:"))]|length' <<<"$out")" = "2" ]
}

# AC: a MEDIUM simplifier finding (no HIGH anywhere) still enters the gating
# set; its fix is a behaviour-preserving refactor, not a TDD micro-cycle.
@test "phase-7: a MEDIUM simplifier finding is gating and behaviour-preserving" {
  f='{"id":"SIMP-1","severity":"MEDIUM","issue":"dup","evidence":"e","recommendation":"dedupe"}'
  r="$(_p7_resp_pre "{\"fleet:simplifier:r1\":{\"artifact_path\":\"/a/reviews-sprint-round-1-simplifier.md\",\"findings\":[$f]}}")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  i_fix="$(_idx "fix:simplifier:SIMP-1:r1" "$out")"
  [ "$i_fix" != "null" ] || { echo "no fix call spawned for the MEDIUM simplifier finding"; false; }
  p="$(jq -r '.calls[]|select(.label=="fix:simplifier:SIMP-1:r1")|.prompt' <<<"$out")"
  [[ "$p" == *"behaviour-preserving"* ]]
  [[ "$p" == *"refactor:"* ]]
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
}

# AC: reviewFixIterations 5 -> FIVE fix rounds before cap_reached; an ignored
# config value is a test failure, not a silent default to 3.
@test "BOUND phase-7: reviewFixIterations 5 is honoured — five fix rounds, then cap" {
  a="$(_p7_args '{"reviewFixIterations":5}')"
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "5" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fix:"))]|length' <<<"$out")" = "5" ]
  # fleet rounds = initial + re-runs = reviewFixIterations + 1.
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" = "6" ]
}

# AC: an unresolved HIGH stops at the default cap (3) with the finding as a
# residual — per-finding waivers are the lead's job AFTER return.
@test "BOUND phase-7: default cap carries the unresolved finding as a residual" {
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "3" ]
  [[ "$(jq -c '.result.residuals' <<<"$out")" == *"SEC-1"* ]]
  # total fleet rounds observable in calls is at most reviewFixIterations + 1.
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" -le 4 ]
}

# AC: a red regression gate short-circuits — no point reviewing a red tree.
@test "phase-7: a red regression gate short-circuits with zero fleet calls and rounds 0" {
  r="$(_p7_resp '{"regression-gate":{"tests_pass":false,"evidence":"3 failed"}}')"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_regression" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" = "0" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
}

# F1 (review WA2 round 1): reviewFixIterations 0 is a legitimate "report,
# don't auto-fix" setting — `cfg.reviewFixIterations || 3` silently rewrote it
# to 3, i.e. three unrequested rounds of agents committing to the sprint branch.
@test "phase-7 F1: reviewFixIterations 0 means zero fix rounds — cap on the first fleet round" {
  a="$(_p7_args '{"reviewFixIterations":0}')"
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fix:"))]|length' <<<"$out")" = "0" ]
  # exactly ONE fleet round: the initial diff+fleet, never a re-run.
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" = "1" ]
}

# F1: the string "0" must mean the same as the number 0 — the truthiness
# default made the cap TYPE-dependent (JSON 0 -> 3 rounds, "0" -> 0 rounds),
# so the same config value meant two different things depending on how the
# lead stringified the arg.
@test "phase-7 F1: reviewFixIterations \"0\" (string) behaves exactly like the number 0" {
  a="$(_p7_args '{"reviewFixIterations":"0"}')"
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fix:"))]|length' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" = "1" ]
}

# F1: a non-numeric reviewFixIterations must fall back to the default 3 —
# Number("garbage") is NaN, `fixRounds >= NaN` is always false, and the fix
# loop would spin UNBOUNDED with a persistent gating finding.
@test "phase-7 F1: non-numeric reviewFixIterations falls back to 3, never an unbounded loop" {
  a="$(_p7_args '{"reviewFixIterations":"garbage"}')"
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$a" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "3" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fix:"))]|length' <<<"$out")" = "3" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" -le 4 ]
}

# F2 (review WA2 round 1): a leg whose command is NON-EMPTY but whose boolean
# the gate agent silently omits must score RED — this is the sprint's ONLY
# whole-suite gate (phase-7.md:39), and an unreported leg is the gate-side
# twin of the fleet's "delivered != never delivered". The old `!== false`
# scoring turned three omitted booleans into three fabricated 'pass' values.
@test "phase-7 F2: gate booleans omitted for non-empty legs score fail and block" {
  r="$(_p7_resp '{"regression-gate":{"tests_pass":true,"evidence":"ok"}}')"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_regression" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fleet:"))]|length' <<<"$out")" = "0" ]
  [ "$(jq -r '.result.regression.typecheck' <<<"$out")" = "fail" ]
  [ "$(jq -r '.result.regression.lint' <<<"$out")" = "fail" ]
  [ "$(jq -r '.result.regression.coverage' <<<"$out")" = "fail" ]
}

# F4 (review WA2 round 1): the negative half of the gating predicate — a
# MEDIUM from a NON-simplifier lane is surfaced, non-blocking (phase-7.md:31)
# and must NOT enter the gating set. Without this case, dropping the severity
# filter entirely (`if (true)`) left the whole suite green.
@test "phase-7 F4: a MEDIUM security finding does not gate — clean on the first fleet round" {
  f='{"id":"SEC-M1","severity":"MEDIUM","issue":"minor","evidence":"e","recommendation":"note it"}'
  r="$(_p7_resp "{\"fleet:security\":{\"artifact_path\":\"/a/reviews-sprint-round-1-security.md\",\"findings\":[$f]}}")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
  [ "$(jq -r '[.calls[]|select(.label|startswith("fix:"))]|length' <<<"$out")" = "0" ]
  # first fleet round only — a non-gating finding must not trigger a re-run.
  [ "$(jq -r '[.calls[]|select(.label|startswith("diff:"))]|length' <<<"$out")" = "1" ]
}

# F4: the CRITICAL arm of the predicate — a CRITICAL from any lane gates.
# Without this case, dropping the `=== 'CRITICAL'` arm left the suite green.
@test "phase-7 F4: a CRITICAL performance finding gates — a fix call is spawned" {
  f='{"id":"PERF-C1","severity":"CRITICAL","issue":"quadratic scan","evidence":"e","recommendation":"index it"}'
  r="$(_p7_resp_pre "{\"fleet:performance:r1\":{\"artifact_path\":\"/a/reviews-sprint-round-1-performance.md\",\"findings\":[$f]}}")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  i_fix="$(_idx "fix:performance:PERF-C1:r1" "$out")"
  [ "$i_fix" != "null" ] || { echo "no fix call spawned for the CRITICAL performance finding"; false; }
  # round 2 reviews the fixed tree (base stub: zero findings) -> clean.
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  [ "$(jq -r '.result.rounds' <<<"$out")" = "1" ]
}

# AC: EVERY status carries rounds as an integer >= 0 (state.sh:252/:89 abort
# on empty or non-integer), with rounds == 0 on the blocked_regression path.
@test "phase-7: every status carries rounds as an integer >= 0" {
  # clean
  out="$(run_wf "$P7" "$P7_ARGS" "$P7_RESP")"
  [ "$(jq -r '.result.status' <<<"$out")" = "clean" ]
  _p7_rounds_ok "$out"
  # blocked_regression (a null gate return is RED too) — rounds is exactly 0.
  out="$(run_wf "$P7" "$P7_ARGS" "$(_p7_resp '{"regression-gate":null}')")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_regression" ]
  _p7_rounds_ok "$out"
  [ "$(jq -r '.result.rounds' <<<"$out")" = "0" ]
  # blocked_fleet
  out="$(run_wf "$P7" "$P7_ARGS" "$(_p7_resp '{"fleet:performance":null}')")"
  [ "$(jq -r '.result.status' <<<"$out")" = "blocked_fleet" ]
  _p7_rounds_ok "$out"
  # cap_reached
  r="$(_p7_resp "$P7_STUCK")"
  out="$(run_wf "$P7" "$P7_ARGS" "$r")"
  [ "$(jq -r '.result.status' <<<"$out")" = "cap_reached" ]
  _p7_rounds_ok "$out"
}

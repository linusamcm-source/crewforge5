# Phase 5 — Fix loop (per story)

**Goal.** Resolve CRITICAL + HIGH findings from Phase 4 via TDD micro-cycles, re-run the Phase-4 reviewer(s), and re-run the coverage gate after fixes. Iterate up to `review_fix_iterations` (default 3). Only the Phase-4 roster re-runs here — no security or performance review (that is Phase 7's fleet).

> **Workflow path.** If the `Workflow` tool is present in your tool list, use it. If it is not, use the prose below. This is
> a fact to check, not a preference to weigh — do not choose between the two paths on judgment. `$SKILL/references/workflows/story-executor.workflow.js`
> runs Phases 3–5 for one story as a single `Workflow` call: `Workflow({ scriptPath: "<skill>/references/workflows/story-executor.workflow.js",
> args: { storyId, artDir, scriptsDir, planPath, testWriterAgent, engineerAgent, coverageMode, worktree?, reviewerAgent?,
> reviewFixIterations?, maxRedAttempts?, maxGreenAttempts?, maxVerify?, maxReviewRespawn?, maxInnerFix?, maxCoverageIters? } })`.
> Every iteration bound is a loop header; exhausting one is a returned outcome (`blocked_verify`, `cap_reached`), never a silent spin.
> (This phase's once-uncapped back-edges — the red-test bounce, the checklist-less reviewer re-spawn, the inner RED→GREEN retry — are
> exactly those loop headers, and `per_ac_checklist_present` is a required schema field, so a missing checklist cannot go unnoticed.)
>
> **Run recording (sequential mode only).** After the call returns, the lead pins the run id — `bash $SCRIPTS/state.sh record-workflow
> "$plan_path" phase-5 <run_id>` → `workflow_runs.phase-5`. Under `scheduling: graph` the node executors are the callers, so the lead skips
> this write: the D7 clobber rule forbids lead-side `state.json` writes while executors run. Known pre-existing exception, unchanged here:
> the workflow itself persists `iterations.review_fix` from inside its review loop.
> **Lead before/after the call.** Before: nothing. After: the exit advance (sequential `advance-phase`; graph `schedule.sh phase … 6`) — the workflow runs none of them.
>
> The prose below is the fallback contract — entry/exit conditions, gates, bounds, outcome vocabulary, artifacts, and a minimal
> executable step list for a `Workflow`-less environment. The workflow owns sequencing; on ordering disagreements the workflow wins.

## Entry condition
Phase 4 complete for the current story. `state.json.current_phase == 5` AND `state.json.current_story_id` set. `$ART/reviews-<story-id>-round-<N>.md` exists.

## Graph mode delta
Under `scheduling: graph` this phase runs inside a **node executor** against the node's worktree (`$PHASES/phase-execute.md`). Entry condition maps to the claimed node record (`schedule.sh phase … <id> 5`), not `state.json`. Re-run reviewers are executor-spawned and return findings to the executor as their final agent return — no SendMessage to team-lead (see phase-4's Graph mode delta); step 1's artifact audit applies with the executor as the persisting spawner. **No `state.json` writes** (D7): step 7 and the exit advance are **sequential mode only** — graph mode advances with `bash "$SCRIPTS/schedule.sh" phase "$ART/graph.json" <id> 6`, per-node counters in the node's `graph.json` record (`$REF/state-schema.md`).

## Gate
- The Phase-4 reviewer(s) re-run clean (zero CRITICAL/HIGH), OR
- After `review_fix_iterations` rounds, unresolved CRITICAL/HIGH still stand → STOP; ask user to override or kill.

## Steps
For each iteration up to `review_fix_iterations`:
1. **Sprint-watchdog policy audit.** Every spawned Phase-4 reviewer (AC reviewer, plus ui-validator/accessibility when the diff was UI-facing) delivered — verified by artifact: `$ART/reviews-<story-id>-round-<N>.md` exists and carries the per-AC checklist, NOT by scanning the message log. Missing or checklist-less artifact → re-spawn the reviewer with explicit final-return delivery instructions (`$REF/sendmessage-protocol.md`); an unpersisted report breaks resume.
<!-- wf:p5-triage -->
2. **Triage findings.** CRITICAL + HIGH → fix tasks queued back to engineers. MEDIUM + LOW → surfaced to the user, non-blocking.
<!-- wf:p5-fix -->
3. **Engineers fix.** Each fix task is its own TDD micro-cycle: regression test that catches the issue (RED) → fix the code (GREEN) → run **only this story's tests** (its test files plus the new regression test — SKILL.md → **Per-story test scoping**; the full suite is Phase 7's gate). A fix that changes behaviour covered by existing tests updates those tests inline.
4. **Provisional commit (both modes).** `git add -A && git commit -m "wip(<story-id>): fix round <N>"`. WHY (D6): the coverage gate and the re-run reviewers' `per_story_diff.sh` diff read committed `BASE...HEAD` — uncommitted or untracked fixes are invisible to them. Phase 6 squashes all `wip(<story-id>)` commits into the single structured story commit.
<!-- wf:p5-coverage -->
5. **Re-run the coverage gate** after fixes (added code shifts the new-line denominator): `bash "$SCRIPTS/coverage_check.sh" --mode "$coverage_mode" --threshold "$coverage_threshold" --story-id "$current_story_id"`. `pass: false` → loop back into the Phase-3-style coverage iteration (capped at 3). `gate_status: "disabled"` is honoured here too.
6. **Re-run the Phase-4 reviewer(s)** over the new diff — the AC reviewer always; ui-validator only if the fixes touched UI files. All clean (zero CRITICAL/HIGH) → break loop.
<!-- wf:p5-persist-counter -->
7. **Increment.** `bash $SCRIPTS/state.sh update "$plan_path" iterations.review_fix=<N+1>`. After `review_fix_iterations` rounds with unresolved CRITICAL/HIGH the loop's outcome is the cap: STOP, surface the remaining findings, ask the user.

## Exit condition
Phase-4 reviewer(s) return clean for this story; `state.json.iterations.review_fix` recorded; coverage gate still green (or still disabled). Advance: `bash "$SCRIPTS/state.sh" advance-phase "$plan_path" 6`.

## Artifacts produced
- Successive `$ART/reviews-<story-id>-round-<N>.md` files (one per iteration); `state.json.iterations.review_fix` updated.

## Scripts referenced
- `$SCRIPTS/coverage_check.sh` (re-run after each fix iteration) · `$SCRIPTS/state.sh`

## References
- `$REF/sendmessage-protocol.md` — re-run reviewer delivery contract. `$REF/state-schema.md` — `iterations.review_fix` semantics.

## Extensions
<!-- subskill-hooks:phase-5 -->
RESERVED — `subskill_hooks.phase-5` is NOT active in v1.0 (Phase 5 is mid-iteration; sub-skills observe stable states only). A configured `phase-5` block logs `subskill_hooks.phase-5 unsupported in v1.0; block ignored` at Phase 0 and is NOT persisted into `state.json.subskill_hooks`. See `$REF/subskill-hooks.md` for rationale.

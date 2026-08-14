# Phase 3 — TDD execution + 80% coverage gate (per story)

**Goal.** Drive the current story RED → GREEN with verified failing-for-the-right-reason tests, then enforce the new-code coverage gate before reviewers see the diff. Runs once per story.

> **Workflow path.** If the `Workflow` tool is present in your tool list, use it. If it is not, use the prose below. This is
> a fact to check, not a preference to weigh — do not choose between the two paths on judgment. `$SKILL/references/workflows/story-executor.workflow.js`
> runs Phases 3–5 for one story as a single `Workflow` call: `Workflow({ scriptPath: "<skill>/references/workflows/story-executor.workflow.js",
> args: { storyId, artDir, scriptsDir, planPath, testWriterAgent, engineerAgent, coverageMode, worktree?, reviewerAgent?,
> reviewFixIterations?, maxRedAttempts?, maxGreenAttempts?, maxVerify?, maxReviewRespawn?, maxInnerFix?, maxCoverageIters? } })`.
> Every iteration bound is a loop header; exhausting one is a returned outcome (`blocked_verify`, `cap_reached`), never a silent spin.
>
> **Run recording (sequential mode only).** After the call returns, the lead pins the run id — `bash $SCRIPTS/state.sh record-workflow
> "$plan_path" phase-3 <run_id>` → `workflow_runs.phase-3`. Under `scheduling: graph` the node executors are the callers, so the lead skips
> this write: the D7 clobber rule forbids lead-side `state.json` writes while executors run. Known pre-existing exception, unchanged here:
> the workflow itself persists `iterations.review_fix` from inside its review loop.
> **Lead before/after the call.** Before: nothing. After: the sprint-watchdog mid-audit and sub-skill hooks (steps 6–7) and the state advance — the workflow runs none of them.
>
> The prose below is the fallback contract — entry/exit conditions, gates, bounds, outcome vocabulary, artifacts, and a minimal
> executable step list for a `Workflow`-less environment. The workflow owns sequencing; on ordering disagreements the workflow wins.

## Entry condition
Phase 2 complete. `state.json.current_phase == 3` AND `state.json.current_story_id` set. Worktree clean of unrelated changes.

## Graph mode delta
Under `scheduling: graph` this phase runs inside a **node executor** against the node's worktree, per the Node-executor contract in `$PHASES/phase-execute.md`. Entry condition maps to the claimed node record — `status: "in_progress"` with `phase: 3` in `graph.json` (set by `schedule.sh claim`) — not `state.json.current_phase`/`current_story_id`. **No `state.json` writes** (parallel executors clobber it, D7): every `state.sh update`/`advance-phase` below is **sequential mode only**; the graph-mode exit advance is `bash "$SCRIPTS/schedule.sh" phase "$ART/graph.json" <id> 4`, and per-node counters live in the node's `graph.json` record (`$REF/state-schema.md`).

## Gate
- This story's tests pass (scoped run — the RED test files plus tests the diff modified, not the whole suite; SKILL.md → **Per-story test scoping**; the full regression suite runs at Phase 7) and typecheck + lint are clean.
- Provisional commit landed: `wip(<story-id>): phase-3 green` (step 4) — the coverage gate and Phase 4 diff read `BASE...HEAD` and see nothing without it.
- Coverage gate: `bash $SCRIPTS/coverage_check.sh --mode <coverage_mode> --threshold $coverage_threshold --story-id <id>` returns `pass: true`, OR `gate_status: "disabled"` (`coverage_threshold:0` or `commands.coverage="true"`).
- Sprint-watchdog mid-audit clean.

## Steps
> **Communication (both modes).** The spawner (node executor under graph mode; the lead sequentially) owns block–collect–close for every child task — children deliver by **final agent return**, no `SendMessage` (`$REF/sendmessage-protocol.md`). Never end a turn with a live child.
<!-- wf:p3-red -->
<!-- wf:p3-red-verify -->
1. **RED.** test-writer — `subagent_type` by the Phase 2 agent-type precedence: explicit non-`auto` `test_writer_agent` from config > `state.json.crew.tester` (set by Phase 0 step 10a under `crew: auto`) > default `rn-test`. It writes failing tests for *this story's* acceptance criteria only. The spawner VERIFIES the tests fail for the *right* reason (missing implementation, not import errors); failing tests alone never close an implementation task — source files must exist first.
<!-- wf:p3-green -->
<!-- wf:p3-green-verify -->
2. **GREEN.** engineer(s) — same precedence: explicit non-`auto` `engineer_agent` > `state.json.crew.developer` > default `rn-engineer`. Minimum code to flip RED → GREEN, no speculative abstractions. The spawner confirms the claimed source files exist on disk before closing the implementation task.
3. **VERIFY.** Run **only this story's tests** (scoped as above, via the runner's path/pattern filter — never the bare whole-suite `commands.test`) plus the resolved `commands.typecheck` + `commands.lint`. All must pass.
<!-- wf:p3-wip-commit -->
4. **Provisional commit (both modes).** `git add -A && git commit -m "wip(<story-id>): phase-3 green"`. WHY (D6): `per_story_diff.sh` and `coverage_check.sh --mode new` read committed `git diff BASE...HEAD` — without this commit both see an empty diff, and working-tree diffs miss untracked files. Phase 6 squashes every `wip(<story-id>)` commit into the single structured story commit, preserving the one-commit-per-story invariant.
<!-- wf:p3-coverage-loop -->
5. **Coverage gate.** `bash "$SCRIPTS/coverage_check.sh" --mode "$coverage_mode" --threshold "$coverage_threshold" --story-id "$current_story_id"`. ONLY when `crew: auto` supplied a coverage command that config lacks, prefix `TS_COMMANDS_COVERAGE='<crew_commands.coverage>'` on the same line (env does not persist between Bash calls), and only when non-empty — the script reads `${TS_COMMANDS_COVERAGE-<config>}` (single-dash), so a set-but-empty value overrides the config command to empty and breaks the gate.
   - `gate_status: "disabled"` → append `{coverage_gate: "disabled", reason, story_id}` to `state.json.gates` via `state.sh update`; proceed.
   - `pass: true` → proceed to Phase 4. `pass: false` → dispatch uncovered files back to test-writer + engineer, land another step-4 wip commit so the re-run measures it, increment `state.json.iterations.coverage`, loop.
   - After 3 coverage iterations still below threshold the loop's outcome is the cap: STOP and surface the uncovered code; don't ship below threshold without explicit user override.
6. **Sprint-watchdog mid-audit.** Story-keyed review artifacts (`$ART/reviews-<story-id>-round-<N>.md`) delivered with per-AC checklists (empty/placeholder = undelivered), every "complete" impl task has its claimed source files, branch still `sprint_branch`. Failures route back as audit-fix tasks before Phase 4.
7. **Sub-skill hooks, fail-soft** — final step before advancing: `bash "$SCRIPTS/run_subskill_hooks.sh" 3 "$plan_path"`.

## Exit condition
Coverage gate green (or disabled); tests + typecheck + lint clean; watchdog mid-audit clean. HEAD carries the story's work as provisional `wip(<story-id>)` commit(s) — Phase 4's diff depends on it. Advance `state.json.current_phase` to 4 via `state.sh advance-phase`.

## Artifacts produced
- `state.json.gates[]` may carry `{coverage_gate: "disabled", reason, story_id}`; `state.json.iterations.coverage` incremented per failed iteration.

## Scripts referenced
- `$SCRIPTS/coverage_check.sh` · `$SCRIPTS/state.sh` · `$SCRIPTS/run_subskill_hooks.sh`

## References
- `$REF/state-schema.md` — `iterations.coverage`, `gates[]`. `$REF/sendmessage-protocol.md` — child delivery contract.

## Extensions
<!-- subskill-hooks:phase-3 -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-3` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

# Phase 4 — AC/DoD review + test validation (per story)

**Goal.** Validate the story mechanically (unit tests, typecheck, lint), then run a single **AC reviewer** over *this story's* diff against its acceptance criteria and Definition of Done; UI-facing diffs additionally get the conditional `ui-validator`. Reviewers deliver findings to their **spawner** as their final agent return — the lead under sequential mode, the node executor under graph mode — and the spawner persists the aggregate to the story-keyed review artifact (step 6). Security and performance review happen once per sprint — inside `pre-commit-review-fleet` at Phase 7 — not per story.

> **Workflow path.** If the `Workflow` tool is present in your tool list, use it. If it is not, use the prose below. This is
> a fact to check, not a preference to weigh — do not choose between the two paths on judgment. `$SKILL/references/workflows/story-executor.workflow.js`
> runs Phases 3–5 for one story as a single `Workflow` call: `Workflow({ scriptPath: "<skill>/references/workflows/story-executor.workflow.js",
> args: { storyId, artDir, scriptsDir, planPath, testWriterAgent, engineerAgent, coverageMode, worktree?, reviewerAgent?,
> reviewFixIterations?, maxRedAttempts?, maxGreenAttempts?, maxVerify?, maxReviewRespawn?, maxInnerFix?, maxCoverageIters? } })`.
> Every iteration bound is a loop header; exhausting one is a returned outcome (`blocked_verify`, `cap_reached`), never a silent spin.
>
> **Run recording (sequential mode only).** After the call returns, the lead pins the run id — `bash $SCRIPTS/state.sh record-workflow
> "$plan_path" phase-4 <run_id>` → `workflow_runs.phase-4`. Under `scheduling: graph` the node executors are the callers, so the lead skips
> this write: the D7 clobber rule forbids lead-side `state.json` writes while executors run. Known pre-existing exception, unchanged here:
> the workflow itself persists `iterations.review_fix` from inside its review loop.
> **Lead before/after the call.** Before: nothing — the workflow regenerates `$ART/diff-<story-id>.patch` itself each review round (step 1), so the patch needs no lead-side producer. After: the sub-skill hooks (step 7) and the step-8 advance (sequential `state.sh update`; graph `schedule.sh phase`) — the workflow runs none of them.
>
> The prose below is the fallback contract — entry/exit conditions, gates, bounds, outcome vocabulary, artifacts, and a minimal
> executable step list for a `Workflow`-less environment. The workflow owns sequencing; on ordering disagreements the workflow wins.

## Entry condition
Phase 3 complete for the current story. `state.json.current_phase == 4` AND `state.json.current_story_id` set. Tests + coverage gate green. HEAD contains the story's work as provisional `wip(<story-id>)` commit(s) (D6) — the step-1 `BASE...HEAD` diff captures the full story including previously untracked files.

## Graph mode delta
Under `scheduling: graph` this phase runs inside a **node executor** against the node's worktree (`$PHASES/phase-execute.md`). Entry condition maps to the claimed node record (`schedule.sh phase … <id> 4`), not `state.json`. Reviewers are executor-spawned: they deliver findings to the executor as their **final agent return** — they do NOT SendMessage team-lead — and the executor aggregates into the story-keyed artifact; its own single `done`/`failed` message references the artifact path. **No `state.json` writes** (D7): step 8 is **sequential mode only** — graph mode advances with `bash "$SCRIPTS/schedule.sh" phase "$ART/graph.json" <id> 5`.

## Gate
- Test validation green (step 2).
- Every spawned reviewer delivered findings to its spawner as its final agent return (verified by sprint-watchdog at Phase 5 step 1 via the aggregated artifact — existence + per-AC checklist — not the message log).
- Aggregated reviewer report exists at `$ART/reviews-<story-id>-round-<N>.md` for this story.

## Steps
<!-- wf:p4-diff -->
1. **Compute per-story diff.** `TS_PLAN_PATH="$plan_path" bash "$SCRIPTS/per_story_diff.sh" "$current_story_id" > "$ART/diff-$current_story_id.patch"` — story id positional, plan path from `TS_PLAN_PATH`, `target_branch` from `state.json` (override with `TS_TARGET_BRANCH`). Result: `git diff <last-story-commit-or-target-branch>...HEAD` — this story's changes only, so the reviewer never re-flags work approved in earlier stories.
<!-- wf:p4-verify -->
2. **Test validation (lead, mechanical — no agent).** Run **only this story's tests** (scoped to its test files — SKILL.md → **Per-story test scoping**) plus the resolved `commands.typecheck` + `commands.lint` from the worktree; never the whole-suite `commands.test` (Phase 7's gate). All green → capture a one-line summary for the reviewer context. Any failure → route back to Phase 3 step 2 (engineer); never spawn the reviewer against a red tree.
<!-- wf:p4-re-review -->
3. **Spawn the AC reviewer** — one reviewer, resolved by the Phase 2 agent-type precedence: explicit config name > `state.json.crew.code_reviewer` > `code-reviewer`. Inputs: worktree path, the story's section of `$ART/plan-final.md` (AC + DoD), `$ART/diff-$current_story_id.patch`, the step-2 test summary, and a pointer to the worktree's `.repomix-output.xml`. Three mandatory spawn-prompt contracts:
   - **Review:** per-AC and per-DoD pass/fail with file:line evidence; plan-vs-implementation drift is a CRITICAL finding (the plan is frozen at Phase 1 — never request plan revisions); flag severity-ranked correctness/quality issues in the diff; no security or performance audit (Phase 7's fleet).
   - **Delivery:** return the findings JSON (step 5 shape) as the **final response** to the spawner — do NOT SendMessage team-lead.
   - **Recon preamble:** grep the worktree-local `.repomix-output.xml` (repo-relative paths resolve against the worktree root, not the main tree); when `<worktree>/graphify-out/graph.json` exists, `graphify query`/`path`/`explain` may answer relationship/coupling questions — cite `source_location` the same way as file:line.
4. **Conditional `ui-validator`.** Only when the diff touches JSX/TSX/CSS/template files — spawned in the same turn as step 3 (plus `state.json.crew.accessibility` alongside, frontend stacks only). Same delivery contract as step 5. Non-UI diff → skip entirely.
5. **Each reviewer ends by returning findings to its spawner** as its final agent return, in both modes: `{"reviewer": "<role>", "findings": [{"severity": "CRITICAL|HIGH|MEDIUM|LOW", "file": "...", "line": 42, "issue": "...", "fix": "...", "ac_ref": "<AC/DoD item or null>"}]}`. No SendMessage is required (the crew-resolved `code-reviewer` type has none; under graph mode team-lead is the wrong aggregation layer). Lead-spawned reviewers that have it may additionally send the stringified payload — belt-and-braces, never required. Delivery matrix: `$REF/sendmessage-protocol.md`.
6. **The spawner aggregates** all reports into `$ART/reviews-<story-id>-round-<N>.md` (story-keyed — no filename collisions across executors or stories; `<N>` = current Phase-5 fix iteration, starting at 0) with a per-AC checklist table. **The artifact is the audit record** — sprint-watchdog verifies delivery by its existence + per-AC checklist, not the message log.
7. **Sub-skill hooks, fail-soft** — `bash "$SCRIPTS/run_subskill_hooks.sh" 4 "$plan_path"`.
8. **Persist (sequential mode only).** `bash $SCRIPTS/state.sh update "$plan_path" current_phase=5` once all reports are aggregated (graph mode: `schedule.sh phase` per the delta above — executors never write `state.json`).

## Exit condition
`$ART/reviews-<story-id>-round-<N>.md` exists for this story; state carries the round number so Phase 5 can pair the fix iteration to the right report.

## Artifacts produced
- `$ART/diff-$current_story_id.patch` and `$ART/reviews-<story-id>-round-<N>.md`.

## Scripts referenced
- `$SCRIPTS/per_story_diff.sh` · `$SCRIPTS/state.sh` · `$SCRIPTS/run_subskill_hooks.sh`

## References
- `$REF/sendmessage-protocol.md` — reviewer delivery contract (mandatory).

## Extensions
<!-- subskill-hooks:phase-4 -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-4` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

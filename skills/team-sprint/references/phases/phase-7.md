# Phase 7 — Sprint-level review fleet, final merge & cleanup

**Goal.** Run the `pre-commit-review-fleet` once over the full sprint diff (security, performance, codebase-consistency, simplifier — this is the sprint's only security/perf review), drive any HIGH findings **and every simplifier finding** through a sprint-level fix loop, then run the sprint-level pre-flight, merge into the target branch, tear down the worktree and team, and finalise the sprint report. Only reached when every story has committed cleanly in Phase 6.

> **Workflow path.** If the `Workflow` tool is present in your tool list, use it. If it is not, use the prose below. This is
> a fact to check, not a preference to weigh — do not choose between the two paths on judgment. `$SKILL/references/workflows/phase-7.workflow.js`
> runs steps 1–3 (regression gate, diff regeneration, four-lane fleet, bounded fix loop) as a single `Workflow` call:
> `Workflow({ scriptPath: "<skill>/references/workflows/phase-7.workflow.js", args: { artDir, scriptsDir, planPath, targetBranch, worktree,
> testCommand, typecheckCommand, lintCommand, coverageCommand, coverageThreshold, securityAgent?, performanceAgent?, consistencyAgent?,
> simplifierAgent?, reviewFixIterations? } })`. A red regression gate or an exhausted fix cap is a returned outcome (`blocked_regression`,
> `cap_reached` with `rounds` and `residuals`), never a silent spin. Steps 4–10 (merge onward) have no workflow and stay lead-side prose.
>
> **Run recording (both scheduling modes).** Phase 7 runs after the graph drains (`$PHASES/phase-execute.md`: advance to Phase 7 only
> when every node is done), so no concurrent executor remains and the D7 clobber risk is gone — the lead records
> `bash $SCRIPTS/state.sh record-workflow "$plan_path" phase-7 <run_id>` → `workflow_runs.phase-7` and `state.sh update … iterations.review_fix=<rounds>`
> from the workflow's Return contract in both sequential and graph mode. Known pre-existing exception, unchanged here: the per-story
> workflow persists `iterations.review_fix` from inside its review loop.
>
> The prose below is the fallback contract for steps 1–3 and the full procedure for steps 4–10. The workflow owns steps 1–3 sequencing;
> on ordering disagreements the workflow wins.

## Entry condition
Every story in `$ART/stories.json` has a corresponding entry in `state.json.story_commits[]`. `state.json.current_phase == 7`. Worktree still exists on `sprint_branch`.

## Gate
- `pre-commit-review-fleet` returns zero unresolved HIGH findings **and zero unresolved simplifier findings** over the sprint diff (or user override per finding), **and every spawned fleet reviewer is accounted for** — the delivery-completeness check (step 1b) confirms a final return or a persisted artifact for each of the reviewers launched. A missing reviewer (no return AND no artifact) blocks the merge: an undelivered HIGH must be distinguishable from "no findings", never silently passed green. Simplifier findings are mandatory-fix regardless of severity: by nature they file as MEDIUM/LOW on the fleet's scale and would otherwise slip through as "surfaced, non-blocking" — the simplifier lane's whole output is the cleanup, so it ships or is explicitly waived per finding, never silently dropped.
- Final typecheck + lint + test + coverage pass across the worktree. Exception: when no coverage command is resolved (`detect_commands.sh` emitted `""`), the coverage leg is neither run nor scored — it is recorded as `unavailable — no coverage command resolved`, a non-blocking note, and the merge is not blocked on that account.
- `git pull --ff-only` on the target branch succeeds (no divergent upstream).
- `git merge --no-ff` succeeds.
- `state.json.done == true` after finalisation.

## Steps
1. **Sprint-level review fleet.** From the worktree, regenerate the full sprint diff:
   <!-- wf:diff-regen -->
   ```bash
   git diff "$TARGET_BRANCH...HEAD" > "$ART/diff-sprint.patch"
   ```
   Run `pre-commit-review-fleet` once over `$ART/diff-sprint.patch`. It is hidden from the catalogue, so the `Skill` tool cannot reach it — `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode pre-commit-review-fleet` answers `MODE=inline`, so read the body it names and drive the fleet from here. If the diff exceeds ~2000 lines, chunk it by story-commit boundaries (`git log --grep='^Story: '` marks each story's SHA) so no reviewer drowns in context. Fleet reviewers are lead-spawned direct children: each delivers its findings JSON by **final agent return** to `team-lead` (`$REF/sendmessage-protocol.md`), and the lead persists each to `$ART/reviews-sprint-round-<N>-<reviewer>.md` as the durable delivery record (`SendMessage` optional belt-and-braces, never required).
   <!-- wf:fleet-completeness -->
   1b. **Delivery-completeness check (before scoring the gate).** The fleet launches four reviewers (security, performance, codebase-consistency, simplifier); every one must be accounted for by a final return **or** its persisted artifact before the aggregate is trusted. A reviewer missing both is re-spawned (once; then STOP and surface to the user) — the gate is never scored green on an incomplete fleet. A reviewer that genuinely found nothing writes a zero-findings artifact, so "delivered, zero findings" and "never delivered" stay distinguishable.
2. **Sprint-level fix loop** (when the fleet reports HIGH findings **or any simplifier findings**). The per-story Phase 5 machinery is retired — stories are already committed — so fixes land as follow-up commits on the sprint branch:
   <!-- wf:simplifier-mandatory -->
   - Triage: HIGH → fix tasks, each a TDD micro-cycle (regression test RED → fix GREEN → suite green; Phase 5 step 3 contract), committed with a Conventional Commits `fix:` subject referencing the finding (no `Story:` line). **Simplifier findings (any severity) → mandatory behaviour-preserving refactor tasks** — no new RED test (no behaviour change to pin); story-scoped tests + typecheck + lint stay green; committed with a `refactor:` subject; skipped only by explicit per-finding user override recorded in the report. MEDIUM/LOW from the other reviewers → surfaced in the report, non-blocking.
   <!-- wf:cap-residuals -->
   - Re-run the fleet over the *new* full sprint diff. Clean (zero HIGH **and zero unresolved simplifier findings**) → proceed. Not clean → iterate, capped at `review_fix_iterations` (shared with Phase 5's cap; tracked in `state.json.iterations.review_fix`). Cap hit with unresolved HIGH or simplifier findings is the `cap_reached` outcome (with `rounds` and `residuals`): STOP; ask user to override or kill.
   <!-- wf:regression-first -->
3. **Final sprint-level pre-flight.** From the worktree, run typecheck + lint + test + coverage across the whole tree — the **full** `commands.test` suite, the sprint's only whole-suite run and its first authoritative regression gate over every merged story together (Phases 3–6 and the Execute integration gate ran story-/node-scoped tests). Any failure routes back as a fix task (step 2 machinery) before merge; a red full suite blocks the merge — the `blocked_regression` outcome.
4. **Merge sprint branch into target.**
   ```bash
   cd "$ORIGINAL_REPO"          # leave the worktree
   git checkout "$TARGET_BRANCH"
   git pull --ff-only            # surface upstream divergence early
   git merge --no-ff "$SPRINT_BRANCH" \
       -m "Merge sprint $WORKTREE_NAME ($N stories)"
   ```
   `--no-ff` keeps per-story commits visible in history while marking the sprint topology. `git pull --ff-only` failure → STOP, don't auto-rebase or force-merge.
5. **Push** if `push_on_merge: true`. Never force-push. Never push to `main`/`master` without explicit user confirmation.

6. **Cleanup.**
   ```bash
   git worktree remove "$WORKTREE_PATH"
   git branch -d "$SPRINT_BRANCH"
   ```
7. **Release the fleet.** Stop any still-running teammates (`TaskStop` for in-flight workers); the session team is implicit, so there is no `TeamDelete` to call.
8. **Finalise sprint report.** Append a summary header to `$ART/sprint-report.md` (per-story entries from Phase 6 already populate the body):
   ```markdown
   # Sprint <name> — Complete

   **Plan:** <plan_path>
   **Target branch:** <target_branch>  →  merged at <sha>
   **Worktree:** <path> (removed)
   **Duration:** <wall clock>
   **Stories shipped:** <N> (commits: <sha1>, <sha2>, …)

   ## Gates
   - Adversarial plan review: PASS (<N> iterations)
   - Per-story TDD coverage: all ≥ <threshold>%
   - Per-story AC/DoD review (+ UI where applicable): PASS
   - Sprint-level pre-commit fleet (security/perf/consistency/simplifier): PASS (<N> fix rounds; <N> simplifier findings resolved, <N> waived by user)
   - Final sprint-level pre-flight: PASS

   ## Per-story results
   <generated from Phase 6 step 4 entries>

   ## Surfaced for follow-up (non-blocking)
   <aggregated MEDIUM/LOW findings from the security/perf/consistency lanes the user should
   be aware of — never simplifier findings: those are resolved (or explicitly waived) above>
   ```

9. **Run sub-skill hooks for this phase, fail-soft.**
   ```bash
   bash "$SCRIPTS/run_subskill_hooks.sh" --phase 7 --plan-path "$plan_path"
   ```

10. **Mark finalised.**
    ```bash
    bash "$SCRIPTS/state.sh" update "$plan_path" \
         done=true \
         finalised_at="\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    ```
    Do NOT delete `$ART/` — it's the post-mortem record and proves the plan-path slug is claimed (so a future plan with the same filename is correctly rejected by Phase 0 step 7).

## Exit condition
`state.json.done == true`; sprint branch merged into `$TARGET_BRANCH`; worktree removed; team released; sprint report finalised. **Disarm the watchdog guard** as the last teardown step: `bash ${CREWFORGE5_ROOT}/hooks/sprint-watchdog-guard.sh --deactivate` (from the repo root) — removes `.claude/scripts/sprint-watchdog/.sprint-active.json` so the `PostToolUse(TaskUpdate)` guard goes inert until the next sprint arms it. Leaving it armed makes every later `TaskUpdate` in the repo verify against a finished sprint's artifacts and record spurious violations.

## Artifacts produced
- `$ART/diff-sprint.patch` (+ fleet report and any fix commits on the sprint branch) · `$ART/reviews-sprint-round-<N>-<reviewer>.md` (one per fleet reviewer — the delivery-completeness audit record) · merge commit on `$TARGET_BRANCH` · finalised `$ART/sprint-report.md` · `state.json.done == true` + `state.json.finalised_at`.

## Scripts referenced
- `$SCRIPTS/state.sh` · `$SCRIPTS/run_subskill_hooks.sh`

## References
- `$REF/sendmessage-protocol.md` — fleet reviewers deliver by final agent return to `team-lead`, persisted to per-reviewer artifacts; SendMessage optional. `$REF/state-schema.md` — `done` / `finalised_at` / `iterations.review_fix` semantics.

## Extensions
<!-- subskill-hooks:phase-7 -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-7` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

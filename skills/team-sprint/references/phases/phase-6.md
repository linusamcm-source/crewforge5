# Phase 6 — Story commit (per story)

**Goal.** Commit the story to the sprint branch with a structured commit message that downstream tooling (`git log --grep`) can parse. Entry is gated on the Phase 5 fix loop having converged — no additional review runs here. The `pre-commit-review-fleet` runs once per sprint at the start of Phase 7, not per story.

## Entry condition

Phase 5 complete for the current story. `state.json.current_phase == 6` AND `state.json.current_story_id` set. Phase-4 reviewer(s) clean (zero CRITICAL/HIGH) or user override recorded.

## Graph mode delta

Under `scheduling: graph` this phase runs inside a **node executor** against the node's worktree, per the Node-executor contract in `$PHASES/phase-execute.md`:

- **Entry condition maps to the node record:** node `status: "in_progress"` in `graph.json` with `schedule.sh phase … <id> 6` set — NOT `state.json.current_phase == 6` / `current_story_id` (unsatisfiable while `current_phase == "execute"`).
- **No `state.json` writes.** Steps 5 and 7 are **sequential mode only**: `story_commits[]` is recorded by the LEAD at integrate time (integration merges are serialized, so lead-side writes cannot race), and `current_story_id` is not used under graph mode.
- **Graph-mode exit:** the story commit lands on the node branch; the executor reports `done <node-id> <sha>` via its single SendMessage as the last action of its task. The wave loop handles `schedule.sh commit`, the integration merge, and onward routing — there is no "back to Phase 3 / Phase 7" inside the executor.

## Gate

- `git commit` succeeds with the message produced by `bash $SCRIPTS/build_commit_msg.sh`.

## Steps

1. **Squash provisional commits + stage.** Phases 3 and 5 landed the story's work as `wip(<story-id>)` provisional commits (required so the `BASE...HEAD` diff scripts saw it — D6). Collapse them back into the index so the story ships as exactly one structured commit:
   ```bash
   git reset --soft "$BASE"
   git add -A
   git diff --cached --stat
   ```
   `<BASE>` resolution:
   - **Graph mode:** the node's `base_commit` from `graph.json` (the claim-time integration HEAD — the same value the executor passed as `TS_DIFF_BASE` / `--diff-base`).
   - **Sequential mode:** the prior story's SHA from `state.json.story_commits[]`, else `git merge-base <sprint_branch> <target_branch>` — the same resolution `per_story_diff.sh` uses.

   The soft reset keeps the one-commit-per-story invariant (no `wip` commits reach the branch history) and leaves the `git log --grep='^Story: <id>'` resume anchor exact. Verify the staged diff matches what was intended for this story. Capture it for the sprint record (Phase 7's fleet chunks by story-commit boundaries; this patch is the per-story audit trail):
   ```bash
   git diff --cached > "$ART/diff-$current_story_id-staged.patch"
   ```

2. **Build commit message.** `build_commit_msg.sh` takes three positionals — `<plan_path> <story_id> <type>` — and resolves the story title + acceptance criteria itself from the plan via `parse_stories.sh`, so they are not passed in. `<type>` is the Conventional Commits type for this story (`feat|fix|refactor|perf|docs|test|chore`); default `feat`, or `fix` for a bug-fix story:
   ```bash
   story_type=feat   # or fix|refactor|perf|docs|test|chore per the story's nature
   bash "$SCRIPTS/build_commit_msg.sh" "$plan_path" "$current_story_id" "$story_type" \
        > "$ART/commit-msg-$current_story_id.txt"
   ```
   The script emits the structured body line `Story: <id> — <title>` that `git log --grep='^Story: <id>'` matches deterministically (mech-9 DoD relies on this for snapshot recovery).

3. **Story commit on sprint branch.**
   ```bash
   git commit -F "$ART/commit-msg-$current_story_id.txt"
   ```
   Conventional Commits prefix (`feat:`, `fix:`, `refactor:`, etc.). Each story = one commit. `git log --oneline` after a sprint reads as a clean per-story changelog.

4. **Append story result to sprint report.** Add an entry under `$ART/sprint-report.md` with the commit SHA, story id, and gates passed.

5. **Record the new SHA in `state.json.story_commits[]` (sequential mode only).** Graph mode: the LEAD records the entry at integrate time — executors never write `state.json` (see Graph mode delta). Must happen BEFORE the hook fires so hook commands that read `state.json` see the SHA the subskill-hooks contract promises (`$REF/subskill-hooks.md` phase-6 row).
   ```bash
   NEW_SHA="$(git rev-parse HEAD)"
   CURRENT_COMMITS="$(bash "$SCRIPTS/state.sh" read "$plan_path" | jq -c '.story_commits // []')"
   NEXT_COMMITS="$(jq -c --arg sha "$NEW_SHA" --arg sid "$current_story_id" '. + [{story_id: $sid, sha: $sha}]' <<<"$CURRENT_COMMITS")"
   bash "$SCRIPTS/state.sh" update "$plan_path" story_commits="$NEXT_COMMITS"
   ```

6. **Run sub-skill hooks for this phase, fail-soft.**
   ```bash
   bash "$SCRIPTS/run_subskill_hooks.sh" --phase 6 --plan-path "$plan_path"
   ```

7. **Advance (sequential mode only).** Persist the next story id, reset per-story
   iteration counters, and put `current_phase` back where the next story starts:
   ```bash
   bash "$SCRIPTS/state.sh" update "$plan_path" \
     current_story_id="\"$NEXT_STORY_ID\"" \
     current_phase=3 \
     iterations='{"adversarial":0,"coverage":0,"review_fix":0}'
   ```
   If more stories remain → back to Phase 3 for the next story. If this was the last story → Phase 7
   (`state.sh advance-phase "$plan_path" 7`) instead of the `current_phase=3` above.

   The `current_phase` write is `update`, not `advance-phase`: looping back is a
   decrement, and `advance-phase` enforces target == current+1. Without it Phase
   3's own entry condition (`current_phase == 3`) is unsatisfiable for every
   story after the first, and any reader that resumes from `state.json` — a
   human, or `crewforge5:execute`'s status source — parks on Phase 6 while the
   sprint is really back at Phase 3.

## Exit condition

Story committed to `sprint_branch`. `$ART/sprint-report.md` has an entry for this story. `state.json.story_commits[]` carries the new SHA.

## Artifacts produced

- `$ART/diff-$current_story_id-staged.patch`
- `$ART/commit-msg-$current_story_id.txt`
- Updated `$ART/sprint-report.md`
- New commit on `sprint/<worktree_name>`

## Scripts referenced

- `$SCRIPTS/build_commit_msg.sh`
- `$SCRIPTS/run_subskill_hooks.sh`
- `$SCRIPTS/state.sh`

## References

- `$REF/state-schema.md` — `story_commits[]` semantics.

## Extensions

<!-- subskill-hooks:phase-6 -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-6` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

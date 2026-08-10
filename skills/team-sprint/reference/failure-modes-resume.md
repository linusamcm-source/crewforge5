## Failure modes & resume

- **Sprint dies mid-phase.** Next invocation scans `$ART/../*/state.json`, matches the one whose `plan_path` equals the invocation's plan path, and resumes at `current_phase`. Sub-phase iteration counters are preserved. Multiple non-finalised state files matching the same `plan_path` → STOP, surface to user.
- **Pre-v1.0 sprint layout (flat `.team-sprint/state.json`)?** See CHANGELOG.md v0.x → v1.0 migration note for manual recovery.
- **Worktree corrupted or branch diverged.** Phase 0 sprint-watchdog audit catches stale worktree; offers to remove and restart from Phase 2.
- **Reviewer keeps flagging same issue across iterations.** After 2 iterations of identical findings → STOP, route to user.
- **Coverage stuck below threshold.** After 3 iterations → STOP (design issue surfaces here).
- **User aborts.** `team-sprint --abort` locates the sprint dir via `bash $SCRIPTS/validate_plan_path.sh --slug-only <plan_path>`, removes the worktree, the sprint branch, and that sprint's `$ART/`. Doesn't touch `$TARGET_BRANCH`.

# Execute — the wave loop (macro-phase between Phase 2 and Phase 7)

**Goal.** Drive the work-graph to drain: schedule ready nodes in dependency-respecting waves, run each through the Phase 3 – 6 node executor in its own worktree, merge completed node branches into the integration branch in order, and advance to Phase 7 once every node is `done`.

This phase has no integer `current_phase`; `state.json.current_phase == "execute"` and **`graph.json` is the durable state-of-record**. The lead is the live scheduler; `schedule.sh` owns the mechanical state transitions so the lead never hand-edits JSON.

## Entry condition

Phase 2 complete. `state.json.current_phase == "execute"`. `$ART/graph.json` valid (all nodes `pending`). Integration worktree exists at `$WORKTREE_PATH` on `sprint/<worktree_name>`. Team provisioned.

## Division of labour

- **`schedule.sh` (deterministic):** computes the ready frontier, enforces the `max_parallel_agents` cap, guards every node transition (`claim`/`commit`/`integrate`/`fail`), and write-ahead-persists each change to `graph.json`. It does **not** spawn agents or run git.
- **The lead (agentic):** asks the engine what to run, spawns node executors via `Agent`, performs the serialized integration merges with git, and reports outcomes back into the engine via `SendMessage` → `schedule.sh`. The shared TaskList is the lead's live view (`addBlockedBy` mirrors the graph); `graph.json` is the spine it is reconciled against.

## The loop

Repeat until `schedule.sh status` reports a terminal verdict:

1. **Read the verdict.** `schedule.sh status $ART/graph.json` → `verdict=running|complete|blocked|deadlock` plus counts. `complete` → go to Exit. `blocked`/`deadlock` → STOP (see Terminal states).
2. **Get the next wave.** `schedule.sh next $ART/graph.json` → the ready node ids, already capped to `max_parallel_agents − in_progress`. Empty while nodes are still `in_progress`/`committed` → wait for the outstanding teammates (step 5) before re-asking.
3. **Claim + spawn each node.** For every id in the batch: capture the **current** integration HEAD — `base_sha="$(git -C "$WORKTREE_PATH" rev-parse HEAD)"` — and pass it to `schedule.sh claim … <id> "$base_sha"` (→ `in_progress`, sets `branch`/`worktree`/`base_commit`; `base_commit` is the node's diff base — see Node-executor contract), branch the node worktree off that same sha, copy the repomix pack in, then spawn the teammate with `Agent(subagent_type=…)` to run Phases 3 – 6 against that worktree — if `$teammate_model` is `inherit` (default) omit the `model` arg so the teammate inherits the current session default; otherwise pass `model: $teammate_model`. The teammate must `SendMessage` its single `done`/`failed` on exit to the lead's verified recipient name `<LEAD_RECIPIENT>` (resolved below; see `$REF/sendmessage-protocol.md`).

   **Lead-recipient resolution (spawn time).** The node executor's one `SendMessage` is addressed to the lead, so the lead hands each executor a verified-resolvable recipient rather than an unverified literal. `team-lead` is the **canonical** recipient name: before spawning, the lead confirms it is addressable as `team-lead` in the session's addressable registry (the lead knows the name it is registered under). If the harness registered the lead under a different name (e.g. the run exposed it only as `main`), the lead substitutes that actual name for the `<LEAD_RECIPIENT>` placeholder in the executor's prompt; otherwise `<LEAD_RECIPIENT>` = `team-lead`. The canonical name is used whenever it resolves; the injected identity is a fallback only.
4. **Optionally track sub-phase.** A teammate (or the lead on its behalf) may `schedule.sh phase … <id> <3-6>` for dashboard visibility; it has no gate effect.
5. **Resolve each completion (serialized).** On `SendMessage`:
   - **done** (teammate reached `committed`): `schedule.sh commit … <id> <node-branch-sha>`, then merge the node branch into the integration branch in the integration worktree — `git merge --no-ff sprint/<worktree_name>-<id>` — and **re-run the integration gate**: typecheck/lint + **only this node's tests** (scoped to the node's test files, per SKILL.md → **Per-story test scoping**; not the whole suite), plus whole-repo coverage only if `coverage_mode: whole`. The full regression suite across all merged nodes runs once at Phase 7 — cross-node regressions surface there, not per merge. On success: `schedule.sh integrate … <id> <merge-sha>` (→ `done`), then tear down the node worktree. Integration merges are done **one at a time**, even though node execution was parallel.
   - **failed**: `schedule.sh fail … <id> "<reason>"`. The engine cascades `blocked` to every transitive dependent. Surface the failed node + blocked subgraph to the user; the rest of the frontier keeps running.

   **Stall watchdog.** An executor that never sends is a stall, not a wait: if a node's executor produces no `SendMessage` within a soft timeout (default `max_wall_clock_minutes / <graph node count>`, floor 15 minutes), poll its task via `TaskOutput`. Task dead or errored → `schedule.sh fail … <id> "executor died"` (the cascade blocks dependents) — or, when the stall is discovered on resume, let `reset-orphans` reclaim the node (see Resume). A stalled executor must never hang the sprint silently.
6. **Loop.** Each `integrate`/`fail` changes the frontier, so return to step 1.

## Node-executor contract

Rules every spawned node executor follows while running Phases 3 – 6 against its worktree:

- **Never end a turn with a live child agent.** `Agent` spawns are async: a child's completion notification routes to the session main loop, and an idle executor is not auto-resumed — an executor that ends its turn with a live child sleeps forever (D1). After every `Agent` spawn the executor blocks until the child is terminal — `TaskOutput` (blocking read) or a `Monitor`/poll loop. If it cannot block, it must not spawn — do the work inline instead.
- **Children return to their spawner.** The executor's sub-agents (test-writer, engineer, reviewers) deliver results as their **final agent return** to the executor — they do NOT SendMessage team-lead. Their completion notifications don't reach a sleeping spawner, and team-lead is the wrong aggregation layer: the executor aggregates.
- **Exactly one SendMessage.** The executor sends the lead exactly one message — `done <node-id> <sha>` or `failed <node-id> <reason>` — as the **last action** of its task, addressed to the verified recipient `<LEAD_RECIPIENT>` (canonically `team-lead`; the injected lead identity only when `team-lead` did not resolve at spawn time), per `$REF/sendmessage-protocol.md`. Sub-phase visibility goes through `schedule.sh phase`, never extra messages.
- **Never write `state.json`.** Parallel executors racing read-modify-write on the shared file clobber `current_phase` (D7). Node progress goes exclusively through `schedule.sh phase|commit` (guarded, atomic); `current_story_id` is not used under graph mode, and `story_commits[]` is recorded by the LEAD at integrate time (serialized by construction — merges are one at a time). Each phase doc's **Graph mode delta** banner maps its sequential-mode state writes onto these rules.
- **Diff base = `base_commit`.** Every per-story diff uses the node's `base_commit` (the claim-time integration HEAD recorded in `graph.json`) — never `state.json.story_commits[]` or merge-base resolution, which would fold previously integrated stories into this node's diff (D8). Concretely:

  ```bash
  TS_DIFF_BASE="$base_commit" bash "$SCRIPTS/per_story_diff.sh" <id>          # Phase 4 review diff
  bash "$SCRIPTS/coverage_check.sh" --mode new … --diff-base "$base_commit"   # Phase 3 coverage gate
  ```

## Terminal states

`schedule.sh status` distinguishes them from `graph.json` (the TaskList alone can't tell "waiting on a failure" from "waiting on impossible work"):

- **complete** — every node `done`. Advance to Phase 7.
- **blocked** — no actionable work and a `failed` node has stalled its dependents. STOP; surface the failed + blocked subgraph; let the user fix-and-resume or abort.
- **deadlock** — `pending` nodes remain but none are reachable and nothing failed (a cycle that slipped past Phase 2's validator). STOP; this is a bug in the plan/graph, not a runtime failure.

## Resume

If a sprint is discovered in `current_phase: "execute"`, rebuild the scheduler from `graph.json` (per `$REF/state-schema.md`):

1. Re-establish the Phase 2 roles — the session team is implicit, so just resume spawning teammates via `Agent`/`subagent_type` as nodes become reachable; no `TeamCreate`.
2. `schedule.sh reset-orphans $ART/graph.json` — `in_progress → pending` (`attempts += 1`, worktree/branch/`base_commit` preserved for inspection; a re-claim records a fresh `base_commit`). A `committed` node is left untouched — it awaits the serialized merge and is re-integrated, not re-run. This is also the stall-recovery path: a node whose executor the step-5 watchdog found dead is just an orphaned `in_progress` node — reset it the same way and let the loop re-claim it.
3. For each node still `committed`, `git merge --abort` in the integration worktree if a partial merge is present, then re-attempt the integration of its node branch (step 5 `done` path) — no Phase 3 – 6 re-run.
4. Re-seed the TaskList from `graph.json` (`addBlockedBy` mirroring `depends_on`; complete the tasks of `done` nodes; recreate `failed` nodes' tasks incomplete).
5. Resume the loop from step 1.

## Gate (to advance)

`schedule.sh status` → `verdict=complete` (every node `done`); integration branch holds all node merges; integration gate green. Then advance:

```bash
bash "$SCRIPTS/state.sh" advance-phase "$plan_path" 7
```

## Scripts referenced

- `$SCRIPTS/schedule.sh` — `frontier` / `next` / `status` / `claim` / `phase` / `commit` / `integrate` / `fail` / `reset-orphans` / `simulate`.
- `$SCRIPTS/state.sh` — macro-phase advance (must accept `current_phase: "execute"`).

## References

- `$REF/state-schema.md` — `graph.json` node lifecycle + resume reconstruction.
- `$REF/sendmessage-protocol.md` — node-completion (`done`/`failed`) delivery contract.

## Dry-running the scheduler

`schedule.sh simulate $ART/graph.json [--fail <ids>]` drives a **fresh** graph to drain with stub executors (no agents, no git) — use it to sanity-check a synthesised graph's wave structure and failure cascades before a real run. It mutates the graph in place, so copy first:

```bash
cp "$ART/graph.json" /tmp/g.json && bash "$SCRIPTS/schedule.sh" simulate /tmp/g.json
```

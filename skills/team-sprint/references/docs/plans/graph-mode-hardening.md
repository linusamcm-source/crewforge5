# Sprint plan — graph-mode hardening (post-mortem fixes)

**Source:** Sprint-lead post-mortem from a real graph-mode run (2026-07). Six reported defects (D1–D6) verified against source; three more coupled defects (D7–D9) found during plan review. All defects concentrate in the graph-mode layer (phase-execute.md, build_graph.sh, schedule.sh, phases 3–6 graph adaptation); the gates, artifacts, and review economics held up.

**Repo:** `~/.claude` (skill lives at `skills/team-sprint/`; the former nested git repo was folded into `~/.claude` on 2026-07-20 — history in `~/team-sprint-nested-history.bundle`). All paths below are relative to `skills/team-sprint/`.

## Defect register (verified, file:line against current tree)

| ID | Sev | Defect | Evidence |
|----|-----|--------|----------|
| D1 | CRITICAL | Node-executor stall by construction. Executor spawns test-writer/engineer/reviewer children but is never told to wait; runtime semantics (async `Agent` spawn; child-completion notifications route to the session main loop; idle teammates are not auto-resumed) mean an executor that ends its turn with live children sleeps forever. | `phases/phase-execute.md:22` (step 3 spawns executor "to run Phases 3–6"); phases 3/4 tell the spawner to await SendMessage with no wait mechanism |
| D2 | HIGH | `build_graph.sh` hybrid inference checks only *direct* declared edges before adding a lexicographic conflict edge. A Touches overlap between transitively-ordered nodes fabricates a back-edge → false cycle (observed: WT1→…→DA4 chain + overlap produced DA4 < WT1). | `scripts/build_graph.sh:121` — `if source == "hybrid" and (b in declared[a] or a in declared[b])` |
| D3 | HIGH | Node branch `sprint/<name>/<id>` under integration branch `sprint/<name>` — git forbids a ref and a ref-directory with the same name; every `git worktree add -b` for a node fails. | `scripts/schedule.sh:137` (`f"{ib}/{nid}"`), `:221` (simulate); `phases/phase-2.md:47`; `phases/phase-execute.md:27`; `reference/state-schema.md:85,137` + examples |
| D4 | MEDIUM | Phase-4 mandates reviewers deliver via SendMessage, but the crew-resolved `code-reviewer` agent type has no SendMessage tool. Also wrong-layered under graph mode: the reviewer's spawner is the node executor, not team-lead, so a SendMessage to team-lead bypasses the executor that must aggregate. | `phases/phase-4.md:46`; `agents/code-reviewer.md` tools = Read/Write/Edit/Bash/Glob/Grep |
| D5 | LOW | `sprint-unknown` branch labels: `build_graph.sh` defaults `TS_WORKTREE_NAME`, and `phase-2.md` step 4 never passes it. | `scripts/build_graph.sh:47`; `phases/phase-2.md:82-86` (invocation without env prefix) |
| D6 | HIGH | Committed-HEAD assumption: `git diff BASE...HEAD` in both diff scripts misses uncommitted AND untracked work. Phase 4 review + `--mode new` coverage run *before* the Phase 6 commit → empty diff. Affects sequential mode too, not just graph. Executors invented a provisional-commit workaround; it must become contract. | `scripts/per_story_diff.sh:57`; `scripts/coverage_check.sh` (`git diff "$RESOLVED_BASE"...HEAD`) |
| D7 | HIGH | Phases 3–6 docs are written for lead-driven sequential mode and poison shared state under graph mode: entry conditions require `current_phase == 3..6` + `current_story_id` (unsatisfiable when `current_phase == "execute"`); phase-4 step 8 writes `current_phase=5`; phase-6 steps 5/7 append `story_commits` and set `current_story_id`. Parallel executors following these verbatim race read-modify-write on `state.json` and clobber `current_phase`. | `phases/phase-4.md:63`; `phases/phase-6.md:41-47,54-59`; `phases/phase-3.md:7` |
| D8 | HIGH | Wrong diff base for node branches: `resolve_diff_base` falls back to `merge-base(sprint_branch, target_branch)`; for a node branched off integration HEAD this includes ALL previously-integrated stories in "this story's" diff. Correct base = integration HEAD at claim time. | `scripts/lib.sh:117-137`; `scripts/per_story_diff.sh` |
| D9 | MEDIUM | `$ART/reviews-round-<N>.md` is not story-keyed: story 2 round 0 overwrites story 1 round 0 sequentially; parallel executors race outright. | `phases/phase-4.md:56` (step 6, gate, artifacts) |

## Preconditions

- **P0 — DONE (2026-07-20).** The in-flight LS-refactor is committed and the nested repo folded into `~/.claude` (commit `6fa2dce`). Working tree at `skills/team-sprint/` is clean. Defect line references were verified against this tree.
- **P1 — baseline green.** `bash scripts/tests/run-all.sh` passes and `bash scripts/lint_skill.sh` is clean before any story begins. If baseline is red, fix or quarantine first — no story may claim a pre-existing failure.

## Verification commands (used by every story's DoD)

```bash
bash scripts/tests/run-all.sh          # full bats suite
bash scripts/lint_skill.sh             # doc/script consistency lint
shellcheck scripts/<touched>.sh        # per touched script
```

---

## Story GH1: build_graph.sh — transitive-ordering check for inferred edges

### Context

Fixes D2. The hybrid guard at `build_graph.sh:121` only skips an inferred edge when a *direct* declared edge orders the pair. Replace with a reachability check on the effective-so-far graph (declared ∪ inferred-edges-added-so-far): if the pair is already ordered in either direction, skip; only when incomparable, add the lower-story-id-first edge. Checking the growing effective graph (not just declared closure) also prevents the three-node interplay cycle (inferred A→M, inferred M→Z, declared Z-before-A) that a declared-closure-only fix would miss. Adding edges only between incomparable nodes keeps the graph acyclic by construction. Pair iteration order is already deterministic (`ids` order, i<j) — keep it so output is reproducible.

### Acceptance Criteria

1. Given stories WT1→WT2→DA4 (declared chain: DA4 depends transitively on WT1) where WT1 and DA4 have overlapping `touches[]`, `build_graph.sh` (hybrid) exits 0, adds **no** inferred edge between WT1 and DA4, and the topo `order[]` places WT1 before DA4.
2. Given declared edge "A depends on Z" plus touches overlaps (A,M) and (M,Z) with no other declared edges, `build_graph.sh` (hybrid) exits 0 and produces an acyclic graph (regression for the inferred-chain interplay).
3. Two nodes with overlapping touches and **no** ordering path between them still get the lexicographic (natural-key) lower-first inferred edge, recorded in the dependent's `inferred_deps[]` — existing behaviour preserved (existing bats test "hybrid mode infers a conflict-ordering edge from Touches overlap" still passes).
4. `declared` and `inferred` modes are behaviourally unchanged.
5. Skipped-as-transitively-ordered pairs are NOT recorded in `inferred_deps[]` (no phantom deps).

### Definition of Done

- [ ] New bats tests in `scripts/tests/build_graph.bats` covering AC1 and AC2 (RED first, then GREEN).
- [ ] All existing `build_graph.bats` tests pass unchanged.
- [ ] `shellcheck scripts/build_graph.sh` clean; `run-all.sh` green.
- [ ] Header comment block in `build_graph.sh` updated to describe the transitive-ordering rule (hybrid section).

### Depends On: none

### Touches: scripts/build_graph.sh, scripts/tests/build_graph.bats

---

## Story GH2: node branch namespace — `sprint/<name>-<id>`

### Context

Fixes D3. `refs/heads/sprint/<name>` (a file) cannot coexist with `refs/heads/sprint/<name>/<id>` (needs `sprint/<name>/` as a directory). Rename the node-branch scheme to `sprint/<name>-<id>` (integration branch unchanged at `sprint/<name>`). Single-source the derivation: both `claim` and `simulate` in schedule.sh must use the same expression.

### Acceptance Criteria

1. `schedule.sh claim` sets `node.branch` to `<integration_branch>-<id>` (e.g. `sprint/fix-auth-DA4`); `simulate` derives identically.
2. `phases/phase-2.md:47`, `phases/phase-execute.md:27` (merge command), and `reference/state-schema.md` (prose line ~85, `branch` field description ~137, both JSON examples) all state the `-<id>` scheme; zero remaining `sprint/<name>/<id>`-style references anywhere in the repo — verified by grep over `*.md` and `*.sh` (excluding CHANGELOG history notes).
3. In a scratch git repo, `git worktree add -b sprint/x-n1 ../wt-n1 sprint/x` succeeds while branch `sprint/x` exists (sanity: the old scheme fails, the new one doesn't).
4. `schedule.sh simulate` on the fixture graph drains to `complete` with the new branch labels.

### Definition of Done

- [ ] bats assertion(s) in `scripts/tests/schedule.bats` / `schedule_scenario.sh` updated + a regression test asserting the branch contains no `/` after the integration-branch prefix.
- [ ] `run-all.sh` + `lint_skill.sh` green; `shellcheck scripts/schedule.sh` clean.

### Depends On: none

### Touches: scripts/schedule.sh, scripts/tests/schedule.bats, scripts/tests/schedule_scenario.sh, phases/phase-2.md, phases/phase-execute.md, reference/state-schema.md

---

## Story GH3: claim-time base commit + diff-base plumbing

### Context

Fixes D8, enables GH4. Under graph mode the only correct diff base for a node is the integration HEAD it branched from. Record it at claim: `schedule.sh claim <graph.json> <id> [<base-sha>]` stores `node.base_commit` (nullable; lead passes `git -C "$WORKTREE_PATH" rev-parse HEAD` at claim). `per_story_diff.sh` gains a `TS_DIFF_BASE` env short-circuit (highest precedence, before story_commits/merge-base resolution). `coverage_check.sh` already accepts `--diff-base`; document that graph-mode executors must pass it. `reset-orphans` preserves `base_commit` alongside branch/worktree.

### Acceptance Criteria

1. `schedule.sh claim g.json N1 abc123` → node has `base_commit: "abc123"`; omitting the sha keeps `base_commit: null` (back-compat; existing claim tests pass).
2. `build_graph.sh` emits `base_commit: null` on every node; `reference/state-schema.md` documents the field and `scripts/state.schema.json` (graph section, if present there) accepts it.
3. `TS_DIFF_BASE=<sha> per_story_diff.sh <id>` diffs from `<sha>` without consulting `state.json.story_commits` or merge-base; unset → behaviour unchanged (existing `per_story_diff.bats` pass).
4. `phases/phase-execute.md` step 3 tells the lead to pass the integration HEAD sha to `claim`, and the executor contract (GH5 section anchor) to run `per_story_diff.sh` with `TS_DIFF_BASE=$base_commit` and `coverage_check.sh` with `--diff-base $base_commit`.

### Definition of Done

- [ ] bats: new claim-with-sha test in `schedule.bats`; new `TS_DIFF_BASE` test in `per_story_diff.bats` (RED first).
- [ ] Header docs updated in `schedule.sh`, `per_story_diff.sh`, `coverage_check.sh`.
- [ ] `run-all.sh` + `lint_skill.sh` green; shellcheck clean on touched scripts.

### Depends On: GH2

### Touches: scripts/schedule.sh, scripts/build_graph.sh, scripts/per_story_diff.sh, scripts/coverage_check.sh, scripts/tests/schedule.bats, scripts/tests/per_story_diff.bats, reference/state-schema.md, phases/phase-execute.md

---

## Story GH4: provisional-commit protocol (both modes)

### Context

Fixes D6. Phase 4 review and `--mode new` coverage need the story's work in HEAD, but the story commit happens at Phase 6. Mandate: Phase 3 ends with a provisional commit; Phase 5 fix iterations add more; Phase 6 squashes to the single structured story commit. Untracked files are covered (two-dot working-tree diffs are not a substitute — they miss untracked files).

- **Phase 3 exit** (after gate green): `git add -A && git commit -m "wip(<story-id>): phase-3 green"`.
- **Phase 5** each fix iteration: `git add -A && git commit -m "wip(<story-id>): fix round <N>"`.
- **Phase 6** step 1 replaced: `git reset --soft <BASE>` then stage-verify + single `git commit -F` as today. `<BASE>` = `node.base_commit` under graph mode; prior-story SHA / merge-base under sequential (same resolution `per_story_diff.sh` uses).
- One-commit-per-story invariant preserved; `git log --grep='^Story: <id>'` resume anchor unaffected.

### Acceptance Criteria

1. `phases/phase-3.md` gate/exit adds the provisional commit step with exact command; phase-5 adds the per-iteration wip commit; phase-6 step 1 documents the soft-reset squash with base resolution for both modes.
2. Docs state WHY (diff scripts read HEAD; untracked files) so future edits don't regress it.
3. `phases/phase-4.md` entry condition notes HEAD now contains the story work (provisional commit from Phase 3).
4. Sequential mode path documented equally — this defect predates graph mode.

### Definition of Done

- [ ] `lint_skill.sh` green.
- [ ] Cross-references between phase-3/5/6 and per_story_diff.sh/coverage_check.sh headers consistent (scripts' comments mention the provisional-commit expectation).

### Depends On: GH3

### Touches: phases/phase-3.md, phases/phase-5.md, phases/phase-6.md, phases/phase-4.md, scripts/per_story_diff.sh, scripts/coverage_check.sh

---

## Story GH5: node-executor concurrency contract + graph-mode deltas

### Context

Fixes D1 + D7 — the stall and the shared-state races. `phase-execute.md` gets a new **"Node-executor contract"** section; phases 3–6 each get a short **"Graph mode delta"** banner. Core rules:

**Executor concurrency (the stall fix):**
- The executor NEVER ends a turn with a live child agent. After every `Agent` spawn it blocks until the child is terminal — `TaskOutput` (blocking read) or a `Monitor`/poll loop. If it cannot block, it must not spawn — do the work inline instead.
- Children (test-writer, engineer, reviewers) deliver results as their **final agent return** to the executor — they do NOT SendMessage team-lead (their completion notifications don't reach a sleeping spawner, and team-lead is the wrong aggregation layer).
- The executor sends exactly **one** SendMessage to team-lead: `done <node-id> <sha>` or `failed <node-id> <reason>`, as the last action of its task, per `$REF/sendmessage-protocol.md`.

**Lead-side stall watchdog:**
- In the wave loop, if an executor produces no SendMessage within a soft timeout (default: `max_wall_clock_minutes / graph node count`, floor 15 min), the lead polls the executor's TaskOutput. Task dead/errored → `schedule.sh fail <id> "executor died"` (cascade handles dependents) or `reset-orphans` on resume. A stalled executor must never hang the sprint silently.

**Graph-mode state ownership (the race fix):**
- Executors NEVER write `state.json`. Node progress goes exclusively through `schedule.sh phase|commit` (guarded, atomic). `story_commits[]` is recorded by the LEAD at integrate time (serialized by construction — merges are one at a time). `current_story_id` is not used under graph mode.
- Phases 3–6 entry conditions gain graph-mode equivalents: "node claimed (`in_progress`), `schedule.sh phase` set" instead of `current_phase == N` + `current_story_id`.
- Phase-4 step 8 (`state.sh update current_phase=5`), phase-6 steps 5/7 (story_commits append, current_story_id advance, "back to Phase 3 / Phase 7" routing) are marked **sequential-mode only**; graph mode replaces them with `schedule.sh phase` transitions and lead-side recording.

### Acceptance Criteria

1. `phase-execute.md` contains the Node-executor contract with the three concurrency rules verbatim-equivalent (never end turn with live child; children return-to-spawner; exactly one done/failed SendMessage), plus the TaskOutput/Monitor blocking mechanism named explicitly.
2. `phase-execute.md` wave loop step 5 documents the lead-side stall watchdog (timeout + TaskOutput poll + fail path).
3. Each of `phases/phase-3.md` … `phase-6.md` carries a "Graph mode delta" banner covering: entry-condition mapping, no `state.json` writes, `schedule.sh phase` for sub-phase tracking, and (phase-6) lead-records-story_commits-at-integrate.
4. `reference/state-schema.md` graph section documents that `story_commits[]` under graph mode is written only by the lead at integrate time.
5. No phase doc instructs an executor-spawned agent to SendMessage team-lead (grep-verified; phase-4's reviewer delivery is rewritten in GH6 — this story only removes the executor-context contradiction it owns and may land the shared banner text).

### Definition of Done

- [ ] `lint_skill.sh` green.
- [ ] `phase-execute.md` Resume section updated: stall recovery folds into `reset-orphans` flow.
- [ ] SKILL.md phase-overview blurbs untouched except where they contradict the new contract (surgical edits only).

### Depends On: GH2, GH4

### Touches: phases/phase-execute.md, phases/phase-3.md, phases/phase-4.md, phases/phase-5.md, phases/phase-6.md, reference/state-schema.md, SKILL.md

---

## Story GH6: reviewer delivery contract — deliver-to-spawner

### Context

Fixes D4 + D9. The SendMessage-only delivery contract assumed (a) every reviewer agent type has the tool (crew-resolved `code-reviewer` doesn't) and (b) the spawner is always team-lead (false under graph mode). New contract:

- **Delivery = structured JSON findings as the reviewer's final agent return to its spawner.** The spawner persists the aggregate to `$ART/reviews-<story-id>-round-<N>.md` (story-keyed — fixes D9) and is responsible for onward relay.
- Sequential mode: spawner is the lead → persistence alone satisfies the contract; lead-spawned reviewers that DO have SendMessage may additionally send (belt-and-braces, not required).
- Graph mode: spawner is the executor → executor persists the aggregate and its single `done`/`failed` SendMessage to team-lead references the review artifact path.
- **The artifact is the audit record.** sprint-watchdog verifies delivery by artifact existence + per-AC checklist presence, not by scanning the message log for reviewer-originated messages.
- `sendmessage-protocol.md` gains a "Reviewer delivery under graph mode" section superseding the message-log-only doctrine; the "SendMessage unavailable → STOP" failure mode is replaced by "SendMessage unavailable → final-return delivery is the contract".

### Acceptance Criteria

1. `phases/phase-4.md` steps 3–6: reviewer spawn prompt requires the JSON findings payload (existing shape) as the final response; step 5 rewritten to deliver-to-spawner; step 6 aggregates to `$ART/reviews-<story-id>-round-<N>.md`; gate + artifact list use the story-keyed name.
2. `phases/phase-5.md` references the story-keyed filename.
3. `reference/sendmessage-protocol.md` documents the two-mode delivery matrix and redefines watchdog verification as artifact-based for reviewers; executor `done`/`failed` remains the one mandatory SendMessage.
4. Works with a SendMessage-less reviewer agent by construction — no relay workaround needed; contract text explicitly notes the crew `code-reviewer` case.
5. No stale references to the non-story-keyed `reviews-round-<N>.md` remain (grep-verified across phases/, reference/, SKILL.md).

### Definition of Done

- [ ] `lint_skill.sh` green.
- [ ] SKILL.md "SendMessage is the protocol" invariant paragraph updated to match (reviewers: deliver-to-spawner + artifact; executors + lead-spawned auditors: SendMessage).
- [ ] CHANGELOG entry summarising the contract change (breaking for sprint-watchdog expectations — noted).

### Depends On: GH5

### Touches: phases/phase-4.md, phases/phase-5.md, reference/sendmessage-protocol.md, SKILL.md, CHANGELOG.md

---

## Story GH7: env wiring + fallback warnings

### Context

Fixes D5. `build_graph.sh` reads `TS_WORKTREE_NAME` / `TS_MAX_PARALLEL_AGENTS` / `TS_DEPENDENCY_SOURCE`, but `phase-2.md` step 4 invokes it bare — so every real run got `sprint-unknown` labels and config defaults. Fix the doc invocation; add stderr WARNs on silent fallbacks.

### Acceptance Criteria

1. `phases/phase-2.md` step 4 invocation becomes:
   ```bash
   TS_WORKTREE_NAME="$WORKTREE_NAME" \
   TS_MAX_PARALLEL_AGENTS="$max_parallel_agents" \
   TS_DEPENDENCY_SOURCE="$dependency_source" \
   bash "$SCRIPTS/build_graph.sh" "$ART/stories.json" "$ART/graph.json"
   ```
2. `build_graph.sh` WARNs to stderr when `TS_WORKTREE_NAME` is unset/empty ("defaulting integration_branch to sprint/sprint-unknown — pass TS_WORKTREE_NAME"); exit code unchanged (warning, not error).
3. `schedule.sh` WARNs to stderr when it falls back to `sprint/unknown` for a missing `integration_branch`.
4. Warnings go to stderr only — stdout output shape unchanged (bats asserting stdout still pass).

### Definition of Done

- [ ] bats: warning-emission tests (stderr contains WARN when env unset; absent when set).
- [ ] `run-all.sh` + `lint_skill.sh` green; shellcheck clean.

### Depends On: GH1, GH2

### Touches: phases/phase-2.md, scripts/build_graph.sh, scripts/schedule.sh, scripts/tests/build_graph.bats, scripts/tests/schedule.bats

---

## Dependency graph

```
GH1 ──────────────┐
GH2 ──┬── GH3 ── GH4 ── GH5 ── GH6
      └───────────┴──────────── GH7 (needs GH1 + GH2)
```

Wave 1: GH1, GH2 (parallel — disjoint files).
Wave 2: GH3, GH7 (GH7 also needs GH1).
Wave 3: GH4. Wave 4: GH5. Wave 5: GH6.

## Sprint-level Definition of Done

- [ ] Full `run-all.sh` bats suite green; `lint_skill.sh` clean; shellcheck clean on all touched scripts.
- [ ] `schedule.sh simulate` on a ≥5-node fixture (with one `--fail`) drains correctly under the new branch naming.
- [ ] Repo-wide greps: zero `sprint/<name>/<id>`-pattern refs; zero non-story-keyed `reviews-round-` refs; zero executor-context "SendMessage to team-lead" instructions for reviewers.
- [ ] CHANGELOG.md entry for the release (breaking: branch naming, reviewer delivery contract, provisional commits).
- [ ] One commit per story, Conventional Commits, on the `~/.claude` repo (scope commits to `skills/team-sprint/` paths only).

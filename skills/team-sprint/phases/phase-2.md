# Phase 2 — Work-graph synthesis + team

**Goal.** Parse `plan-final.md` into work-graph nodes, synthesise and harden the dependency graph, establish the integration base, and provision the agent fleet the scheduler dispatches across Phases 3 – 6 in dependency-respecting waves.

## Entry condition

Phase 1 complete. `$ART/plan-final.md` exists. `state.json.current_phase == 2`.

**Plan-of-record gate (mandatory, before any other step).** The reviewed plan must provably be
the plan about to execute (obs 18983/18988: four review rounds ran against a 6-story plan-v4
while the config still pointed at the original 7-story plan — Phase 2 would have executed the
wrong plan and discarded every finding). Two checks, in order:

1. **Content check.** Compare `$ART/plan-final.md` against the hash Phase 1 recorded at
   promotion:
   ```bash
   bash "$SCRIPTS/state.sh" check-plan "$plan_path" "$ART/plan-final.md"
   ```
   `STATUS=OK` → the file about to execute is the recorded plan of record (same path, same
   bytes) as what Phase 1 promoted.
   `STATUS=FAIL` → STOP and surface the script's stderr (recorded vs actual hashes, reason
   `path-mismatch` when the file is not the recorded `plan_of_record.path`, or reason
   `no-record` when Phase 1 never ran `record-plan`). Do not proceed: re-enter Phase 1, or
   re-run `state.sh record-plan` only as a deliberate, user-confirmed override.
   Any other outcome — exit 2 with no `STATUS=` line (state.json missing: the sprint was
   never init'd or its state was lost) — is also STOP, never a pass.

2. **Sprint-dir check.** The configured `plan_path` and the plan under execution must resolve
   to the same sprint dir:
   ```bash
   source "$SCRIPTS/lib.sh"
   [ "$(art_dir "$plan_path")" = "$(art_dir "$ART/plan-final.md")" ]
   ```
   Mismatch → STOP with a message naming both paths (`configured plan_path <path> resolves to
   <dir-A>; executing $ART/plan-final.md resolves to <dir-B>`) — the config points at a
   different sprint than the plan being executed.

## Gate

`$ART/stories.json` and `$ART/graph.json` populated; graph passes validation (acyclic topo sort; no dangling `Depends On` refs; no self-edges; no same-wave file-conflict pair lacking an edge); graph-hardening adversarial review ran to zero findings of any severity (or per-finding user override at the `adversarial_iterations` cap) — mandatory, step 5; integration worktree exists at `$WORKTREE_PATH` on branch `sprint/<worktree_name>` (the integration branch) based on `$TARGET_BRANCH`; repomix pack present in the integration worktree; team roles defined (teammates spawn on demand via `Agent` — the session team is implicit, no provisioning step); `state.json` carries `worktree_path`, `sprint_branch`, `graph_path`.

> **Sequential mode.** With `scheduling: sequential` (`worktree_strategy: single`), this phase behaves as it did pre-graph: single shared worktree, no graph synthesis — skip steps 3 – 5 and 7, and build the legacy cross-story blocked TaskList instead (one task per acceptance criterion, `addBlockedBy` chaining tests→impl→reviewers within a story and each story's reviewers→next story's RED). The steps below describe the default `graph` path.

## Steps

1. **Create the integration worktree + branch.** Sibling directory, same filesystem (cheap hardlinks, fast git ops, stable IDE paths). This is the lead's tree — where serialized node→integration merges and the Phase 7 final suite run:

   ```bash
   MAIN_TREE="$(pwd)"
   REPO_NAME=$(basename "$MAIN_TREE")
   WORKTREE_PATH="../${REPO_NAME}-${WORKTREE_NAME}"     # integration worktree (lead)
   SPRINT_BRANCH="sprint/${WORKTREE_NAME}"             # integration branch
   git worktree add -b "$SPRINT_BRANCH" "$WORKTREE_PATH" "$TARGET_BRANCH"
   ```

   **Copy the Phase 0 repomix pack into the integration worktree.** This is the canonical pack; the scheduler copies it into each node worktree at spawn (paths in grep results are repo-relative and must resolve against the worktree root):

   ```bash
   cp "$MAIN_TREE/.repomix-output.xml" "$WORKTREE_PATH/.repomix-output.xml"
   # Carry the Phase 0 graphify graph into the worktree too (when graphify != off),
   # so `graphify query`/`graphify path` resolve against the worktree CWD for the
   # graph-synthesis check below and the Phase 4 reviewers. graph.json paths are
   # repo-relative, so they resolve correctly under the worktree root.
   [ -d "$MAIN_TREE/graphify-out" ] && cp -R "$MAIN_TREE/graphify-out" "$WORKTREE_PATH/graphify-out"
   cd "$WORKTREE_PATH"
   ```

   **Carry the crew in too.** A worktree cut from a base ref older than the
   crew commit has no `.claude/agents/` — and that does not fail here, it fails
   at spawn. One way, main tree authoritative:

   ```bash
   bash "$SCRIPTS/crew_copy.sh" "$MAIN_TREE" "$WORKTREE_PATH"   # STATUS=OK|NO_CREW
   ```

   `STATUS=NO_CREW` is normal before `crew-factory` has ever run; it is not a
   stop condition. The scheduler repeats this per node worktree — see
   `phases/phase-execute.md` step 3.

   Persist:

   ```bash
   bash "$SCRIPTS/state.sh" update "$plan_path" \
     worktree_path="\"$WORKTREE_PATH\"" \
     sprint_branch="\"$SPRINT_BRANCH\""
   ```

   Node worktrees (`../${REPO_NAME}-${WORKTREE_NAME}-<node-id>` on `sprint/${WORKTREE_NAME}-<node-id>` — a sibling ref of the integration branch; git forbids a slash-nested node ref under the existing `sprint/${WORKTREE_NAME}` ref) are created **lazily by the scheduler** when a node enters the frontier — not here.

2. **Refresh repomix in the integration worktree only if stale.** The copy from step 1 is reused as-is for short sprints; refresh-in-worktree happens only if the pack's age exceeds `repomix_max_age_minutes`:

   ```bash
   bash "$SCRIPTS/repomix_refresh.sh" --max-age-minutes "$repomix_max_age_minutes" --target-dir "$WORKTREE_PATH"
   ```

   (`repomix_refresh.sh` is idempotent — it no-ops when the pack is fresh enough.)

3. **Parse stories into nodes.** `parse_stories.sh` must now also extract the two graph fields:

   ```bash
   bash "$SCRIPTS/parse_stories.sh" "$ART/plan-final.md" > "$ART/stories.json"
   ```

   Each entry carries `story_id`, `acceptance_criteria[]`, `definition_of_done[]`, **`depends_on[]`** (ids from `### Depends On:`; `[]` when `none`/absent), **`touches[]`** (globs from `### Touches:`), and any extra context (screenshot links, repro steps, file pointers). No `## Story` headings → one implicit node keyed by the plan filename, `depends_on: []`.

   > **Script change required.** `parse_stories.sh` gains two extractors: `### Depends On:` → `depends_on[]` (split on commas/whitespace, drop `none`), and `### Touches:` → `touches[]` (one glob per token/line).

4. **Synthesise the work-graph.** `build_graph.sh` consumes `stories.json` + config and emits `graph.json`. The env wiring is mandatory — a bare invocation falls back to `sprint/sprint-unknown` branch labels and config defaults (`build_graph.sh` WARNs on stderr when `TS_WORKTREE_NAME` is unset/empty):

   ```bash
   TS_WORKTREE_NAME="$WORKTREE_NAME" \
   TS_MAX_PARALLEL_AGENTS="$max_parallel_agents" \
   TS_DEPENDENCY_SOURCE="$dependency_source" \
   bash "$SCRIPTS/build_graph.sh" "$ART/stories.json" "$ART/graph.json"
   ```

   Edge sources, per `dependency_source`:

   - **`declared`** — edges from `depends_on[]` only.
   - **`inferred`** — edges only from `Touches` glob overlap (requires `infer_from_touches: true`).
   - **`hybrid` (default)** — declared edges are authoritative; additionally, for any two nodes whose `touches[]` globs overlap and which have **no** declared edge between them, add an inferred conflict-ordering edge (direction: lower `story_id` first) and record it in the dependent's `inferred_deps[]`.

   `build_graph.sh` is the validator: it exits non-zero — naming the offending node(s) — on a **cycle** (prints the cycle path), a **dangling `depends_on` ref** (id absent from `stories.json`), or a **self-edge**. On success it writes `graph.json` with every node at `status: "pending"` (the scheduler derives `ready` at execute entry), `depends_on` = `declared_deps ∪ inferred_deps`, and a cached topological `order[]`. Schema: `$REF/state-schema.md` (graph.json section).

   > **Script change required.** `build_graph.sh` is new — see its contract above and the graph.json schema in `$REF/state-schema.md`.

5. **Harden the graph adversarially** (MANDATORY under `scheduling: graph` — hard-wired, no config toggle; skip only under `scheduling: sequential`, which builds no graph). Mechanical loop:

   ```
   N = 0
   while True:
       N += 1
       reviewer  = spawn general-purpose, seeded with the body at
                   `subskill_resolve.sh adversarial-review` (MODE=inline),
                   over graph.json + stories.json
                   (if $adversarial_model is `inherit` omit the model arg, else pass it)
       findings  = block-collect reviewer's final agent return
                   (json adversarial-summary tail per $REF/reviewer-contract.md)
       persist $ART/graph-review-round-<N>.md
       state.sh update iterations.adversarial += 1
       if findings (any severity) == 0: break          # gate: all-severities clean
       if N >= adversarial_iterations: prompt user (override per finding / extend / abort); break
       apply edge corrections (re-run build_graph.sh with an overlay, or patch + re-validate)
   ```

   The reviewer critiques **false independence** (nodes scheduled in parallel that actually share an interface or file the `Touches` globs missed), **missing edges**, **redundant edges**, and **semantic cycles** the mechanical check can't see. When `graphify != off`, the reviewer should query the knowledge graph to ground these claims — `graphify path "<symbol-in-node-A>" "<symbol-in-node-B>"` surfaces real call/import coupling between two supposedly-independent nodes that the `Touches` globs never saw, turning a hunch about false independence into a cited edge. It returns findings to `team-lead` as its **final agent return** — team-lead is its direct spawner, so no `SendMessage` is used (`$REF/sendmessage-protocol.md`, channel 1). `state.json.iterations.adversarial` is seeded at Phase 1 with the planner's review-round count; these graph rounds increment it from there.

6. **Define the team roles.** The session team is implicit — there is no `TeamCreate` step. The scheduler instantiates these roles per node / per wave via the `Agent` tool (selecting the role with `subagent_type`), **not** as a fixed standing pool; `max_parallel_agents` caps concurrent node executors:

   | Role | Responsibility |
   | --- | --- |
   | `team-lead` | Orchestrator. Owns `graph.json` + the TaskList projection. Runs the wave loop, the serialized integration merges, and collects results: **final agent return** from its direct children (the Phase 2 graph reviewer and the Phase 7 fleet), `SendMessage` only from node executors (`done`/`failed`) (`$REF/sendmessage-protocol.md`). |
   | `test-writer` | Writes RED tests for each acceptance criterion (per node). |
   | `engineer` (1+) | Implements production code until RED tests turn GREEN (per node). |
   | `ac-reviewer` | Phase 4's single reviewer: AC/DoD verification + code-quality over the story diff (absorbs the former code/spec reviewer roles). Security/perf review happens once per sprint via the Phase 7 fleet, not here. |
   | `ui-validator` | Reviews the diff at Phase 4 if the change is UI-facing. |
   | `<domain_agents>` | Optional per-config (e.g. `oceanographer`, `go-engineer`). |

   **Role → agent-type resolution (canonical — phases 3 and 4 apply this at spawn time).** Precedence for every role, evaluated per spawn:

   1. an explicit, non-`auto` agent name in config (`engineer_agent`, `test_writer_agent`, or a `domain_agents` entry) — always wins;
   2. else `state.json.crew.<key>` from the manifest (present when `crew: auto`, written by Phase 0 step 10a);
   3. else the role's static default.

   This is the single source of truth; phase-3 (test-writer, engineer) and phase-4 (reviewers) reference it rather than re-deriving. Role → manifest key:

   | team-sprint role | crew manifest key |
   | --- | --- |
   | `engineer` | `crew.developer` |
   | `test-writer` | `crew.tester` |
   | `ac-reviewer` | `crew.code_reviewer` |
   | `<domain_agents>` | `crew.architect`, `crew.simplifier`, `crew.docs_writer`, `crew.dependency_auditor` (spawned by the scheduler as a node needs them) |

   `crew.security` and `crew.profiler` are NOT spawned per story — security/perf review is the Phase 7 fleet's job (the manifest still builds them; they remain available to `pre-commit-review-fleet` and to users directly). when the manifest carries a frontend `crew.accessibility` agent (present only for react-native/web stacks), add it as a second UI-facing reviewer at Phase 4 alongside `ui-validator` — otherwise the generated accessibility agent is never assigned. When `crew: off`, fall back to `engineer_agent` / `test_writer_agent` / `domain_agents` from config. An explicit non-`auto` agent name in config always overrides the manifest.

7. **Seed the TaskList projection.** Create one task per node, `addBlockedBy` mirroring `graph.json` edges, so the team dashboard shows the structure. **`graph.json` is authoritative** — never read frontier state from the TaskList; the scheduler keeps the projection in sync via `TaskUpdate` as node statuses change.

8. **Run sub-skill hooks for this phase, fail-soft.** Final step before advancing:

   ```bash
   bash "$SCRIPTS/run_subskill_hooks.sh" 2 "$plan_path"
   ```

## Exit condition

`stories.json` + `graph.json` populated and graph valid; integration worktree exists; team provisioned; `state.json` carries `worktree_path`, `sprint_branch`, `graph_path`. Advance into the **execute** macro-phase (the scheduler then drives Phases 3 – 6 per node until the graph drains, at which point it advances to phase 7):

```bash
bash "$SCRIPTS/state.sh" advance-phase "$plan_path" execute
```

> **Script change required.** `state.sh` (and `state.schema.json`) must accept `current_phase: "execute"` — see `$REF/state-schema.md`.

## Artifacts produced

- `$ART/stories.json` (now with `depends_on[]` + `touches[]`)
- `$ART/graph.json`
- `$ART/graph-review-round-<N>.md` (one per graph-review round; graph mode only)
- `<integration-worktree>/.repomix-output.xml`
- `state.json.worktree_path`, `state.json.sprint_branch`, `state.json.graph_path`

## Scripts referenced

- `$SCRIPTS/state.sh`
- `$SCRIPTS/repomix_refresh.sh` (with `--target-dir`)
- `$SCRIPTS/parse_stories.sh` (extended: extracts `depends_on` + `touches`)
- `$SCRIPTS/build_graph.sh` (new: edge synthesis + topo validation → `graph.json`)
- `$SCRIPTS/run_subskill_hooks.sh`

## References

- `$REF/sendmessage-protocol.md` — reviewer + node-completion delivery contract.
- `$REF/state-schema.md` — `state.json` + `graph.json` field semantics; the `execute` macro-phase; resume reconstruction.
- `$REF/subskill-hooks.md` — sub-skill hook contract.

## Extensions

<!-- subskill-hooks:phase-2 -->

Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-2` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

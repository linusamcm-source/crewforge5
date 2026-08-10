# `state.json` + `graph.json` — schema & resume contract

**WHO READS THIS / WHEN:** Phase 0 reads this before initialising `$ART/state.json`; every phase that updates state (advancing `current_phase`, recording `gates[]`, appending `story_commits[]`) reads it; the resume scan in Phase 0 step 8 and on next-invocation startup reads it to interpret the file it discovered. Under `scheduling: graph`, the controller additionally reads and writes **`$ART/graph.json`**, which is **authoritative for per-node progress and frontier computation** during the `execute` macro-phase.

Persist sprint metadata to `$ART/state.json`:

```bash
bash "$SCRIPTS/state.sh" init "$plan_path" "$target_branch" "$worktree_name"
```

The machine schema lives at `$SCRIPTS/state.schema.json` (JSON Schema draft-2020-12); this prose document is the human-readable counterpart.

## Macro-phase model

`current_phase` tracks the **sprint-level** position, not per-node progress:

| `current_phase` | meaning |
| --- | --- |
| `0`, `1`, `2` | lead-side, single-threaded (pre-flight, plan review, graph synthesis) |
| `"execute"` | the wave loop is running Phases 3 – 6 per node; **`graph.json` node records are authoritative** for which node is at which sub-phase |
| `7` | wave finalize (integration → target + cleanup) |

There is no single `current_phase` value for "Phase 3" / "Phase 4" etc. under graph mode — different nodes sit at different sub-phases simultaneously, and each node's sub-phase lives in its `graph.json` record (`phase` field, `3`–`6`, or `null` when not executing). Under `scheduling: sequential` the legacy integer-only progression (`3`,`4`,`5`,`6`) still applies and `graph.json` is absent.

## `state.json` — schema

Changes from the pre-graph schema: `current_phase` now accepts the string `"execute"` in addition to integers; `scheduling`, `worktree_strategy`, and `graph_path` are added (the last is required when `scheduling == "graph"`). `sprint_branch` denotes the **integration branch** and `worktree_path` the **integration worktree** under graph mode. `iterations.coverage` is sprint-level only under sequential mode; under graph mode the per-node coverage counters live in `graph.json` (the sprint-level field is retained for back-compat and may stay `0`). `iterations.review_fix`, by contrast, is written at sprint level in **both** scheduling modes, because Phase 7 runs after the graph drains (see `phase-execute.md:52`). `current_story_id` is deprecated under graph mode (graph.json is authoritative). Under graph mode `story_commits[]` is written **only by the lead at integrate time** (integration merges are serialized, so lead-side writes cannot race) — node executors never write `state.json` (see the Node-executor contract in `$PHASES/phase-execute.md`).

`$SCRIPTS/state.schema.json` (JSON Schema draft-2020-12) is the **authoritative machine schema and single source of truth** for `state.json`'s shape; this section documents it in prose rather than duplicating the JSON. `additionalProperties` is `true` (unknown keys pass through untouched), and `state.sh`'s `_validate_state` smoke-checks a subset of these constraints on every write.

**Required top-level keys:** `plan_path`, `plan_slug`, `worktree_name`, `target_branch`, `worktree_path`, `artifact_dir`, `started_at`, `current_phase`, `iterations`, `repo_root`. When `scheduling == "graph"`, `graph_path` and `sprint_branch` are additionally required.

| property | type | notes |
| --- | --- | --- |
| `plan_path` | string | source plan the sprint tracks |
| `plan_slug` | string | slug derived from the plan filename |
| `worktree_name` | string | sprint worktree name |
| `target_branch` | string | branch the sprint ultimately merges into |
| `worktree_path` | string | integration worktree path under graph mode |
| `artifact_dir` | string | `$ART` — e.g. `.team-sprint/sprints/<worktree_name>` |
| `started_at` | string | ISO-8601 UTC init timestamp |
| `current_phase` | integer ≥ 0 or `"execute"` | sprint-level position; `"execute"` marks the wave loop |
| `repo_root` | string | shared main-repo root (not the worktree) |
| `scheduling` | string | `"graph"` or `"sequential"` |
| `worktree_strategy` | string | `"per-node"` or `"single"` |
| `graph_path` | string | path to `graph.json`; required under graph mode |
| `iterations` | object | `{ adversarial, coverage, review_fix }`, each integer ≥ 0; `adversarial` is seeded at Phase 1 from the planner's provenance stamp, then incremented by Phase 2 graph-review rounds |
| `crew` | object | resolved agent crew for the sprint |
| `crew_commands` | object | per-role command overrides for the crew |
| `subskill_hooks` | array | hook records `{ skill, command, required, phase, source }` |
| `story_commits` | array | `{ story_id, sha }` per committed story |
| `gates` | array | `{ coverage_gate, reason, story_id }` gate waivers |
| `workflow_runs` | object | `phase-<n>` → workflow run id (string); written by `state.sh record-workflow`, latest run wins |
| `graphify_degraded` | boolean | graphify subskill ran in degraded mode |
| `done` | boolean | sprint finalised |
| `finalised_at` | string | ISO-8601 UTC finalise timestamp |
| `sprint_branch` | string | integration branch under graph mode |
| `current_story_id` | string | deprecated under graph mode (`graph.json` is authoritative) |
| `supersedes_plan` | string | prior plan this sprint replaces |
| `plan_final` | string | path to the finalised plan |

`state.sh`'s `_validate_state` enforces only presence + top-level types + the `iterations` sub-fields (and `current_phase ∈ integer ∪ {"execute"}`); it does not check the inner item shapes of `subskill_hooks` / `story_commits` / `gates`. For those, `state.schema.json` is authoritative.

`workflow_runs` entries are recorded via `bash "$SCRIPTS/state.sh" record-workflow "$plan_path" phase-<n> "<run_id>"`. A per-phase journal/transcript artifact is deliberately not recorded — deferred pending verification of the Workflow tool's return shape.

### Example instance — graph mode (`execute`)

```json
{
  "plan_path": "docs/plans/sprint-team-sprint-mech-refactor-v3.md",
  "plan_slug": "sprint-team-sprint-mech-refactor-v3",
  "worktree_name": "sprint-sprint-team-sprint-mech-refactor-v3",
  "target_branch": "main",
  "worktree_path": "/repo/example-sprint-team-sprint-mech-refactor-v3",
  "artifact_dir": ".team-sprint/sprints/<worktree_name>",
  "started_at": "2026-05-20T00:00:00Z",
  "current_phase": "execute",
  "scheduling": "graph",
  "worktree_strategy": "per-node",
  "graph_path": ".team-sprint/sprints/sprint-sprint-team-sprint-mech-refactor-v3/graph.json",
  "sprint_branch": "sprint/sprint-sprint-team-sprint-mech-refactor-v3",
  "iterations": { "adversarial": 2, "coverage": 0, "review_fix": 0 },
  "repo_root": "/repo/example"
}
```

(`sprint_branch` is the integration branch; node branches are `<sprint_branch>-<node-id>` — sibling refs, since git forbids a slash-nested node ref under the existing `<sprint_branch>` ref. `worktree_path` is the integration worktree; node worktrees are `<worktree_path>-<node-id>`.)

## `graph.json` — schema

Present only under `scheduling: graph`. Written by `build_graph.sh` at Phase 2, then mutated in place by the controller throughout `execute` (the only authoritative record of node progress). `nodes` form a DAG; `order` caches the topological sort.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://anthropic.com/skills/team-sprint/graph.schema.json",
  "title": "team-sprint graph.json",
  "type": "object",
  "required": ["graph_version", "scheduling", "generated_at", "nodes"],
  "additionalProperties": true,
  "properties": {
    "graph_version":       { "type": "integer", "minimum": 1 },
    "scheduling":          { "const": "graph" },
    "generated_at":        { "type": "string" },
    "max_parallel_agents": { "type": "integer", "minimum": 1 },
    "integration_branch":  { "type": "string" },
    "order": {
      "type": "array",
      "items": { "type": "string" },
      "description": "cached topological order of node ids"
    },
    "nodes": {
      "type": "array",
      "items": { "$ref": "#/$defs/node" }
    }
  },
  "$defs": {
    "node": {
      "type": "object",
      "required": ["id", "title", "status", "depends_on", "touches"],
      "additionalProperties": true,
      "properties": {
        "id":            { "type": "string" },
        "title":         { "type": "string" },
        "status": {
          "enum": ["pending", "ready", "in_progress", "committed", "done", "failed", "blocked"]
        },
        "phase": {
          "oneOf": [
            { "type": "integer", "minimum": 3, "maximum": 6 },
            { "type": "null" }
          ],
          "description": "active per-node sub-phase (3-6) while in_progress, else null"
        },
        "depends_on":    { "type": "array", "items": { "type": "string" }, "description": "effective edges = declared_deps union inferred_deps" },
        "declared_deps": { "type": "array", "items": { "type": "string" }, "description": "from ### Depends On:" },
        "inferred_deps": { "type": "array", "items": { "type": "string" }, "description": "from ### Touches: glob overlap" },
        "touches":       { "type": "array", "items": { "type": "string" } },
        "branch":        { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "sprint/<worktree_name>-<id> (sibling ref of the integration branch); null until ready" },
        "worktree":      { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "ephemeral; null until spawned, cleared on teardown" },
        "base_commit":   { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "integration HEAD sha the node branched from, passed by the lead at claim; the node's diff base (per_story_diff.sh TS_DIFF_BASE / coverage_check.sh --diff-base); null until claimed" },
        "commit":            { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "node-branch HEAD sha at `committed`" },
        "integrated_commit": { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "merge commit on integration branch at `done`" },
        "iterations": {
          "type": "object",
          "properties": {
            "coverage":   { "type": "integer", "minimum": 0 },
            "review_fix": { "type": "integer", "minimum": 0 }
          }
        },
        "attempts":   { "type": "integer", "minimum": 0, "description": "incremented each time an orphaned node is reset to pending on resume" },
        "blocked_by": { "oneOf": [ { "type": "string" }, { "type": "null" } ], "description": "the failed node whose failure blocked this one" },
        "started_at": { "oneOf": [ { "type": "string" }, { "type": "null" } ] },
        "done_at":    { "oneOf": [ { "type": "string" }, { "type": "null" } ] }
      }
    }
  }
}
```

### Example instance — 4-node graph mid-execute

```json
{
  "graph_version": 1,
  "scheduling": "graph",
  "generated_at": "2026-05-20T00:11:00Z",
  "max_parallel_agents": 4,
  "integration_branch": "sprint/sprint-sprint-team-sprint-mech-refactor-v3",
  "order": ["9", "11", "12", "13"],
  "nodes": [
    {
      "id": "9", "title": "Extract mech config loader",
      "status": "done", "phase": null,
      "depends_on": [], "declared_deps": [], "inferred_deps": [],
      "touches": ["src/mech/config/**"],
      "branch": "sprint/sprint-sprint-team-sprint-mech-refactor-v3-9",
      "worktree": null, "base_commit": "0f1e2d3",
      "commit": "a1b2c3d", "integrated_commit": "e4f5a6b",
      "iterations": { "coverage": 1, "review_fix": 0 },
      "attempts": 0, "blocked_by": null,
      "started_at": "2026-05-20T00:12:00Z", "done_at": "2026-05-20T00:24:00Z"
    },
    {
      "id": "11", "title": "Refactor mech state machine",
      "status": "in_progress", "phase": 4,
      "depends_on": ["9"], "declared_deps": ["9"], "inferred_deps": [],
      "touches": ["src/mech/state/**"],
      "branch": "sprint/sprint-sprint-team-sprint-mech-refactor-v3-11",
      "worktree": "/repo/example-sprint-team-sprint-mech-refactor-v3-11",
      "base_commit": "e4f5a6b",
      "commit": null, "integrated_commit": null,
      "iterations": { "coverage": 1, "review_fix": 0 },
      "attempts": 0, "blocked_by": null,
      "started_at": "2026-05-20T00:25:00Z", "done_at": null
    },
    {
      "id": "12", "title": "Wire mech middleware",
      "status": "pending", "phase": null,
      "depends_on": ["9", "11"], "declared_deps": ["11"], "inferred_deps": ["9"],
      "touches": ["src/mech/config/**", "src/mech/middleware/index.ts"],
      "branch": null, "worktree": null, "base_commit": null,
      "commit": null, "integrated_commit": null,
      "iterations": { "coverage": 0, "review_fix": 0 },
      "attempts": 0, "blocked_by": null,
      "started_at": null, "done_at": null
    },
    {
      "id": "13", "title": "Mech telemetry hooks",
      "status": "ready", "phase": null,
      "depends_on": ["9"], "declared_deps": ["9"], "inferred_deps": [],
      "touches": ["src/mech/telemetry/**"],
      "branch": null, "worktree": null, "base_commit": null,
      "commit": null, "integrated_commit": null,
      "iterations": { "coverage": 0, "review_fix": 0 },
      "attempts": 0, "blocked_by": null,
      "started_at": null, "done_at": null
    }
  ]
}
```

In this snapshot node `9` is `done` (merged); `11` is executing Phase 4 in its worktree; `13` is `ready` (its only dep `9` is done) and is the next spawn candidate; `12` stays `pending` because `11` isn't `done` yet. Note `12.depends_on` is the union `["9","11"]` — `9` arrived via `Touches` overlap on `src/mech/config/**` and is recorded in `inferred_deps`. Note also `11.base_commit == 9.integrated_commit`: node 11 branched off the integration HEAD after 9's merge, and that sha is exactly the diff base its executor passes to `per_story_diff.sh` (`TS_DIFF_BASE`) and `coverage_check.sh` (`--diff-base`).

## Node lifecycle

`pending → ready → in_progress → committed → done`, plus `failed` and `blocked`. Transitions:

- **pending → ready** — every dependency reached `done` (scheduler-derived; not persisted as a separate gate).
- **ready → in_progress** — scheduler spawned a teammate; `branch`/`worktree`/`started_at` set, `base_commit` records the integration HEAD sha the lead passed to `schedule.sh claim` (the node's diff base), `phase` tracks 3→6.
- **in_progress → committed** — Phase 6 commit landed on the node branch; `commit` set.
- **committed → done** — lead merged the node branch into the integration branch (serialized, re-gated) via `schedule.sh integrate`; `integrated_commit`/`done_at` set, `worktree` cleared. The lead records the story's `{story_id, sha}` in `state.json.story_commits[]` here — the only `story_commits` writer under graph mode (executors never write `state.json`).
- **→ failed** — node executor or integration-merge gate failed.
- **→ blocked** — a transitive dependency `failed`; `blocked_by` records the originating failure; never spawned.

## Resume reconstruction

On a resume that lands in `current_phase: "execute"`, the controller recomputes from `graph.json` (not from `current_phase`, which only says "we're in the wave loop"):

1. **Frontier** — `ready = { n : n.status == pending AND every dep.status == done }`.
2. **Orphan reset** — any node left `in_progress` (its teammate is gone) is reset to `status: "pending"`, `phase: null`, `worktree` retained for inspection, `attempts += 1`. A `committed` node is left as-is — it awaits the serialized merge and is re-integrated, not re-run. Its ephemeral worktree, node branch, and `base_commit` are preserved so a human can inspect the partial work before the node re-runs (a re-claim records a fresh `base_commit`).
3. **Preserved** — `done`, `committed`, `failed`, `blocked` are left as-is. A `committed`-but-not-`done` node simply needs its integration merge re-attempted by the lead.
4. **Drain check** — if no node is `ready`/`in_progress`/`committed` and none remain `pending`, the graph is drained → advance to Phase 7. If `pending` nodes remain with no `ready`/running node, that's a deadlock → STOP, surface the blocking subgraph.

The shared TaskList is a **projection** of `graph.json`, not a second source of truth — on resume it is rebuilt from `graph.json`, never the reverse.

## Validator notes

`state.sh`'s runtime validator enforces a subset (presence + top-level types + iteration sub-fields) and is a fast smoke-check only; the JSON Schema above is the source of truth. Two changes are required in `scripts/state.sh` for graph mode:

- accept `current_phase: "execute"` (the smoke-check currently assumes an integer);
- accept and pass through `scheduling`, `worktree_strategy`, `graph_path` on `update`/`advance-phase`.

`graph.json` has no bash smoke-checker; `build_graph.sh` is responsible for emitting a schema-valid file and is the only writer at creation time, after which the controller mutates node records in place.

## Resume contract (summary)

If a sprint dies mid-flight, the next invocation discovers it by scanning `.team-sprint/sprints/*/state.json` and resumes the one matching `plan_path`. For `current_phase ∈ {0,1,2,7}` it resumes at that phase; for `current_phase == "execute"` it reconstructs the frontier from `graph.json` per the rules above.

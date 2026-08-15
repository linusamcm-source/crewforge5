**WHO READS THIS / WHEN:** Phase 0 reads this when resolving `team-sprint.config.yaml.subskill_hooks` into `state.json`; the lead reads it at every active phase (0, 2, 3, 4, 6, 7) before invoking `$SCRIPTS/run_subskill_hooks.sh`; sub-skill authors read it when writing a hook command that needs the TS_* contract; reviewers read it when assessing whether a hook entry is well-formed.

### Sub-skill hook contract (v1.0)

Sub-skill hooks are user-declared shell commands that the lead runs at stable, post-work commit points inside an active phase. The contract is small, additive, and fail-soft. As of v1.0 **no canonical sub-skill consumer ships** — the contract is the extension surface. The `integration-diagram` skill is a planned future consumer; its plan is authored in a separate sprint.

### Hook phases

Six phases run hooks. Each phase commits a different slice of sprint state before its hooks fire; choose the phase whose committed state your hook needs to read.

| Phase | Phase doc | State committed before hooks fire |
|-------|-----------|------------------------------------|
| 0 | `$PHASES/phase-0.md` | `state.json` initialised; `subskill_hooks` array merged + persisted; repomix pack fresh. |
| 2 | `$PHASES/phase-2.md` | Worktree exists on `sprint_branch`; team provisioned; `$ART/stories.json` populated. |
| 3 | `$PHASES/phase-3.md` | Per-story TDD GREEN + coverage gate passed (or disabled); typecheck + lint clean. |
| 4 | `$PHASES/phase-4.md` | Parallel reviewers delivered findings; `$ART/reviews-<story-id>-round-<N>.md` aggregated. |
| 6 | `$PHASES/phase-6.md` | Story commit landed on `sprint_branch`; the lead-side `state.json.story_commits[]` update is performed BEFORE the hook fires (see `$PHASES/phase-6.md` step 7). |
| 7 | `$PHASES/phase-7.md` | Sprint merged into `target_branch`; sprint report finalised; `done == true` about to flip. |

**Phases 1 and 5 are RESERVED.** Their phase docs carry the `<!-- subskill-hooks:phase-N -->` marker for layout uniformity (mech-9 + mech-14 lint), but `subskill_hooks.phase-1` and `subskill_hooks.phase-5` blocks are unsupported in v1.0 — sub-skills should observe stable states, not in-flight ones. A future minor version may activate these without a marker-layout change. Entries declared under those keys at Phase 0 are silently dropped with one INFO log line.

### Field semantics

```yaml
subskill_hooks:
  phase-6:
    - skill: my-skill                                 # metadata + preflight probe target
      command: 'bash /path/to/my-skill/run.sh' # actual shell line, always runs
      required: false                                  # optional; defaults to false
```

- **`skill`** — metadata. Doubles as the `preflight_subskills.sh` probe target and the log label written to `$ART/subskill-phase-N.log`. **`skill` may be set to a non-existent string for tests** (e.g. `skill: noop`) — its only effect is the preflight probe (which can be skipped with `--probe-fn` or made non-fatal by leaving `required: false`), never gating.
- **`command`** — the shell line executed when the hook fires. **`command` is authoritative** — it always runs when the hook fires, regardless of whether the `skill` preflight passed. Runs in the worktree dir with the TS_* env vars set (see below). Captured stdout+stderr is appended to `$ART/subskill-<phase-N>.log`.
- **`required`** — optional boolean, defaults to `false`. Honoured **at preflight time only** (`preflight_subskills.sh --probe-all`); a `required: true` skill whose probe fails aborts Phase 0. At hook-run time `required` is ignored — the run layer is always fail-soft (see "Fail-soft policy" below).

One-line example:

```yaml
subskill_hooks: { phase-6: [{skill: my-skill, command: 'bash /path/to/my-skill/run.sh'}] }
```

### TS_* contract env vars

Each hook command is invoked with the following env vars exported. They are the **only** cross-phase contract between team-sprint and a hook command:

| Env var | Meaning |
|---------|---------|
| `TS_PLAN_PATH` | Plan file path (whatever was passed to the sprint, normalised to absolute when possible). |
| `TS_STORY_ID`  | Current story id (`state.json.current_story_id`); empty for pre-story phases. |
| `TS_TASK_ID`   | Phase identifier as `phase-N` (e.g. `phase-6`). |
| `TS_ART_DIR`   | Absolute `$ART` path for this sprint. |
| `TS_WORKTREE`  | Absolute worktree path; empty when invoked before Phase 2 sets `worktree_path`. |

**Namespace invariant (locked).** All hook env vars stay under the `TS_*` prefix. Future additions stay in this namespace; collisions with `GIT_*`, `BATS_*`, or POSIX-standard names are forbidden. Adding a new TS_* var is a state-schema change — bump `$SCRIPTS/schemas/state.schema.json` and update this doc.

### Fail-soft policy

`$SCRIPTS/run_subskill_hooks.sh` **always exits 0**. A failing hook command:

- Has its non-zero rc logged to `$ART/subskill-<phase-N>.log` (`END rc=<n>`).
- Does **not** abort the phase, the story, or the sprint.
- Does **not** prevent subsequent hooks in the same phase from running — when two hooks are declared and the first fails, the second still fires.

As of v1.0 there is **no strict mode** for hooks. Users who need CI-style strictness today must wrap their `command` to fail loudly themselves (e.g. `command: 'bash my-hook.sh || (echo HOOK FAILED >&2 && false)'` — still won't abort the sprint, but their CI log will flag it). A future minor version may add `subskill_hooks.strict_phases: [phase-N, …]`.

### Preflight (`preflight_subskills.sh`)

Phase 0 step 10.3 probes every entry in the merged `state.json.subskill_hooks` list **before** any hook can fire:

```bash
bash "$SCRIPTS/preflight_subskills.sh" --probe-all "$plan_path"
```

- **Default probe** is a pure-shell filesystem check: `test -f "$HOME/.claude/skills/<skill-name>/SKILL.md"`. Pure shell deliberately — bash scripts cannot invoke Claude's Agent/Skill tool, and the filesystem probe is portable, fast, and deterministic.
- **`--probe-only <skill-name>`** — single-skill probe used for graceful-degrade flows (e.g. `integration_diagram: auto`). Exit 0 if present, exit 1 if absent.
- **`--probe-fn <path-to-script>`** — injection point used by bats fixtures to supply canned verdicts without touching the filesystem. The script is invoked as `<probe-fn> <skill-name>`; exit 0 = present, non-zero = absent.

**Optional lead-side cache enrichment.** The lead orchestrator (Claude) MAY perform an additional Skill/Task-tool probe before invoking `preflight_subskills.sh` and write the enriched verdict to `$ART/preflight-cache.json`. **Cache schema (pinned):**

```json
{
  "<skill-name>": {
    "present":   true,
    "probed_at": "2026-05-20T12:34:56Z",
    "source":    "agent-tool"
  }
}
```

- Keys are skill names; values are per-skill verdicts.
- `present` is a boolean; `probed_at` is ISO-8601 UTC; `source` is `"agent-tool"` for lead-side enrichment.
- **Cache verdict wins over filesystem** when both have a definitive answer for the same skill name (the lead's Skill-tool probe is the higher-confidence signal by design).
- **Absent skill names fall back to filesystem** — partial enrichment is supported; the cache need not list every skill.
- The cache is purely optional — the production default does NOT depend on it. `--probe-fn` injection still wins over both (test isolation).

### Required-flag honouring

`--probe-all` honours per-entry `required` at preflight time:

- `required: true` + probe fail → exit 1; Phase 0 ABORTs (lead surfaces the failing skill name in the error).
- `required: false` (default) + probe fail → log a WARN line `subskill probe FAILED (optional): <name> — hook will still attempt to run (command is authoritative)` and exit 0.

The run layer (`run_subskill_hooks.sh`) does NOT consult `required` — see "Fail-soft policy" above.

### State persistence

Phase 0 step 10 writes the resolved hook list to `state.json.subskill_hooks` as a flat array; each entry carries `skill`, `command`, `required`, `phase` (string `"phase-N"`), and `source` (`"user"` for YAML-declared, `"auto"` for auto-prepended). The schema lives at `$SCRIPTS/schemas/state.schema.json`. See also `$REF/state-schema.md`.

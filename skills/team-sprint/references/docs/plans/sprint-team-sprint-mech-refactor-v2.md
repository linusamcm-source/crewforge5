# Sprint: team-sprint Mechanical Refactor v2 (`team-sprint-mech`)

**Supersedes:** `sprint-team-sprint-mech-refactor.md` (v1, 2026-05-20).
**Goal:** Same v1 goal — optimise `~/.claude/skills/team-sprint` by extracting mechanical pseudocode into executable scripts, splitting SKILL.md into per-phase docs, tightening defaults, closing contract gaps — **plus** reserve a stable extension surface so the per-project `integration-diagram` skill (see `sprint-integration-diagram-skill-v2.md`) can plug into team-sprint without further refactor.

**Target directory:** `~/.claude/skills/team-sprint/`
**Target branch:** `develop` (or `main` if the skills repo has no `develop`)
**Out of scope:** Per-repo `team-sprint` variants under `~/Development/*`; new sub-skills; rewriting `validate_plan_path.sh` (interface stable); the `integration-diagram` skill itself (separate sprint).

**Why v2 exists:** v1 of this plan was scoped before `integration-diagram` (IDS) was specified. IDS Story IDS-6 patches the global team-sprint SKILL.md — but mech-9 in this sprint splits that very file into `phases/phase-{0..7}.md`. Without v2 coordination, the IDS-6 patch text targets a layout that no longer exists. v2 reserves named anchor points in the post-split phase docs, exposes a `subskill_hooks` config block, and adds a preflight probe for `integration-diagram` so the two skills compose cleanly.

**Deployment ordering (cross-sprint contract):** This sprint **must merge before** the `integration-diagram` sprint starts. IDS-6 is written against the post-mech layout. If this sprint is paused or aborted partway, IDS sprint is blocked at Phase 0.

**Conventions for this plan:** unchanged from v1 — `$SKILL_DIR`, `$SCRIPTS`, `$PHASES`, `$REF` aliases; bash 3.2-safe; `set -euo pipefail`; bats fixtures under `scripts/tests/`.

---

## Stories mech-1 … mech-14

**Unchanged from v1**, with the following targeted amendments. Apply v1 acceptance criteria + DoD as written, then layer the v2 deltas below.

### mech-1 amendment — state schema accommodates sub-skills

- `state.schema.json` adds an **optional** top-level field `subskills: { [skill_name]: { enabled: bool, last_event_id?: string, last_artifact_sha?: string } }`. Additive only — sprints started under v1 schema remain readable (the field defaults to `{}` when absent).
- `state.sh update <plan_path> subskills.integration-diagram.last_event_id=<id>` resolves nested keys via `jq` setpath; bats fixture covers a nested update without clobbering siblings.

### mech-9 amendment — phase docs carry named extension anchors

Each `$PHASES/phase-N.md` includes a `## Extensions` section at the bottom with a stable HTML anchor:

```markdown
## Extensions
<!-- subskill-hooks:phase-N -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-N` run here, fail-soft. Each hook is `{skill: <name>, command: <cli>}`. team-sprint invokes them after the phase's main work completes, ignoring non-zero exits and continuing.
```

The literal HTML comment markers `<!-- subskill-hooks:phase-N -->` are the patch anchors IDS-6 keys off. mech-14's `lint_skill.sh` asserts the marker is present in every phase doc.

### mech-12 amendment — subskill_hooks config block

In addition to v1's new config fields, add:

```yaml
subskill_hooks:
  phase-0:  []
  phase-2:  []   # bootstrap point (was "Phase 2.5" in IDS v1)
  phase-3:  []   # per-task gate point
  phase-4:  []   # post-review point
  phase-6:  []   # per-story commit point
  phase-7:  []   # finalize point
integration_diagram: auto    # auto | on | off; auto = on iff the skill resolves
```

- `auto` resolution: Phase 0 probes whether `integration-diagram` is loadable by a subagent; on success, prepends its hook spec into `subskill_hooks.phase-{0,2,3,4,6,7}` for the duration of the sprint. The user's explicit `subskill_hooks` entries are preserved and merge-deduped.
- `off` short-circuits the probe and the merge — useful for sprints where the diagram would be noise.
- The merged hook list is logged once at Phase 0 exit so the audit trail shows exactly which hooks ran.

### mech-13 amendment — preflight probes every declared subskill

v1 added a preflight probe for `adversarial-review`. v2 generalises: Phase 0 probes every skill named in `subskill_hooks.*[].skill` plus `integration-diagram` (when enabled). Probe = spawn a `general-purpose` subagent with `Skill` tool access; ask it to list skills and confirm presence; abort Phase 0 if any required skill is missing (warn + continue if `integration_diagram: off`).

### mech-14 amendment — `lint_skill.sh` covers extension anchors

`lint_skill.sh` gains three checks on top of v1:

1. Every `$PHASES/phase-N.md` contains the literal `<!-- subskill-hooks:phase-N -->` marker exactly once (for N ∈ {0,2,3,4,6,7}; phases 1 and 5 are optional but if present must follow the same form).
2. `team-sprint.config.yaml.example` (new file) contains the full `subskill_hooks` block + the `integration_diagram` knob.
3. `$REF/subskill-hooks.md` (new file) documents the hook contract: invocation timing, working directory, env vars passed (`TS_PLAN_PATH`, `TS_STORY_ID`, `TS_TASK_ID`, `TS_ART_DIR`, `TS_WORKTREE`), fail-soft semantics, exit-code policy (lead ignores non-zero, logs to `$ART/subskill-<phase>.log`).

---

## NEW Story mech-15: Stable extension surface for sub-skills

### Context
The amendments above are spread across mech-1, mech-9, mech-12, mech-13, mech-14. Bundling them into a dedicated story keeps each prior story focused on its v1 contract and gives the cross-sprint integration with `integration-diagram` a single review surface. mech-15 ships after mech-14 so the lint added in mech-14 immediately validates the artifacts mech-15 produces.

### Acceptance Criteria

- `$REF/subskill-hooks.md` exists and documents:
  - The six hook phases (0, 2, 3, 4, 6, 7) and what state is committed at each one.
  - The contract env vars listed in the mech-14 amendment.
  - The fail-soft policy in one paragraph + a one-line example invocation.
  - Cross-link to `sprint-integration-diagram-skill-v2.md` as the canonical first consumer.
- `$SKILL_DIR/team-sprint.config.yaml.example` exists, contains the full v1 + v2 config surface, and is referenced from SKILL.md Phase 0.
- A new helper `$SCRIPTS/run_subskill_hooks.sh <phase> <plan_path>` reads merged hook list from state.json (Phase 0 writes the resolved list there), invokes each hook in declaration order with the contract env vars set, captures stdout+stderr to `$ART/subskill-<phase>.log`, and **always exits 0**. Bats fixture covers: zero hooks (no-op), one passing hook, one failing hook (logged, exit still 0), two hooks where the first fails (second still runs).
- `phase-{0,2,3,4,6,7}.md` invoke `run_subskill_hooks.sh` as their final step, after the phase's main work but before advancing `current_phase`.
- The preflight probe from the mech-13 amendment lives at `$SCRIPTS/preflight_subskills.sh`; bats fixture mocks subagent probe results for present-skill, missing-skill, and `integration_diagram: off` cases.
- An ADR-style note at `$SKILL_DIR/docs/adr/001-subskill-extension-surface.md` records: why hook phases were chosen (matches the IDS-6 patch points), why fail-soft (sub-skills can never block the main sprint), why env vars over stdin (subagents and shell commands both consume env naturally).

### Definition of Done

- `shellcheck` clean on `run_subskill_hooks.sh` and `preflight_subskills.sh`.
- `lint_skill.sh` passes (i.e. all mech-14 checks plus the v2 amendments).
- A dry-run sprint with `subskill_hooks: { phase-6: [{skill: noop, command: 'true'}] }` shows the hook fires once per story commit and the log file contains the expected single line.
- A dry-run sprint with `integration_diagram: off` skips all diagram-related probes and hooks; `git log` shows no diagram artifacts.
- ADR note linked from SKILL.md's "Architecture & decisions" section (added once in mech-9; v2 adds the link).

---

## Cross-story invariants (apply to every story, v2)

All v1 invariants apply, plus:

- **The sub-skill hook contract is additive only.** Future sub-skills add to `subskill_hooks` without modifying the contract; never break it.
- **Hook env vars are versioned implicitly through `state.schema.json`.** Adding a new env var requires bumping the schema and updating `$REF/subskill-hooks.md`; removing one is a breaking change and forbidden in any patch release.
- **`integration_diagram` is the canonical reference consumer.** When designing future hook points, sanity-check them against the IDS sprint's needs first.

## Sprint-level Definition of Done (v2)

All v1 sprint-DoD items, plus:

- `lint_skill.sh` passes with mech-15 artifacts present.
- A fixture sprint that enables `integration_diagram: auto` (with the skill stubbed as a no-op shell script in PATH) runs Phase 0 → Phase 7 with zero non-zero exits from the hook layer.
- CHANGELOG v1.0 entry calls out the extension surface and points readers at `$REF/subskill-hooks.md`.

## Surfaced risks (v2 additions)

- **Hook list resolution at Phase 0 is the single coordination point with IDS.** If a future change moves resolution to a later phase, IDS's `init` step loses its bootstrap signal. Lock this into the ADR in mech-15.
- **`auto` mode hides the diagram skill's presence.** Users who didn't ask for diagrams may be surprised by commits to `*.integration.drawio`. Mitigation: Phase 0 logs "integration-diagram: enabled (auto-detected)" prominently; IDS sprint provides an explicit opt-out flag in addition to `integration_diagram: off`.
- **Env-var contract surface grows over time.** Cap it: any addition past v1 of the hook contract requires an ADR note explaining why the data wasn't already derivable from `TS_PLAN_PATH` + `TS_ART_DIR`.

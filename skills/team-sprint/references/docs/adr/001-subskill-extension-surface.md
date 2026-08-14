# ADR-001: Sub-skill extension surface

**Status:** Accepted (v1.0)
**Date:** 2026-05-20
**Deciders:** team-sprint skill maintainers

## Context

team-sprint is a project-agnostic orchestrator. Teams that adopt it will
inevitably want to chain in project-specific behaviour at specific points
during a sprint — diagram generation, doc updates, notification emitters,
project-internal validators. Hard-coding every such consumer into the
core skill is untenable; each new consumer would expand SKILL.md and the
phase docs without benefit to projects that don't need it.

We need a stable, narrow, additive extension surface that:

1. Lets users declare `<phase, command>` pairs in their per-repo config.
2. Runs those commands at well-defined, stable commit points within the
   sprint pipeline.
3. Does not let a misbehaving extension wedge the sprint.
4. Survives the team-sprint skill's own internal refactors — the contract
   between team-sprint and an extension is small and locked.

As of v1.0 there is **no canonical sub-skill consumer**. The contract IS
the deliverable. A planned `integration-diagram` skill is documented as
a future consumer; its plan is authored in a separate sprint.

## Decision

Adopt the **`subskill_hooks` map + `TS_*` env contract** documented in
`$REF/subskill-hooks.md`. Six phases run user-declared hook commands at
their final step:

- **Phase 0** — after `state.json` is initialised and the subskill list is merged.
- **Phase 2** — after the worktree + team are provisioned and `stories.json` is parsed.
- **Phase 3** — after per-story TDD GREEN + coverage gate.
- **Phase 4** — after the parallel-review report is aggregated.
- **Phase 6** — after the per-story commit lands.
- **Phase 7** — after the final merge and sprint report.

A driver script `$SCRIPTS/run_subskill_hooks.sh <phase> <plan_path>` reads
`state.json.subskill_hooks`, filters by phase, and invokes each entry's
`command` in declaration order with the `TS_*` env vars set, in the
worktree directory. Stdout + stderr append to `$ART/subskill-<phase>.log`.

A separate `$SCRIPTS/preflight_subskills.sh` probes presence at Phase 0
using a pure-shell filesystem check (with `--probe-fn` injection for tests
and an optional `$ART/preflight-cache.json` for lead-side enrichment).

## Why hook phases were chosen

The selected phases are the **natural stable commit points** of the
pipeline. State at each is durable and the work that produced it has
already passed its own quality gate:

- Phase 0 — pre-flight done, state.json initialised.
- Phase 2 — worktree setup done.
- Phase 3 — per-story TDD done, coverage gate green.
- Phase 4 — post-review aggregation done.
- Phase 6 — per-story commit landed.
- Phase 7 — final merge + finalise.

Hooks fire at the end of each phase, after the phase's own work is
committed but before `current_phase` is advanced. This guarantees a
sub-skill observes a state that the sprint itself considers consistent.

## Why phases 1 and 5 carry markers but NO config blocks in v1.0

Phase 1 (adversarial plan review) and Phase 5 (fix loop) are both
**mid-iteration**: their work is a sequence of revisions that the lead
re-runs until clean. A sub-skill observing partway through would see a
draft state that may never ship. Sub-skills should observe stable states,
not in-flight ones.

We still emit the `<!-- subskill-hooks:phase-1 -->` / `phase-5` markers in
those phase docs so the layout is uniform across all 8 phases (mech-9 +
mech-14 lint depend on the marker count). The markers are **reserved** —
the lead does not invoke `run_subskill_hooks.sh` from phase-1.md or
phase-5.md, and Phase 0 step 10.4 silently drops any entries declared
under `phase-1` / `phase-5` in user config with one INFO log line.

This decision resolves the round-2 contradiction between an early ADR
draft's opt-in language ("hooks fire only on phases that opt in") and
mech-9/mech-14's "all 8 markers mandatory" lint rule. The marker is a
structural lint artifact; the config block is a behavioural opt-in. They
are decoupled.

A future minor version may activate phase-1 / phase-5 without requiring
a marker-layout change. The schema stays additive.

## Why fail-soft

`run_subskill_hooks.sh` **always exits 0**. A hook command's failure is
logged but never propagates. Rationale:

- **Sub-skills must never block the main sprint.** A sprint that's blocked
  by a third-party diagram script is a regression versus running without
  the script at all. The user can always look at the log and fix.
- **Reproducibility.** A flaky hook should not turn into a flaky sprint.
- **Strict mode is forward-compatible.** A future minor version may add
  `subskill_hooks.strict_phases: [phase-N, …]` to opt specific phases
  into a fail-loud mode. v1.0 has none; users who need CI-style strictness
  today must wrap their `command` to fail loudly themselves.

Note: `required: true` at preflight time DOES gate. A required sub-skill
that's missing aborts Phase 0 — that's preflight, not runtime. The
distinction matters: preflight is about "the user's intent is to use
this skill", runtime is about "the command happens to fail this time".

## Why env vars over stdin

Hook commands consume their context from **`TS_*` env vars**, not from
stdin. Rationale:

- **Subagents and shell commands both consume env naturally.** A hook
  command might be a one-line shell script, a Python invocation, or a
  spawn of another Claude skill — all of them read env vars cleanly.
- **Stdin is single-use.** A hook command that reads its own input
  (e.g. `xargs`, `jq -s`, an interactive prompt) would conflict with any
  attempt by team-sprint to push context via stdin.
- **Env vars are introspectable.** `printenv TS_STORY_ID` from inside a
  hook works without parsing anything; stdin-based contexts require the
  command to know its own ingestion grammar.
- **Schema-pinned.** Adding a new env var requires bumping
  `state.schema.json`; the contract is explicit.

## TS_* namespace invariant (locked)

All hook env vars stay under the `TS_*` prefix. Collisions with `GIT_*`,
`BATS_*`, or POSIX-standard names are forbidden. Adding a new TS_* var
is a state-schema change — bump `$SCRIPTS/state.schema.json` and update
`$REF/subskill-hooks.md`. Removing one is a breaking change forbidden in
any patch release.

This is the single most important invariant of the contract: the entire
extension surface is `subskill_hooks: { phase-N: [{skill, command}] }` +
the `TS_*` env vars. Everything else is implementation detail and may
change.

## Consequences

- Project-specific behaviour can be chained in without touching SKILL.md.
- v1.0 ships the surface with **zero canonical consumers**. The cost is
  the script + reference doc + tests; the operational impact is zero
  until someone declares a hook.
- A future `integration-diagram` skill (and any other consumer) plugs in
  via this surface without modifying team-sprint internals.
- Strict-mode hooks are intentionally absent in v1.0. Users who need
  CI-style strictness must wrap their `command` to fail loudly themselves.
- The `TS_*` namespace invariant locks in v1.0; downstream consumers can
  rely on it.

## References

- `$REF/subskill-hooks.md` — full hook contract.
- `$SCRIPTS/run_subskill_hooks.sh` — runtime driver.
- `$SCRIPTS/preflight_subskills.sh` — Phase 0 probe.
- `$SCRIPTS/state.schema.json` — schema for `subskill_hooks` + `subskills`.

# Phase 6 — Draft

**Goal of the phase:** write the plan file `crewforge:execute` will run.

## Steps

1. Load the planner's body — it owns the plan contract, the story shape and the
   acceptance-criteria discipline:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" team-sprint-planner
   ```

2. Choose the filename before writing a line of it. It must carry a story or
   epic id — `epic-1-three-skill-condensation.md`, `bug-42-stale-lock.md`. Bare
   `plan.md` is rejected by the gate, because the sprint directory is derived
   from the filename and two `plan.md`s collide into one sprint.
3. Write the plan under `docs/plans/`, including the debt-coverage table: one row
   per finding ID that phase 5 dispositioned into this plan.
4. Record where it landed — the phase 7 and phase 8 gates both read this key:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/flow_state.sh" plan set \
     plan_path docs/plans/<story-id>-<slug>.md
   ```

5. Read the mechanical read-back aloud to the user and let them correct it. The
   gate prints it; the correction is yours to make.

## Gate

`validate_plan_path.sh <plan>` then `plan_readback.sh <plan>`. The first proves
the filename carries an id and does not clobber an existing sprint; the second
proves the file parses into stories with resolvable dependencies. Both run
against the `plan_path` key, so a plan that was never recorded fails here rather
than three phases later.

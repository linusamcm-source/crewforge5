# Phase 8 — Verify

**Goal of the phase:** prove mechanically that the plan kept the promises phase 5
made about existing debt. A disposition table nobody checks is a wish list.

## Steps

1. Run the coverage check over the impact map and the plan:

   ```bash
   bash "${CREWFORGE5_ROOT:-.}/skills/master_plan/scripts/check_coverage.sh" \
     docs/plans/GOAL_IMPACT.md "$(bash "${CREWFORGE5_ROOT:-.}/scripts/flow/flow_state.sh" plan get plan_path)"
   ```

2. It compares finding IDs found in the impact map's table rows against the same
   IDs in the plan's table rows, and reports two failures by name:

   - `MISSING from plan coverage table` — a finding phase 5 dispositioned never
     reached the plan. Add the row, or go back to phase 5 and change the
     disposition; do not delete the finding from the impact map to make the
     check green.
   - `DUPLICATED in plan coverage table` — one ID carries two dispositions, so
     nobody chose.

3. On `CLEAN`, tell the user the plan is deployable and name the next command:
   `/crewforge5:execute <plan path>`.

## Gate

`check_coverage.sh docs/plans/GOAL_IMPACT.md <plan>` — exits 0 with `CLEAN` only
when every intersecting finding ID appears exactly once in the plan. Its stdout
is recorded into `state.json`, so a resumed flow can read which ID was missing
without re-running anything.

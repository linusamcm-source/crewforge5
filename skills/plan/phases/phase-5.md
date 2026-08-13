# Phase 5 — Triage

**Goal of the phase:** decide, once, what this plan does about each piece of
existing debt it will touch — and write the decision down where phase 8 can
check it.

## Steps

1. Load the `master_plan` skill body for the impact-map mechanic:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" master_plan
   ```

   The resolver treats `-` and `_` as interchangeable, so `master-plan` reaches
   the same file.
2. Intersect the goal's touched surface (phase 1) with the audit's findings
   (phase 4). A finding outside the touched surface is not this plan's problem.
3. Write `docs/plans/GOAL_IMPACT.md` with a disposition table — one row per
   **intersecting** finding, each with exactly one disposition:

   ```markdown
   | ID | Finding | Disposition |
   | --- | --- | --- |
   | F001 | intake accepts an empty goal | fix in Story 1 |
   | F002 | coverage table drifts silently | accept, out of scope |
   ```

   `fix in Story N`, `accept` and `defer` are all legitimate. Two dispositions
   for one ID is not — phase 8 counts occurrences, and an ID carrying two
   answers means nobody chose.

## Gate

`test -s docs/plans/GOAL_IMPACT.md`. Phase 8 is where the table is checked
against the plan; this gate only proves the table exists to be checked.

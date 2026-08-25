# Phase 5 — Triage

**Goal of the phase:** decide, once, what this plan does about each piece of
existing debt it will touch — and write the decision down where phase 8 can
check it.

## Steps

1. Load the `master_plan` skill body for the impact-map mechanic:

   ```bash
   bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" master_plan
   ```

   The resolver treats `-` and `_` as interchangeable, so `master-plan` reaches
   the same file. **Take its Phase 2 (impact map) only.** The rest of that body
   is a standalone pipeline whose other phases are this flow's phases 4, 6 and 8
   under different names — re-running them from here re-enters phases this flow
   has already gated or will gate.
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
   for one ID is not — an ID carrying two answers means nobody chose. A goal
   whose touched surface intersects nothing writes a literal
   `No intersecting findings.` line instead of an empty table.

## Gate

`plan_gate.sh triage` — every ID in the table exists in `TECH_DEBT_AUDIT.md`
(an invented ID would sail through phase 8, which only compares this table
against the plan), appears exactly once, and carries a disposition in its row;
zero rows passes only with the explicit `No intersecting findings.` claim.
Phase 8 still checks this table against the plan — this gate proves the table
is worth checking.

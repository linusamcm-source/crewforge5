# Phase 7 — Review

**Goal of the phase:** drive the plan to adversarial-clean, then stamp it. The
stamp is what `crewforge:execute` checks before it will run anything, so it is a
claim about work done, not a formality.

## Steps

1. Load the reviewer's body:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" adversarial-review
   ```

2. Loop: review → annotate each finding into the plan as a
   `<!-- FINDING <id> (<severity>): <recommendation> -->` marker → fold each
   marker into revised prose and delete it → re-review. The loop converges only
   because the markers are deleted; a plan that accumulates them ends up more
   comment than content.
3. When a round produces no new findings, stamp the plan on its own line:

   ```markdown
   <!-- adversarial-review: status=clean rounds=<N> date=<YYYY-MM-DD> reviewer=crewforge:plan -->
   ```

   `status=user-override` is the honest alternative when the user chooses to
   ship with a known open finding. Inventing `status=clean` over an unfolded
   finding is the one failure this phase exists to prevent.

## Gate

`findings_gate.sh <plan>` then a stamp grep. The findings gate fails while any
`<!-- FINDING ` marker remains, so the stamp cannot be reached with a finding
still open, and `flow_next.sh plan` re-offers phase 7 rather than advancing to
phase 8.

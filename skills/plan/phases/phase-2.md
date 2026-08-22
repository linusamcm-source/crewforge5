# Phase 2 — Diverge

**Goal of the phase:** before any decision is argued, make sure there is more
than one candidate. A plan that only ever saw one design cannot claim to have
chosen it.

## Steps

1. List the **open decisions** the goal forces — the ones where two competent
   engineers would reasonably disagree. Settled mechanics are not decisions.
2. Load the `adhd` skill body for the framing mechanic:

   ```bash
   bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" adhd
   ```

   It reports `MODE=inline` under `--load-mode`, so read it here.
3. Run its parallel frames over **each** open decision — one frame set per
   decision, not one set for the whole goal.
4. Write the result to `frames.md` **beside this run's `state.json`** — the
   file is this planning run's working notes, so it is subject-keyed for the
   same reason state is: two concurrent plans must not share it.

   ```bash
   ART="$(dirname "$(bash "${CREWFORGE5_ROOT:-.}/scripts/flow/flow_state.sh" plan path)")"
   # write $ART/frames.md
   ```

   One section per decision, and the shape is load-bearing — the gate parses it,
   and phase 3 matches on the `D<n>` ids:

   ```markdown
   ## D1 — <decision, phrased as a question>
   - Frame A: <candidate> — <what it buys, what it costs>
   - Frame B: ...
   ```

## Skip conditions

The user asked for the quick, standard, canonical or textbook answer. Say so,
write the single frame with the reason on its own `Skip:` line in that section,
and move on — divergence over a settled question is theatre. The `Skip:` line is
what lets the gate tell a recorded skip from a decision nobody bothered to frame.

## Gate

`plan_gate.sh frames` — at least one `## D<n>` section, and every section offers
a real choice: two or more `- Frame` bullets, or one bullet plus its `Skip:`
reason. A section with no frames at all is a question that was named and never
answered, and non-emptiness alone — the old gate — could not see the difference.

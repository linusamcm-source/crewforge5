# Phase 2 — Diverge

**Goal of the phase:** before any decision is argued, make sure there is more
than one candidate. A plan that only ever saw one design cannot claim to have
chosen it.

## Steps

1. List the **open decisions** the goal forces — the ones where two competent
   engineers would reasonably disagree. Settled mechanics are not decisions.
2. Load the `adhd` skill body for the framing mechanic:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" adhd
   ```

   It reports `MODE=inline` under `--load-mode`, so read it here.
3. Run its parallel frames over **each** open decision — one frame set per
   decision, not one set for the whole goal.
4. Write the result to `.crewforge/plan/frames.md`, one section per decision:

   ```markdown
   ## D1 — <decision, phrased as a question>
   - Frame A: <candidate> — <what it buys, what it costs>
   - Frame B: ...
   ```

## Skip conditions

The user asked for the quick, standard, canonical or textbook answer. Say so,
write the single frame with that reason recorded, and move on — divergence over
a settled question is theatre.

## Gate

`test -s .crewforge/plan/frames.md` — the frames file exists and is non-empty.
Every open decision listed in step 1 has a section in it before you run the gate.

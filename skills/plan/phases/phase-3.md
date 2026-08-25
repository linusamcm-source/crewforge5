# Phase 3 — Grill

**Goal of the phase:** convert every framed decision into a ratified one. The
user decides; you stress-test.

## Steps

1. Load the `grill-me` skill body for the questioning mechanic:

   ```bash
   bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" grill-me
   ```

2. Work this run's `frames.md` top to bottom (it sits beside `state.json` —
   `dirname "$(flow_state.sh plan path)"`). For each decision:
   **ask one question at a time**, in a single `AskUserQuestion` call, and
   wait for the answer before composing the next one.
   Batching questions is what makes a grilling feel like a form: the interesting
   follow-up is always the one that depends on the previous answer, and it
   cannot be written in advance.
3. Push back once on a weak answer, with the evidence from phase 1. If the user
   holds, record their decision — capitulation and nagging are both failures.
4. Append each ratified answer to `decisions.md`, in the same directory as
   `frames.md`. The heading id and the `**Chosen:**` line are both load-bearing —
   the gate cross-checks them against the frames:

   ```markdown
   ## D1 — <decision>
   **Chosen:** <frame> — <one-line rationale, in the user's words>
   ```

This is why the flow stays inline. A forked subagent has no user to ask, so
`crewforge5:plan` declares no `context: fork` and no `agent:` frontmatter.

## Gate

`plan_gate.sh decisions` — every `D<n>` framed in phase 2 has a matching section
here carrying a `**Chosen:**` line. It fails by name: `MISSING=` for a framed
decision with no section, `UNCHOSEN=` for one that was discussed but never
decided. An unanswered decision goes into the plan as an assumption nobody
agreed to, which is exactly what the old non-emptiness gate let through.

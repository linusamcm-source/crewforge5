# Phase 3 — Grill

**Goal of the phase:** convert every framed decision into a ratified one. The
user decides; you stress-test.

## Steps

1. Load the `grill-me` skill body for the questioning mechanic:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" grill-me
   ```

2. Work `.crewforge/plan/frames.md` top to bottom. For each decision:
   **ask one question at a time**, in a single `AskUserQuestion` call, and
   wait for the answer before composing the next one.
   Batching questions is what makes a grilling feel like a form: the interesting
   follow-up is always the one that depends on the previous answer, and it
   cannot be written in advance.
3. Push back once on a weak answer, with the evidence from phase 1. If the user
   holds, record their decision — capitulation and nagging are both failures.
4. Append each ratified answer to `.crewforge/plan/decisions.md`:

   ```markdown
   ## D1 — <decision>
   **Chosen:** <frame> — <one-line rationale, in the user's words>
   ```

This is why the flow stays inline. A forked subagent has no user to ask, so
`crewforge:plan` declares no `context: fork` and no `agent:` frontmatter.

## Gate

`test -s .crewforge/plan/decisions.md` — every decision framed in phase 2 has a
recorded answer here before you run the gate. An unanswered decision goes into
the plan as an assumption nobody agreed to.

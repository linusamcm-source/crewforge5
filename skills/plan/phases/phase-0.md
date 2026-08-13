# Phase 0 — Intake

**Goal of the phase:** get a goal worth planning, in the user's own words, into
`state.json`. Nothing downstream is meaningful without it: divergence with no
goal invents decisions, and the debt triage in phase 5 has no intersection to
compute against.

## Steps

1. If the invocation carried a goal, read it back to the user in one sentence and
   ask them to confirm or correct it.
2. If it did not, **stop and ask**. Do not infer a goal from the repo, the branch
   name, or an open plan file — a guessed goal produces a plan nobody asked for.
   Ask with a single `AskUserQuestion`, then wait.
3. Record the confirmed goal, and nothing else:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/flow_state.sh" plan set goal "<confirmed goal>"
   ```

4. Optionally record `scope` and `plan_dir` alongside it if the user volunteered
   them. Do not record a `plan_path` here — phase 6 owns that key, and writing it
   early would let phase 6's gate pass against a file that does not exist.

## Gate

`flow_state.sh plan get goal` — exits 1 while the key is unset, so an intake that
was never answered records `FAIL` and `flow_next.sh plan` re-offers phase 0
rather than advancing into an empty plan.

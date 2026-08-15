# Phase 5 — Rectify

Repair what phase 4 found, then re-validate. The loop stops at grade A, not at
"looks better now".

## Work

For each failing component, load the matching rectifier through the resolver
(`MODE=inline` — neither declares `context: fork`):

- `skill-rectifier` for a skill
- `agent-rectifier` for an agent

Each ships a fix catalogue keyed by the check that failed, so a finding maps to
a specific repair rather than a rewrite. Apply the fix, re-run that component's
validator, repeat. Components are disjoint, so fan out one agent per failing
component.

Two rules keep this from turning into drift:

- **Repair the finding, not the file.** A rectifier that rewrites a component
  wholesale loses the judgment the author put there and passes validation by
  replacing what was being validated.
- **Do not silence a check.** If a finding is genuinely wrong for this
  component, say so in the report and leave it — a suppressed check is a lie
  the next run inherits.

## Gate

`init_gate.sh rectify` — every component grades **A** on `grade.sh`'s scale:
0 FAIL and at most 2 WARN. That is the same scale `skill-validator` grades on,
so the stopping condition is the validator's, not this flow's.

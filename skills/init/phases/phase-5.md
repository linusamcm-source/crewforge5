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
validator, **rewrite that component's findings file** under
`$INIT_STATE/findings/`, repeat. Components are disjoint, so fan out one agent
per failing component.

Rewriting the findings file is what makes the repair count: the gate reads those
files, so a component repaired but not re-validated still carries its old
findings and still fails. Only the components you touched need re-validating —
the gate caches the structural half on content, so the ones you did not touch
cost nothing to re-check.

Two rules keep this from turning into drift:

- **Repair the finding, not the file.** A rectifier that rewrites a component
  wholesale loses the judgment the author put there and passes validation by
  replacing what was being validated.
- **Do not silence a check.** If a finding is genuinely wrong for this
  component, say so in the report and leave it — a suppressed check is a lie
  the next run inherits.

The rectifier loop is bounded: grade A, a 5-round cap, zero-fix rounds, or
no-progress rounds — the last three all **escalate** rather than spin. An
escalated component is a legitimate outcome, not a retry: record it with
`flow_state.sh init set rectify_escalated.<component> <report-path>`, stop
working that component, and carry it forward.

## Gate

`init_gate.sh rectify` — every component grades **A** on `grade.sh`'s scale:
0 FAIL and at most 2 WARN. That is the same scale `skill-validator` grades on,
so the stopping condition is the validator's, not this flow's. A run holding an
escalated component therefore ends here, gate FAIL, by design: report the
escalation report path(s) to the user and stop — the flow's verdict is "needs
human judgment on <components>", which is a real answer. Do not loop phases 4-5
hoping for a different grade, and do not suppress the check.

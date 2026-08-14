# Self-Audit Checklist (run before delivery)

Baseline evidence discipline is audited against CLAUDE.md "Evidence rules for
review and audit roles" — quoted evidence on every finding, triple-verified
negatives, Read-verified line citations, no memory/training-data claims,
`UNVERIFIED` marking. Answer YES to each skill-specific check below or rerun
the affected phase:

- [ ] Every "X does not exist" claim ran `scripts/verify-negative.sh` (or all three checks — exact Grep, case-insensitive Grep, Glob — quoted individually).
- [ ] If repomix or any packed/derived snapshot was used, `scripts/evidence-fresh.sh` passed for it (chunked mode: never regenerate the shared pack — fall back to live Read/Grep when stale).
- [ ] All `UNVERIFIED` items are downgraded by one severity level (none sit at CRITICAL/HIGH).
- [ ] In chunked mode: the `json adversarial-summary` tail block is present, well-formed, and every finding's `quoted_evidence` is a verbatim substring of the plan (see [chunked-return-contract.md](chunked-return-contract.md)).

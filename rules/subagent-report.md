---
description: Delivery and evidence contract for spawned subagents: the structured final return is the delivery.
---

# If you were spawned as a subagent

Main-session agents can skip this whole section.

Every custom subagent inherits this file automatically — do not restate these rules in
`agents/*.md`; duplicates drift and contradict. The two exceptions are the built-in
`Explore` and `Plan` agents, which skip CLAUDE.md and git status entirely and cannot be
configured to load them; if a rule must reach one, put it in the delegation prompt.

## Delivering your report

**Your structured final return IS the delivery.** One channel. Deliver on completion
without waiting to be prompted; never leave findings as inline prose instead.

- When a schema was supplied, it is the contract — satisfy it rather than narrating around
  it. Prose where a schema was expected is a non-delivery.
- `SendMessage` is the rare exception, only for a recipient that did not spawn you: `to`,
  `message` (plain string — stringify payloads), `summary`. No `recipient`/`content`/
  `metadata` field. Check the returned result; "no error" ≠ delivered. Valid `to` values
  come from the sibling roster, which exists only when your `tools` include `SendMessage`
  and another agent is named — no roster means no cross-boundary delivery, so say so
  rather than guessing a recipient.
- If you cannot deliver at all (missing tool), say so **before** doing the work.
- Run TaskGet before any TaskUpdate — ownership drifts across parallel agents.

## Evidence rules for review and audit roles

- Every factual claim about the codebase must be backed by a tool call **you ran in this
  session** (Read/Grep/Glob). Nothing from memory, training data, or prior conversations.
- Quote the verifying evidence inline: the exact command and its literal output, truncated
  if huge but never paraphrased.
- Negative claims ("X doesn't exist") are the easiest thing to get wrong — run
  `${CREWFORGE_ROOT}/skills/adversarial-review/scripts/verify-negative.sh`, which does the exact-name,
  case-insensitive and filename passes and requires all three to return zero.
- Line-number citations require a Read of the cited range, not just a Grep hit.
- Snapshots are recon; the live tree is evidence. Freshness-check any derived artifact
  before citing it (`evidence-fresh.sh`). On disagreement, live wins.
- If a claim cannot be verified, mark it `UNVERIFIED` and downgrade severity. A fabricated
  finding is worse than no finding.


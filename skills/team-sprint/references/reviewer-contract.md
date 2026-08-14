**WHO READS THIS / WHEN:** The Phase 2 graph reviewer (mandatory under `scheduling: graph`) reads this before composing findings. The plan-review chunk reviewers that used to run in Phase 1 now run in `team-sprint-planner`'s adversarial review loop, which carries its own copy of this contract (`references/reviewer-contract.md` there).

> **Canonical shape lives in team-sprint-planner's `references/dynamic-review-workflow.md`** (the
> `FINDING` schema — the plan-review loop and its workflow moved planner-side). On the Workflow
> path the schema is machine-enforced at the tool layer; the fenced block below is the
> hand-rolled equivalent for the prose fallback and for this skill's Phase 2 graph reviewer. If
> you change one, change both — or retire the fallback. The grounding rules underneath apply
> identically to both paths.

### Reviewer return contract (per chunk)

Each chunk's subagent ends its response with exactly one fenced block:

````markdown
```json adversarial-summary
{
  "round": 1,
  "chunk_id": "3-of-6",
  "story_ids_reviewed": ["2026-05-03T21:34:30Z", "..."],
  "counts": { "CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 0, "UNVERIFIED": 0 },
  "findings": [
    {
      "id": "H-1",
      "severity": "HIGH",
      "story_id": "2026-05-03T21:34:30Z",
      "issue": "...",
      "quoted_evidence": "<verbatim substring of the plan, ≤200 chars>",
      "recommendation": "...",
      "codebase_grep": "<grep command + literal output line, e.g. \"src/config/featureFlags.ts:RATING_10_SCALE: false\">"
    }
  ]
}
```
````

Two layers of grounding, both required per finding:

- **Plan-side (`quoted_evidence`):** verbatim substring of `current_plan`. Proves the reviewer actually read the story it is finding a problem in — without it, reviewers can attach real codebase grep evidence to fabricated story titles.
- **Codebase-side (`codebase_grep`):** exact grep command + literal output line. Already mandated by the agent definition's anti-fabrication protocol.

`story_id: "*"` is reserved for cross-cutting findings (e.g. "i18n parity not enforced anywhere in the plan") — the `quoted_evidence` may then be drawn from any story or from the sprint-level notes section, but must still be a real substring.

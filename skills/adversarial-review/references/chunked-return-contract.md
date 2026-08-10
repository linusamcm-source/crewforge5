## Return Contract for Chunked Invocation

When this skill is invoked by an orchestrator (e.g. `/team-sprint-planner`'s adversarial review loop)
that chunks a multi-story plan into parallel reviewer batches, the reviewer
MUST conform to a structured return contract so the lead can aggregate
findings deterministically and strip hallucinations before applying them.

### Two-layer grounding (both required per finding)

1. **Plan-side (`quoted_evidence`)** — a verbatim substring of the document
   under review (≤200 chars, non-empty). This proves the reviewer actually
   read the story it is finding a problem in. Without this layer, reviewers
   can attach real codebase grep evidence to fabricated story titles — a
   failure mode observed in production.
2. **Codebase-side (`codebase_grep`)** — exact grep command + literal
   output line (the existing rule from the agent's anti-fabrication
   protocol, just promoted to a structured field). A `graphify query`/`path`
   command plus its returned `source_location` line is equally valid here for
   relationship/coupling findings — the field name stays `codebase_grep` for
   aggregator compatibility, but the evidence may be a graph result.

If a finding is purely cross-cutting (no single-story owner — e.g. "i18n
parity not enforced anywhere"), set `story_id: "*"` and draw the
`quoted_evidence` from any story or sprint-level notes block. The substring
still has to be a real, verbatim hit.

### Mandatory JSON tail block

Every reviewer response ends with **exactly one** fenced block tagged
` ```json adversarial-summary `. The block IS the machine-readable
contract; surrounding prose is decorative.

````markdown
```json adversarial-summary
{
  "round": 1,
  "chunk_id": "3-of-6",
  "story_ids_reviewed": ["<story_id>", "..."],
  "counts": { "CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 0, "UNVERIFIED": 0 },
  "findings": [
    {
      "id": "H-1",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW|UNVERIFIED",
      "story_id": "<id from plan heading, or '*' for cross-cutting>",
      "issue": "<short description>",
      "quoted_evidence": "<verbatim substring of plan, ≤200 chars>",
      "recommendation": "<actionable fix; required for CRITICAL/HIGH>",
      "codebase_grep": "<grep OR graphify command + literal output line, optional>"
    }
  ]
}
```
````

### Finding ID convention

Per chunk: `<sev>-<seq>` where sev = `C` | `H` | `M` | `L` | `U` and seq
restarts at 1 within each severity. The lead aggregator namespaces them
across chunks during merge.

### Lead-side validator (what your output is checked against)

Orchestrators run a deterministic validator on every finding before
counting it. Any finding that fails any of these checks is rejected and
written to a `rejected.md` sidecar, NOT counted toward gating:

- `quoted_evidence` non-empty AND a literal substring of the doc.
- `story_id` either matches a parsed `## Story <id>:` heading or equals `"*"`.
- For `severity ∈ {CRITICAL, HIGH}`: `recommendation` non-empty and not a
  generic placeholder ("consider X", "investigate Y").

If your reject rate exceeds 50% on a chunk, the orchestrator re-runs that
chunk ONCE with your rejected findings quoted back at you. If you cannot
repair them, drop them.

### Loop semantics (informational)

The orchestrator iterates rounds until `counts.CRITICAL == 0 AND counts.HIGH == 0`
(post-validation). MEDIUM and LOW are surfaced but do not gate the loop.
After a soft cap (default 6 rounds), the user is prompted with override /
extend / abort options — the loop won't silently fail.

# Large repos: spawn subagents

If the repo is >50k LOC or has >5 top-level modules (top-level source directories with distinct responsibilities), dispatch subagents (Agent tool) in parallel — one per module — and synthesize their reports. Serial reading on a large repo eats the context window before findings can be written.

Each subagent gets: scope (one module), the nine audit dimensions, the evidence instruments (all subagents grep the same pack and query the same graph, so findings stay citation-consistent), and the citation requirement. The main agent merges, dedupes, and ranks the combined set down to the Phase 3 findings budget.

## Required Caller Tools

This skill assumes the invoking agent has these tools loaded:

- `Read`, `Grep`, `Glob`, `Bash` — codebase verification
- `Edit` — surgical doc patches in Step 4 (whole-doc mode only; chunked mode does not edit)
- `TaskGet`, `TaskUpdate` — required when invoked as a sprint teammate (task lifecycle). `SendMessage` — needed only for the cross-boundary delivery case; planner chunk reviewers and the Phase 2 graph reviewer deliver by final agent return and do not require it (see Delivery Protocol)
- `mcp__claude_ai_Context7__resolve-library-id`, `mcp__claude_ai_Context7__query-docs` — optional, library/SDK feasibility checks
- `WebFetch` — optional fallback when Context7 has no entry
- `graphify` CLI (via `Bash`) — optional, relationship/coupling verification when a graph exists
- `mcp__plugin_claude-mem_mcp-search__memory_search` / `observation_search` / `get_observations` (or the `mem-search` skill), and `observation_add` / `memory_add` — optional, project-memory recall + record

The `general-purpose` subagent type carries the core tools. The graphify and claude-mem integrations are optional and fail-soft — when their tools are absent, skip those verification sources silently (do not block the review). If a *required* tool is missing, surface it immediately rather than completing work that cannot be delivered.

**Recommended model:** `opus`. Adversarial review is dense reasoning over real codebase evidence; defaulting to a smaller model produces shallow findings and higher fabrication rates.


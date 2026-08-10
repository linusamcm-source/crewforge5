## Codebase intelligence: repomix + graphify + claude-mem

Ground every finding in the source that fits the question — the repomix pack is the default recon target; three complementary tools:

- **repomix pack grep** (default) — explicit `rtk grep` on the pack (bare `grep`/`rg` only as a no-rtk fallback), plus Glob / live `Read` — exact text and occurrences.
- **`graphify`** (optional; when `graphify-out/graph.json` exists — `/team-sprint` Phase 0 builds it): current structure, coupling, reachability. graphify is the relationship complement to this skill's text grep — when the question is "what calls / reaches / is coupled to X" rather than "where does this string occur", reach for graphify. Prefer the CLI form — `graphify query "what calls X"`, `graphify path "A" "B"`, `graphify explain "N"` — over grepping `graph.json` raw (only the commands traverse transitively). Cite the returned `source_location`.
- **`claude-mem`** (optional): decisions, conventions, and known issues recorded across past sessions. claude-mem is the history complement — "did we decide X", "was this fixed before" — which neither grep nor the graph answers. Recall via the `mem-search` skill or `memory_search`/`observation_search` → `get_observations`; record a durable new finding/decision with `observation_add`/`memory_add` (≤500-token summary).

Evidence rules: when these sources and the live tree disagree, the **live tree wins**; freshness-check any snapshot before citing it; `claude-mem` grounds *intent/history* claims, never *current-code* claims — verify those with grep/graphify. Both graphify and claude-mem are optional and **fail-soft**: if their tools aren't loaded, skip them and work from grep + the live tree.

## Working With `use-repo-code`

This skill leans hard on `use-repo-code`. Its artifact is the repomix pack at
`${REPOMIX_PACK:-.repomix-output.xml}` (repo root, XML style). Quick
reference — all searches via explicit `rtk grep` (bash):

- **Locate file in pack**:
  `rtk grep '<file path="src/foo/bar.ts">' "$PACK" -A 80`
- **Find all callers of symbol**:
  `rtk grep 'symbolName' "$PACK" -B 2 -A 2` (`-B 2` catches the owning `<file path="...">` tag)
- **Don't Read the pack in full** — it's huge; grep only.
- The skill itself runs as a forked subagent (`context: fork`, Explore) — when
  invoking it rather than grepping the pack directly, pass the instruction
  *"search the pack with `rtk grep` (bash), not the Grep tool or bare grep"*
  so the forked agent's context survives the sweep.

When the pack is stale (recent commits changed the area you are verifying),
fall back to live `Grep` across the source tree. Note the staleness in the
finding so the user can regenerate the pack via `repomix` if needed.

## Working With `graphify` (optional — relationship/coupling claims)

Use the knowledge graph when `graphify-out/graph.json` exists; skip silently when it does not
(most ad-hoc reviews run without one — do not block on it). Quick reference:

- **Caller / reachability**: `graphify query "what calls <symbol>"` — verifies "X is/ isn't used".
- **Coupling between two areas**: `graphify path "<A>" "<B>"` — a returned path refutes a "these
  are independent" claim; an empty path supports it.
- **Node summary**: `graphify explain "<symbol>"` — what a module/function is, in plain language.
- **Freshness**: the graph is a snapshot like the repomix pack — freshness-check it the same way
  (SKILL.md § Evidence Rules, `evidence-fresh.sh`) and prefer the live tree on disagreement.

**Prefer the CLI command form over grepping `graphify-out/graph.json` directly.** `graphify
query`/`path` perform graph *traversal* — transitive callers, reachability, shortest path between
two nodes — that a raw `grep` of `graph.json` cannot. On a tiny tree a live `Grep` is fine and
authoritative; but when a coupling or reachability claim spans a real codebase ("nothing reaches
X", "A and B are independent"), run the command, not a hand-rolled JSON grep — the grep sees only
direct string hits and will miss multi-hop coupling.

The graph is a verification aid, not a source of truth: never assert an edge graphify did not
return, and when graphify and a live `Grep` disagree, the live tree wins.

## Working With `claude-mem` (optional — project memory / decisions / history)

graphify maps what the code **is now**; `claude-mem` recalls what the project already **decided,
fixed, and discovered** across past sessions. Use them together — graphify for structure, claude-mem
for history — so a review catches both "this contradicts the current code" and "this contradicts a
decision we already made." Optional and fail-soft: when claude-mem is unavailable (its MCP tools or
the `mem-search` skill are not loaded), skip silently — never block a review on it.

**Recall before reviewing** (when the doc touches an area with project history). Search memory for
prior decisions, conventions, and known issues so a finding can cite them:

- `mem-search` skill, or `memory_search` / `observation_search` for a topic ("config centralisation",
  "auth token expiry") — returns observation IDs + summaries.
- `get_observations([IDs])` to pull the full detail of a hit before citing it.

**What memory is good for in a review:**

- **Decision drift** — the plan proposes X but `observation_search "X"` surfaces a recorded decision
  to do the opposite. CRITICAL/HIGH: the plan contradicts a settled call.
- **Known issues / prior fixes** — the plan re-introduces a bug a prior observation logged as fixed,
  or ignores a constraint a past session recorded.
- **Convention recall** — house patterns captured in memory that the plan should follow.

**Record after reviewing.** When the review surfaces a durable convention, a load-bearing
decision, or a recurring failure mode worth keeping, persist it:
`observation_add` / `memory_add` with a tight summary (≤500 tokens — chunk if longer). Record
durable project knowledge only; not session-specific scratch.

**Evidence rule (critical):** a memory observation grounds an *intent/history* claim, never a
*current-code* claim. Memory can be stale — a recorded decision may have been reversed since. So:
cite an observation to support "we decided / we knew / this was fixed," but verify "the code does X
now" with grep/graphify against the live tree. When memory and the live tree disagree, the live tree
wins (same rule as the repomix pack and the graphify graph).


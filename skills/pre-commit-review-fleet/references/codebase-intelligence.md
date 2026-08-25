# Codebase Intelligence (repomix + graphify + claude-mem)

All four reviewers ground findings in three complementary sources. The repomix
pack — searched with `rtk grep` / `rtk rg` (token-filtered, grouped by file) — is
the **default** text-recon source; `graphify` and `claude-mem` are optional lenses
layered on top. Match the source to the question — using grep for a coupling
question, or memory for a current-code question, is how reviews go wrong:

| Source | Answers | Use for |
|--------|---------|---------|
| `use-repo-code` / repomix pack (**default**) | exact text / occurrence | string hits, finding a definition, symbol/caller search — pack greps go through `rtk grep` / `rtk rg` (token-filtered) |
| `graphify` (optional) | current structure, coupling, reachability | "what calls X", "does input reach a sink", "does this util already exist", caller fan-in |
| `claude-mem` (optional) | history — decisions, conventions, known issues | "did we decide X", "is this a recorded pattern", "was this bug fixed before" |

1. **repomix pack (default)** — resolve `use-repo-code` rather than reaching for
   the `Skill` tool, which cannot see a hidden skill:

   ```bash
   bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code
   ```

   It answers `MODE=agent`, so spawn it through the `Agent` tool with the type its
   frontmatter names. Never read its body inline: it forks to keep a whole pack out
   of the caller's window, and inlining it puts the pack there instead. The pack is
   `.repomix-output.xml`, regenerated on demand by
   `bash ${CREWFORGE5_ROOT}/skills/use-repo-code/scripts/pack.sh`. Search it with
   bash `grep`/`rg` on the pack — the RTK `PreToolUse` hook rewrites these to
   `rtk grep`/`rtk rg`, so output is token-filtered and grouped by file — instead
   of per-file `Read`. This is the primary recon for every lane: existence checks,
   symbol/caller text search, "does this already exist". Fall back to live
   `Grep`/`Read` for the exact lines you will cite, or when the diff changed code
   the pack does not yet reflect.
2. **graphify** (optional) — when `graphify-out/graph.json` exists (under
   `/team-sprint`, Phase 0 builds it). An on-demand relationship lens for the
   reachability/coupling questions text grep can't answer (taint path, hot-path
   fan-in, caller-count for dup/dead-code). Prefer the CLI command form (`graphify
   query`/`path`/`explain`) over grepping `graph.json` raw — only the commands do
   traversal (transitive callers, reachability) a flat grep cannot. Cite the
   returned `source_location` as evidence.
3. **claude-mem** (optional) — recall recorded decisions/conventions before
   flagging a "consistency" or "we already decided" issue (`mem-search` skill, or
   `memory_search` / `observation_search` → `get_observations`). After the run,
   a durable new convention or recurring failure mode worth keeping can be
   recorded with `observation_add` / `memory_add` (≤500-token summaries).

**Evidence rules (same as the live tree):**

- When `graphify`, `claude-mem`, and the live tree disagree, **the live tree
  wins**. Freshness-check any snapshot (`graph.json`, repomix pack) before
  citing it — a stale artifact is not evidence.
- `claude-mem` grounds an *intent/history* claim ("we decided", "known issue"),
  never a *current-code* claim — verify "the code does X now" with grep/graphify.
- Both `graphify` and `claude-mem` are **optional and fail-soft**: when their
  tools are not loaded, skip those sources silently and review on grep + live
  tree. Never block the fleet on them.

# Recon instruments

Three instruments, layered — same convention as `tech-debt-audit`:

1. **`use-repo-code` (repomix pack) — the text-evidence instrument.** Every broad sweep —
   "does X already exist", "where does this string occur", "list everything under feature W" —
   goes through the `use-repo-code` skill instead of fanning out live Greps or per-file Reads.
   **The pack must be freshly regenerated for this plan — no exceptions.** The skill's own
   freshness check tolerates a pack up to 2 hours old; a plan must not be grounded against even
   that. Force it by deleting the pack first, so the skill's Step 1 always rebuilds:

   ```bash
   rm -f "${REPOMIX_PACK:-.repomix-output.xml}"
   ```

   Then invoke `use-repo-code` for the sweeps. A plan claim cited from a stale pack is exactly
   the kind of drift the Phase 7 adversarial review loop exists to catch — don't hand it to
   your own reviewers.

   **Search the pack through `rtk` — explicitly, not via the hook.** `use-repo-code` assumes an
   RTK PreToolUse hook rewrites bare `grep`/`rg` calls; do not rely on that hook being installed.
   Call `rtk grep` directly for every pack sweep — it truncates lines, caps results, and groups
   hits by file, which is the difference between recon fitting in context and recon drowning it:

   ```bash
   rtk grep '<pattern>' "${REPOMIX_PACK:-.repomix-output.xml}"
   ```

   A hit does not carry its filename: the owning `<file path="...">` tag routinely sits
   hundreds of lines above, so no `-B <n>` window reaches it. Attribute the hit by `Read`ing
   the live file, never by guessing from surrounding pack context.

   When invoking the `use-repo-code` skill (it runs as a forked subagent), pass this as an
   instruction in the request: *"search the pack with `rtk grep` (bash), not the Grep tool or
   bare grep."* Bare grep against a repomix pack returns full-width XML lines and floods the
   forked agent's context before the sweep finishes.
2. **graphify — the structural instrument** (call sites, reachability, coupling) — below.
3. **Live `Read` — the verification instrument.** Any file/line the plan will *cite* gets
   confirmed against the live tree before it's asserted. Pack and graph are recon; the live
   tree is evidence. When they disagree, the live tree wins.

**Use graphify for the call-site and dependency-mapping recon.** A knowledge graph answers
"what calls X", "what reaches Y", and "are A and B coupled" far better than grep — exactly the two
bullets above. Ensure it's installed for this project and build the graph once, then query it:

```bash
GE=${CREWFORGE_ROOT}/skills/team-sprint/scripts/graphify_ensure.sh
if [ -x "$GE" ]; then bash "$GE" --ensure; bash "$GE" --graph-status; fi
```

**Route structural questions through the recon router first.** `recon.sh` normalises the
structural intents (`callers`, `callees`, `impact`, `docs`) across codegraph/graphify/repomix
and names the provider and freshness behind every answer, so a provider that cannot parse the
language degrades visibly instead of returning an empty "no callers" that reads as safe:

```bash
RS=${CREWFORGE_ROOT}/skills/team-sprint/scripts/recon.sh
if [ -x "$RS" ]; then bash "$RS" --probe; bash "$RS" callers "<symbol>"; fi
```

When `recon.sh` is absent (team-sprint not installed), fall back to the graphify CLI below
and to `rtk grep` over the pack — the instruments are unchanged, only the routing is missing.

If `graphify_ensure.sh` is absent (team-sprint not installed) or it reports `STATUS=MISSING`/
`STATUS=STALE`, invoke the **`/graphify`** skill on the repo root — it self-installs graphify and
builds `graphify-out/graph.json`. Then ground recon claims with `graphify query "what calls
<symbol>"`, `graphify path "<A>" "<B>"`, and `graphify explain "<module>"`, citing the
`source_location` each result reports. Keep using grep for exact text/occurrence — graphify
augments it, it doesn't replace it.

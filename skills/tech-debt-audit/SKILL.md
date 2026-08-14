---
name: tech-debt-audit
model: opus
context: fork
agent: general-purpose
description: Whole-repo "debt audit", "codebase health check", "architecture review", "code quality assessment" → TECH_DEBT_AUDIT.md, file-cited, plus a "looks bad but is actually fine" section
disable-model-invocation: true
---

# Tech Debt Audit

A Claude Code skill that conducts a deliberate, opinionated audit of an entire codebase and produces `TECH_DEBT_AUDIT.md` with cited findings.

This entire file is the protocol to execute when invoked via `/tech-debt-audit`. Human-facing documentation (installation, philosophy, sample output, adaptation notes, license) lives in `README.md` beside this file — do not load it during an audit; it contains no protocol steps.

## When to use

Thorough, user-invoked tech debt and architecture audit of the current codebase. Produces `TECH_DEBT_AUDIT.md` with file-cited findings, severity, effort estimates, and a required "looks bad but is actually fine" section. Uses the repomix pack (use-repo-code) as the default text-evidence instrument, with graphify knowledge-graph queries for structural/coupling questions when available, and live-tree verification for every citation.

## Operating principles

Find what's actually wrong. Not diplomatic. Not surface-only. Don't pattern-match to generic best practices without grounding in this specific repo. No sycophancy. No "overall the codebase is well-structured" filler.

Cite `file:line` for every concrete finding. Vague claims like "the code generally..." don't count. Read code before judging it — a pattern that looks wrong in isolation may be load-bearing.

## Phase 0: Scope and repeat-run check

Run this before anything else — Phase 3 overwrites `TECH_DEBT_AUDIT.md`, so a prior audit must be read before it's destroyed.

1. If invoked with a path argument (`/tech-debt-audit src/payments`), scope the entire audit to that subtree.
2. If `TECH_DEBT_AUDIT.md` already exists in the repo, read it now — and extract its
   finding inventory mechanically:
   `bash ${CREWFORGE5_ROOT}/skills/tech-debt-audit/scripts/prior-findings.sh` (prints
   `ID<TAB>severity<TAB>file:line` per prior finding). In Phase 3, mark resolved
   findings `RESOLVED`, update stale ones, and tag new findings `NEW`. This turns the
   audit into a living document tracked over time.

## Phase 1: Orient

Do not skip this. Forming opinions before understanding the system produces bad audits.

1. Read the README, package manifest (`package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / `*.psd1`), and any architecture docs in `/docs` or `/adr`.
2. Prepare the repomix pack (regenerate if missing or >2h old) — the default recon instrument for this audit (see "Evidence instruments" below). For the structural dimensions (coupling, circular deps, god nodes, dead code), also run graphify when available: `graphify .` if no `graphify-out/graph.json` exists (establishes the baseline), `graphify update .` if one does (no-LLM code re-extract; add `--force` if code was deleted since the last build); if the graphify CLI isn't loaded, fail-soft and grep the pack for the same signals. When built, the graph's god-node and community report doubles as a head start on your architecture mental model.
3. Map the directory structure and identify the major modules / layers.
4. Run `bash ${CREWFORGE5_ROOT}/skills/tech-debt-audit/scripts/orient.sh [scope-dir]` — it emits
   the top 20 largest files, the 20 most-modified in 6 months, their intersection
   (where debt usually hides), repo LOC, and the findings-budget band. Never derive
   these lists by hand.
5. Identify entry points, hot paths, and cold corners (judgment — read the
   intersection files from step 4 first).
6. Skim `git log --oneline -100` for what's actually changing thematically — the
   counting is already done by step 4.
7. Publish a phase plan with the task-tracking tool available in your harness (`TodoWrite` or `TaskCreate`); if neither is loaded, print the plan as plain text so the user can see progress.

Write a 1–2 paragraph mental model of the architecture before proceeding. If your model contradicts the README, flag it — that itself is a finding.

## Evidence instruments (priority order)

Every finding must be grounded in evidence. Reach for these in this order — each exists because the one above it can't answer its class of question:

1. **repomix pack (`use-repo-code`)** — the default recon sweep: find every occurrence of a pattern across the codebase in one grep instead of dozens of per-file reads. `use-repo-code` is hidden from the catalogue, so resolve it — `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code` answers `MODE=agent`, so spawn it through the `Agent` tool with the type its frontmatter names rather than reading its body inline. Check `.repomix-output.xml` at repo root; if missing or older than 2 hours, regenerate per that skill's Step 1. Grep the pack with bash `grep`/`rg` — the RTK `PreToolUse` hook rewrites these to `rtk grep`/`rtk rg`, so output is token-filtered and grouped by file — and pass `-B 2` so each hit carries its owning `<file path="...">` tag; never `Read` the pack whole — it's huge. This is the primary instrument for the Phase 2 sweep dimensions (consistency, types, error handling, security), because per-file live reads on those sweeps burn context the pack was built to save.
2. **graphify** (when available) — structural questions: coupling hotspots, circular dependencies, god nodes, reachability, dead code (zero-caller queries) — the class of question a text grep can't answer, which is why it's the right instrument for the structural dimensions. Run it before Phase 2 when the CLI is loaded: if `graphify-out/graph.json` does not exist, run `graphify .` to establish the baseline; if it exists, run `graphify update .` to bring it to current state (the no-LLM code re-extract — works without an API key; add `--force` when code was deleted since the last build). Refresh it before use so the graph doesn't silently lag the working tree and corrupt a structural finding. Query with the CLI — `graphify query "what calls X"`, `graphify path "A" "B"`, `graphify explain "N"` — not by grepping `graph.json` raw, because only the commands traverse transitively. Treat graph edges as leads, not proof: edges can be INFERRED or direction-inverted, so confirm each structural finding against the live source before citing it. Fail-soft: if the graphify CLI isn't available, grep the pack for the same structural signals and continue.
3. **Live `Read` / `rg`** — ground truth and citation verification. Every `file:line` citation must be verified against the live file before it's written, because pack and graph line numbers drift from the working tree. When any snapshot and the live tree disagree, the live tree wins.
4. **claude-mem** (optional; only if a memory MCP is loaded) — decisions, conventions, and known issues from past sessions. Grounds *intent/history* claims only ("was this fixed before", "did we decide X"), never *current-code* claims — verify those with the instruments above.

Fail-soft: if the graphify CLI or repomix is unavailable, note the gap in the audit's open questions and continue with the live tree. Missing tooling degrades the audit; it never blocks it.

## Phase 2: Audit across these dimensions

Audit all nine dimensions: 1. Architectural decay · 2. Consistency rot · 3. Type & contract debt · 4. Test debt · 5. Dependency & config debt · 6. Performance & resource hygiene · 7. Error handling & observability · 8. Security hygiene · 9. Documentation drift.

Before sweeping, load the per-dimension detail and instrument notes: [references/dimensions.md](references/dimensions.md). Cite `path/to/file.ext:LINE` for every finding, verified live per the evidence rules.

## Phase 3: Deliverable

Write to `TECH_DEBT_AUDIT.md` in the repo root with this structure:

- **Executive summary** — max 10 bullets, ranked by impact.
- **Architectural mental model** — your understanding of the system as it actually is.
- **Findings table** — columns: `ID | Category | File:Line | Severity (Critical/High/Medium/Low) | Effort (S/M/L) | Description | Recommendation`. Scale the findings budget to repo size: small repos (<5k LOC) typically yield 10–30 material findings, medium repos 30–80. Never pad to hit a number — the anti-padding rule always wins over the target range.
- **Top 5 "if you fix nothing else, fix these"** — with concrete diff sketches or refactor outlines, not vague advice.
- **Quick wins** — Low effort × Medium+ severity, as a checklist.
- **Things that look bad but are actually fine** — calls you considered flagging and chose not to, with reasoning. **This section is required.** If it's empty, you didn't look hard enough.
- **Open questions for the maintainer** — things you couldn't tell were debt vs. intentional.

## Rules

- Cite `file:line` for every concrete finding, verified against the live file.
  Before delivering, run the mechanical gate:
  `bash ${CREWFORGE5_ROOT}/skills/tech-debt-audit/scripts/verify-citations.sh TECH_DEBT_AUDIT.md`
  — exit 1 means a citation points at a missing file or a line past EOF; fix every
  FAIL before the audit is done.
- If unsure whether something is debt or intentional, ask in the open questions section — don't assert.
- Don't recommend rewrites. Recommend specific, scoped changes.
- Don't pad. If a category has nothing material, write "Nothing material" and move on.
- No sycophancy. Tell the user what's broken.

For dimension-5 CVE/dependency scans and stack linters: load [references/stack-tooling.md](references/stack-tooling.md).

If the repo is >50k LOC or >5 top-level modules: load [references/large-repos.md](references/large-repos.md) for parallel-subagent dispatch.

---
name: context-hygiene
description: Context-engineering passes over CLAUDE.md, rules, hooks and MCP config — /crewforge5:init drives it in phase 2. Use directly on "slim CLAUDE.md" or "apply context-engineering rules"
disable-model-invocation: true
---

# Context Hygiene — Claude 5 Generation Rules

Core finding: over 80% of Claude Code's system prompt was removed for advanced models with no
measurable performance loss. Modern models perform better with judgment-level guidance than with
rigid rules. Every instruction file in the environment should be re-audited against that bar.

## Principles

1. **Judgment over rules.** Replace explicit micro-constraints ("never write multi-paragraph
   docstrings", "default to no comments") with high-level guidance ("write code that reads like
   the surrounding code: match its comment density, naming, and idiom"). If a rule exists to
   compensate for a weaker model, delete it.

2. **Progressive disclosure everywhere.** Context should appear when needed, not upfront.
   - CLAUDE.md holds only what every session needs; everything else becomes a skill loaded on demand.
   - Long skills split into a short SKILL.md entry point plus `references/` files read just-in-time.
   - Tool definitions defer-load: the agent searches full schemas only before use.

3. **CLAUDE.md stays lightweight.**
   - Briefly describe repo purpose.
   - Document only gotchas — non-obvious constraints the file system cannot reveal
     (e.g. "types are kept in one monolithic file, do not split").
   - Delete anything Claude can infer from the repo structure itself.
   - Move any multi-paragraph procedure out into a skill.

4. **Skills are lightweight guides, not rulebooks.**
   - Encode team-specific opinions, gotchas, and taste — not generic best practice the model
     already knows.
   - Over-constrain only where the cost of deviation is high (security, irreversible actions).
   - A skill that restates model-obvious behaviour is negative-value: it costs tokens every trigger.

5. **Expressive interfaces beat usage examples.** For tools and scripts, let parameter names and
   enumerations carry the semantics (e.g. `status: pending | in_progress | completed`) instead of
   documenting usage in prose.

6. **Memory is automatic now.** The model saves relevant memories itself. Do not maintain
   hand-curated state dumps in CLAUDE.md; reserve memory files for facts the repo cannot record.

7. **Prefer code-based specs over prose.** When a skill or plan needs a reference, point at
   HTML mockups, function signatures, or test suites via @-mentions — higher fidelity than
   descriptions. Rubrics let verification agents judge against specific standards.

## Refactor Workflow

Run these passes over the target environment — the config root under audit: `INIT_TARGET`
when `/crewforge5:init` drives this skill, otherwise whatever root the user named
(typically their user config plus the project's `.claude/`):

**Audit the principles, not surface patterns.** Judge each file against the principle, don't pattern-match for keywords. Read the context the way Claude receives it - what loads always, what loads on demand - and ask per shift: is this workspace still living in the THEN column? The smells below are illustrations, not definitions; something can smell fine and still break the principle, and vice versa.

1. **Judgement over rules** - is Claude constrained where judgement would serve better? Smell: absolute directives about matters of taste or style, or two directives that pull against each other. Safety and money rules are legitimately hard - never flag those.
2. **Interfaces over examples** - do skills teach by boxing Claude into worked examples where a clearer interface (better parameters, names, structure) would carry it?
3. **Progressive disclosure over upfront loading** - does every always-loaded line earn its place? Smell: detail that's only occasionally needed sitting in files that load every session instead of a tree read on demand.
4. **One home over repetition** - does each instruction have one authoritative home? Smell: the same guidance restated in several places, especially copies that have drifted apart.
5. **Auto-memory over guidance-file memory** - are facts about the user or the work (preferences, dates, decisions) living as prose in guidance files instead of the memory system?
6. **Rich references over simple specs** - are active builds steered by plain markdown descriptions where a higher-fidelity reference (code, a test suite, an HTML mockup, a rubric) exists or would be cheap to make?


### Pass 1 — Measure
- Measure mechanically, not by impression:
  `python3 "${CREWFORGE5_ROOT}/skills/token-slim/scripts/baseline.py" --skills-dir <config-root>/skills --report`
  prints per-skill description and body sizes. Record its output plus `wc -c` on
  CLAUDE.md and each rules file — that is the before-picture Pass 5 compares against.
- Inventory the rest of the per-session load the script cannot see: CLAUDE.md's
  `@`-included files, always-on hooks output, MCP server instructions. The frontmatter
  `description` of every skill loads every session — that list is part of the budget.

### Pass 2 — CLAUDE.md
- Flag every line that is (a) inferable from the repo, (b) generic best practice, or (c) a rigid rule compensating for a weaker model. Propose deletion or judgment-level rewrite.
- Flag any section longer than a few paragraphs as a skill-extraction candidate.
- **Never apply a trim without running the retention gate over it.** Write the proposal to a scratch file and check it against the original:

  ```bash
  P="$(mktemp "${TMPDIR:-/tmp}/claude-md-proposed.XXXXXX")"   # per-run scratch — a fixed
  # name collides when two hygiene passes run concurrently
  bash "${CREWFORGE5_ROOT}/scripts/retention_gate.sh" CLAUDE.md "$P"
  ```

  A trim is measured by how much shorter it got, and the lines worth the most tokens are usually the ones worth keeping — an absolute directive nobody re-derives, the one exact command that works, a version somebody bled for. The gate fails the proposal if any `never`/`always`/`must` line, backticked command, path, version or quoted error string stopped appearing anywhere. It reads two files and returns a verdict; it cannot edit anything, so the decision to apply stays with the user.

### Pass 3 — Skills
- Merge overlapping skills. Deleting a skill is gated the same way a CLAUDE.md trim is:
  a skill is "dead" only when nothing references it, its triggers duplicate another
  skill's, and the user confirms — propose the deletion with that evidence, never apply
  it silently.
- For the trim-and-split mechanic (descriptions to trigger phrases plus one line,
  long SKILL.md into entry point + references, redundant usage examples out), drive
  `token-slim` — it owns that procedure and its verification; do not restate it here.

### Pass 4 — Tools, hooks, MCP
- Prefer deferred tool loading over always-loaded schemas.
- Remove hooks whose output restates what the model would do anyway.
- Disable MCP servers not used in the project; their instructions load every session.

### Pass 5 — Verify
- Confirm no trigger phrase, gotcha, or hard constraint was lost in trimming.
- Re-run the Pass 1 measurement commands and compute the before/after delta — the same
  instruments both times, so the delta is a number, not an impression.
- Report the delta and every deletion with its justification; anything uncertain gets flagged for the user rather than silently removed.

## What NOT to cut

- Security constraints and irreversible-action guards.
- Genuine gotchas (non-obvious repo invariants).
- Exact commands, versions, and error strings — precision here is cheap and load-bearing.
- Trigger phrases in skill descriptions — they are how skills get found.

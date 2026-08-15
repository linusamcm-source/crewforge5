---
name: context-hygiene
description: Audit and refactor the Claude environment (CLAUDE.md, skills, agents, hooks, MCP config) to Claude 5-generation context-engineering rules. Use on "clean up my Claude config", "slim CLAUDE.md", "refactor my skills", "audit context load", or "rightsize the environment".
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

Run these passes over the target environment (usually `$HOME/.claude` and project `.claude/`):

**Audit the principles, not surface patterns.** Judge each file against the principle, don't pattern-match for keywords. Read the context the way Claude receives it - what loads always, what loads on demand - and ask per shift: is this workspace still living in the THEN column? The smells below are illustrations, not definitions; something can smell fine and still break the principle, and vice versa.

1. **Judgement over rules** - is Claude constrained where judgement would serve better? Smell: absolute directives about matters of taste or style, or two directives that pull against each other. Safety and money rules are legitimately hard - never flag those.
2. **Interfaces over examples** - do skills teach by boxing Claude into worked examples where a clearer interface (better parameters, names, structure) would carry it?
3. **Progressive disclosure over upfront loading** - does every always-loaded line earn its place? Smell: detail that's only occasionally needed sitting in files that load every session instead of a tree read on demand.
4. **One home over repetition** - does each instruction have one authoritative home? Smell: the same guidance restated in several places, especially copies that have drifted apart.
5. **Auto-memory over guidance-file memory** - are facts about the user or the work (preferences, dates, decisions) living as prose in guidance files instead of the memory system?
6. **Rich references over simple specs** - are active builds steered by plain markdown descriptions where a higher-fidelity reference (code, a test suite, an HTML mockup, a rubric) exists or would be cheap to make?


### Pass 1 — Measure
- Run `claude doctor` to rightsize skills and CLAUDE.md files.
- Inventory per-session token load: CLAUDE.md (+ every `@`-included file), always-on hooks output, MCP server instructions, skill descriptions. The frontmatter `description` of every skill loads every session — that list is part of the budget.

### Pass 2 — CLAUDE.md
- Flag every line that is (a) inferable from the repo, (b) generic best practice, or (c) a rigid rule compensating for a weaker model. Propose deletion or judgment-level rewrite.
- Flag any section longer than a few paragraphs as a skill-extraction candidate.

### Pass 3 — Skills
- Merge overlapping skills; delete dead ones.
- Trim descriptions to trigger phrases plus one line of purpose — descriptions are the always-loaded surface, the body is the on-demand surface.
- Split any long SKILL.md into entry point + reference files.
- Remove usage examples that an expressive interface makes redundant.

### Pass 4 — Tools, hooks, MCP
- Prefer deferred tool loading over always-loaded schemas.
- Remove hooks whose output restates what the model would do anyway.
- Disable MCP servers not used in the project; their instructions load every session.

### Pass 5 — Verify
- Confirm no trigger phrase, gotcha, or hard constraint was lost in trimming.
- Re-run `claude doctor` and compare token load before/after.
- Report the delta and every deletion with its justification; anything uncertain gets flagged for the user rather than silently removed.

## What NOT to cut

- Security constraints and irreversible-action guards.
- Genuine gotchas (non-obvious repo invariants).
- Exact commands, versions, and error strings — precision here is cheap and load-bearing.
- Trigger phrases in skill descriptions — they are how skills get found.

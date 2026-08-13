# Phase 3 — Slim

Cut what the config costs every turn, without losing what makes a skill findable.

## Work

Load `token-slim` through the resolver (`MODE=inline`) and apply both mechanics
to each skill under `INIT_TARGET/skills`:

- **Trim** the frontmatter `description` to at most 300 normalised chars,
  keeping every quoted trigger phrase. Descriptions load in every session; the
  body loads only on invocation, so this is the expensive half.
- **Split** a long body into `references/*.md`, linked from `SKILL.md`, so the
  detail loads on demand rather than on every invocation.

Skill directories are disjoint, so fan out one agent per skill.

## Gate

`init_gate.sh slim` — `check.sh` per skill against the phase-1 baseline, then
`sweep.py` for the plan-level totals. Between them they assert: description
within cap, every baseline trigger phrase still present somewhere in the skill
directory, every baseline heading still present, every `references/` link
resolving.

Both run because a trim can pass every skill individually and still blow the
total.

The usual failure is a trim that dropped a quoted trigger phrase. Restore the
phrase and cut padding instead — the phrase is how the skill gets found.

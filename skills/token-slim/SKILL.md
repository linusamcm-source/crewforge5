---
name: token-slim
model: sonnet
description: Cuts per-turn skill token load — "token-slim" a skills directory, "trim skill descriptions", "split a SKILL.md into references". Harness gates trims, verifies no trigger phrase or link is lost
disable-model-invocation: true
---

# Token-Slim — trim descriptions, split bodies into on-demand references

Skill frontmatter descriptions load **every turn** via the available-skills listing;
SKILL.md bodies load **at invocation**. This skill slims both, with a mechanical
harness proving nothing discoverable was lost. First applied to `$CLAUDE_CONFIG_DIR/skills/`
(2026-07: 24,512 → 11,016 desc chars, ~3,374 tok/turn saved; see
`skills/.token-slim/report.md` for that run's record).

## When to use

Also trigger on "audit skill token load", "skills are bloating my context",
"slim the skills", "my skill descriptions are too long", or after adding several
new skills to a repo. Works on any directory of `<skill>/SKILL.md` folders —
`$CLAUDE_CONFIG_DIR/skills/` or a project's `.claude/skills/`.

## Scripts

All take explicit paths — nothing is hardcoded to one repo:

```bash
SCRIPTS=${CREWFORGE_ROOT}/skills/token-slim/scripts
python3 $SCRIPTS/baseline.py --skills-dir <dir> --out <work>/baseline.json   # snapshot
python3 $SCRIPTS/baseline.py --skills-dir <dir> --report                     # live measure
bash    $SCRIPTS/check.sh <skill> <dir> <work>/baseline.json [desc-cap]     # per-skill gate
python3 $SCRIPTS/sweep.py --skills-dir <dir> --baseline <work>/baseline.json \
        [--ceilings <work>/ceilings.json] [--max-total N]                    # totals gate
bats    ${CREWFORGE_ROOT}/skills/token-slim/tests                                    # harness self-test
python3 $SCRIPTS/mech-candidates.py --skills-dir <dir> [--min-hits N]        # sandwich candidates
```

## Workflow

1. **Baseline (immutable).** Create a work dir `<skills-dir>/.token-slim/` (dot-prefixed
   so the skill loader ignores it). Run `baseline.py --out` into it and commit the
   snapshot before any edit. Every later gate compares against this file.
2. **Scope.** Trim-scope = descriptions >500 normalized chars → cut to ≤300.
   Split-scope = bodies >10k chars → extract conditional content to `references/*.md`.
   Assign each split skill a class ceiling (fraction of baseline body chars) and record
   them in `ceilings.json`: template-heavy ≤50%, runbook ≤75%, high-stakes runbook ≤80%,
   near-threshold ≤85%.
3. **Trim mechanic.** Rewrite the description to ≤300 normalized chars: imperative
   "Use when…" framing, strongest quoted triggers kept, single-line plain YAML scalar.
   Relocate the cut long-tail triggers and positioning prose into a `## When to use`
   section of the body — **nothing is deleted**. Every baseline quoted trigger phrase
   must survive verbatim somewhere in the skill's directory.
4. **Split mechanic.** Standing rule: **always-executed workflow stays inline; only
   genuinely conditional content moves** (templates, catalogs, integration guides,
   flag-gated steps). Move sections verbatim, headings included, and leave a one-line
   link at the extraction point stating when to load it. Detailed guidance, per-class
   judgment calls, and known caveats (symlinked skills, singular `reference/` dirs,
   protected byte-identical sections): [references/method.md](references/method.md).
5. **Verify per skill.** `check.sh` must exit 0 (desc cap, phrase retention, heading
   retention, link resolution). Split skills additionally get a skill-validator
   grade-A pass (0 failures, ≤2 warnings) — validators regularly surface real
   pre-existing defects (phantom file citations, stale references); fix those too.
6. **Sweep and report.** `sweep.py` with the ceilings file (and `--max-total` if the
   plan set one) must exit 0. Write a `report.md` in the work dir with per-skill
   before/after desc and body chars and the estimated per-turn saving (chars ÷ 4).

## Mechanisation candidates (optional audit)

Separate from slimming: `mech-candidates.py` ranks skills whose SKILL.md prose asks the
model to do countable work (count/verify/threshold/compare) that scripts would do
deterministically. Include the ranked list in `report.md` when asked for a full audit.
Detection only — the conversion is per-skill judgment work following
[references/script-sandwich.md](references/script-sandwich.md); never batch-transform.

## Orchestration

Skill dirs are disjoint, so trims and splits parallelize cleanly — one agent per
skill, each self-gating on `check.sh`, with an independent verifier re-running the
gates and judging trim quality. Re-run the gates yourself before committing; commit
per story/batch with the measured ratios in the message.

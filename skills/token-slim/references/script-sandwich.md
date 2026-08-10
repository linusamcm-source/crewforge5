# The script-sandwich pattern

Convert a prose-driven skill so scripts do the deterministic work and the model does
exactly one judgment job in the middle:

```
route (script) → load (script) → [MODEL JUDGES] → verify gates (scripts) → log (script)
```

Prose instructions like "count the directives", "verify identifiers survive", "check the
density dropped" are silent-failure points: the model may skip them, count them wrong, or
report compliance it didn't earn. As scripts they exit nonzero and can't be skipped.

## Components

- **Router**: classifies the input mechanically (signal scoring, file globbing, manifest
  parsing) and emits `key=value` lines the model reads. Confidence tiers, not binary:
  high = proceed with a stated receipt, medium = proceed but flag, low = ask the user.
- **Gates**: post-judgment verification with exit codes. Extract-then-diff invariants,
  before/after metric deltas, wordlist checks. A failing gate loops the model, not the user.
- **Ledger**: every phase (scripts AND model judgment findings) appends
  `FAIL [phase]: ...` / `WARN [phase]: ...` lines to one file.
- **Deterministic scorer**: any grade, pass/fail, or loop-termination decision is computed
  from the ledger by a script. The model never tallies its own homework — if prose and the
  scorer disagree, the scorer wins.

## What stays prose (correctly)

The actual judgment: rewriting, reviewing, extracting meaning, taste. Also anything whose
criteria can't be stated as a regex or a threshold without lying about precision. If a
"mechanical" script needs the model to interpret its output beyond read-the-numbers, the
boundary is in the wrong place.

## Worked examples in this repo

- `skills/humanise/scripts/` — sniff (router), packs (loader), invariants + tells +
  au-check (gates), deliver + feedback (log/learn loop). Model does one rewrite between them.
- `skills/skill-validator/scripts/` — validate_structure + functional + efficiency +
  baseline-drift (gates feeding a ledger), grade.sh (deterministic scorer). Model does
  compliance diagnosis and agent simulation between them.

## Anti-patterns

- **Decorative metadata**: a `voice_weight: 0.3` scalar the model "applies" dials nothing.
  Map every knob to named behaviour tiers with concrete examples, or delete it.
- **Gaming gates**: re-adding a lost heading to please a retention check instead of
  refreshing the baseline. Gates measure reality; fix reality or fix the baseline.
- **Judgment in a script**: a shell script that greps for "bad writing" isn't a gate, it's
  a worse model. Scripts get facts (counts, presence, deltas); models get calls.
- **Model-side tallying**: prose that says "grade A means 0 failures" invites rounding.
  Termination conditions belong in the scorer.

## Finding candidates

`scripts/mech-candidates.py --skills-dir <dir>` greps SKILL.md prose (code fences
stripped) for countable-work smells — counting, check-each, thresholds, comparing,
invariant language — and ranks skills by hit count with sample lines. Detection only:
read the samples and judge; a hit inside a genuinely judgment-bound sentence is a false
positive, and the conversion itself is a per-skill job, not a batch transform.

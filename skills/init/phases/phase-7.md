# Phase 7 — Report

Re-measure, and write down what actually changed.

## Work

Re-run the measurements from phase 1 against the tree as it now stands:

```bash
python3 "${CREWFORGE5_ROOT}/skills/token-slim/scripts/baseline.py" \
  --skills-dir "$INIT_TARGET/skills" --report
bash "${CREWFORGE5_ROOT}/scripts/budget_check.sh" --verbose
```

Write `$INIT_STATE/report.md`. It must carry the three measured numbers as
literal lines, because the gate re-measures and compares:

```
DESC_CHARS_BEFORE=<sum of desc_chars in baseline.json>
DESC_CHARS_AFTER=<same sum measured now>
DESC_CHARS_DELTA=<before - after>
```

Around them, in prose: which files phase 2 rewrote, which skills phase 3
trimmed or split, what phase 4 found, what phase 5 repaired, what phase 6
distilled — and anything a phase deliberately left alone, with the reason. A
report that lists only wins is not a record of the run.

## Gate

`init_gate.sh report` — the report exists and the three numbers in it match a
fresh measurement of the tree. A report claiming a saving the tree does not
support fails, because the one number anybody quotes should not be the one
number nobody verified.

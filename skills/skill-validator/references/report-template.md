# Report Template (Step 6)

Full template for the validation report written in Step 6. Copy it verbatim and fill in the placeholders.

Use this template:

```markdown
# Skill Validation Report: {skill-name}

**Date:** {YYYY-MM-DD HH:MM}
**Skill Path:** {path}
**Validator Version:** 1.2
**Mode:** {initial | report-only re-validation, round N}

## Summary

| Category | Pass | Warn | Fail | Skip |
|----------|------|------|------|------|
| Structural | X | X | X | X |
| Functional | X | X | X | X |
| Efficiency | X | X | X | X |
| Instruction Compliance | X | X | X | X |
| Agent Simulation | X | X | X | X |
| **Total** | **X** | **X** | **X** | **X** |

**Overall Grade:** {grade= value from grade.sh}

```
{verbatim grade.sh output: grade= fails= warns= skipped=}
```

<details><summary>Findings ledger</summary>

{verbatim ledger contents}

</details>

The scale lives in one place only — the header of `scripts/grade.sh`, which is the code that
applies it. Do not restate it here. A prose copy of this scale drifted a full grade away from
the executable one and survived, because a reader checks the nearest copy and the nearest copy
was wrong.

## Structural Validation
{checklist with PASS/WARN/FAIL per item}

## Functional Validation
{script results table}

## Efficiency Analysis

| Metric | Value | Status |
|--------|-------|--------|
| SKILL.md lines | X | PASS/WARN/FAIL |
| Estimated tokens | ~X | PASS/WARN/FAIL |
| Heavy directives | X | PASS/WARN |
| Progressive disclosure | X | PASS/WARN |

## Instruction Compliance

### Critical Instructions: {X}/{Y} clear ({Z}% compliance-ready)

{Compliance test matrix from Step 4c}

### Failure Modes Detected
{List of specific problems with fixes}

### Suggested Rewrites
{Before/after for each problematic instruction}

## Agent Simulation
{Test prompt, compliance results, timing}

## Recommendations
{Ordered list of fixes — failures first, then warnings, then improvements}
```

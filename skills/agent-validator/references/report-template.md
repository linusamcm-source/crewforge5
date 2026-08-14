# Agent Validator — Report Template (Step 6)

Load this file when writing the Step 6 report. Copy the template verbatim, filling the
placeholders.

The Overall Grade is whatever `grade.sh` printed — never a number you tallied yourself. Paste
its output block and the full ledger into the report verbatim; the rectifier parses them, and
if your prose summary and `grade.sh` disagree, `grade.sh` wins.

```markdown
# Agent Validation Report: {agent-name}

**Date:** {YYYY-MM-DD HH:MM}
**Agent Path:** {path}
**Validator Version:** 1.0

## Summary

| Category | Pass | Warn | Fail | Skip |
|----------|------|------|------|------|
| Structural | X | X | X | X |
| Tool Coherence | X | X | X | X |
| Efficiency | X | X | X | X |
| Instruction Compliance | X | X | X | X |
| Behavioral Simulation | X | X | X | X |
| **Total** | **X** | **X** | **X** | **X** |

**Overall Grade:** {grade= value from grade.sh}

```
{verbatim grade.sh output: grade= fails= warns= skipped=}
```

<details><summary>Findings ledger</summary>

{verbatim ledger contents}

</details>

The scale lives in one place only — the header of
`${CREWFORGE5_ROOT}/skills/skill-validator/scripts/grade.sh`, which is the code that
applies it. Do not restate it here. A prose copy of this scale drifted a full grade away
from the executable one and survived, because a reader checks the nearest copy and the
nearest copy was wrong.

## Structural Validation
{checklist with PASS/WARN/FAIL per item}

## Tool Coherence
{declared vs referenced tools matrix, skill reference checks}

## Efficiency Analysis

| Metric | Value | Status |
|--------|-------|--------|
| Agent file lines | X | PASS/WARN/FAIL |
| Estimated tokens | ~X | PASS/WARN/FAIL |
| Description (always-loaded) | X chars / ~X tok | PASS/WARN |
| Heavy directives (non-safety) | X | PASS/WARN |
| Safety-exempt directives | X | INFO — do not soften |
| Role statement | Present/Missing | PASS/WARN |
| Completion gate | Present/Missing | PASS/WARN |

## Instruction Compliance

### Critical Instructions: {X}/{Y} clear ({Z}% compliance-ready)

{Compliance test matrix from Step 4c}

### Failure Modes Detected
{List of specific problems with fixes}

### Suggested Rewrites
{Before/after for each problematic instruction}

## Behavioral Simulation
{Test prompts, compliance results, or SKIPPED}

## Recommendations
{Ordered list: failures first, then warnings, then improvements}
```

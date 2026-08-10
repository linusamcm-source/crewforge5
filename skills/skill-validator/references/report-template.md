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

**Overall Grade:** {A/B/C/D/F}
- A: All pass, 0-2 warnings — production-ready
- B: All pass, 3-5 warnings — usable, minor improvements recommended
- C: All pass, 6+ warnings — works but agents will be inconsistent
- D: 1-2 failures — needs fixes before deployment
- F: 3+ failures or critical failure — broken, do not deploy

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

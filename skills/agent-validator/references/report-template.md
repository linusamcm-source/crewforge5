# Agent Validator — Report Template (Step 6)

Load this file when writing the Step 6 report. Copy the template verbatim, filling the
placeholders. Content relocated verbatim from SKILL.md.

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

**Overall Grade:** {A/B/C/D/F}
- A: All pass, 0-2 warnings — production-ready
- B: All pass, 3-5 warnings — usable, minor improvements recommended
- C: All pass, 6+ warnings — works but agent will be inconsistent
- D: 1-2 failures — needs fixes before deployment
- F: 3+ failures or critical failure — broken, do not deploy

## Structural Validation
{checklist with PASS/WARN/FAIL per item}

## Tool Coherence
{declared vs referenced tools matrix, skill reference checks}

## Efficiency Analysis

| Metric | Value | Status |
|--------|-------|--------|
| Agent file lines | X | PASS/WARN/FAIL |
| Estimated tokens | ~X | PASS/WARN/FAIL |
| Heavy directives | X | PASS/WARN |
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

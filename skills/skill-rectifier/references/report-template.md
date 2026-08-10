# Rectification Report Template

Template for the report written in Step 7 of SKILL.md. Load this when generating the
rectification report.

```markdown
# Skill Rectification Report: {skill-name}

**Date:** {YYYY-MM-DD HH:MM}
**Skill Path:** {path}
**Source Validation Report:** {path-to-validation-report}
**Grade Before:** {original grade}
**Grade After:** {grade from the re-validation round if it has run, otherwise "pending re-validation (round N)" — never predict a grade}
**Round:** {N} of max 5

## Summary

| Category | Fixed | Deferred | Total |
|----------|-------|----------|-------|
| Structural | X | X | X |
| Functional | X | X | X |
| Efficiency | X | X | X |
| Instruction Compliance | X | X | X |
| **Total** | **X** | **X** | **X** |

## Changes Applied

### {Category}: {check_name}
**Severity:** FAIL/WARN
**Issue:** {what was wrong}
**Fix:** {what was changed}
**Files modified:** {list}
**Diff:**
```diff
- old content
+ new content
```

{repeat for each fix}

## Deferred Items

{Items that need human judgment — explain why they couldn't be auto-fixed}

## Verification

{Results of post-fix validation script run}

## Round History

| Round | Fixes Applied | FAILs After | WARNs After | Grade After |
|-------|--------------|-------------|-------------|-------------|
| 1 | X | X | X | {grade or pending} |

## Next Steps

- [ ] Review deferred items manually
- [ ] Test skill with a real prompt to verify agent compliance
```

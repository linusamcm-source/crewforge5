# Rectification Report Template (Step 7)

Load this file when writing the rectification report.

```markdown
# Agent Rectification Report: {agent-name}

**Date:** {YYYY-MM-DD HH:MM}
**Agent Path:** {path}
**Source Validation Report:** {path-to-validation-report}
**Grade Before:** {original grade}
**Grade After:** {expected grade after fixes}

## Summary

| Category | Fixed | Deferred | Total |
|----------|-------|----------|-------|
| Structural | X | X | X |
| Tool Coherence | X | X | X |
| Efficiency | X | X | X |
| Instruction Compliance | X | X | X |
| **Total** | **X** | **X** | **X** |

## Changes Applied

### {Category}: {check_name}
**Severity:** FAIL/WARN
**Issue:** {what was wrong}
**Fix:** {what was changed}
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

## Next Steps

- [ ] Review deferred items manually
- [ ] Re-run agent-validator to confirm grade improvement
- [ ] Test agent with a real prompt to verify behavioral compliance
```

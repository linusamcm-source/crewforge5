# AC Validation Report Template

Write the report using this exact structure so fix agents can parse it reliably.

```markdown
# AC Validation Report — {backlog-name or story-id}

**Date:** {ISO date}
**Source:** {path to backlog or story file}
**App URL:** {url}

## Summary

| Story | ACs | Pass | Fail | Blocked | Backend-only |
|-------|-----|------|------|---------|--------------|
| {story-id} | {n} | {n} | {n} | {n} | {n} |

## {story-id}: {story title}

### PASS

- **AC{N}:** {exact AC text}
  - Evidence: `{screenshot path}`

### FAIL

- **AC{N}:** {exact AC text}
  - Expected: {what the AC requires}
  - Actual: {observed behavior}
  - Screenshot: `{screenshot path}`
  - Selectors checked: {CSS selectors / element references}
  - Console errors: {output of browser_console_messages, or "none"}
  - Page snapshot: {DOM state summary at failure}

### BLOCKED

- **AC{N}:** {exact AC text}
  - Reason: {why test state could not be set up}
  - Screenshot: `{screenshot path}`

### BACKEND-ONLY

- **AC{N}:** {exact AC text} — not UI-testable; skipped ({reason})
```

Rules:

- Omit any section (PASS/FAIL/BLOCKED/BACKEND-ONLY) that has no entries.
- Quote AC text verbatim from the story file.
- Every PASS/FAIL/BLOCKED entry must reference a screenshot.

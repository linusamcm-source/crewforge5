# Report Template (Step 4 — Surface The Report)

```
## Pre-Commit Review — N findings

  CRITICAL: 0
  HIGH:     1
  MEDIUM:   3
  LOW:      4
  NIT:      2

[HIGH] [security] SQL string concatenation in src/db/foo.ts:42
       Use parameterised query.
[MED]  [consistency] New error class src/foo/MyError.ts duplicates
       AppError in src/errors/AppError.ts
[MED]  [perf] Unmemoised renderItem in app/saved-list/index.tsx:88
[MED]  [simplifier] new helper formatMaybe() wraps one ?? — inline it
[LOW]  ...

Status: BLOCKING — 1 HIGH finding present.
```

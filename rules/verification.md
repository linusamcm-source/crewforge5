---
description: Verification rules: never claim code works, an API exists, or a command succeeds without running it this session.
---

## Verification

Never state that code works, an API exists, or a command succeeds
unless it has been verified in this session.

- **APIs and library functions**: check the actual docs or type
  definitions before use. Do not rely on recalled signatures —
  they are frequently wrong for less common libraries and for
  anything that changed after training.
- **Existing code**: read the file before editing or describing it.
  Do not infer contents from filenames, imports, or earlier context.
- **Claims about behaviour**: run it. Tests, a REPL, or a throwaway
  script. "This should work" is not a result.
- **After edits**: re-read the changed region. Confirm the edit
  landed as intended rather than assuming the tool call succeeded.

When verification isn't possible, say so explicitly and label the
claim as unverified. An acknowledged gap is more useful than a
confident guess.


Precedence: skill and agent instructions win inside their own scope; this file wins on
process; `SOUL.md` wins on tone and judgment. Between two rules here, the specific beats
the general.


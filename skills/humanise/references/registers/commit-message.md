---
scenario: commit-message
extends: code-doc
---
# Register pack: commit message

Extends [code-doc.md](code-doc.md).

**Conventions**
- Imperative subject line, ≤72 chars, no trailing full stop.
- Body explains why, not what — the diff shows what.
- Match `git log --oneline -20` house style: conventional-commit prefixes (feat/fix/...) only if the repo uses them; emoji only if the repo uses them.
- No AU respelling of anything that names code.

**Tell emphasis**: "Updated code to", "Made changes to", "Various fixes", subject lines that describe the act of committing instead of the change.

---
scenario: readme
extends: code-doc
---
# Register pack: README

Extends [code-doc.md](code-doc.md) — inherits structural tier, strict invariants, spelling-only AU.

**Conventions**
- Order: what it is (one sentence) → why you'd use it → quickstart → detail. Readers bail early; front-load.
- Match the repo's existing heading depth and case; don't add badges, emoji, or a table of contents the repo doesn't already use.
- Code blocks must be runnable as written — they're covered by the invariant lockfile.
- Cut roadmap promises and "contributions welcome" boilerplate unless already present.

**Siblings**: other READMEs in the same repo/org define the house style. Vet each with `tells.sh --max 3` before imitating — an AI-generated sibling is contamination, not a style guide.

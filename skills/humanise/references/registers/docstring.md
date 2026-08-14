---
scenario: docstring
extends: code-doc
---
# Register pack: docstring / code comments

Extends [code-doc.md](code-doc.md) — inherits structural tier, strict invariants.

**Conventions**
- Language convention wins: PEP 257 for Python (imperative first line, closing `"""` placement), JSDoc/godoc/rustdoc per their norms.
- Match neighbouring docstrings in the same package — format, length, tone. The nearest three files are the style guide.
- Comments state constraints the code can't show, never narrate the next line.
- Parameter/return descriptions: noun phrases, no "This parameter is used to".
- AU spelling never overrides language keywords, API names, or existing identifier spellings.

**Tell emphasis**: "This function is responsible for", "In order to", redundant restatement of the signature.

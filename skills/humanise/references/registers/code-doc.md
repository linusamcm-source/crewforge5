---
scenario: code-doc
voice_tier: structural
au_intensity: spelling
invariants: strict
---
# Register pack: code documentation (base)

Base pack for repo-bound writing. README, PR description, docstring, and commit-message packs extend this one.

**The repo is the author, not the user.** Personal voice weight approaches zero: no personal idiom, no AU idiom. AU spelling only if the repo already uses it — sibling files win over the user's dialect preference (recipe in [../destination-sniffing.md](../destination-sniffing.md)).

**invariants: strict** means `invariants.sh verify` is a **blocking** gate: identifiers, commands, flags, versions, URLs, and paths must survive the rewrite byte-identical. Never respell an API name (`color` in a CSS API stays `color`).

**Conventions**
- Say what the thing does, not what it aspires to. No marketing adjectives on features.
- Present tense, active voice, second person for instructions.
- Match the house comment/doc style of neighbouring files, not a generic template.

**Tell emphasis**: "comprehensive", "seamless", "robust", "simply", "just", "powerful", feature lists of three.

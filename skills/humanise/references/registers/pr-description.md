---
scenario: pr-description
extends: code-doc
voice_tier: professional
---
# Register pack: PR description

Extends [code-doc.md](code-doc.md); voice tier raised to professional — a PR description can carry some of the author's voice.

**Conventions**
- Lead with what changed and why; reviewer-facing, not changelog-facing.
- Never open with "This PR". State the change directly.
- Reference issues/tickets by their real IDs (invariant-protected).
- Match the repo's merged-PR house style: `gh pr list --state merged --limit 5 --json title,body` — vet each body with `tells.sh --max 3` before imitating.
- Test plan section only if the repo's PRs have one.

**Fact-grounding (optional but cheap)**: cross-check the description's claims against `git diff main...` — a described change that isn't in the diff is a bug in the description, flag it to the user.

# Architecture Decision Records

This directory holds the team-sprint skill's ADRs. Each ADR captures one
decision: its context, the options considered, the chosen option, and the
consequences. ADRs are append-only history — they document why something
is the way it is, not how to do it (that lives in `SKILL.md`, `$PHASES/`,
and `$REF/`).

## Filename scheme

```
<3-digit-zero-padded>-<kebab-slug>.md
```

Examples:

- `001-subskill-extension-surface.md`
- `002-coverage-gate-modes.md`
- `017-merge-strategy.md`

The kebab-slug is short (2–6 hyphenated words), lowercase, ASCII.

## Numbering

- **Monotonic.** Each new ADR takes the next integer.
- **Assigned at PR open.** The author picks the next free number when they
  open their PR — not at branch-creation, not after merge.
- **Never renumbered after merge to `main`.** Once an ADR's number lives in
  `main`, that number is permanent. Subsequent ADRs cite the old number;
  rewriting history would break those citations.

## Concurrent-PR tiebreaker

If two PRs are opened with the same `NNN-` prefix (a numbering collision):

1. **Earlier `mergedAt` keeps the number.** The PR that merges first wins
   the lower number; its filename stays as-is.
2. **Later `mergedAt` renumbers.** The PR that merges second must rebase,
   rename its ADR file to the next available integer, and update any
   internal links — **in its merge commit**, not a follow-up PR.
3. **Resolve `mergedAt` via `gh`.**
   ```bash
   gh pr view <pr-number> --json mergedAt
   ```
4. **Reviewers of the later PR enforce the rebase before approval.** Any
   post-merge renumbering on `main` is rejected as a breaking change
   (other ADRs' "See ADR-NNN" references would silently rot).

## Linking from SKILL.md

Each ADR is appended to the `## Architecture & decisions` section of
`SKILL.md` by number + title. The linter (mech-14) does NOT enforce this
yet — authors do it manually as part of the ADR-introducing PR.

---
name: code-reviewer
model: opus
description: Code review for TypeScript, JavaScript, Python, Swift, Kotlin, Go — use when reviewing a pull request, diff, or staged changes, giving code feedback, or security scanning before merge
disable-model-invocation: true
---

# Code Reviewer

Tooling and reference material for thorough code review across multiple languages.

## When to Use

- The user asks to "review this code", "review this PR", "review the diff"
- Pre-commit / pre-merge gate (often invoked via `/pre-commit-review-fleet`)
- Phase 4 of `/team-sprint` as the `code-reviewer` role
- Spot-checking a file the user is about to ship

Includes automated code analysis, best-practice checking, security scanning, and review checklist generation. When invoked as part of a multi-agent review (e.g. `/team-sprint` Phase 4 or `/pre-commit-review-fleet`), deliver findings per the sprint's delivery contract (`${CREWFORGE5_ROOT}/skills/team-sprint/references/sendmessage-protocol.md`): structured findings as your **final agent return** to your spawner, written into the story-keyed review artifact — inline-only descriptions that reach neither channel do not satisfy the review contract.

This skill and the `code-reviewer` **agent** under `agents/` share a name on purpose: the agent is the spawnable reviewer identity (crew-factory's reuse candidate), this skill is the procedure either that agent or a crew-generated reviewer loads. When both are in play, the agent is spawned and this skill is what it follows.

## Workflow

1. **Scope.** Identify what to review: a diff (`git diff`, PR), a file, a directory, or staged changes (`git diff --cached`). When in doubt, ask the user.
2. **Read with context.** Read the file(s) and their immediate dependencies before forming an opinion. Reviewing in isolation produces shallow findings.
3. **Run the checklist.** One pass per dimension, in this order: correctness, design, security, performance, testing, accessibility, docs. A pass that finds nothing is reported as such — silence reads as "not looked at".
4. **Ground the claims in tool output.** Run whatever the repo already has — its linter, type checker, test suite, `git diff --stat` — and cite what they printed. A finding backed by a command someone else can re-run survives disagreement; an assertion does not.
5. **Categorise findings.** Severity-tag every finding:
   - `CRITICAL` — security vuln, data loss, crash, broken contract
   - `HIGH` — likely bug, broken edge case, missing test, perf regression
   - `MEDIUM` — design smell, simplification opportunity, missing docs
   - `LOW` — nit, style, naming
6. **Deliver.** If reviewing standalone for a user, return the report inline. If invoked from a multi-agent sprint, ALSO deliver via `SendMessage` to `team-lead` with structured JSON:
   ```json
   {"reviewer": "code-reviewer", "findings": [{"severity": "...", "file": "...", "line": 42, "issue": "...", "fix": "..."}]}
   ```

## Languages and Stacks Covered

**Languages:** TypeScript, JavaScript, Python, Go, Swift, Kotlin, Rust
**Frontend:** React, Next.js, React Native, Svelte, Vue, Flutter
**Backend:** Node.js, Express, GraphQL, REST APIs, gRPC
**Database:** PostgreSQL, Prisma, NeonDB, Supabase, MySQL, SQLite
**DevOps:** Docker, Kubernetes, Terraform, GitHub Actions, CircleCI
**Cloud:** AWS, GCP, Azure

## What To Look For

### Correctness
- Off-by-one errors, sign errors, comparison operators (`<` vs `<=`)
- Null/undefined handling at every boundary
- Race conditions and shared mutable state
- Error swallowing (`catch { }` with no logging or rethrow)
- Failure modes: what happens when the network/disk/DB is unreachable?

### Security
- Input validation at trust boundaries
- SQL injection, command injection, path traversal
- Authentication/authorization on every protected route
- Secrets in source/env files
- Dependency vulnerabilities (`npm audit`, `pip-audit`, `govulncheck`)
- CSRF, XSS, SSRF in web handlers

### Design
- Cohesion and coupling — does this module do one thing well?
- Naming clarity — would a new contributor understand this in 30 seconds?
- Abstraction level — too thin (boilerplate) or too thick (over-engineered)?
- Public API surface — minimal? hard to misuse?

### Performance
- N+1 queries, unbatched API calls
- Unnecessary allocations in hot paths
- Missing indexes on queried columns
- Render thrash, re-render loops in UI

### Testing
- Coverage of acceptance criteria
- Edge case tests (empty, single, max, error, timeout)
- Mocked vs integration coverage — are the integration boundaries actually exercised?
- Test brittleness (over-coupled to implementation)

## Codebase intelligence

Primary recon is the repomix pack via `use-repo-code` — hidden from the catalogue, so resolve it: `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code` answers `MODE=agent`; spawn it through the `Agent` tool with the type its frontmatter names, never inline (it forks precisely to keep the pack out of this window). The pack is `.repomix-output.xml`, regenerated on demand by `bash ${CREWFORGE5_ROOT}/skills/use-repo-code/scripts/pack.sh`.

The full source guide — pack vs `graphify` vs `claude-mem`, and the evidence rules (live tree wins; freshness-check snapshots; memory never grounds current-code claims) — has one home: read `${CREWFORGE5_ROOT}/skills/use-repo-code/references/codebase-intelligence.md` before your first finding. Both optional tools are fail-soft.

## Anti-patterns to Avoid in Your Own Review

- **Approving without reading.** Skim ≠ review.
- **Shallow nits only.** Style nits without a single substantive finding suggests you didn't go deep enough.
- **Vague findings.** "This is wrong" → unactionable. Always include file:line and a concrete fix.
- **Missing severity.** Without severity, the lead can't triage. Always tag.
- **Inline-only delivery in a multi-agent context.** Not delivered via `SendMessage` = not delivered.

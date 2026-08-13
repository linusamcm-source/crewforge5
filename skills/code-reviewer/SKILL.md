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

Includes automated code analysis, best-practice checking, security scanning, and review checklist generation. When invoked as part of a multi-agent review (e.g. `/team-sprint` Phase 4 or `/pre-commit-review-fleet`), the reviewer MUST deliver findings to team-lead via SendMessage — inline-only descriptions do not satisfy the review contract.

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

## Codebase intelligence: repomix + graphify + claude-mem

Ground every finding in the source that fits the question — the repomix pack is the default recon target; three complementary tools:

- **repomix pack (default)** via the `use-repo-code` skill — the repo is packed at session start (`repomix-prewarm.sh` → `.repomix-output.xml`). Search it with bash `grep`/`rg` (the RTK `PreToolUse` hook rewrites these to `rtk grep`/`rtk rg`, so output is token-filtered and grouped by file) instead of per-file `Read`. This is your primary recon: existence checks, symbol/caller text search, file-list verification, "does this already exist". `<file path="...">` tags are the jump target; use live `Read` only for the exact lines you will edit or debug.
- **`graphify`** (optional, on-demand — only when the question is *relational*, not textual; needs `graphify-out/graph.json`): repomix grep finds occurrences, graphify answers reachability/coupling that text can't. Before flagging duplication, dead code, or a risky change, `graphify query "what calls <symbol>"` shows the real caller set / blast radius and whether a canonical helper already exists rather than the one being added. Reach for it only when you need the relationship — not for routine lookups. Prefer the CLI (`graphify query "what calls X"`, `graphify path "A" "B"`, `graphify explain "N"`) over grepping `graph.json` raw. Fail-soft: if its tools aren't loaded, skip it — repomix + the live tree carry the review.
- **`claude-mem`** (optional): decisions, conventions, and known issues recorded across past sessions. Recall via the `mem-search` skill or `memory_search`/`observation_search` → `get_observations`; record a durable new finding with `observation_add`/`memory_add` (≤500-token summary).

Evidence rules: when these sources and the live tree disagree, the **live tree wins**; freshness-check any snapshot before citing it; `claude-mem` grounds *intent/history* claims, never *current-code* claims — verify those with repomix grep. `graphify` and `claude-mem` are both optional and **fail-soft**: if their tools aren't loaded, work from the repomix pack + the live tree.

## Anti-patterns to Avoid in Your Own Review

- **Approving without reading.** Skim ≠ review.
- **Shallow nits only.** Style nits without a single substantive finding suggests you didn't go deep enough.
- **Vague findings.** "This is wrong" → unactionable. Always include file:line and a concrete fix.
- **Missing severity.** Without severity, the lead can't triage. Always tag.
- **Inline-only delivery in a multi-agent context.** Not delivered via `SendMessage` = not delivered.

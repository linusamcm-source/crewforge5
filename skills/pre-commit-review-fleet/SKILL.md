---
name: pre-commit-review-fleet
model: opus
description: Run a parallel reviewer fleet (security, performance, consistency, simplifier) over the staged diff; severity-ranked report, optional HIGH auto-patch. Use when asked to "review my staged changes", "run the review fleet", "audit this diff", "is this safe to commit", or on /pre-commit-review-fleet.
disable-model-invocation: true
---

# Pre-Commit Review Fleet

## Why This Skill Exists

A human pre-commit review is one perspective. Real bugs hide in the gaps
between perspectives — a security reviewer spots an SSRF, a perf reviewer
spots an N+1 query, a consistency reviewer notices the new file ignores
an existing pattern, and a simplifier notices the change introduces an
abstraction it does not need.

Spawning all four in parallel on the staged diff turns "the review I
should have done" into a 60-second gate. The team has caught a
HIGH-severity issue in past reviews this way; the cost of running it on
every non-trivial commit is small. The cost of *not* running it shows up
during code review, deploy, or production.

## When To Use

Trigger on:

- About to commit a non-trivial change (more than ~30 lines of diff or
  any change touching `src/`, `app/`, `db/`, security-relevant code,
  build config, or shared utilities).
- The user explicitly asks for a review, audit, or sanity check on
  staged changes.
- The user says "review the diff before I commit", "do a quick
  pre-commit review", "find issues before I push", "check for
  security/perf/consistency issues", "anything wrong with this diff",
  "review-staged", or "before I land this".
- Pre-PR review gate before opening a pull request.

Default to triggering when the user is staging or about to commit
non-trivial code — this is the team's last cheap chance to catch issues
before they enter the branch history.

Skip on:

- Tiny diffs (typo fixes, comment-only changes, doc-only edits).
- Generated-file diffs (lockfiles, snapshot test outputs).
- Pure formatting changes (Prettier reflow). The reviewers would just
  return noise.

## Intake gate — ask before spawning the fleet

Before spawning reviewers, if not already clear from the invocation, call **AskUserQuestion** to confirm scope and disposition. Ask only the open questions.

- **HIGH findings** — What should happen to HIGH-severity findings? Options: `Report only, I'll fix them (Recommended)` / `Auto-patch HIGH findings` / `Auto-patch everything HIGH and above`.
- **Lenses** — Which reviewers should run? (multiSelect) Options: `Security` / `Performance` / `Consistency` / `Simplifier`. Default to all four if the user has no preference.

Spawn only the selected lenses and follow the chosen disposition when the aggregated report is ready.

## Inputs

The skill expects:

- A non-empty staged diff (`git diff --cached`). If empty, abort with a
  message: *"No staged changes — stage with `git add` first."*

Optional:

- `--scope=<paths>` to restrict the review to a subset of staged paths.
- `--severity=<floor>` to filter findings (default: report everything,
  block on HIGH+).
- `--auto-fix` to spawn a fix-implementer for HIGH findings.

## The Four Reviewers

Each reviewer is a focused subagent with a system prompt tuned to its
lane. All four read the same staged diff plus relevant context files.

### 1. Security Reviewer

Looks for:

- Injection vectors (SQL, command, prompt, template, log)
- Secret leakage (API keys committed, secrets in logs, secrets in error
  messages)
- Auth/authz gaps (missing checks, broken role boundaries, IDOR)
- SSRF / path traversal / unvalidated redirects
- Crypto misuse (weak hashes, fixed IVs, missing constant-time compares)
- Data exposure (over-permissive DB queries, PII in client logs)
- Trust-boundary violations in LLM-touched code (unescaped tool input,
  prompt injection vectors)

Default recon is `use-repo-code` / `rtk grep` on the repomix pack for the text hits —
where untrusted input enters, which sinks exist. When a graph exists, use `graphify`
to confirm the taint path — `graphify path "<untrusted-input>" "<sink>"` proves
whether tainted data actually reaches a dangerous call, and `graphify query "what
calls <auth-check>"` finds paths that bypass it; otherwise trace it with
`use-repo-code` / `rtk grep` on the pack. Use `claude-mem` to recall prior security
decisions and known-vuln patterns the project already logged, so a finding can cite
them.

### 2. Performance Reviewer

Looks for:

- N+1 queries / loops doing per-iteration I/O
- Sync work in async contexts (and vice versa)
- Missing memoisation on hot paths (React `useMemo`/`useCallback`,
  Skia draw loops, FlatList renderItem creation)
- Unbounded list growth, cache misses, allocations in hot paths
- Big O regressions (nested loops where a Set/Map would do)
- Bundle-size impact of new imports (especially RN/Expo)
- Unnecessary re-renders / re-computes / re-builds

Default recon is `use-repo-code` / `rtk grep` on the repomix pack to find the changed
code and count its call sites. When a graph exists, use `graphify` to confirm the hot
path — `graphify query "what calls <fn>"` shows the caller fan-in, and a path into a
render/draw/request loop turns "looks expensive" into "expensive on a hot path";
otherwise judge the fan-in from `use-repo-code` / `rtk grep` on the pack. Use
`claude-mem` to recall perf hotspots and regressions the project previously recorded.

### 3. Codebase-Consistency Reviewer

Looks for:

- New code that ignores an established pattern or a decision recorded in
  `claude-mem` (project memory of prior decisions/conventions)
- Inline duplication of a utility that already exists in the repo — default to
  `use-repo-code` / `rtk grep` on the pack to find the canonical `<helper>`; when
  a graph exists, use `graphify` to confirm what calls it
- Locally invented error class / store key / type union that conflicts
  with a canonical one
- Naming that breaks the project's conventions (file paths, export
  shapes, MMKV keys, route names)
- Skipped quality gates (untested code in covered dirs, missing i18n
  keys for user-facing strings)
- Drift from CLAUDE.md or from a convention recorded in `claude-mem`

This reviewer leans on three sources: `use-repo-code` / `rtk grep` on the pack as
the default for fast text lookup, `graphify` (optional, when a graph exists) for
"does this utility already exist / what depends on the symbol being changed", and
`claude-mem` for recorded conventions and decisions. See
[references/codebase-intelligence.md](references/codebase-intelligence.md).

### 4. Simplifier

Looks for:

- New abstractions introduced for a single caller
- Helper functions that wrap one stdlib/library call
- Defensive code for impossible states (validating internal invariants,
  null checks where the type system already guarantees non-null)
- Half-finished refactors / TODO trails
- Backwards-compat shims for code with no other callers
- Comments that explain *what* the code does (vs *why*) — flag for
  removal
- Premature parameterisation (config knobs no caller exercises)

The simplifier follows the project rule: *"Three similar lines is better
than a premature abstraction."*

"Introduced for a single caller" and "shim for code with no other callers" are
literally caller-count questions — default to `use-repo-code` / `rtk grep` on the
pack to count call sites; when a graph exists, use `graphify query "what calls
<symbol>"` to confirm the fan-in before flagging, so the finding rests on a real
count, not a guess. Use `claude-mem` to avoid re-flagging an abstraction a prior
decision deliberately kept.

## Workflow

### Step 1 — Capture The Diff

```bash
bash ~/.claude/skills/pre-commit-review-fleet/scripts/capture-diff.sh [scope-paths...]
```

Exit 1 = nothing staged, abort with its message. It writes the patch, prints
file/insertion/deletion counts, and classifies triviality (`trivial=yes` = all
docs/lockfiles/snapshots — the documented skip case; `trivial=maybe` = under 30
lines, your call). If `--scope=` is set, pass the paths as arguments.

### Step 2 — Spawn All Four Reviewers In Parallel

Launch all four subagents in **a single message** so they run
concurrently. Each gets:

- The full staged diff (or scoped diff)
- Read access to the live tree
- Pointers to the three codebase-intelligence sources — `use-repo-code`
  (text), `graphify` (structure/coupling, when a graph exists), `claude-mem`
  (recorded decisions/conventions) — see [references/codebase-intelligence.md](references/codebase-intelligence.md)
- Their role contract (lane, severity scale, output format)

Output contract per reviewer:

```json
{
  "reviewer": "security",
  "findings": [
    {
      "severity": "HIGH",
      "title": "SQL string concatenation in src/db/foo.ts:42",
      "evidence": "src/db/foo.ts:42 — `db.run(\"SELECT * FROM x WHERE id=\" + req.id)`",
      "why": "Allows SQLi via the `id` request parameter",
      "fix": "Use parameterised query: `db.run(\"SELECT * FROM x WHERE id=?\", req.id)`"
    }
  ]
}
```

**Delivery — final agent return in BOTH modes:** each reviewer returns
this JSON as its **final agent output** to its direct spawner. In a
standalone run the spawner is the invoking session; under `/team-sprint`
Phase 7 the spawner is `team-lead` (the fleet reviewers are lead-spawned
direct children), so the final return reaches the lead with no boundary
to cross. The spawner persists each reviewer's JSON to a per-reviewer
artifact (see Step 3) — that artifact, not a message, is the durable
delivery record. If a reviewer also carries `SendMessage`: load [references/delivery-sendmessage.md](references/delivery-sendmessage.md) for the optional belt-and-braces send.

### Step 3 — Aggregate Into A Ranked Report

**Completeness check first.** Before ranking, confirm all four reviewers
are accounted for. The aggregation step reads each reviewer's persisted
artifact — under `/team-sprint` Phase 7 the lead writes each reviewer's
final-return JSON to `$ART/reviews-sprint-round-<N>-<reviewer>.md`; a
standalone run persists to `docs/review-fleet-runs/<timestamp>-<reviewer>.json`.
Mechanised:

```bash
S=~/.claude/skills/pre-commit-review-fleet/scripts
bash $S/fleet-complete.sh <artifact-dir> security performance consistency simplifier
```

Exit 1 lists the missing/invalid reviewers — re-spawn them (or STOP and
surface after one re-spawn) rather than aggregating an incomplete fleet. A
reviewer that found nothing still writes an artifact recording zero findings,
so "delivered, zero findings" is never confused with "never delivered".

Then merge — also mechanical, never hand-merge or hand-rank:

```bash
bash $S/aggregate.sh <artifact-dir> --out docs/review-fleet-runs/<timestamp>.md
```

It ranks by severity, dedupes same-`file:line` findings across reviewers
(contributing reviewers listed), renders the table, and computes the commit
verdict (`block` = CRITICAL present, `waive` = HIGH present, `pass`). If the
model's summary and the script's verdict disagree, the script wins. Severity
meanings:

- **CRITICAL** (block commit): exploitable security issue, data loss
  risk, broken core invariant.
- **HIGH** (block commit unless waived): likely real bug, perf
  regression on a known hot path, codebase pattern violation that will
  cause future drift.
- **MEDIUM** (do not block, must address before PR review): smell,
  ambiguity, missing test, simplification with clear win.
- **LOW** (FYI): nit, polish, style note.
- **NIT** (suppress unless `--verbose`): pure preference.

Deduplication is aggregate.sh's job (same `file:line` collapses to one entry
with contributing reviewers listed). Your judgment call on top: findings at
*different* locations that are really one root cause — merge those manually
and keep the strongest fix suggestion.

### Step 4 — Surface The Report

Print a compact summary in the conversation — for the exact format, load [references/report-template.md](references/report-template.md).

### Step 5 — Decide On Action

Three modes:

1. **Default:** report only, leave commit decision to user.
2. **`--auto-fix`:** for each CRITICAL/HIGH finding, spawn a
   fix-implementer with the exact finding payload as input. Fix
   implementer applies the fix, re-runs the relevant reviewer to
   confirm resolution, and re-stages. Loop with a hard cap of 2
   fix-rounds before falling back to mode 1.
3. **Hook-blocked:** if wired into a `pre-commit` git hook (see
   [references/pre-commit-hook.md](references/pre-commit-hook.md)), the commit is blocked until findings are resolved or the
   commit message contains an explicit waiver token (e.g.
   `// REVIEW-WAIVED: <reason>`).

### Step 6 — Persist The Report

Save the full report (including evidence and fix payloads) to
`docs/review-fleet-runs/<timestamp>.md` so the user can refer back to
it during PR review or after landing.

To wire the fleet into a git pre-commit hook: load [references/pre-commit-hook.md](references/pre-commit-hook.md).

For the full recon-source guide (repomix pack vs graphify vs claude-mem, plus evidence rules): load [references/codebase-intelligence.md](references/codebase-intelligence.md).

If a reviewer misbehaves (no findings on a risky diff, severity disagreement, `--auto-fix` looping, huge diff): load [references/failure-modes.md](references/failure-modes.md).

## Tone & Posture

The fleet is a colleague doing pre-flight checks, not a gatekeeper. It
should be terse, evidence-based, and pragmatic. A finding without
evidence and a concrete fix is noise — the reviewers must produce both.
The user always retains the final call; the fleet's job is to make sure
the call is informed.

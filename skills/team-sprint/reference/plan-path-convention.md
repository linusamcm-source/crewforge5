**WHO READS THIS / WHEN:** Phase 0 pre-flight reads this before running `scripts/validate_plan_path.sh` against `$plan_path`; `team-sprint-planner` follows the same convention when naming the plan file (its step 5), so its review loop and this skill's Phase 0 agree on the slug.

### Plan path naming convention (REQUIRED — uniqueness contract)

**Rule:** every plan filename MUST include the user story id (or, for multi-story plans, the epic/sprint id) as a slug component. Plans without a story slug are rejected at Phase 0.

**Why:** the worktree name, sprint branch, state directory, and per-sprint artifact dir are all derived from the plan filename (`worktree_name: sprint-<auto-slug-from-plan>`). Two plans with overlapping filenames silently overwrite each other's `state.json`, `plan-final.md`, review artifacts, and reports. A plan path that does not carry the story id is a uniqueness bug waiting to happen.

**Required form (single-story plan):**

```
<dir>/<story-id>-<short-kebab-slug>.md
e.g. _bmad-output/planning-artifacts/1-0-aws-region-realignment.md
     docs/bug_fixes/BUG-417-tide-cache-stale.md
```

- `<story-id>` is the canonical story identifier from the tracker / spec (`1-0`, `1-15`, `BUG-417`, `2026-05-03T21-34-30Z`).
- `<short-kebab-slug>` is 2–5 hyphenated words describing the change, kebab-case, lowercase.
- No spaces, no underscores in the story-id component, no duplicate filenames across the `<dir>` namespace.

**Required form (multi-story plan):**

```
<dir>/<epic-or-sprint-id>-<short-kebab-slug>.md
e.g. _bmad-output/planning-artifacts/epic-1-credit-economy-sprint.md
     docs/bug_fixes/bug-sweep-2026-05-12.md
```

Multi-story plans still need a unique top-level id so the worktree and state dir don't collide with another sprint started the same day.

**Phase 0 validator (`scripts/validate_plan_path.sh`):**

Phase 0 step 7 runs the bundled script `scripts/validate_plan_path.sh` (where `$SKILL_DIR` is this skill's install directory) against `$plan_path`. It is a real, shell-syntax-checkable script — not inline pseudocode — and is reused by `team-sprint --abort`:

```bash
if verdict=$(bash "$SKILL_DIR/scripts/validate_plan_path.sh" "$plan_path"); then
  eval "$verdict"          # stdout is eval-safe: STATUS=OK|RESUME, SLUG=…, SPRINT_DIR=…
  [[ "$STATUS" == RESUME ]] && info "resuming — Phase 0 step 8 surfaces the resume state"
else
  # exit 1/2 — the script printed the offending filename + required form to stderr
  fail "plan-path validation failed — STOP; surface the script's stderr reason to the user"
fi
```

### Plan format

Markdown. Auto-detect multi-story (one `## Story <id>: <title>` heading per story, each carrying `### Acceptance Criteria` + `### Definition of Done`) vs single-story (no `## Story` headings — entire plan = one implicit story keyed by filename). Phases 3–6 iterate once per story (one commit each); Phase 7 runs once at sprint end.

**`### Boundaries:` — cross-boundary review scope (optional per story).** Lists the
cross-language, cross-repo, and deployment artifacts a story's **correctness** depends on
even though the story never edits them:

```markdown
### Touches: services/gateway/internal/server/spotconfig_cap.go
### Boundaries: services/lambdas/auth/pre_token.py (produces custom:tier),
                packages/infra-consolidated/lib/config/dev.ts (decides which env runs this),
                ~/Development/other-app/src/services/spotConfigApiService.ts (the real caller)
```

It is a **review-scope directive only**. It MUST NOT reach the dependency DAG: `### Touches:`
feeds inferred edges (`dependency_source: hybrid`, `infer_from_touches: true`), so a boundary
path landing in `touches[]` would invent phantom edges and corrupt Phase 2 scheduling.
`parse_stories.sh` ignores the section by construction — `classify()` recognises only
ac/dod/deps/touches — and `scripts/tests/boundaries_dag_isolation.bats` pins byte-identical
graph output with and against it.

Phase 1 reviewers must cite every `Boundaries:` entry or state why it is irrelevant, and may
**add** boundaries the plan omitted — the section is authored by the same person whose blind
spot produced the gap, so treat it as a floor, never a ceiling.

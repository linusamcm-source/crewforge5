# Sprint: team-sprint Mechanical Refactor (`team-sprint-mech`)

**Goal:** Optimise `$HOME/.claude/skills/team-sprint` by extracting mechanical pseudocode into executable scripts, splitting SKILL.md into per-phase reference docs, tightening defaults, and closing under-specified contract gaps. No behavioural regression to the resume contract or to existing sub-skill integrations.

**Target directory:** `$HOME/.claude/skills/team-sprint/`
**Target branch:** `develop` (or `main` if the skills repo has no `develop`)
**Out of scope:** Per-repo `team-sprint` variants under `~/Development/*`; new sub-skills; rewriting `validate_plan_path.sh` (interface stable).

**Why this plan exists:** SKILL.md is currently 492 lines, with several phases describing mechanical work as inline pseudocode (lead validator, finding application, coverage parsing, commit message build, resume scan). LLM-driven mechanical work is non-deterministic, expensive in tokens, and untestable. Extracting these to `scripts/*.sh` makes them deterministic, shell-syntax-checkable, fixture-testable, and cheap. Splitting the prose into per-phase docs loaded on-demand cuts per-turn context cost ~60%.

**Conventions for this plan:**
- `$SKILL_DIR` = `$HOME/.claude/skills/team-sprint`
- `$SCRIPTS` = `$SKILL_DIR/scripts`
- `$PHASES` = `$SKILL_DIR/phases`
- `$REF` = `$SKILL_DIR/reference`
- Every script: `set -euo pipefail`, `#!/usr/bin/env bash`, bash 3.2-safe (macOS default).
- Every script produces JSON on stdout (eval-safe KEY=VALUE only where back-compat with `validate_plan_path.sh` is required).
- Every script has at least one bats fixture under `scripts/tests/`.

---

## Story mech-1: Foundation library + state management

### Context
Every later script needs shared logging, JSON helpers, ART (per-sprint artifact dir) resolution, and atomic state.json read/write. Currently the lead does state I/O inline in prose; this is the highest-frequency mechanical step. Centralising it once unblocks every later story.

### Acceptance Criteria
- `$SCRIPTS/lib.sh` exists and is sourced (not executed) by all other scripts. Provides: `log()`, `info()`, `warn()`, `fail()` (exits 1 with stderr message), `art_dir <plan_path>` (returns `.team-sprint/sprints/sprint-<slug>`), `require_jq()` (asserts `jq` on PATH; fails loud).
- `$SCRIPTS/state.sh` exposes subcommands:
  - `state.sh init <plan_path> <target_branch> <worktree_name>` — creates fresh state.json under ART, fails if one already exists with `done != true`.
  - `state.sh read <plan_path>` — prints state.json to stdout; exits 2 if missing.
  - `state.sh update <plan_path> <key>=<json-value>` (repeatable) — merges into state.json atomically (`jq` + `mv`); preserves keys not mentioned.
  - `state.sh advance-phase <plan_path> <N>` — sets `current_phase`; fails if N != current+1 unless `--force`.
  - `state.sh resume-scan` — lists every `.team-sprint/sprints/*/state.json` with `done != true` as JSON array: `[{slug, plan_path, current_phase, started_at}]`.
- `$SCRIPTS/state.schema.json` is JSON Schema draft-2020-12 covering every field in state.json. `state.sh` validates writes against it.
- Atomicity: state updates use `tmpfile + mv` pattern; concurrent invocations cannot corrupt state.json.
- All operations bash 3.2-safe; verified by running each command on stock macOS bash.

### Definition of Done
- `bash -n $SCRIPTS/lib.sh $SCRIPTS/state.sh` passes.
- `shellcheck $SCRIPTS/lib.sh $SCRIPTS/state.sh` passes with zero findings.
- Bats fixture exercises: init → read → update (3 keys) → advance-phase (valid + invalid) → resume-scan (0 sprints, 1 sprint, 2 sprints, 1 finalised + 1 active).
- `state.sh update` with a schema-violating value exits 1 and leaves state.json unchanged.
- SKILL.md Phase 0 / Phase 2 references update to call `state.sh` instead of describing the JSON inline.

---

## Story mech-2: Adversarial lead validator script

### Context
SKILL.md Phase 1 contains ~25 lines of bash pseudocode for the lead-side validator that strips hallucinated findings. Currently the lead is expected to run this inline. Hallucination filtering is critical — a fabricated CRITICAL blocks the sprint. Must be deterministic.

### Acceptance Criteria
- `$SCRIPTS/lead_validator.sh <plan_path> <findings_json>` reads JSON from stdin OR a file arg, returns two JSON arrays on stdout: `{"accepted": [...], "rejected": [{...finding, "reject_reason": "..."}]}`.
- Validation rules (all enforced):
  1. `quoted_evidence` is non-empty.
  2. `quoted_evidence` is a verbatim substring of the plan (use `grep -F -q`).
  3. `story_id` matches a heading in the plan OR equals `"*"` for cross-cutting findings.
  4. CRITICAL/HIGH findings must have non-empty `recommendation`.
  5. `severity` ∈ {CRITICAL, HIGH, MEDIUM, LOW, UNVERIFIED}.
- Exit code 0 always (validator is a filter, not a gate); caller decides on counts.
- Per-chunk reject-rate calculator: `lead_validator.sh --reject-rate <findings.json>` returns single number 0.00–1.00.
- Output is reproducible — same inputs produce identical bytes.

### Definition of Done
- `shellcheck` clean.
- Bats fixture covers: empty input, all-accepted, all-rejected, mixed, unicode in quoted_evidence, `story_id: "*"` with valid cross-cutting evidence, missing recommendation on HIGH.
- SKILL.md Phase 1 prose collapses the inline pseudocode into a 3-line description + reference to the script.
- Reject-rate threshold (>50% triggers chunk re-run) referenced from the script, not duplicated in prose.

---

## Story mech-3: Plan revision script (apply_findings)

### Context
SKILL.md Phase 1 step "`apply_findings_to_plan` — mechanical plan revision" is currently fully prose. The lead is told to "rewrite the surrounding paragraph or AC bullet per `finding.recommendation`". That's LLM judgement, not mechanical — but the locating + diffing is mechanical and should be scripted. Recommendation application stays LLM-driven; everything around it is deterministic.

### Acceptance Criteria
- `$SCRIPTS/apply_findings.sh <current_plan> <accepted_findings_json> <out_plan>`:
  - For each accepted CRITICAL/HIGH finding, locates `quoted_evidence` in current_plan and inserts a `<!-- FINDING <id> (<severity>): <recommendation> -->` marker on the line immediately above the quote.
  - Skips MEDIUM/LOW silently.
  - Skips findings whose `recommendation` is empty, "consider X", "investigate X", "evaluate X" (regex `^(consider|investigate|evaluate)\b`) and logs them to stderr as "non-actionable, retained for next round".
  - Writes the annotated plan to `out_plan`. Lead then makes the substantive edits.
- `$SCRIPTS/plan_diff.sh <plan_a> <plan_b> <out_diff>` — produces a unified diff stored at `out_diff`, used for `plan-diff-<N>-to-<N+1>.md`.
- Both scripts idempotent: rerunning with same inputs produces identical outputs.

### Definition of Done
- `shellcheck` clean.
- Bats fixture: 1 finding, multiple findings on different stories, finding whose evidence appears twice in plan (must annotate first occurrence only and warn), non-actionable recommendation, empty findings array.
- SKILL.md Phase 1 step `apply_findings_to_plan` becomes a 4-line block referencing the scripts.

---

## Story mech-4: Story parser + chunker

### Context
SKILL.md Phase 1 and Phase 2 both parse the plan into stories. Phase 1 chunks them for parallel review. Currently the lead does this inline by reading the plan and splitting on `## Story` headings. Should be one script invoked twice.

### Acceptance Criteria
- `$SCRIPTS/parse_stories.sh <plan_path>` emits JSON array to stdout:
  ```json
  [{"story_id": "...", "title": "...", "heading_line": 42, "acceptance_criteria": ["..."], "definition_of_done": ["..."], "body_markdown": "..."}]
  ```
  Single-story plans (no `## Story` headings) produce an array of length 1 with `story_id` = plan basename without `.md`.
- Robust to: trailing whitespace on heading, missing AC/DoD sections (returns empty arrays), AC/DoD sections that are not bullet lists (treats whole paragraph as one item), unicode story ids.
- `$SCRIPTS/chunk_stories.sh <stories_json> <chunk_size>` emits JSON array of chunks: `[{"chunk_id": "1-of-6", "story_ids": [...]}]`. `chunk_size <= 1` returns single chunk containing all stories.

### Definition of Done
- `shellcheck` clean.
- Bats fixture: 0 stories (single-implicit), 1 story, 5 stories chunk 5, 26 stories chunk 5 (→ 6 chunks), unicode title, story with no AC, story with malformed DoD.
- SKILL.md Phase 1 step 1 and Phase 2 step 3 both reference this script; inline parsing prose removed.

---

## Story mech-5: Multi-language coverage parser

### Context
SKILL.md Phase 3 says "Parse coverage report (Istanbul JSON, Go coverprofile, etc.)" but provides no implementation. Coverage parsing is the hottest source of mechanical bugs (regex on text reports is fragile; threshold off-by-one ships untested code). Must support TypeScript/JavaScript (istanbul), Go (coverprofile), Python (coverage.py xml/json), Rust (cargo tarpaulin / llvm-cov), and an autodetection fallback. Also must support **new-code coverage** (lines introduced by current story diff) — clarifies the per-story gate ambiguity in current SKILL.md.

### Acceptance Criteria
- `$SCRIPTS/coverage_check.sh --mode whole|new --threshold <pct> [--diff-base <ref>] [--story-id <id>]` emits JSON:
  ```json
  {"mode": "new", "pct": 83.5, "threshold": 80, "pass": true, "uncovered": [{"file": "src/x.ts", "lines": [12, 13, 14]}], "format_detected": "istanbul"}
  ```
- Autodetects coverage format by file presence (priority): `coverage/coverage-final.json` (istanbul) → `coverage.out` (go) → `coverage.xml` / `coverage.json` (python) → `target/tarpaulin/cobertura.xml` (rust). Configurable override via `commands.coverage_report_path`.
- `--mode new`: intersects uncovered lines with lines added in `git diff <diff-base>...HEAD` (default base = sprint branch fork point or last story commit). Returns coverage as `covered_new_lines / total_new_lines`.
- `--mode whole`: classic whole-tree coverage.
- Threshold default 80; exits 0 always; `pass` field is authoritative.
- If no coverage file found, exits 1 with stderr explaining detection chain. No silent zero.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures using committed sample coverage files for each format (istanbul JSON snippet, go coverprofile snippet, python coverage.json snippet).
- Each fixture asserts: detected format, pct, pass/fail, uncovered list shape.
- SKILL.md Phase 3 step 4 explicitly states **"new-code coverage by default"**; rewrites the gate description as: "≥ threshold of lines added by this story's diff are covered".
- Migration note: per-story gates that historically computed whole-tree coverage are documented in CHANGELOG.

---

## Story mech-6: Per-story diff + commit message builder

### Context
SKILL.md Phase 4 wants "per-story diff" — `git diff <last-story-commit-or-target-branch>...HEAD`. The "last-story-commit" resolution is not specified. Phase 6 builds a conventional commit message inline. Both are mechanical.

### Acceptance Criteria
- `$SCRIPTS/per_story_diff.sh <story_id>` emits the diff text on stdout. Resolution: read `state.json` history (new field `story_commits: [{"story_id": "...", "sha": "..."}]`) and diff `HEAD` against the SHA of the previous story; if none, diff against the merge-base with `target_branch`.
- `$SCRIPTS/build_commit_msg.sh <plan_path> <story_id> <type>` (where `type` ∈ {feat, fix, refactor, perf, docs, test, chore}) emits the full commit message to stdout, populating: subject line (≤72 chars enforced; truncate + warn), Story line, Plan line, Acceptance criteria bullets from parsed story, Gates summary line.
- After story commit, `state.sh update <plan_path> story_commits='[<merged>]'` records the new SHA.

### Definition of Done
- `shellcheck` clean.
- Bats fixture: story 1 (no prior), story 3 (diff against story 2), missing story id (error), title exceeding 72 chars (truncated with `…`).
- SKILL.md Phase 4 step 1 references `per_story_diff.sh`. SKILL.md Phase 6 step 3 replaces inline heredoc with `build_commit_msg.sh` call.

---

## Story mech-7: Project autodetect + repomix refresh

### Context
SKILL.md Phase 0 says "If `commands.*` are omitted, infer them from the repo: `package.json` scripts, `justfile` recipes, `Makefile` targets, `pyproject.toml`, `Cargo.toml`. If multiple stacks coexist, ask the user." Pure prose. Phase 0 also says refresh `.repomix-output.xml` if older than 1 hour — also prose.

### Acceptance Criteria
- `$SCRIPTS/detect_commands.sh` emits JSON:
  ```json
  {"typecheck": "...", "lint": "...", "test": "...", "coverage": "...", "stack": "node|go|python|rust|mixed", "confidence": "high|medium|low", "ambiguities": ["..."]}
  ```
  - Priority order: `justfile` → `package.json` scripts → `Makefile` → `pyproject.toml` (poetry/pdm/rye) → `Cargo.toml` → `go.mod`.
  - `confidence: low` or `stack: mixed` ⇒ exits 0 with `ambiguities` populated; SKILL.md instructs lead to ask user when low confidence.
- `$SCRIPTS/repomix_refresh.sh [--max-age-minutes 60]` regenerates `.repomix-output.xml` if missing or older than threshold. Idempotent. Stays in main tree (worktree symlinks/copies it in Phase 2 — covered by story mech-12).
- Both scripts exit 0 on no-op success; exit 1 only on actual failure.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures: pure node repo, pure go repo, repo with both `package.json` and `justfile` (justfile wins), repo with neither (low confidence + ambiguities), stale repomix pack (regenerated), fresh repomix pack (no-op).
- SKILL.md Phase 0 step 5 / step 9 replaced with script invocations.

---

## Story mech-8: Test fixtures + CI lint

### Context
All scripts above need exercise harness. Without it, the next refactor breaks them silently. Lightweight: bats-core under `scripts/tests/`, runnable locally via `just test` or `bash scripts/tests/run-all.sh`.

### Acceptance Criteria
- `$SCRIPTS/tests/` contains one `.bats` file per script (`state.bats`, `lead_validator.bats`, `apply_findings.bats`, `parse_stories.bats`, `chunk_stories.bats`, `coverage_check.bats`, `per_story_diff.bats`, `build_commit_msg.bats`, `detect_commands.bats`, `repomix_refresh.bats`).
- `$SCRIPTS/tests/fixtures/` holds sample plans, coverage files, stories.json, etc.
- `$SCRIPTS/tests/run-all.sh` runs every bats file; exits non-zero on any failure.
- README at `$SCRIPTS/tests/README.md` documents how to add a new script + fixture.
- `shellcheck` invoked across all `$SCRIPTS/*.sh` in `run-all.sh`.

### Definition of Done
- `bash scripts/tests/run-all.sh` exits 0 on a clean checkout.
- Coverage by inspection: every script in `$SCRIPTS` has at least one `@test` referencing it.
- CHANGELOG notes bats as a new dev dependency (`brew install bats-core`).

---

## Story mech-9: SKILL.md split — phases/phase-{0..7}.md

### Context
SKILL.md is 492 lines. Most content is per-phase detail. Lead only needs phase N's detail when entering phase N. Split phases into separate files; SKILL.md retains overview, inputs, sub-skill manifest, phase index, guardrails.

### Acceptance Criteria
- `$PHASES/phase-0.md` … `$PHASES/phase-7.md` exist; each is self-contained for that phase (entry condition, gate, steps, exit condition, artifacts produced, references to scripts and reference docs).
- SKILL.md replaces each phase section with: heading, 1-line goal, gate condition, and explicit "**Load `$PHASES/phase-N.md` when entering this phase.**" line.
- SKILL.md ≤ 180 lines after the split.
- Cross-phase invariants (state.json schema location, ART path convention, SendMessage protocol) remain in SKILL.md, not duplicated into phase docs.
- Phase docs reference scripts by absolute-from-skill-root path: `$SCRIPTS/state.sh`, etc. SKILL.md defines `$SCRIPTS`, `$PHASES`, `$REF` aliases once.

### Definition of Done
- `wc -l SKILL.md` ≤ 180.
- Each phase doc passes a manual checklist: entry condition stated, gate stated, exit condition stated, artifacts listed, scripts referenced (not pseudocode).
- Phase index in SKILL.md ↔ phase doc filenames cross-match (verified by mech-13 lint).
- No phase doc duplicates the state.json schema, ART path convention, or guardrail rules.

---

## Story mech-10: Reference docs extraction

### Context
SKILL.md embeds several long stable references: "Plan path naming convention" (~40 lines), "Reviewer return contract" (~30 lines), "Lead validator anti-hallucination gate" pseudocode (~30 lines). These are read-once-per-sprint references, not orchestration. Move out.

### Acceptance Criteria
- `$REF/plan-path-convention.md` — full naming convention spec, examples, rejection rules.
- `$REF/reviewer-contract.md` — JSON tail schema, two-layer grounding rules, story_id="*" rule.
- `$REF/state-schema.md` — human-readable description of state.json fields; references `$SCRIPTS/state.schema.json` for machine schema.
- `$REF/sendmessage-protocol.md` — extracted from CLAUDE.md and current SKILL.md guardrails; defines the exact `to`/`message`/`summary` shape and post-delivery verification.
- SKILL.md Phase sections reference these files instead of repeating their content.

### Definition of Done
- Every `$REF/*.md` opens with a one-line "WHO READS THIS / WHEN" header.
- SKILL.md Phase 0 step 7, Phase 1 reviewer contract section, Phase 4 reviewer delivery section all link to the relevant reference doc.
- No reference content duplicated between SKILL.md and `$REF/`.

---

## Story mech-11: Prose compression + drop migration boundary

### Context
SKILL.md repeats `.team-sprint/sprints/<worktree_name>/` ~20 times. The "Migration boundary" subsection (~10 lines) is a one-time concern for sprints started before the per-sprint layout. After 6 months, no live sprints predate the layout — content belongs in CHANGELOG.

### Acceptance Criteria
- SKILL.md introduces `$ART` alias once: "Throughout this skill, `$ART` = `.team-sprint/sprints/<worktree_name>` (the per-sprint artifact dir). Every later reference uses `$ART/<filename>`."
- All `.team-sprint/sprints/<worktree_name>/<file>` references replaced with `$ART/<file>`.
- "Migration boundary" subsection removed from SKILL.md; equivalent content appended to `$SKILL_DIR/CHANGELOG.md` under the v0.x → v1.0 entry.
- Filler / hedging phrases removed (e.g. "It also adds", "This skill is a thin orchestrator — the heavy work happens…" condensed to factual statements). No information lost.

### Definition of Done
- `grep -c '\.team-sprint/sprints/<worktree_name>/' SKILL.md` returns 1 (the `$ART` definition line) or 0 (if defined without literal repetition).
- "Migration boundary" string absent from SKILL.md; present in CHANGELOG.md.
- SKILL.md word count drops by ≥15% after this story (independent of the phase split in mech-9; measure on the SKILL.md remaining after mech-9).

---

## Story mech-12: Config defaults + new parameters

### Context
Defaults need calibration. `adversarial_iterations: 6` is too generous — most plans clear in 1–2 rounds; 6 enables wallowing. No wall-clock budget exists. `model: opus` for adversarial subagents is hardcoded; should be a config knob. Spec-reviewer at Phase 4 has no explicit "impl-only, no plan revision" contract.

### Acceptance Criteria
- Default `adversarial_iterations` changes from `6` to `3`.
- New config field `max_wall_clock_minutes` (default `240` = 4 hours). When the sprint exceeds it, sprint-watchdog raises a warning to the user with current phase + remaining work; user decides extend/abort. Not a hard kill — sprint state persists.
- New config field `adversarial_model` (default `opus`). Used wherever the skill currently hardcodes `model: opus`.
- New config field `coverage_mode` (default `new`, alternatives `whole`). Wired into `coverage_check.sh` invocation.
- Phase 4 spec-reviewer instructions explicitly state: "Findings are impl-only. Plan is frozen at Phase 1; spec-reviewer must NOT request plan revisions. Plan-vs-implementation drift findings become CRITICAL fix tasks for the engineer."
- Subagent skill preflight: Phase 0 verifies that the `adversarial-review` skill is discoverable by a `general-purpose` subagent (spawn a no-op probe). If not, STOP at Phase 0.

### Definition of Done
- Default config block in SKILL.md updated.
- Phase 0 phase-doc lists the subagent skill preflight as step 10.
- Phase 4 phase-doc spec-reviewer subsection contains the "impl-only" contract verbatim.
- `coverage_check.sh` invocation in Phase 3 phase-doc reads from `coverage_mode`.

---

## Story mech-13: Worktree repomix + skill discovery

### Context
`use-repo-code` produces `.repomix-output.xml` in the main tree at Phase 0. Reviewers in Phase 4 run in the worktree. Currently the skill doesn't say which path they read. If main-tree, paths from grep results are relative to main tree and may not exist in worktree (file added during sprint). If worktree-local, the pack is stale (pre-sprint snapshot). Resolution must be explicit.

### Acceptance Criteria
- Phase 2 step 1 (worktree creation) gains a sub-step: copy `.repomix-output.xml` from main tree to worktree (`cp <main>/.repomix-output.xml <worktree>/.repomix-output.xml`). Refresh-in-worktree happens only if sprint duration exceeds `repomix_max_age_minutes` (new config, default 240).
- Phase 4 reviewer prompts state: "Grep the worktree-local `.repomix-output.xml`. Paths in grep results are repo-relative; resolve them against the worktree root, not the main tree."
- `repomix_refresh.sh` gains `--target-dir <path>` arg so it can refresh inside the worktree if needed.
- Lead spawn prompt for Phase 1 chunked reviewers + Phase 4 spec-reviewer includes a one-line preamble: "Verify the `adversarial-review` skill is available via the Skill tool before starting. If not, abort and report."

### Definition of Done
- Phase 2 phase-doc explicitly handles the repomix pack location.
- Phase 4 phase-doc reviewer prompts include the worktree path resolution note.
- Subagent skill discovery preamble appears in every relevant spawn prompt template.

---

## Story mech-14: Phase doc lint + skill-validator + CHANGELOG

### Context
After the refactor, the skill spans many files. A drift between SKILL.md's phase index and the actual phase docs would cause silent breakage. A lint step catches it. Skill-validator must pass end-to-end. CHANGELOG records the v1.0 cut.

### Acceptance Criteria
- `$SCRIPTS/lint_skill.sh` runs every check below; exits non-zero on any failure:
  - SKILL.md mentions `$PHASES/phase-N.md` for N = 0..7 and each file exists.
  - SKILL.md mentions every `$REF/*.md` that exists and vice versa.
  - SKILL.md mentions every `$SCRIPTS/*.sh` that exists OR the script is listed under `$SCRIPTS/tests/` (test harness).
  - Every `$PHASES/*.md` references at least one script.
  - `shellcheck` over every `$SCRIPTS/*.sh` passes.
  - `bats scripts/tests/` passes.
- `$SKILL_DIR/CHANGELOG.md` records the v1.0 cut with the migration note from mech-11 + summary of new scripts.
- `skill-validator` skill invoked against `team-sprint` returns grade A (0 failures, ≤2 warnings).
- Frontmatter `description` field reviewed: trim filler phrases without dropping trigger keywords. Target ≤200 words; current ~265.

### Definition of Done
- `$SCRIPTS/lint_skill.sh` is invoked from `$SCRIPTS/tests/run-all.sh`.
- `skill-validator` report attached to the sprint commit message for mech-14.
- CHANGELOG entry includes: scripts added, defaults changed, config fields added, files moved, behavioural changes (new-code coverage default), migration notes (pre-per-sprint-layout sprints, repomix worktree handling).
- Final commit on this story is a `chore(team-sprint-mech): cut v1.0` with the validator output quoted in the body.

---

## Cross-story invariants (apply to every story)

- **No behavioural regression to the resume contract.** A sprint started under the current skill version must still be resumable under the refactored version (state.json schema only adds fields, never renames or removes). `state.schema.json` is additive.
- **`validate_plan_path.sh` interface stays stable.** `team-sprint --abort` callers must keep working. Only its internals or accompanying lib may change.
- **Every script call site in SKILL.md / phase docs uses absolute-from-skill-root paths.** No `./scripts/...`; always `$SCRIPTS/...` after the alias is defined.
- **Caveman mode does not apply to skill text.** Skill instructions are spec; write normal prose.
- **Each story commits as a single conventional commit** per the team-sprint Phase 6 contract — `feat(team-sprint-mech)`, `refactor(team-sprint-mech)`, `chore(team-sprint-mech)` as appropriate.
- **Don't touch per-repo team-sprint variants under `~/Development/*`.** They will migrate in a follow-on sprint.

## Sprint-level Definition of Done

- All 14 stories shipped, each on its own commit on the sprint branch.
- `bash scripts/tests/run-all.sh` exits 0.
- `skill-validator` returns grade A.
- SKILL.md line count ≤ 180.
- Token-audit on a fresh dry-run sprint shows ≥50% reduction in per-turn context cost vs. pre-refactor baseline (measured on the same fixture plan).
- CHANGELOG updated with the v1.0 entry.
- No behavioural regression on a fixture sprint that resumes from a v0.x state.json.

## Surfaced risks (track during execution)

- **Bats not installed on macOS by default.** Story mech-8 documents the dev dep. Sprint can proceed without bats locally if `run-all.sh` falls back to a plain-bash test runner — keep a fallback in mind during mech-8.
- **`shellcheck` strictness varies by version.** Pin the expected version in CHANGELOG; mech-8 documents `brew install shellcheck` >= 0.9.
- **`coverage_check.sh --mode new` relies on `git diff` semantics.** First story of a sprint has no prior story commit; diff base = `target_branch` merge-base. Sub-cases must be tested in mech-5.
- **Subagent skill discovery (mech-12, mech-13) is environment-dependent.** Some Claude Code installs may not expose the `adversarial-review` skill to a `general-purpose` subagent. If preflight fails on a real user, the sprint STOPs at Phase 0 — surface the install fix clearly.
- **Frontmatter description trim (mech-14) could reduce trigger sensitivity.** Validate post-trim by running `skill-validator`'s trigger-accuracy mode if available; otherwise eyeball against the existing trigger phrase list before committing.

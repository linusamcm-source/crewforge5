# Sprint: team-sprint Mechanical Refactor v3 (`team-sprint-mech`)

**Supersedes:** `sprint-team-sprint-mech-refactor.md` (v1, 2026-05-20) and `sprint-team-sprint-mech-refactor-v2.md` (v2, 2026-05-20). v3 is fully self-contained — every AC and DoD is expressed inline. No "see v1/v2" inheritance. Adversarial round 1 surfaced layering itself as a CRITICAL ambiguity (different engineers resolved conflicts differently); v3 eliminates the problem by being the single source of truth.

**Goal:** Optimise `$HOME/.claude/skills/team-sprint` by:
1. Extracting mechanical pseudocode into executable scripts (deterministic, fixture-testable).
2. Splitting SKILL.md into per-phase reference docs (loaded on demand, cuts per-turn context).
3. Tightening defaults and closing under-specified contract gaps.
4. Reserving a stable extension surface (`subskill_hooks`) so future sub-skills (e.g. an `integration-diagram` skill) can plug in without further refactor.

**Target directory:** `$HOME/.claude/skills/team-sprint/`
**Target branch:** `develop`
**Out of scope:** Per-repo `team-sprint` variants under `~/Development/*`; new sub-skills; rewriting `validate_plan_path.sh`'s stdout/exit-code interface (internals may change; external contract preserved).

**Why v3 exists:** Adversarial round 1 of v2 found 7 CRITICAL + 15 HIGH findings (0 hallucinations). v3 folds every gating finding into the relevant story AC/DoD and resolves the five cross-cutting design calls inline. The integration-diagram skill (sometimes referenced as "IDS") remains a future consumer but **no forward references to a non-existent `sprint-integration-diagram-skill-v2.md` are made anywhere in v3** — the cross-sprint contract is informational, not gated.

**Cross-cutting design decisions (locked in for v3):**

| ID | Decision | Rationale |
|---|---|---|
| CC-1 | ART (artifact dir) is always `validate_plan_path.sh`-derived (`.team-sprint/sprints/sprint-<slug>/`). `worktree_name` config affects only the sibling worktree directory path, never ART. Path resolution is anchored at the main repo root via `git rev-parse --show-toplevel` (captured at Phase 0 init), so `art_dir` invocations from worktree CWD still return the main-repo absolute path. | Preserves `validate_plan_path.sh` stdout interface (required by `team-sprint --abort`). Decouples ART from worktree dir naming. Eliminates the dual-resolution conflict and the worktree-CWD drift. |
| CC-2 | No forward references to `sprint-integration-diagram-skill-v2.md` or any non-existent plan. Cross-skill integration is documented as informational. Enforcement (if any) lives in the consuming sprint, never in this one. | Plan files must reference real artefacts. Future consumers self-enforce on the published surface (`$REF/subskill-hooks.md`, marker comments, config block). |
| CC-3 | "Migration boundary" stays in SKILL.md as a one-line breadcrumb in the "Failure modes & resume" section, pointing to CHANGELOG for full text. **CHANGELOG.md is created by mech-11 alongside the breadcrumb** (not deferred to mech-14) so the breadcrumb resolves on its own commit. mech-14 appends v1.0-cut additions later. | Pre-v1.0 sprints exist on users' disks; removing the recovery hint sacrifices a real operational signal. Breadcrumb must resolve at commit time, not eventually. |
| CC-4 | SKILL.md line-count gates are absolute, staged: ≤250 after mech-9 commit (intermediate), ≤180 after mech-11 commit (sprint-final). mech-10 is ungated on lines (its DoD covers structural correctness instead). | "≥15% drop" is unmeasurable when mech-9 has already reduced SKILL.md drastically. Absolute targets are reviewable on every commit. |
| CC-5 | v1 ↔ v2 ↔ v3 layering precedence is resolved by v3 being self-contained. Future patches to this plan must be issued as numbered amendments WITHIN v3 (e.g. "Amendment 1 to v3"), with explicit precedence on conflict stated at the top of the amendment. No future "v4 amends v3" inheritance pattern. | Adversarial Round 1 found layering itself was a CRITICAL ambiguity (C1-3). Self-contained plans are auditable; layered amendments are not. |
| CC-6 | **Story commit order:** mech-1 → mech-2 → … → mech-14a → mech-15 → mech-14b. mech-14 is split (per its own story section) into 14a (lint script body, no run-all wire-in, no check #10, no cut v1.0) and 14b (check #10 + run-all wire-in + skill-validator + cut v1.0). mech-9 captures a pre-split snapshot of SKILL.md to `$ART/skill-md-pre-split.md` at commit time so mech-10 can locate sections by stable heading anchors against the snapshot (not against the live, already-split SKILL.md). Phase docs created by mech-9 may reference `$REF/*.md` paths even before mech-10 authors those files; mech-14a's lint (without check #10) passes after both mech-9 and mech-10 have shipped; mech-14b's lint (with check #10) passes after mech-15 has shipped. | Lint check ordering issues surfaced in rounds 2–3. Locking commit order + snapshot policy + 14a/14b split makes mid-sprint state legitimate. |
| CC-7 | **"Dry-run sprint" definition (referenced by mech-15 DoD + sprint-DoD):** a fixture-plan execution where every story's `commands.test` is the literal `true`, `coverage_threshold` is `0`, and every `subskill_hooks` entry's `command` is `true`. The dry-run exercises orchestration (Phase 0 → Phase 7, all 15 stories, all hooks fire, all artifacts produced) without writing real test/coverage/lint output. | The phrase "dry-run sprint" was previously undefined; reviewers flagged the contradiction with "Phase 0 → Phase 7 over 15 stories". This locks the definition. |
| CC-8 | **External-tool preflight is mandatory at Phase 0.** Before any sprint story begins, the lead invokes a single Phase 0 entry step that asserts every required external binary (`jq`, `python3`, `bats`, `shellcheck`, `repomix`) is on PATH via `lib.sh require_all`. Failure aborts Phase 0 with install hints. | mech-2 + mech-6 hard-depend on `python3`; mech-7 on `repomix`; mech-8 on `bats` + `shellcheck`. Round 2 H-1 (chunk 1) found `require_python3` declared but never invoked. This CC consolidates preflight at one entry point. |

**Conventions:**
- `$SKILL_DIR` = `$HOME/.claude/skills/team-sprint`
- `$SCRIPTS` = `$SKILL_DIR/scripts`
- `$PHASES` = `$SKILL_DIR/phases`
- `$REF` = `$SKILL_DIR/reference`
- `$ART` = `.team-sprint/sprints/sprint-<slug>` where `<slug>` is the `validate_plan_path.sh` output for `$plan_path`. `worktree_name` does NOT affect `$ART`.
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, bash 3.2-safe (macOS default).
- Every script produces JSON on stdout (except `validate_plan_path.sh` which retains its eval-safe KEY=VALUE format for back-compat).
- Every script has at least one bats fixture under `$SCRIPTS/tests/`.

---

## Story mech-1: Foundation library + state management

### Context
Every later script needs shared logging, JSON helpers, ART resolution, and atomic state.json read/write. Centralising once unblocks every later story. v2 amendment for optional `subskills` field is folded in; v3 also pre-declares `story_commits` (used by mech-6) so the schema is complete from day one and concurrency uses `flock`.

### Acceptance Criteria

- `$SCRIPTS/lib.sh` is sourced (not executed) by every other script. Provides:
  - `log`, `info`, `warn`, `fail` (exit 1 with stderr message).
  - `art_dir <plan_path>` — invokes `$SCRIPTS/validate_plan_path.sh --slug-only "$plan_path"`, parses `SPRINT_DIR=...`, and resolves it to an **absolute path anchored at the main repo root**. Resolution: if `state.json.artifact_dir` is already set on this `<plan_path>`, return that absolute path (set at Phase 0 init from `git rev-parse --show-toplevel`); otherwise compute it from `$(git rev-parse --show-toplevel)/SPRINT_DIR`. **Single source of truth for ART; downstream code never independently derives it; correct even when called from the worktree CWD.**
  - `require_jq`, `require_bats`, `require_shellcheck`, `require_repomix`, `require_python3` — each asserts the named tool is on PATH; fails loud with install hint on stderr if missing.
  - `require_all` — probes every `require_*` above in declaration order; **accumulates the install hint for each missing tool** and exits non-zero ONLY AFTER all probes complete (not on first failure). Single-missing case emits a single hint; multi-missing case emits all hints concatenated. **Phase 0 invokes `require_all` as its entry step** (per CC-8), so Phase 1+ can rely on every external binary being present.
- `$SCRIPTS/state.sh` exposes subcommands:
  - `state.sh init <plan_path> <target_branch> <worktree_name>` — creates fresh state.json under ART; fails if one already exists with `done != true`. **Captures `git rev-parse --show-toplevel` as `state.json.repo_root` (absolute path) and `state.json.artifact_dir` (absolute path = `repo_root/SPRINT_DIR`) so later `art_dir` calls from worktree CWD resolve correctly.**
  - `state.sh read <plan_path>` — prints state.json; exits 2 if missing.
  - `state.sh update <plan_path> <key>=<json-value>` (repeatable) — merges into state.json atomically under `flock` on `$ART/.state.lock`; preserves top-level keys not mentioned. **Merge semantics for array-valued keys: top-level key replacement (caller assembles the new array value). Example: existing `story_commits: [A]` + `state.sh update story_commits='[A,B]'` → state contains `[A,B]`; passing `'[B]'` would overwrite to `[B]` (caller error, but documented).** Bats fixture covers both cases.
    - **Nested keys:** `<key>` may use `.` as path separator (`subskills.integration-diagram.last_event_id=...`); resolved via `jq setpath`.
    - **Path-separator escape:** `.` is reserved; skill or field names containing a literal `.` are rejected with `unsupported character in key path` and exit 1.
    - Bats fixture covers: nested update with `-` in a path component (e.g. `integration-diagram`); rejection of a key whose component contains `.`.
  - `state.sh advance-phase <plan_path> <N>` — sets `current_phase`; fails if `N != current+1` unless `--force`.
  - `state.sh resume-scan` — lists every `.team-sprint/sprints/*/state.json` with `done != true` as JSON array: `[{slug, plan_path, current_phase, started_at}]`.
  - All subcommands acquire `flock` on `$ART/.state.lock` for the entire read-modify-write sequence.
- `$SCRIPTS/state.schema.json` is JSON Schema draft-2020-12. Required fields: `plan_path`, `plan_slug`, `worktree_name`, `target_branch`, `worktree_path`, `artifact_dir`, `started_at`, `current_phase`, `iterations`, `repo_root`. Optional fields explicitly declared (with type contracts):
  - `subskills: { [skill_name]: { enabled: bool, last_event_id?: string, last_artifact_sha?: string } }` — long-lived per-skill metadata (event cursors, artifact SHAs).
  - `subskill_hooks: array<{ skill: string, command: string, required: bool, phase: string, source: "user" | "auto" }>` — resolved hook list written at Phase 0 step 4 (per mech-13). Distinct from `subskills` (map vs array) because the two carry orthogonal concerns: `subskills` is per-skill state, `subskill_hooks` is per-execution invocation list.
  - `story_commits: array<{ story_id: string, sha: string }>` — populated by mech-6.
  - `gates: array<{ coverage_gate: string, reason: string, story_id: string }>` — populated by Phase 3 skip-path (mech-5).
  - `done: bool`, `finalised_at: string` — Phase 7 finalisation.
  - **`repo_root`** is REQUIRED (not optional): absolute path captured by `state.sh init` from `git rev-parse --show-toplevel`; consumed by `art_dir` so resolution from worktree CWD returns a main-repo absolute path. Without this field, `art_dir` could only re-derive it from a live `git rev-parse` (slower; incorrect outside the worktree/main tree) — requiring the field eliminates that branch and makes post-init resolution deterministic from state alone.
  - Future fields land here as **additive optional**; renaming or removing a field is a breaking change requiring a major version bump documented in CHANGELOG.
- **`state.sh init` uses a write-then-validate-then-delete-on-failure flow** (separate from `state.sh update`'s rollback semantics; init has no prior state to roll back to). On post-write schema-validation failure, `init` deletes the half-written state.json and exits 1. Bats fixture covers this.
- `state.sh update` rejects writes that violate the schema (exits 1, leaves state.json unchanged); fixture covers this.
- Atomicity: `flock` + `tmpfile + mv`. Bats fixture spawns two background updates of distinct keys and asserts both fields survive.
- All operations bash 3.2-safe; verified on stock macOS bash.

### Definition of Done
- `bash -n $SCRIPTS/lib.sh $SCRIPTS/state.sh` passes.
- `shellcheck $SCRIPTS/lib.sh $SCRIPTS/state.sh` passes with zero findings.
- Bats fixtures exercise: init → read → update (3 keys) → advance-phase (valid + invalid + `--force`) → resume-scan (0 / 1 / 2 / 1-finalised-1-active sprints) → nested update with `-` in path → rejection of `.`-in-component key → concurrent-update survives → schema-violation rolls back → array-replacement semantics `[A]+[A,B]→[A,B]`, `[A]+[B]→[B]` → init flow: write-then-validate-then-delete-on-failure (post-write schema-violation deletes the half-written state.json; no prior state to roll back to).
- **`require_all` semantics fixture:** probes every tool in declaration order, accumulates install hints for every missing tool, exits non-zero only AFTER all probes complete (not on first failure); single-missing emits single hint; multi-missing emits all hints concatenated.
- **All state.sh bats fixtures run inside a tmp git repo** (fixture setup performs `git init`) so `git rev-parse --show-toplevel` resolves for `art_dir` and `state.sh init`.
- **SKILL.md Phase 0 gains a new step 0** (before any other check), inserted by this story: `source $SCRIPTS/lib.sh && require_all`. Failure aborts Phase 0 with concatenated install hints. Verify with `grep -n 'require_all' SKILL.md` returning ≥1 line after mech-1 commit.
- SKILL.md Phase 0 / Phase 2 references update to call `state.sh` instead of describing JSON inline.

---

## Story mech-2: Adversarial lead validator script

### Context
SKILL.md Phase 1 carries ~25 lines of bash pseudocode for the lead-side validator that strips hallucinated findings. v3 makes the validator independent of any specific heading shape (so it works on plans of either `## Story` or `### <id> amendment` flavour), uses a Python-based substring check (handles multi-line `quoted_evidence`), and is reproducibility-locked via `jq --sort-keys`.

### Acceptance Criteria
- `$SCRIPTS/lead_validator.sh <plan_path> [<findings_json>]` reads findings JSON from stdin OR a file arg; returns `{"accepted": [...], "rejected": [{...finding, "reject_reason": "..."}]}` on stdout.
- Validation rules (all enforced):
  1. `quoted_evidence` is non-empty.
  2. `quoted_evidence` is a substring of `<plan_path>` (use Python: `python3 -c 'import sys; q=sys.argv[1]; p=open(sys.argv[2]).read(); sys.exit(0 if q in p else 1)' "$qe" "$plan_path"` — handles embedded newlines that `grep -F` rejects).
  3. `story_id` is a valid story per the plan. **Validator consumes `parse_stories.sh` (mech-4) output** — does not re-grep headings. `story_id == "*"` is always accepted as cross-cutting.
  4. CRITICAL/HIGH findings must have non-empty `recommendation`.
  5. `severity ∈ {CRITICAL, HIGH, MEDIUM, LOW, UNVERIFIED}`.
- All JSON output is emitted via `jq --sort-keys` so object key order is stable and two runs over the same input produce byte-identical output.
- Exit code 0 always (validator is a filter, not a gate); caller decides on counts.
- `lead_validator.sh --reject-rate <findings_json>` returns a single number `0.00–1.00`.
- **Bootstrap escape (mech-2 ships before mech-4):** If `parse_stories.sh` is absent from `$SCRIPTS`, the validator treats every non-`*` story_id as `valid: unknown` and accepts with a `MEDIUM` warning attached. This escape is gated by an explicit `--allow-bootstrap` flag the lead passes ONLY when invoked during the mech-2-before-mech-4 window. Once mech-4 ships, the lead stops passing `--allow-bootstrap`; further runs that hit "parse_stories.sh present but exited non-zero" or "absent without --allow-bootstrap" produce a HIGH `parse_stories_unavailable` finding (no silent accept). Bats fixture covers: (a) absent + `--allow-bootstrap` → accept-with-warn; (b) absent without flag → HIGH warning; (c) present but exits 1 → HIGH warning regardless of flag. Post-mech-4 DoD removes the flag from lead-side call sites.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures cover: empty input; all-accepted; all-rejected; mixed; unicode in `quoted_evidence`; multi-line `quoted_evidence`; `story_id: "*"` with cross-cutting evidence; missing `recommendation` on HIGH; reproducibility (byte-identical output across two runs).
- SKILL.md Phase 1 prose collapses inline pseudocode into a 3-line description + reference to the script. Reject-rate threshold (`>50%` triggers chunk re-run) referenced from the script's `--reject-rate` mode, not duplicated in prose.

---

## Story mech-3: Plan revision script (apply_findings)

### Context
SKILL.md Phase 1 step `apply_findings_to_plan` is currently prose. The locating + marker insertion is mechanical; substantive rewrite stays LLM-driven. v3 adds an explicit idempotency rule (skip if marker for same finding id already present above the quote) so reruns produce byte-identical output.

### Acceptance Criteria
- `$SCRIPTS/apply_findings.sh <current_plan> <accepted_findings_json> <out_plan>`:
  - For each accepted CRITICAL/HIGH finding, locate `quoted_evidence` in `current_plan` and insert a `<!-- FINDING <id> (<severity>): <recommendation> -->` marker on the line immediately above the quote.
  - **Idempotency + ID namespacing handoff (lead-side rewrite, not script-side):** The lead, before invoking `apply_findings.sh`, rewrites each finding's `id` field in the accepted_findings JSON to `R<N>-C<C>-<orig_id>` (e.g. round 2 chunk 1's `H-1` becomes `R2-C1-H-1`). The script reads `id` verbatim and uses it as the marker id with no transformation. Example input shape after lead rewrite:
  ```json
  [{"id": "R2-C1-H-1", "severity": "HIGH", "story_id": "mech-9", "issue": "...", "quoted_evidence": "...", "recommendation": "..."}]
  ```
  This eliminates cross-round ID collisions structurally (round N's `H-1` and round N+1's `H-1` produce distinct marker IDs). Idempotency rule (in-script): scan the line immediately above the matched quote; skip the insert ONLY if the existing marker's `id` AND `<recommendation>` text both match. If `id` matches but `<recommendation>` differs (rerun with corrected recommendation within same round/chunk), replace the marker in place. Cross-round same-original-id findings always stack (newest at top) because their namespaced IDs differ, preserving audit history. Bats fixtures: (a) two runs same JSON → byte-identical output; (b) same round same id revised recommendation → marker replaced; (c) input JSON with `R2-C1-H-1` then `R3-C1-H-1` against same quote → both markers present (stacked).
  - **Duplicate-evidence:** when `quoted_evidence` appears more than once in the plan, annotate only the first occurrence and log to stderr `multi-occurrence quote for finding <id>: annotated first only`. Bats fixture covers this case.
  - Skip MEDIUM/LOW silently (still allowed in input; written to a `<out_plan>.skipped.json` sidecar).
  - Skip findings whose `recommendation` is empty or matches `^(consider|investigate|evaluate)\b` (case-insensitive) and log to stderr as `non-actionable, retained for next round`.
- `$SCRIPTS/plan_diff.sh <plan_a> <plan_b> <out_diff>` — produces a unified diff stored at `out_diff`. Idempotent (same inputs → byte-identical output).

### Definition of Done
- `shellcheck` clean.
- Bats fixtures: 1 finding; multiple findings on different stories; finding whose evidence appears twice (annotates first, warns); non-actionable recommendation; empty findings array; idempotency (two runs → identical output); MEDIUM finding skipped (appears in sidecar, not in `out_plan`).
- SKILL.md Phase 1 step `apply_findings_to_plan` becomes a 4-line block referencing the scripts.

---

## Story mech-4: Story parser + chunker

### Context
SKILL.md Phase 1 and Phase 2 both parse stories from the plan. v3 makes the parser **shape-agnostic**: it supports both `## Story <id>: <title>` (canonical) and `### <id> amendment` (v2-style) and `## NEW Story <id>: <title>` (mixed) — required because some future plans may mix or rely on inheritance. Returns structured JSON consumed by `lead_validator.sh` (mech-2) for story-id verification.

### Acceptance Criteria
- `$SCRIPTS/parse_stories.sh <plan_path>` emits JSON array to stdout:
  ```json
  [{"story_id": "...", "title": "...", "heading_line": 42, "acceptance_criteria": ["..."], "definition_of_done": ["..."], "body_markdown": "..."}]
  ```
  - Heading shapes recognised (all yield same `story_id` field):
    - `^## Story <id>:` (e.g. `## Story mech-1: Foundation library`)
    - `^## NEW Story <id>:` (treated identically to `## Story`)
    - `^### <id> amendment` (e.g. `### mech-1 amendment` — `<id>` is the entire token before ` amendment`)
  - Single-story plans (no recognised heading) produce an array of length 1; `story_id` = plan basename without `.md`.
- Robust to: trailing whitespace on heading, missing AC/DoD sections (returns empty arrays), AC/DoD sections that are not bullet lists (treats whole paragraph as one item), unicode story ids.
- `$SCRIPTS/chunk_stories.sh <stories_json> <chunk_size>` emits JSON array of chunks: `[{"chunk_id": "1-of-6", "story_ids": [...]}]`. **`chunk_size <= 1` always returns a single chunk containing all stories** (unconditional; not "for small specs only"). Bats fixtures cover `chunk_size=0`, `=1`, `=-1`.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures: 0 stories (single-implicit), 1 story, 5 stories chunk 5, 26 stories chunk 5 (→ 6 chunks), unicode title, story with no AC, story with malformed DoD, **amendment-style plan** (mix of `### mech-N amendment` headings), mixed plan (one `## NEW Story` + several `### N amendment`).
- SKILL.md Phase 1 step 1 and Phase 2 step 3 reference this script.
- **Bootstrap-flag cleanup (mech-2 → mech-4 hand-off):** this story's DoD includes the bullet:
  - "Remove every `--allow-bootstrap` flag from SKILL.md, every phase doc, and every lead-side `lead_validator.sh` invocation. After mech-4 commit, `grep -rn 'allow-bootstrap' SKILL.md phases/ 2>/dev/null` returns 0 lines."
  - mech-2's bootstrap-fallback bats fixture (a) (absent + `--allow-bootstrap` → accept-with-warn) is removed by this story; mech-2 fixtures (b) and (c) (HIGH warn on no-flag / present-but-failed) become the only retained cases.
  - mech-14's `lint_skill.sh` gains check #11: `grep -rn 'allow-bootstrap' SKILL.md phases/ 2>/dev/null` returns 0 lines (lint scope excludes `$REF/` + `docs/adr/` + the `team-sprint.config.yaml.example`, which may legitimately document the historical flag).

---

## Story mech-5: Multi-language coverage parser

### Context
SKILL.md Phase 3 says "Parse coverage report (Istanbul JSON, Go coverprofile, etc.)" with no implementation. v3 provides multi-language support **plus an explicit skip path for bash-only projects** (which this very sprint runs on). The `--diff-base` ambiguity is resolved by tying the default to the invocation context.

### Acceptance Criteria
- `$SCRIPTS/coverage_check.sh --mode whole|new --threshold <pct> [--diff-base <ref>] [--story-id <id>]` emits JSON:
  ```json
  {"mode": "new", "pct": 83.5, "threshold": 80, "pass": true, "uncovered": [{"file": "src/x.ts", "lines": [12, 13, 14]}], "format_detected": "istanbul"}
  ```
- Autodetects coverage format by file presence (priority): `coverage/coverage-final.json` (istanbul) → `coverage.out` (go) → `coverage.xml` / `coverage.json` (python) → `target/tarpaulin/cobertura.xml` (rust). Override via `commands.coverage_report_path` config.
- **Skip path (bash-only / no-coverage projects)** is implemented INSIDE `coverage_check.sh` itself (not in lead prose). The script reads `commands.coverage` and `coverage_threshold` from `team-sprint.config.yaml`; if either signals skip (`commands.coverage == "true"` OR `coverage_threshold == 0`), the script:
  1. Writes the line `coverage gate disabled by config (commands.coverage="true" or coverage_threshold=0)` to **stderr** (visible in interactive sessions, captured in any sprint-run log file).
  2. Emits the disabled-gate JSON on stdout: `{"mode": "skipped", "gate_status": "disabled", "pass": null, "reason": "<which-config>", "story_id": "<from --story-id arg>"}`. **`pass: null` (not `true`)** so downstream consumers cannot mistake "skipped" for "high coverage achieved". Consumers that need a yes/no answer must check `gate_status` first; `null` means "no gate decision".
  3. The lead reads the JSON and appends a `{coverage_gate: "disabled", reason: ..., story_id: ...}` entry to `state.json.gates` via `state.sh update gates='[<merged>]'` (array; declared in mech-1 schema). State write happens lead-side because state-mutation is a lead responsibility, not a per-script concern.
  4. Phase 3 phase-doc (mech-9) consumes `gate_status` first (treats `"disabled"` as pass-through) and only then reads `pass`. **`pass` is authoritative ONLY when `mode != "skipped"`.** Bats fixture exercises the SCRIPT directly (it's the script-under-test): `commands.coverage="true"` → disabled JSON (`gate_status:"disabled"`, `pass:null`) + stderr line; `coverage_threshold=0` → same; threshold>0 with coverage file → normal path (`mode:"new"` or `"whole"`, `gate_status:"measured"`, `pass:true|false`). **A separate integration test (not in `coverage_check.bats`) verifies the lead-side gates append; that test seeds a tmp git repo + valid state.json via `state.sh init` before invoking the skip-path.**
- `--mode new`: intersects uncovered lines with lines added in `git diff <diff-base>...HEAD`. Default `<diff-base>` resolution:
  - First story of sprint (no prior `story_commits` entry): `git merge-base <sprint_branch> <target_branch>`.
  - Subsequent stories: SHA of the prior story from `state.json.story_commits[]`.
  - `--mode whole` without `--story-id`: `git merge-base <sprint_branch> <target_branch>`.
- `--mode whole`: classic whole-tree coverage.
- Threshold default 80; exits 0 always; `pass` field is authoritative.
- If no coverage file found AND `commands.coverage != "true"` AND `coverage_threshold > 0`: exits 1 with stderr explaining the detection chain. No silent zero.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures using committed sample coverage files for each format (istanbul JSON snippet, go coverprofile snippet, python coverage.json snippet) and **a fixture that asserts the skip path triggers when `coverage_threshold=0`**.
- Each fixture asserts: detected format, pct, pass/fail, uncovered list shape.
- SKILL.md Phase 3 step 4 states **"new-code coverage by default; skipped entirely for bash-only projects with `coverage_threshold:0`"**. Rewrites the gate description as: "≥ threshold of lines added by this story's diff are covered (skipped when coverage_threshold=0)".

---

## Story mech-6: Per-story diff + commit message builder

### Context
SKILL.md Phase 4 wants "per-story diff" — `git diff <last-story-commit-or-target-branch>...HEAD`. v3 grounds "last-story-commit" in the `story_commits[]` field declared in mech-1's schema. Commit subject truncation is made unicode-safe.

### Acceptance Criteria
- `$SCRIPTS/per_story_diff.sh <story_id>` emits diff text to stdout. Resolution: read `state.json.story_commits[]` (declared in mech-1 schema) and diff `HEAD` against the SHA of the previous story; if `story_id` is the first in the sprint or no prior entry exists, diff against `git merge-base <sprint_branch> <target_branch>`.
- After story commit, the lead invokes `state.sh update <plan_path> story_commits='[<merged-array-with-new-entry>]'` to record the new SHA. (Schema field declared in mech-1; no ad-hoc field addition.)
- `$SCRIPTS/build_commit_msg.sh <plan_path> <story_id> <type>` (where `type ∈ {feat, fix, refactor, perf, docs, test, chore}`) emits the full commit message to stdout, populating: subject line (≤72 **unicode code points**; truncation uses `python3 -c 'import sys; s=sys.argv[1]; print(s[:72])'` so it never lands mid-codepoint; truncated suffix appends `…`); Story line; Plan line; AC bullets from parsed story; Gates summary line.
- Locale handling: `build_commit_msg.sh` sets `LC_ALL=en_US.UTF-8` internally so multi-byte input is counted as code points, not bytes.

### Definition of Done
- `shellcheck` clean.
- Bats fixture: story 1 (no prior); story 3 (diff against story 2's recorded SHA); missing story id (error); title exceeding 72 code points (truncated with `…`, never invalid UTF-8); **multi-byte / emoji title fixture** (e.g. `feat(BUG-417): フィードバック表示の修正`).
- SKILL.md Phase 4 step 1 references `per_story_diff.sh`. SKILL.md Phase 6 step 3 replaces inline heredoc with `build_commit_msg.sh` call.

---

## Story mech-7: Project autodetect + repomix refresh

### Context
SKILL.md Phase 0 commands-inference is prose. v3 specifies concrete confidence rules and adds the missing `require_repomix` preflight.

### Acceptance Criteria
- `$SCRIPTS/detect_commands.sh` emits JSON:
  ```json
  {"typecheck": "...", "lint": "...", "test": "...", "coverage": "...", "stack": "node|go|python|rust|bash|mixed", "confidence": "high|medium|low", "ambiguities": ["..."]}
  ```
  - Priority order: `justfile` → `package.json` scripts → `Makefile` → `pyproject.toml` (poetry/pdm/rye) → `Cargo.toml` → `go.mod`.
  - **Confidence rules (explicit):**
    - `high` = exactly one stack-marker file is present AND it defines all four targets (`typecheck`, `lint`, `test`, `coverage`).
    - `medium` = exactly one stack-marker file is present but it is missing one or more of the four targets.
    - `low` = no stack-marker file is recognised OR no recognised targets.
    - `mixed` = more than one stack-marker file is present from different language families (e.g. `package.json` + `Cargo.toml`).
  - `low` or `mixed` ⇒ exits 0 with `ambiguities` populated; SKILL.md instructs lead to ask user when confidence isn't `high`.
  - **Explicit-config precedence:** when `team-sprint.config.yaml.commands.<target>` is explicitly set (non-empty, non-null), the detector does NOT mark that specific target as `medium`/`low` ambiguous — the explicit value wins and the target is reported as `high` regardless of stack-marker file detection. The lead asks the user only for targets neither configured nor confidently auto-detected. Bats fixture: repo with Makefile defining only `test` + `lint` BUT config sets `commands.typecheck` and `commands.coverage` → confidence `high` (no ask).
- `$SCRIPTS/repomix_refresh.sh [--max-age-minutes 60] [--target-dir <path>]`:
  - Calls `require_repomix` from `lib.sh` first; on missing `repomix` CLI, prints install hint (`npm i -g repomix` OR `bun add -g repomix`) and exits 1.
  - **`--target-dir <path>` semantics:** defaults to `$PWD` when omitted. `<path>` may be absolute or relative-to-`$PWD`. The script `cd`s into `<path>` before invoking `repomix` and **passes `-o .repomix-output.xml` explicitly** (overriding repomix CLI's default `repomix-output.xml` without leading dot), so the output lands at `<path>/.repomix-output.xml`. `--max-age-minutes` is checked against `<path>/.repomix-output.xml` mtime (not the main tree's). On invocation completion the script returns to the original CWD.
  - Regenerates `.repomix-output.xml` if missing or older than threshold.
  - Idempotent; no-op when fresh.
- Both scripts exit 0 on no-op success; exit 1 only on actual failure.

### Definition of Done
- `shellcheck` clean.
- Bats fixtures: pure node repo (`high`), pure go repo (`high`), node + justfile (justfile wins, `medium` because targets may be partial), bash-only repo (`stack: bash`, `low` because none of the four targets resolve to anything except `true`), repo with neither (`low` + `ambiguities` populated), `repomix` not on PATH (exits 1 with install hint), stale repomix pack (regenerated), fresh repomix pack (no-op), **`--target-dir` to a tmpdir with no `.repomix-output.xml` produces `<tmpdir>/.repomix-output.xml`; `--target-dir` with fresh pack inside it is no-op; relative `--target-dir` resolves against caller CWD.**
- SKILL.md Phase 0 step 5 / step 9 replaced with script invocations.

---

## Story mech-8: Test fixtures + shellcheck harness

### Context
Story renamed from v1's "Test fixtures + CI lint" — "CI" over-promised, no `.github/workflows/` exists in the skill repo. v3 makes the harness explicitly local; a future story (out of scope) may add a GitHub Actions workflow. Plus: every script in `$SCRIPTS` (including the pre-existing `validate_plan_path.sh`) gets a fixture.

### Acceptance Criteria
- `$SCRIPTS/tests/` contains one `.bats` file per script. **Including `validate_plan_path.bats` for the pre-existing script** — this is the one backfill exception (adding tests doesn't violate the "interface stable" out-of-scope rule). Full list:
  - `validate_plan_path.bats` (backfill)
  - `state.bats`, `lead_validator.bats`, `apply_findings.bats`, `plan_diff.bats`, `parse_stories.bats`, `chunk_stories.bats`, `coverage_check.bats`, `per_story_diff.bats`, `build_commit_msg.bats`, `detect_commands.bats`, `repomix_refresh.bats`
- `$SCRIPTS/tests/fixtures/` holds sample plans, coverage files, stories.json, etc.
- **`$SCRIPTS/tests/lib/bats-fallback.sh` is an explicit deliverable** alongside the `.bats` files. Exports as plain-bash functions: `assert_equal`, `assert_success`, `assert_failure`, `assert_output`, `assert_stderr`, `refute_output`, `refute_stderr`, `assert_line`, `refute_line`, `assert_regex`, `assert_not_equal`. Under real `bats`, the file's exports are no-ops or shadowed (bats-assert provides its own). Every `.bats` file in this story sources it via `source "$(dirname "$BATS_TEST_FILENAME")/lib/bats-fallback.sh"` at the top of the file.
- **Fixtures may use only the helpers exported by `bats-fallback.sh`.** Lint check #12 (added in mech-14) rejects `.bats` files that invoke bats-assert helpers outside the exported set; suggested fix in the error message is "either add the helper to `bats-fallback.sh` or use an exported alternative".
- `$SCRIPTS/tests/run-all.sh`:
  - Runs `shellcheck` over every `$SCRIPTS/*.sh` first; aborts on any finding.
  - Runs `bats` over every `.bats` file; aborts on first failure.
  - If `bats` is not installed: falls back to invoking each `.bats` file as a plain bash script. Fixtures are also valid bash because every `.bats` sources `$SCRIPTS/tests/lib/bats-fallback.sh` at the top, which exports the assert helpers used by every fixture.
  - Exit 0 on success; non-zero on any failure.
  - **Note:** mech-14 amends this script to invoke `$SCRIPTS/lint_skill.sh` after bats and before exit; mech-8 ships the file without that hook.
- README at `$SCRIPTS/tests/README.md` documents how to add a new script + fixture and the bats-vs-fallback contract.

### Definition of Done
- `bash scripts/tests/run-all.sh` exits 0 on a clean checkout.
- Every script in `$SCRIPTS` (including `validate_plan_path.sh`) has at least one `@test` referencing it.
- CHANGELOG notes `bats-core`, `shellcheck`, and `repomix` as recommended dev dependencies (`brew install bats-core shellcheck`; `npm i -g repomix` OR `bun add -g repomix`). Versions pinned in CI/dev docs: bats `≥1.10`, shellcheck `≥0.9`, repomix `≥1.14`. `lib.sh require_repomix` install hint includes the `(≥1.14)` constraint.

---

## Story mech-9: SKILL.md split — phases/phase-{0..7}.md

### Context
SKILL.md is 491 lines. Lead only needs phase N's detail when entering phase N. Split. v3 keeps ALL eight phase docs mandatory (no v2-style "phase 1 and 5 optional") — uniform structure simplifies the lint rule and the reader's mental model. v3 also creates the "Architecture & decisions" section in SKILL.md so mech-15's ADR has a place to link from.

### Acceptance Criteria
- `$PHASES/phase-0.md` … `$PHASES/phase-7.md` ALL exist; each is self-contained for that phase (entry condition, gate, steps, exit condition, artifacts produced, scripts referenced, references to relevant `$REF/*` docs).
- **All eight phase docs include the literal extension marker `<!-- subskill-hooks:phase-N -->` exactly once** at the bottom of the doc in an `## Extensions` section. mech-14 lint check #5 enforces this uniformly across 0..7. Marker BODY TEXT differs by phase to avoid misleading documentation:
  - **Active phases (N ∈ {0, 2, 3, 4, 6, 7}):** body reads:
    ```markdown
    ## Extensions
    <!-- subskill-hooks:phase-N -->
    Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-N` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.
    ```
  - **Reserved phases (N ∈ {1, 5}):** body reads:
    ```markdown
    ## Extensions
    <!-- subskill-hooks:phase-N -->
    RESERVED — `subskill_hooks.phase-N` is NOT active in v1.0 (Phase N is mid-iteration; sub-skills should observe stable states only). Users who add a `phase-N` block to their config will see an INFO log line `subskill_hooks.phase-N unsupported in v1.0; block ignored` at Phase 0; the block is NOT persisted into `state.json.subskill_hooks`. A future minor version may activate this hook without requiring a marker-layout change. See `$REF/subskill-hooks.md` for rationale.
    ```
  - mech-14 lint check #5 accepts either body template per phase-N, but the marker comment line itself must be byte-identical.
- SKILL.md replaces each phase section with: heading, 1-line goal, gate condition, and explicit `**Load `$PHASES/phase-N.md` when entering this phase.**` line.
- SKILL.md gains a new section titled `## Architecture & decisions` that lists every ADR in `docs/adr/` by number + title. mech-15's ADR links from this section.
- **Line-count target (intermediate):** `wc -l SKILL.md ≤ 250` immediately after mech-9 commits. Sprint-final target (`≤180`) is enforced at mech-14, not here. mech-10 is ungated on lines.
- Cross-phase invariants (state.json schema location, `$ART` path convention, SendMessage protocol) remain in SKILL.md, not duplicated into phase docs.
- Phase docs reference scripts by absolute-from-skill-root path: `$SCRIPTS/state.sh`, etc. SKILL.md defines `$SCRIPTS`, `$PHASES`, `$REF`, `$ART` aliases once.

### Definition of Done
- `wc -l SKILL.md` ≤ 250 after this story's commit.
- **Pre-split snapshot of SKILL.md is written to `$ART/skill-md-pre-split.md` BEFORE the split is performed** (per CC-6). mech-10 reads sections from this snapshot, not the post-split SKILL.md. **Snapshot resilience:** the snapshot lives in gitignored `$ART/`; if missing at mech-10 start (e.g. user cleared `.team-sprint/` between commits), mech-10 aborts with the regen instruction: `git show $(git log -E --grep='^Story: mech-9' -n1 --format=%H)~1:SKILL.md > $ART/skill-md-pre-split.md`. **Rationale:** `git log --grep` is line-oriented (searches each line of the commit message independently). `build_commit_msg.sh` (mech-6) emits the structured body line `Story: mech-9 — <title>` for every story commit, so matching on `^Story: mech-9` is deterministic regardless of subject-line wording. If grep still finds no match (e.g. user squashed commits), engineer falls back to: `git log --format='%H %s%n%b' --all | grep -B1 -E '^Story: mech-9' | head -1 | awk '{print $1}'` to find the SHA, then `git show <sha>~1:SKILL.md > $ART/skill-md-pre-split.md`. mech-10 bats fixture covers the missing-snapshot abort path with deterministic test commits using the same `Story:` body shape `build_commit_msg.sh` produces.
- Each phase doc passes a manual checklist: entry condition stated, gate stated, exit condition stated, artifacts listed, scripts referenced (not pseudocode), `<!-- subskill-hooks:phase-N -->` marker present once.
- `## Architecture & decisions` section exists in SKILL.md.
- No phase doc duplicates state.json schema, `$ART` path convention, or guardrail rules.
- **Every phase doc references at least one script at this story's commit time** (closes mech-14 lint check #4 ordering issue). Minimum scripts per phase doc:
  - `phase-0.md`: `$SCRIPTS/validate_plan_path.sh`, `$SCRIPTS/state.sh`, `$SCRIPTS/detect_commands.sh`, `$SCRIPTS/repomix_refresh.sh`
  - `phase-1.md`: `$SCRIPTS/lead_validator.sh`, `$SCRIPTS/apply_findings.sh`, `$SCRIPTS/plan_diff.sh`, `$SCRIPTS/parse_stories.sh`, `$SCRIPTS/chunk_stories.sh`
  - `phase-2.md`: `$SCRIPTS/state.sh`, `$SCRIPTS/repomix_refresh.sh` (with `--target-dir`)
  - `phase-3.md`: `$SCRIPTS/coverage_check.sh`, `$SCRIPTS/state.sh`
  - `phase-4.md`: `$SCRIPTS/per_story_diff.sh`, `$SCRIPTS/state.sh`
  - `phase-5.md`: `$SCRIPTS/coverage_check.sh` (re-runs after fix iterations), `$SCRIPTS/state.sh`
  - `phase-6.md`: `$SCRIPTS/per_story_diff.sh`, `$SCRIPTS/build_commit_msg.sh`, `$SCRIPTS/run_subskill_hooks.sh`
  - `phase-7.md`: `$SCRIPTS/state.sh`, `$SCRIPTS/run_subskill_hooks.sh`
- Phase docs may reference `$REF/*.md` paths even though mech-10 has not yet created those files (per CC-6); mech-14's lint passes only after both mech-9 and mech-10 have shipped.

---

## Story mech-10: Reference docs extraction

### Context
SKILL.md embeds several long stable references. Move them out so SKILL.md stays lean. v3 adds a **per-section move map** so reviewers can verify the extraction line-by-line, and explicitly mandates updating SKILL.md cross-refs to the new locations.

### Acceptance Criteria

- **Source of extracted content is `$ART/skill-md-pre-split.md`** (the pre-split snapshot captured in mech-9's DoD per CC-6), NOT the live, post-split SKILL.md. Anchors below refer to the snapshot.
- **If the snapshot is missing at mech-10 start, mech-10 ABORTS** with the regen instruction from mech-9 DoD (no silent fallback to live SKILL.md, which would re-introduce line-number drift).
- The following reference docs are created with content extracted per this move map. **Anchors are section headings (stable across compression), not line numbers** — engineer locates each by `grep -n '^### <heading>' $ART/skill-md-pre-split.md` then extracts from the heading line through the heading-terminator (next H2/H3 or end of relevant block).
- **Convention rewrite during extraction (prose-only):** any literal `.team-sprint/sprints/<worktree_name>/` substring inside the extracted PROSE is rewritten to `$ART/` inline as the content is written to `$REF/state-schema.md` (or any other `$REF/*.md` that legitimately quoted the old form). **"Preserved verbatim" categories (two only, both backtick-delimited):** (1) inside fenced code blocks (delimited by triple backticks ```…```); (2) inside inline code spans (delimited by single backticks `…`). Everything else — including double-quoted JSON-looking tokens in flowing prose — IS prose and gets rewritten. Specifically: the state.json example JSON block in `$REF/state-schema.md` keeps `"artifact_dir": ".team-sprint/sprints/<worktree_name>"` as the literal schema value (in a fenced block); the prose paragraph above the block uses `$ART/`. Verify with: `awk '/```/{f=!f; next} !f' $REF/state-schema.md | grep -oE '\`[^\`]*\`' -o > /tmp/inline.txt; awk '/```/{f=!f; next} !f' $REF/state-schema.md | grep -v -F -f /tmp/inline.txt | grep -c '\.team-sprint/sprints/<worktree_name>/'` returns 0 (prose-only count after subtracting both fenced and inline-code occurrences).

| Source (heading anchor in `$ART/skill-md-pre-split.md`) | Destination |
|---|---|
| `### Plan path naming convention (REQUIRED — uniqueness contract)` H3 section through the closing of the `Phase 0 validator (\`scripts/validate_plan_path.sh\`):` bash code fence (≈ pre-split lines 54–98, but locate by heading) | `$REF/plan-path-convention.md` |
| `### Reviewer return contract (per chunk)` H3 section through the closing of the ```` ```json adversarial-summary ```` code fence and the immediately-following `story_id: "*"` paragraph (≈ pre-split lines 220–253, but locate by heading) | `$REF/reviewer-contract.md` |
| The paragraph beginning `Persist sprint metadata to .team-sprint/sprints/<worktree_name>/state.json:` through the closing of its JSON code fence + the immediately-following `This file is the resume contract — …` paragraph (in the "Per-sprint artifact dir (uniqueness):" section) | `$REF/state-schema.md` (machine schema stays at `$SCRIPTS/state.schema.json`) |
| `SendMessage` protocol rules synthesised from SKILL.md guardrails (the "Guardrails" section bullet starting `**SendMessage is the protocol.**`) | `$REF/sendmessage-protocol.md` (**authored fresh inside the skill**, NOT copy-pasted from `$HOME/.claude/CLAUDE.md` — the user-global file is referenced as upstream only) |

- Every removed section in SKILL.md is replaced by a single-line reference of the form `See **<title>** in $REF/<file>.md`. No link to removed content remains broken; mech-14's `lint_skill.sh` greps SKILL.md for known stale internal anchors (`#plan-path-naming`, `#reviewer-return-contract`, etc.) and asserts zero hits.
- Every `$REF/*.md` opens with a `**WHO READS THIS / WHEN:**` line (e.g. "Reviewers in Phase 1 chunked subagents read this before composing findings.").
- SKILL.md preserves all cross-refs to `scripts/validate_plan_path.sh` (currently at SKILL.md lines 82, 84, 96, 482 — verify on commit) by updating them to point at `$REF/plan-path-convention.md` for the convention text and at `$SCRIPTS/validate_plan_path.sh` for the script itself.

### Definition of Done
- All four `$REF/*.md` files exist with `**WHO READS THIS / WHEN:**` header.
- SKILL.md references each `$REF/*.md` exactly once with a one-line link; no duplicated reference content remains.
- `grep -E '\(#plan-path-naming|#reviewer-return-contract|#state-schema|#sendmessage-protocol\)' SKILL.md` returns 0 lines (no dangling internal anchors).
- `$REF/sendmessage-protocol.md` includes a note: "This document is the canonical SendMessage contract for the team-sprint skill. The user-global `$HOME/.claude/CLAUDE.md` may carry similar rules but is not authoritative for this skill."
- **Freshness fingerprint:** `$REF/sendmessage-protocol.md` MUST contain ALL THREE of the genuinely skill-local terms in its body: `spec-reviewer`, `Phase 4`, `Phase 6`. (Note: `team-lead` was removed from the fingerprint set because it appears in `$HOME/.claude/CLAUDE.md`'s SendMessage-protocol section — its presence does not prove freshness.) Verify: `grep -c 'spec-reviewer' $REF/sendmessage-protocol.md && grep -cE 'Phase 4' $REF/sendmessage-protocol.md && grep -cE 'Phase 6' $REF/sendmessage-protocol.md` each return ≥1.

---

## Story mech-11: Prose compression + Migration boundary breadcrumb

### Context
SKILL.md repeats `.team-sprint/sprints/<worktree_name>/` ~20 times — `$ART` alias collapses these. The "Migration boundary" subsection (~10 lines) is reduced to a one-line breadcrumb pointing to CHANGELOG (per cross-cutting decision CC-3 — full removal sacrifices a real operational signal). Line-count target is absolute, not percentage.

### Acceptance Criteria
- SKILL.md introduces `$ART` alias once: "Throughout this skill, `$ART` = the per-sprint artifact dir, resolved via `$SCRIPTS/state.sh art_dir <plan_path>`. Every later reference uses `$ART/<filename>`."
- All `.team-sprint/sprints/<worktree_name>/<file>` references replaced with `$ART/<file>`.
- **`$SKILL_DIR/CHANGELOG.md` is created by this story** (per CC-3). It contains an initial `## [Unreleased] / v0.x → v1.0 migration note` section with the full "Migration boundary" text moved from SKILL.md. mech-14 later appends the full v1.0 cut entry above this section.
- "Migration boundary" full subsection moved from SKILL.md into CHANGELOG.md. **A one-line breadcrumb remains in SKILL.md's "Failure modes & resume" section: "Pre-v1.0 sprint layout (flat `.team-sprint/state.json`)? See CHANGELOG.md v0.x → v1.0 migration note for manual recovery."**
- Filler / hedging phrases removed without information loss (e.g. "It also adds", "This skill is a thin orchestrator — the heavy work happens…" condensed).

### Definition of Done
- `grep -c '\.team-sprint/sprints/<worktree_name>/' SKILL.md` returns 1 (the `$ART` definition line) or 0.
- `CHANGELOG.md` exists at `$SKILL_DIR/CHANGELOG.md` and contains the migration note section.
- Migration boundary breadcrumb present in SKILL.md's "Failure modes & resume" section; full subsection absent from SKILL.md but present in CHANGELOG.md.
- **`wc -l SKILL.md` ≤ 180** after this story's commit (absolute target, no percentage).

---

## Story mech-12: Config defaults + new parameters

### Context
Defaults need calibration. `adversarial_iterations` becomes 3. New fields support the extension surface (mech-15) and address ambiguity in `integration_diagram` auto-mode (graceful degrade is explicit, never aborts).

### Acceptance Criteria
- Default `adversarial_iterations` changes from `6` to `3`.
- New config field `max_wall_clock_minutes` (default `240`). When exceeded, sprint-watchdog raises a warning to the user with current phase + remaining work; user decides extend/abort. Not a hard kill — state persists.
- New config field `adversarial_model` (default `opus`). Replaces every hardcoded `model: opus` in the skill text.
- New config field `coverage_mode` (default `new`, alternatives `whole`). Wired into `coverage_check.sh`.
- New config field `repomix_max_age_minutes` (default `240`).
- New config block `subskill_hooks` with named phases:
  ```yaml
  subskill_hooks:
    phase-0:  []
    phase-2:  []
    phase-3:  []
    phase-4:  []
    phase-6:  []
    phase-7:  []
  ```
  Each entry is `{skill: <name>, command: <cli>, required?: bool}`. `skill` is metadata (label + preflight probe target); `command` is the executed shell line (always runs when the hook fires); `required` (default `false`) controls preflight strictness — see mech-13 step 3. The semantics are documented explicitly in `$REF/subskill-hooks.md` (mech-15).
- **Ownership: `$SKILL_DIR/team-sprint.config.yaml.example` is CREATED by this story** with the full v3 config surface enumerated above (sans `subskill_hooks` body, which mech-15 extends with example hooks). mech-14 only lints existence + content; mech-15 only extends. No story re-creates the file.
- Phase 4 spec-reviewer instructions explicitly state: "Findings are impl-only. Plan is frozen at Phase 1; spec-reviewer must NOT request plan revisions. Plan-vs-implementation drift findings become CRITICAL fix tasks for the engineer."
- Subagent skill preflight: Phase 0 invokes `$SCRIPTS/preflight_subskills.sh` (created in mech-15); on failure of any required skill, Phase 0 STOPs.

### Definition of Done
- Default config block in SKILL.md updated to list every field above.
- `$SKILL_DIR/team-sprint.config.yaml.example` exists (created by this story), contains the full v3 config surface.
- Phase 0 phase-doc lists the subagent skill preflight as an explicit step.
- Phase 4 phase-doc spec-reviewer subsection contains the "impl-only" contract verbatim.
- `coverage_check.sh` invocation in Phase 3 phase-doc reads `coverage_mode` from config.

---

## Story mech-13: Worktree repomix + preflight ordering

### Context
`use-repo-code` produces `.repomix-output.xml` in the main tree at Phase 0. Reviewers in Phase 4 run in the worktree. v3 makes the location explicit and locks the **preflight + auto-resolution ordering** so the resolved hook list in `state.json` is reproducible.

### Acceptance Criteria
- Phase 2 step 1 (worktree creation) gains a sub-step: copy `.repomix-output.xml` from main tree to worktree (`cp <main>/.repomix-output.xml <worktree>/.repomix-output.xml`). Refresh-in-worktree only if sprint duration exceeds `repomix_max_age_minutes`.
- Phase 4 reviewer prompts include: "Grep the worktree-local `.repomix-output.xml`. Paths in grep results are repo-relative; resolve them against the worktree root, not the main tree."
- **Preflight + auto-resolution ordering (locked in):** Phase 0 executes in this exact sequence:
  1. Read `team-sprint.config.yaml`.
  2. If `integration_diagram == auto`, invoke `$SCRIPTS/preflight_subskills.sh --probe-only integration-diagram`. On success: prepend the diagram skill's hook spec into `subskill_hooks.phase-{0,2,3,4,6,7}` (auto-prepended entries default `required: false`). On failure: log `integration-diagram: not found, auto → off` at INFO and do NOT prepend. (No Phase 0 abort on auto-mode failure; this is graceful degrade.)
  3. Invoke `$SCRIPTS/preflight_subskills.sh --probe-all` over the merged hook list. **Probe-failure handling is governed by the per-entry `required` flag, not by user-declared-vs-auto-prepended status:** if `required: true` and probe fails → Phase 0 ABORT with the failing skill name in the error. If `required: false` (default) and probe fails → log a WARN line `subskill <name> probe failed; hook will still attempt to run (command is authoritative)` and continue. This keeps the fail-soft contract (the `command` is always what executes) coherent with users' explicit strictness choice.
  4. **Config-to-state transformation (explicit):** for each map key `phase-N` in `team-sprint.config.yaml.subskill_hooks`, iterate its array of entries. **If `N ∈ {1, 5}`** (reserved phases per mech-9 + mech-15 ADR), emit an INFO log line `subskill_hooks.phase-N unsupported in v1.0; block ignored` and SKIP the entries (do not persist into state). For all other phase-N (∈ {0,2,3,4,6,7}), emit one object per entry into the merged hook list with: `skill` and `command` copied from the entry; `required` set to `entry.required ?? false`; `phase` set to the literal map key (`"phase-0"`, `"phase-2"`, …); `source: "user"`. Auto-prepended entries (from `integration_diagram: auto` resolution in step 2) emit with `source: "auto"`. **Array order:** for each active phase in ascending order (0, 2, 3, 4, 6, 7), emit all auto-prepended entries first (in declaration order from the diagram skill's hook spec), then all user-declared entries (in YAML declaration order). Write the resulting flat array to **`state.json.subskill_hooks`** (the dedicated array field declared in mech-1 schema; distinct from `state.json.subskills` which holds per-skill metadata only) via `state.sh update subskill_hooks='[...]'`. Bats integration fixture: config with entries under phase-1 + phase-6 → state.json.subskill_hooks contains ONLY the phase-6 entries; phase-1 INFO log line emitted.
  5. Emit a single INFO log line prefixed `subskill_hooks resolved:` listing every resolved hook + its `required` value + `source` (so the audit trail is unambiguous and greppable). **Privacy (deny-list, not allow-list):** the log line includes the `command` verbatim UNLESS `command` contains any of the shell-injection-enabling characters `| ; & \` $( > <` (pipe, semicolon, ampersand, backtick, command-substitution, redirection). When any of those characters is present, the line reads `<command redacted — contains shell metachars>`. Common safe characters including `~`, `=`, `:`, `@`, `+`, `-`, `,`, `'`, `"` are NOT redaction triggers (they're routinely used in safe argv positions; e.g. the documented example `bash $HOME/.claude/skills/my-skill/run.sh` is logged verbatim). **Acknowledged limitation:** the redactor is a character-class scan, not a shell parser; it cannot distinguish a literal backtick inside single quotes (shell-safe) from a backtick-command-substitution. Effect is cosmetic over-redaction in the rare case a user embeds a literal backtick in a hook command; the full unredacted command is still committed to `state.json.subskill_hooks` for audit. The full command is committed regardless; redaction applies only to the audit log line.
- `repomix_refresh.sh` gains `--target-dir <path>` arg so it can refresh inside the worktree if needed (defined in mech-7; this story adds the Phase 2 invocation that uses it).
- Lead spawn prompt for Phase 1 chunked reviewers + Phase 4 spec-reviewer includes a one-line preamble: "Verify the `adversarial-review` skill is available via the Skill tool before starting. If not, abort and report."

### Definition of Done
- Phase 2 phase-doc explicitly handles the repomix pack location and references `$SCRIPTS/repomix_refresh.sh --target-dir <worktree>`.
- Phase 0 phase-doc lists the five-step preflight + auto-resolution sequence verbatim.
- Phase 4 phase-doc reviewer prompts include the worktree path resolution note.
- Subagent skill discovery preamble appears in every relevant spawn prompt template.

---

## Story mech-14: Phase doc lint + skill-validator + CHANGELOG

**Commit count: 2** (14a + 14b — see Story split section below). Sprint-DoD reconciles by stating "all 15 stories shipped on 16 commits, with mech-14 split per CC-6".

### Context
After the refactor, the skill spans many files. Drift between SKILL.md's phase index and the actual phase docs causes silent breakage. v3 tightens the lint scope explicitly (excludes `$REF/`, `docs/adr/`, `docs/plans/` from marker checks) AND splits the story into two commits to resolve the mech-14 ↔ mech-15 ordering conflict found in round 3.

### Story split (resolves R3-2C1 ordering conflict)

- **mech-14a** (ships before mech-15): authors `$SCRIPTS/lint_skill.sh` with checks #1–#9 + #11 + #12 below. Does NOT include check #10 (subskill-hooks.md existence). Does NOT wire `lint_skill.sh` into `run-all.sh`. Does NOT run `skill-validator`. Does NOT cut v1.0.
- **mech-14b** (ships immediately AFTER mech-15): adds check #10 to `lint_skill.sh`, wires `lint_skill.sh` into `run-all.sh`, runs `skill-validator`, performs the `cut v1.0` commit. Final story of the sprint.

Both ship within this single story (one feature, two commits — the split is purely an ordering accommodation, no scope change).

### Acceptance Criteria
- `$SCRIPTS/lint_skill.sh` runs every check below; exits non-zero on any failure. **Lint script enumerates phase docs via `find "$PHASES" -name 'phase-*.md' -maxdepth 1`** (no wildcard recursion). Files outside `$PHASES/` (specifically `$REF/`, `docs/adr/`, `docs/plans/`, `team-sprint.config.yaml.example`, and the skill root) may legitimately mention any marker / flag string and are NEVER scanned by any check below.
  1. SKILL.md mentions `$PHASES/phase-N.md` for N = 0..7 and each file exists.
  2. SKILL.md mentions every `$REF/*.md` that exists and vice versa.
  3. SKILL.md mentions every `$SCRIPTS/*.sh` that exists OR the script is listed under `$SCRIPTS/tests/` (test harness exempt).
  4. Every `$PHASES/phase-N.md` references at least one script (verified by `grep -E '\$SCRIPTS/[a-z_]+\.sh'`).
  5. Every `$PHASES/phase-N.md` contains the literal `<!-- subskill-hooks:phase-N -->` marker **exactly once for N ∈ {0..7}**.
  6. `grep -E '\(#plan-path-naming|#reviewer-return-contract|#state-schema|#sendmessage-protocol\)' SKILL.md` returns 0 lines (no dangling internal anchors).
  7. `shellcheck` over every `$SCRIPTS/*.sh` passes.
  8. `bats scripts/tests/` passes (or fallback runner if bats absent).
  9. `team-sprint.config.yaml.example` exists and contains the full v3 config surface.
  10. `$REF/subskill-hooks.md` exists (created by mech-15). **Added in mech-14b** (after mech-15 has shipped) so mech-14a does not fail on a not-yet-existent file.
  11. `grep -rn 'allow-bootstrap' SKILL.md phases/ 2>/dev/null` returns 0 lines. (Lint scope excludes `$REF/` and `team-sprint.config.yaml.example` which may legitimately document the retired flag.)
  12. Every `.bats` file under `$SCRIPTS/tests/` uses only bats-assert helpers exported by `$SCRIPTS/tests/lib/bats-fallback.sh`. **Detection (subtractive — must enumerate the namespace AND check for non-allowed members):** `grep -hoE '\b(assert|refute)_[a-z_]+\b' "$SCRIPTS/tests/"*.bats | sort -u | grep -vxE '(refute_output|refute_stderr|assert_line|refute_line|assert_regex|assert_not_equal|assert_equal|assert_success|assert_failure|assert_output|assert_stderr)'` returns 0 lines. Non-zero output means a forbidden helper is invoked; the lint emits the offending name and suggests "either add to bats-fallback.sh or use an exported alternative".
- `$SKILL_DIR/CHANGELOG.md` records the v1.0 cut: scripts added, defaults changed, config fields added, files moved, behavioural changes (new-code coverage default, line-count targets), full "Migration boundary" content moved here from SKILL.md.
- `skill-validator` skill (already present at `$HOME/.claude/skills/skill-validator`) invoked against `team-sprint` returns grade A (0 failures, ≤2 warnings).
- Frontmatter `description` reviewed: trim filler without dropping trigger keywords. Target ≤200 words.

### Definition of Done
- **mech-14a commit:** `lint_skill.sh` exists with checks 1–9 + 11 + 12 (NO check #10). `$SCRIPTS/tests/lint_skill.bats` also authored (covers: clean-state lint passes; missing-marker fails check #5; allow-bootstrap residue fails #11; forbidden-helper-in-fixture fails #12). This satisfies mech-8 DoD invariant ("every script in $SCRIPTS has at least one @test referencing it"). `run-all.sh` unchanged (no lint wire-in yet). `lint_skill.sh` runs clean against the post-mech-13 state.
- **mech-14b commit (after mech-15 ships):** `lint_skill.sh` amended to also run check #10. `$SCRIPTS/tests/run-all.sh` amended to invoke `lint_skill.sh` after bats and before exit: shellcheck → bats → lint_skill.sh → exit. lint_skill.sh failure produces non-zero exit.
- `skill-validator` report attached to the sprint commit message for mech-14b.
- CHANGELOG entry complete (mech-11 created the file with the migration note; mech-14b prepends the full v1.0 cut entry above it).
- Final commit on this story (i.e. on mech-14b): `chore(team-sprint-mech): cut v1.0` with validator output quoted in body.

---

## Story mech-15: Stable extension surface for sub-skills

### Context
Hook contract + preflight script + ADR + reference doc. This is the user-visible extension surface that future sub-skills (e.g. a yet-to-be-authored `integration-diagram` skill) will consume. v3 drops every forward reference to a non-existent `sprint-integration-diagram-skill-v2.md` (per cross-cutting decision CC-2) and treats the integration-diagram skill as a generic future consumer documented only in informational terms.

### Acceptance Criteria
- `$REF/subskill-hooks.md` exists and documents:
  - The six hook phases (0, 2, 3, 4, 6, 7) and what state is committed at each.
  - **Field semantics:** `skill` is metadata (preflight probe target + log label); `command` is the shell line executed in the worktree dir. **The `command` is always run when the hook fires.** `skill` may be set to a non-existent string for tests (e.g. `skill: noop`) — its only effect is the preflight probe (which can be made non-fatal with `--probe-only`), not gating.
  - The TS_* contract env vars: `TS_PLAN_PATH`, `TS_STORY_ID`, `TS_TASK_ID`, `TS_ART_DIR`, `TS_WORKTREE`. **Namespace invariant: future env vars stay under `TS_*`; collisions with `GIT_*`/`BATS_*`/POSIX-standard names are forbidden.**
  - Fail-soft policy: hooks always run; non-zero exits are logged but do not block the sprint. (v1.0 has no strict mode; deferred to a future story.)
  - One-line example: `subskill_hooks: { phase-6: [{skill: my-skill, command: 'bash $HOME/.claude/skills/my-skill/run.sh'}] }`.
  - **Note: as of v1.0 of the hook contract, no canonical sub-skill consumer ships. The integration-diagram skill is documented as a planned future consumer; its plan is authored in a separate sprint.**
- `$SKILL_DIR/team-sprint.config.yaml.example` (created in mech-12) is EXTENDED by this story with the example `subskill_hooks` block + the `integration_diagram` knob; do NOT recreate. After this story commit, the file contains the full v1 + v3 config surface and is referenced from SKILL.md Phase 0.
- `$SCRIPTS/run_subskill_hooks.sh <phase> <plan_path>`:
  - Reads merged hook list from **`state.json.subskill_hooks`** (Phase 0 wrote it; array field declared in mech-1 schema). Filters by `phase` arg.
  - Invokes each hook's `command` in declaration order with the TS_* contract env vars set, in the worktree dir.
  - Captures stdout+stderr to `$ART/subskill-<phase>.log` (append, not overwrite).
  - **Always exits 0.**
  - Bats fixture covers: zero hooks (no-op), one passing hook, one failing hook (logged, exit still 0), two hooks where the first fails (second still runs), schema-required-flag honoured at preflight time but not at run time (run is always fail-soft).
- `phase-{0,2,3,4,6,7}.md` invoke `run_subskill_hooks.sh` as their final step, after the phase's main work but before advancing `current_phase`.
- `$SCRIPTS/preflight_subskills.sh`:
  - Accepts `--probe-only <skill-name>` (probe a single skill, exit 0 if present, 1 if absent — for graceful-degrade use cases like `integration_diagram: auto`).
  - Accepts `--probe-all` (probe every entry in the merged hook list from **`state.json.subskill_hooks`** — the dedicated array field declared in mech-1 schema, written by mech-13 step 4. Iterates the array; `required` is read per-entry from each array element, NOT from the per-skill metadata map `state.json.subskills`).
  - **Default probe is a filesystem check** — pure shell, no Agent tool involved: `test -f "$HOME/.claude/skills/<skill-name>/SKILL.md"` is the canonical existence test. Rationale: bash scripts cannot invoke Claude's Agent/Skill tool; the filesystem probe is portable, fast, and deterministic.
  - **Accepts `--probe-fn <path-to-script>` injection point.** Default is the filesystem check above. Bats fixtures override via `--probe-fn` to supply canned results (present-skill, missing-skill) without filesystem manipulation. Bats fixtures cover: present-skill (filesystem-real or stub-probe), missing-skill (filesystem-real or stub-probe), `integration_diagram: off` (no probe attempted), `required: true` skill missing (exit non-zero), `required: false` skill missing (exit 0 with WARN), **cache-present with skill marked present (no filesystem probe, exit 0), cache-present with skill marked absent (no filesystem probe, exit per required flag)**.
  - **Optional lead-side enrichment:** the lead orchestrator (Claude) MAY perform an additional Skill/Task-tool probe BEFORE invoking `preflight_subskills.sh` and write the enriched verdict to `$ART/preflight-cache.json`. **Cache schema (pinned):** `{ "<skill-name>": { "present": bool, "probed_at": "<ISO-8601 UTC>", "source": "agent-tool" } }`. Keys are skill names; values are per-skill verdicts. Absent keys → filesystem fallback (partial enrichment supported). **Cache verdict wins over filesystem when both are available** (the lead's cache is the higher-confidence signal by design). This is purely optional — the production default does NOT depend on it. Documented in `$REF/subskill-hooks.md`.
- `$SKILL_DIR/docs/adr/001-subskill-extension-surface.md` ADR records:
  - Why hook phases were chosen (matches the natural stable commit points: pre-flight, worktree setup, per-story TDD, post-review, per-story commit, finalise).
  - **Why phases 1 and 5 carry markers but NO config blocks in v1.0:** Phase 1 = plan review, mid-iteration; Phase 5 = fix loop, mid-iteration. Sub-skills should observe stable states, not in-flight ones. **All 8 phase docs (0..7) carry the `<!-- subskill-hooks:phase-N -->` marker (per mech-9 + mech-14 lint uniformity)**; the markers for phase-1 and phase-5 are "reserved" — config blocks `subskill_hooks.phase-1` / `subskill_hooks.phase-5` are unsupported by v1.0 (the lead does not invoke `run_subskill_hooks.sh` from phase-1.md or phase-5.md). A future minor version may enable them without requiring a marker-layout change. This resolves the round-2 contradiction between ADR opt-in language and mech-9/mech-14's "all 8 markers mandatory" rule.
  - Why fail-soft (sub-skills must never block the main sprint).
  - Why env vars over stdin (subagents and shell commands both consume env naturally; stdin is single-use and conflicts with hook commands that read their own input).
  - TS_* namespace invariant (locked).
- **`docs/adr/` directory is created by this story (`mkdir -p docs/adr`)**, and `docs/adr/README.md` documents:
  - Filename scheme: `<3-digit-zero-padded>-<kebab-slug>.md` (e.g. `001-subskill-extension-surface.md`).
  - Numbering: monotonic, assigned at PR open time. Never renumbered after merge to main.
  - **Concurrent-PR tiebreaker:** if two PRs are opened with the same `NNN-` prefix, the PR with the later `mergedAt` timestamp (`gh pr view <pr> --json mergedAt`) is the renumberer; it must rebase, rename its ADR file to the next available integer, and update internal links **in its merge commit** (not in a follow-up PR). The earlier-merged PR keeps its number unchanged. Reviewers of the later PR enforce the rebase before approval; any post-merge renumbering on main is rejected as a breaking change.
- ADR linked from SKILL.md's `## Architecture & decisions` section (created in mech-9).

### Definition of Done
- `shellcheck` clean on `run_subskill_hooks.sh` and `preflight_subskills.sh`.
- **`$SCRIPTS/tests/run_subskill_hooks.bats` and `$SCRIPTS/tests/preflight_subskills.bats` are explicit deliverables** of this story (alongside the scripts themselves), satisfying mech-8 DoD invariant. Fixture cases listed inline above.
- `lint_skill.sh` passes (i.e. all mech-14 checks plus the v3 amendments here).
- **Dry-run sprint (per CC-7)** with `subskill_hooks: { phase-6: [{skill: noop, command: 'true'}] }` shows the hook fires once per story commit and the log file contains the expected single line.
- **Dry-run sprint** with `integration_diagram: off` skips all diagram-related probes and hooks.
- **Dry-run sprint** with `integration_diagram: auto` and `integration-diagram` skill absent logs the graceful-degrade INFO line and continues; no Phase 0 abort.
- ADR linked from SKILL.md's `## Architecture & decisions` section.
- `docs/adr/README.md` exists with the numbering scheme + concurrent-PR tiebreaker.

---

## Cross-story invariants

- **No behavioural regression to the resume contract.** A sprint started under the current skill version must still be resumable under v1.0 (state.json schema additions only — never renames or removes).
- **`validate_plan_path.sh` stdout/exit-code interface stays stable.** Internals may be refactored (e.g. lib.sh integration); the externally-observable contract (stdout: `SLUG=…`, `SPRINT_DIR=…`, `STATUS=OK|RESUME|FAIL`; exit codes 0/1/2) does not change. `team-sprint --abort` callers keep working.
- **`$ART` is single-sourced.** Only `$SCRIPTS/state.sh art_dir` (which delegates to `validate_plan_path.sh --slug-only`) resolves ART. No other script independently derives it.
- **Every script call site in SKILL.md / phase docs uses absolute-from-skill-root paths** via the `$SCRIPTS`, `$PHASES`, `$REF`, `$ART` aliases.
- **Each story commits as a single conventional commit** per the team-sprint Phase 6 contract — `feat(team-sprint-mech)`, `refactor(team-sprint-mech)`, `chore(team-sprint-mech)` as appropriate.
- **The sub-skill hook contract is additive only.** Future sub-skills add to `subskill_hooks` without modifying the contract; never break it. Adding a new env var requires bumping `state.schema.json` and updating `$REF/subskill-hooks.md`. Removing one is a breaking change forbidden in any patch release.
- **TS_* env namespace is locked.** New hook env vars stay under `TS_*`.

## Sprint-level Definition of Done

- All 15 stories shipped on the sprint branch as **16 commits total** (every story = 1 commit, except mech-14 which ships as two commits per CC-6: mech-14a before mech-15, mech-14b after).
- `bash scripts/tests/run-all.sh` exits 0.
- `skill-validator` returns grade A.
- `wc -l SKILL.md` ≤ 180.
- Token-audit on a fresh **dry-run sprint** (per CC-7) shows ≥50% reduction in per-turn context cost vs. pre-refactor baseline (measured on the same fixture plan).
- CHANGELOG updated with the v1.0 entry.
- No behavioural regression on a fixture sprint that resumes from a v0.x state.json.
- **Dry-run sprint (per CC-7)** with `integration_diagram: auto` (and integration-diagram skill ABSENT) runs Phase 0 → Phase 7 with zero non-zero exits from the preflight or hook layers.

## Surfaced risks

- **Bats not installed by default on macOS.** Mitigated by `run-all.sh` plain-bash fallback (mech-8).
- **`shellcheck` strictness varies by version.** Pinned at `≥0.9` in CHANGELOG; mech-8 documents `brew install shellcheck` requirement.
- **`coverage_check.sh --mode new` `git diff` semantics.** First-story case (no prior commit) and `--mode whole` cases explicitly covered in mech-5 ACs.
- **Subagent skill discovery is environment-dependent.** Some Claude Code installs may not expose `adversarial-review` to a `general-purpose` subagent. Preflight catches at Phase 0; STOP with install hint.
- **Frontmatter description trim could reduce trigger sensitivity.** Validate post-trim via `skill-validator` trigger-accuracy mode.
- **Integration-diagram skill is a hypothetical future consumer.** v3 ships the extension surface WITHOUT depending on the future skill existing. If the integration-diagram skill is never authored, the extension surface remains a no-op feature — non-zero cost (config block, hook script) but no operational impact.
- **Forward references to non-existent files are forbidden in this plan** (CC-2). If a future amendment to v3 needs to reference a file that doesn't exist yet, it must either author the file first or document the reference as informational (with no enforcement).
- **Strict-mode for hooks is intentionally absent in v1.0** of the hook contract. A future minor version may add `subskill_hooks.strict_phases: [phase-N, ...]`. Users who need CI-style strictness today must wrap their `command` to fail loudly themselves.

---

**End of plan v3.**

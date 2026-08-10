---
name: team-sprint
model: opus
description: Multi-agent sprint runner — stamped plan to merged commit via TDD fleet in a git worktree, coverage + AC/DoD gates. Use on "run a team sprint", "kick off a sprint", "/team-sprint <plan>"
disable-model-invocation: true
---
You are running a team sprint: a multi-agent pipeline that takes a markdown plan **already reviewed to adversarial-clean by `team-sprint-planner`** and drives it to a merged commit. Recon, grilling, decomposition and plan review happen planner-side; this skill is the deployment side. Every phase has a gate, every reviewer delivers findings to its spawner, failures route back as fix tasks and the gates re-run. Nothing ships unless every gate is green.

## When to use

Trigger on "run a team sprint", "kick off a sprint", "spawn a team to implement this plan", "/team-sprint <plan>", "execute this plan with an agent fleet", "ship this story with TDD + reviews", "agent team this", "team this PR", "drive this plan to merge", "sprint-execute", or any explicit /team-sprint invocation — whenever a planning artifact is ready to implement and the user wants the full review-test-merge pipeline rather than one coding agent.

## Intake gate — ask before running

Before Phase 0, call **AskUserQuestion** for any run-shape answer not already clear from the invocation or a `team-sprint.config.yaml` — only the open questions — then map the answers onto the config below. "Other" free text beats the mapped default.

- **Scope** — `All in the plan` / `A named subset` / `Single story` → what Phase 0 parses.
- **Rigour** — `Full — 80% coverage + full Phase 7 fleet (Recommended)` / `Fast — 60% coverage, security-only fleet` / `Prototype — coverage gate off` → `coverage_threshold` + the Phase 7 fleet.
- **On green** — `Merge into target branch (Recommended)` / `Open a PR, don't merge` / `Leave the worktree for me to inspect` → Phase 7 merge behaviour + `target_branch`.

## Why this skill exists

Three gates the per-repo TDD skeleton lacked — plan-review provenance before code, a hard coverage gate, `pre-commit-review-fleet` over the whole sprint diff at Phase 7 — inside an isolated worktree, so a sprint cannot poison the main tree. Rationale + review/test economics: `$REF/architecture-decisions.md`.

## Path aliases

- `$SCRIPTS` — `<skill-install-dir>/scripts/`, `$PHASES` — `<skill-install-dir>/phases/`, `$REF` — `<skill-install-dir>/reference/`
- `$ART` — per-sprint artifact dir, from `bash $SCRIPTS/state.sh art-dir <plan_path>` (absolute, under `<repo-root>/.team-sprint/sprints/sprint-<slug>/`; slug from the plan filename, unique per Phase 0's path validator). Never `source lib.sh` from your own shell to get it — a zsh session has no `BASH_SOURCE` and mis-resolves `$SCRIPTS`.

## Inputs

Required: a markdown plan path. Everything else defaults, overridable via `team-sprint.config.yaml` at the repo root or inline arguments.

```yaml
plan_path: <required>  # markdown plan (story, spec, fix plan, …)
target_branch: develop
worktree_name: sprint-<auto-slug-from-plan>
coverage_threshold: 80  # hard gate; 0 disables
coverage_mode: new  # new | whole
scheduling: graph  # graph (Phase 2 DAG, parallel waves) | sequential
worktree_strategy: per-node  # per-node | single
dependency_source: hybrid  # hybrid | declared | inferred
infer_from_touches: true  # `### Touches:` overlap → inferred edges
max_parallel_agents: 4
adversarial_iterations: 3
adversarial_model: inherit
review_fix_iterations: 3
max_wall_clock_minutes: 240
repomix_max_age_minutes: 240
graphify: off  # off | auto (fail-soft) | on (gate) — step 9a
graphify_max_age_minutes: 240
recon: auto  # off | auto (fail-soft) | on (gate) — step 9b
recon_min_files: 20  # below this file count, intents SKIP
recon_providers: codegraph graphify repomix tokensave  # allow-list
recon_log: on  # off | on — JSONL per intent to .recon/
recon_max_lines: 50  # per-answer cap; COUNT= reports the true total
recon_probe_max_age_minutes: 1440
integration_diagram: off  # off | auto | on
subskill_hooks: {phase-0: [], phase-2: [], phase-3: [], phase-4: [], phase-6: [], phase-7: []}
commands: {typecheck, lint, test, coverage, coverage_report_path}
domain_agents: []
crew: auto  # auto → .claude/crews/<lang>.json | off
test_writer_agent: auto  # → crew.tester
engineer_agent: auto  # → crew.developer
teammate_model: inherit
ui_loop: ui-validation-loop
push_on_merge: false
```

The fields sprints actually override. Every remaining field and its default —
recon, graphify, adversarial and review-loop caps, subskill hooks, agent
overrides — is in `$REF/config-reference.md`, with the per-field reasoning in
`team-sprint.config.yaml.example` at the skill root.

Omitted `commands.*` are inferred from the repo (`package.json`, `justfile`, `Makefile`, `pyproject.toml`, `Cargo.toml`); coexisting stacks → ask the user. `commands.coverage: "true"` skips the coverage gate (`gate_status: disabled`). Full per-field docs: `team-sprint.config.yaml.example` at the skill root. The `subskill_hooks` + `TS_*` env contract: `$REF/subskill-hooks.md`.

### Stack-matched agent crew (`crew: auto`)

A React-Native crew is the wrong tool for a Python repo. Phase 0 detects the language, resolves `.claude/crews/<lang>.json` (built by `crew-factory` on a miss) and persists the role map to `state.json.crew`; Phases 3–4 resolve each `subagent_type` at spawn as explicit config name > `state.json.crew.<key>` > static default. Contract: `$REF/crew-resolution.md`; mechanics in `$PHASES/phase-0.md` step 10a.

### Plan format

Markdown, auto-detecting multi-story (one `## Story <id>: <title>` heading each, carrying `### Acceptance Criteria` + `### Definition of Done`) vs single-story. Phases 3–6 iterate once per story, one commit each; Phase 7 runs once. Section shapes, the path-uniqueness contract enforced at Phase 0, and the optional `### Boundaries:` review-scope directive — which must never reach the dependency DAG: `$REF/plan-path-convention.md`.

## Resources / required sub-skills

Required sub-skills — missing any → STOP at Phase 0:

- **`use-repo-code`** — repomix-backed grep; refreshed once per sprint at Phase 0.
- **`sprint-watchdog`** — pre/mid/post-phase audits.
- **`ui-validation-loop`** — Playwright UI verification in Phase 4 (UI-facing diffs only).
- **`pre-commit-review-fleet`** — the Phase 7 fleet: security, performance, codebase-consistency, simplifier.

Optional sub-skills:

- **`adversarial-review`** (required under `scheduling: graph`, unused under `sequential`) — hardens the Phase 2 work-graph; hard-wired, not a config toggle. Plan-level review moved to `team-sprint-planner`.
- **`graphify`** (`graphify != off`) — knowledge-graph intel that **augments**, never replaces, repomix text grep, for Phase 2/4 reviewers. Install, build, verify and the `auto`-vs-`on` split: `$PHASES/phase-0.md` step 9a, via `$SCRIPTS/graphify_ensure.sh`.
- **`recon`** (`recon != off`) — tiers 1–2 of the escalation ladder via `$SCRIPTS/recon.sh`, which names the provider and freshness behind each answer so a provider that cannot parse the language degrades visibly instead of returning an empty "no callers". Intents and probe rules: `$PHASES/phase-0.md` step 9b.

### Required runtime capability — multi-agent (implicit team)

A lead plus teammates on a shared task list (`TaskCreate` / `TaskUpdate` / `TaskList`), one implicit team per session. Deferred transport tools are load-verified before use at Phase 0 step 4a, which STOPs under `scheduling: graph` or falls back to `sequential` — never silently to single-agent execution. Contract: `$REF/sendmessage-protocol.md`.

## Phases — overview

Eight phases in order. Phases 3–6 run once per story; everything else once per sprint. Each doc under `$PHASES/` is authoritative for its own goal, steps and gate — load it on entry and hold the gate it states.

### Phase 0 — Pre-flight (fail loud)

Environment, plan path, resume state; config defaults load here. Any failing check → STOP, surface it, do not advance. → `$PHASES/phase-0.md`

### Phase 1 — Plan-review provenance gate (thin)

Verify the `<!-- adversarial-review: status=clean|user-override ... -->` stamp, then freeze the plan as `$ART/plan-final.md`. No stamp → hard STOP: "run `/team-sprint-planner` first". → `$PHASES/phase-1.md`

### Phase 2 — Worktree + team

Isolated worktree on `sprint/<worktree_name>` off `$TARGET_BRANCH`, repomix refreshed inside it, fleet provisioned, `plan-final.md` parsed into `$ART/stories.json` + the work graph. Graph reviewer contract: `$REF/reviewer-contract.md`. → `$PHASES/phase-2.md`

### Phase 3 — TDD + coverage gate (per story)

RED → GREEN with verified failing-for-the-right-reason tests, then the new-code coverage gate. `$SKILL/workflows/story-executor.workflow.js` owns Phases 3–5 when the `Workflow` tool is present; the lead stays at the gates. → `$PHASES/phase-3.md`

### Phase 4 — AC/DoD review + test validation (per story)

Mechanical validation, then one AC reviewer over *this story's* diff against its AC + DoD (plus `ui-validator` on UI-facing diffs), delivered by final agent return into `$ART/reviews-<story-id>-round-<N>.md`. No security/perf review here — that is Phase 7. Sequencing: `$SKILL/workflows/story-executor.workflow.js`. → `$PHASES/phase-4.md`

### Phase 5 — Fix loop (per story)

CRITICAL + HIGH findings resolved via TDD micro-cycles; re-run coverage and the Phase-4 reviewer(s) only, up to `review_fix_iterations`, then STOP for a user override. `$SKILL/workflows/story-executor.workflow.js`. → `$PHASES/phase-5.md`

### Phase 6 — Story commit (per story)

Commit the story with the `build_commit_msg.sh` message required for grep-based resume. Entry is acceptance that Phase 5 converged; no review here. → `$PHASES/phase-6.md`

### Phase 7 — Sprint-level review fleet, final merge & cleanup

`pre-commit-review-fleet` once over the full sprint diff — the sprint's only security/perf review. HIGH findings and **all simplifier findings (any severity — mandatory-fix, per-finding user waiver only)** feed a fix loop capped at `review_fix_iterations`; then the full regression suite, merge, teardown, sprint report. `$SKILL/workflows/phase-7.workflow.js` owns steps 1–3 when the `Workflow` tool is present. → `$PHASES/phase-7.md`

## Cross-phase invariants

### Per-story test scoping

Per-story/per-node phases (Phase 3 VERIFY, Phase 4 test validation, Phase 5 fix cycles, the Execute integration gate) run **only the current story's tests**, never the whole suite: the test files the test-writer authored in Phase 3 RED plus any pre-existing tests the story's diff modified. Derive paths from the story diff's changed test files (`git diff --name-only`, filtered to test files) or the story's `### Touches:` test globs, and invoke via the runner's path filter (`pytest <paths>`, `jest <paths>`, `bats <files>`, …) — **not** the bare whole-suite `commands.test` string. Coverage stays story-scoped via `coverage_check.sh --story-id`. The **full** suite runs exactly once, at **Phase 7**, as the sprint's regression gate.

### `$ART` — per-sprint artifact dir (uniqueness)

All sprint artifacts live under `$ART` (resolution: see Path aliases); the legacy flat `.team-sprint/state.json` layout is retired. Phase 0's path validator guarantees the slug carries the story id, so `$ART` is unique per plan. Schema + file list: `$REF/state-schema.md`.

### `state.json` — resume contract

`bash $SCRIPTS/state.sh init|read|update|advance-phase` is the only writer; `$SCRIPTS/state.schema.json` is the machine schema. A dead sprint is found by the next invocation scanning `$ART/../*/state.json` for the entry whose `plan_path` matches. For `--abort`, a stuck reviewer/coverage loop, or a stale worktree or pre-v1.0 layout: `$REF/failure-modes-resume.md`.

### Agent communication — two channels

Chosen by **who spawned the sender**: **final agent return** is the default for every direct child in both scheduling modes, no `SendMessage`; **`SendMessage` to `team-lead`** is the exception, only where the recipient is not the sender's direct spawner — the graph-mode node executor's single `done`/`failed`. The **spawner** owns "block, collect, close": block until the child is terminal (`TaskOutput`/`Monitor`), collect, verify claimed source files exist, close the child's task itself. Never end a turn with a live child (it sleeps forever — D1). Phase 4/5 findings persist to `$ART/reviews-<story-id>-round-<N>.md`, the audit record sprint-watchdog verifies at Phase 5 step 1. Full contract: `$REF/sendmessage-protocol.md`.

### Defect signals — the ledger

Defects a sprint surfaces about the toolchain itself (not the code under test) are durable findings, and prose in a transcript loses them. `$REF/signal-ledger.md` is the SQLite schema they persist to — categories, severity, `dedupe_key`, the sweep loop; `$REF/signal-audit-brief.md` briefs the auditing agent that produces them. Emit at Phase 7 alongside the fleet report; never let an agent repair a signal it also verified.

## Guardrails

- **Worktree isolation is absolute.** Never run sprint operations against the main working tree.
- **Quality gates are not optional.** Plan-review provenance, 80% coverage, per-story AC/DoD review, the Phase 7 fleet — all must pass to merge. Override per finding, never skip a gate.
- **Spawners block-collect-close every child.** Never end a turn with a live child.
- **Source-file existence is verified.** Sprint-watchdog enforces between phases.
- **Conventional Commits on merge.** Subject ≤72 chars, type prefix (`feat:`, `fix:`, …), body from `build_commit_msg.sh` (its `Story: <id> — <title>` line is grep-anchored for resume).
- **No force-push, no main-branch writes without explicit user confirmation.**

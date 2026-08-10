---
name: team-sprint
model: opus
description: Multi-agent sprint runner — stamped plan to merged commit via TDD fleet in a git worktree, coverage + AC/DoD gates. Use on "run a team sprint", "kick off a sprint", "/team-sprint <plan>"
disable-model-invocation: true
---
You are running a team sprint: a structured, multi-agent pipeline that takes a markdown plan **already reviewed to adversarial-clean by `team-sprint-planner`** and drives it to a merged commit on the target branch. All pre-deployment work (recon, grilling, decomposition, adversarial plan review) happens planner-side; this skill is the deployment side. Every phase has a quality gate. Every reviewer must deliver structured findings to its spawner, persisted to a review artifact. Failures route back to engineers as fix tasks and the gates re-run. Nothing ships unless every gate is green.

## When to use

Trigger on "run a team sprint", "kick off a sprint", "spawn a team to implement this plan", "/team-sprint <plan>", "execute this plan with an agent fleet", or "ship this story with TDD + reviews". Also fires on "agent team this", "team this PR", "drive this plan to merge", "sprint-execute", or any explicit /team-sprint invocation. Default to triggering whenever a planning artifact (story, spec, ADR, fix plan) is ready for implementation and the user wants the full review-test-merge pipeline rather than a single coding agent.

## Intake gate — ask before running

Before Phase 0, call **AskUserQuestion** for any run-shape answer not already clear from the invocation or a `team-sprint.config.yaml` — ask only the open questions — then map the answers onto the config fields below and proceed.

- **Scope** — Which stories run this sprint? Options: `All in the plan` / `A named subset` / `Single story`. → selects which stories Phase 0 parses.
- **Rigour** — How hard should the gates be? Options: `Full — 80% coverage + full Phase 7 fleet (Recommended)` / `Fast — 60% coverage, security-only fleet` / `Prototype — coverage gate off`. → sets `coverage_threshold` and which Phase 7 reviewers spawn.
- **On green** — What happens when every gate passes? Options: `Merge into target branch (Recommended)` / `Open a PR, don't merge` / `Leave the worktree for me to inspect`. → sets the Phase 7 merge behaviour and `target_branch`.

If the user picks "Other", honour the free text over the mapped default.

## Why this skill exists

Consolidates the per-repo team-sprint skeleton (TDD → AC/DoD review → commit), parameterises stack-specific bits, and adds three gates: plan-review provenance before code (the adversarial review itself runs in `team-sprint-planner`; Phase 1 hard-STOPs an unstamped plan), a hard coverage gate, `pre-commit-review-fleet` over the full sprint diff at Phase 7 — all in an isolated git worktree, so a sprint can never poison the main tree and failed sprints stay inspectable + restartable.

Review economics: per-story review is one AC/DoD reviewer (plus conditional UI validation) with mechanical test validation; security and performance are reviewed once per sprint by the Phase 7 fleet. Test economics match: per-story phases run only the current story's tests, the full suite once at Phase 7 — see **Per-story test scoping** under Cross-phase invariants.

## Path aliases

- `$SCRIPTS` — `<skill-install-dir>/scripts/`
- `$PHASES` — `<skill-install-dir>/phases/`
- `$REF` — `<skill-install-dir>/reference/`
- `$ART` — per-sprint artifact dir, resolved via `bash $SCRIPTS/state.sh art-dir <plan_path>` (absolute, under `<repo-root>/.team-sprint/sprints/sprint-<slug>/`; slug from the plan filename, unique per Phase 0's path validator). Never `source lib.sh` from your own shell to get it — a zsh session has no `BASH_SOURCE` and mis-resolves `$SCRIPTS`.

## Inputs

The skill takes a markdown plan path as its required input. Everything else has a default and can be overridden via a `team-sprint.config.yaml` at the repo root or via inline arguments at invocation.

```yaml
plan_path: <required>                           # path to markdown plan (story, spec, fix plan, etc.)
target_branch: develop                          # branch to merge into at Phase 7
worktree_name: sprint-<auto-slug-from-plan>     # sibling dir; full path ../<repo>-<worktree_name>
coverage_threshold: 80                          # hard gate; sprint blocks until met
coverage_mode: new                              # new (new-code) | whole (whole-repo)
scheduling: graph                               # graph (Phase 2 DAG, parallel waves) | sequential (one story at a time, shared worktree)
worktree_strategy: per-node                     # per-node (graph: worktree+branch per node) | single (sequential shared worktree)
dependency_source: hybrid                        # hybrid (declared `### Depends On:` + inferred `### Touches:` overlap) | declared | inferred
infer_from_touches: true                         # whether `### Touches:` glob overlap contributes inferred edges
max_parallel_agents: 4                           # cap on concurrent node worktrees (schedule.sh `next` honours it)
adversarial_iterations: 3                       # soft cap on Phase 2 graph-review rounds (loop until zero findings)
adversarial_model: inherit                      # model for the Phase 2 graph-review spawn; inherit → session default
review_fix_iterations: 3                        # max review→fix→re-review rounds (Phase 5 per story; Phase 7 fleet)
max_wall_clock_minutes: 240                     # soft budget; sprint-watchdog WARNs, user decides
repomix_max_age_minutes: 240                    # max age of .repomix-output.xml before refresh
graphify: off                                   # off | auto (fail-soft) | on (hard Phase 0 gate) — see Phase 0 step 9a
graphify_max_age_minutes: 240                   # max age of graphify-out/graph.json before Phase 0 rebuilds
recon: auto                                     # off | auto (fail-soft) | on (hard Phase 0 gate) — see Phase 0 step 9b
recon_min_files: 20                             # small-repo guard: structural intents below this file count return SKIP
recon_providers: codegraph graphify repomix tokensave  # space-separated allow-list; the only provider opt-out
recon_log: on                                   # off | on — one JSONL line per intent call to .recon/calls.jsonl
recon_max_lines: 50                             # result-line cap per answer; COUNT= still reports the pre-truncation total
recon_probe_max_age_minutes: 1440               # TTL of the .recon/capabilities.json capability cache
integration_diagram: off                        # off | auto | on — auto-prepend integration-diagram hooks to subskill_hooks.*
subskill_hooks:                                 # per-phase hooks: {skill, command, required?}
  phase-0: []
  phase-2: []
  phase-3: []
  phase-4: []
  phase-6: []
  phase-7: []
commands:
  typecheck: <project-detected if omitted>
  lint: <project-detected if omitted>
  test: <project-detected if omitted>
  coverage: <project-detected if omitted>        # literal "true" SKIPS the gate; coverage_check.sh → gate_status: disabled
  coverage_report_path: <autodetected if omitted># cobertura/lcov path; autodetected when omitted
domain_agents: []
crew: auto                                      # auto → language-matched crew via crew-factory + .claude/crews/<lang>.json; off → static *_agent fields
test_writer_agent: auto                          # auto → crew.tester; explicit agent name overrides
engineer_agent: auto                             # auto → crew.developer; explicit agent name overrides
teammate_model: inherit                          # model for per-node teammate spawns (Phases 3–6); inherit → session default
ui_loop: ui-validation-loop
push_on_merge: false
```

If `commands.*` are omitted, infer from the repo (`package.json`, `justfile`, `Makefile`, `pyproject.toml`, `Cargo.toml`). Multiple coexisting stacks → ask the user.

Every field above is fully documented (type, default, alternatives, when to override) in `team-sprint.config.yaml.example` at the skill root — copy and trim when bootstrapping a project config. The full `subskill_hooks` + `TS_*` env contract — what runs when, fail-soft semantics, preflight probe rules — lives in `$REF/subskill-hooks.md`.

### Stack-matched agent crew (`crew: auto`)

The fleet is stack-specific by construction: a React-Native crew is the wrong tool for a Python repo. `crew: auto` resolves agents from the repo's detected language:

- Phase 0 detects the language and looks for `.claude/crews/<lang>.json` (the crew manifest).
- **Hit** → load it. **Miss** → spawn the `crew-factory` agent: it surveys the stack, builds and `agent-validator`-grades the **senior-developer agent to A first**, seeds every other role (architect, tester, profiler, security, code-reviewer, simplifier, docs-writer, dependency-auditor) from that base, validates each to A, writes the manifest. Cached — re-run only by deleting the manifest or `--refresh`. The factory reuses good existing registry specialists and generates only the gaps.
- Phase 0 persists the role map to `state.json.crew`. Phases 3–4 resolve each `subagent_type` at spawn by precedence: explicit config agent name > `state.json.crew.<key>` > static default. Unset `commands.*` come from the manifest — the lead runs the test/typecheck/lint trio via `$SCRIPTS/run_gate.sh` (tees each gate to `<log-dir>/<gate>.log`, emits pass/fail JSON, exit 1 on failure) and passes the coverage command to `coverage_check.sh` via `TS_COMMANDS_COVERAGE` (gate scripts read config/env, not `state.json`).

`crew: off` uses the static `*_agent` fields verbatim; any non-`auto` `*_agent` value overrides the manifest.

### Plan format

Markdown. Auto-detect multi-story (one `## Story <id>: <title>` heading per story, each carrying `### Acceptance Criteria` + `### Definition of Done`) vs single-story (no `## Story` headings — entire plan = one implicit story keyed by filename). Phases 3–6 iterate once per story (one commit each); Phase 7 runs once at sprint end.

Path-uniqueness contract (enforced at Phase 0): `$REF/plan-path-convention.md`.

**`### Boundaries:` — cross-boundary review scope (optional per story).** Lists the
cross-language, cross-repo, and deployment artifacts a story's **correctness** depends on
even though the story never edits them:

```markdown
### Touches: services/gateway/internal/server/spotconfig_cap.go
### Boundaries: services/lambdas/auth/pre_token.py (produces custom:tier),
                packages/infra-consolidated/lib/config/dev.ts (decides which env runs this),
                ~/Development/surf-seer/src/services/spotConfigApiService.ts (the real caller)
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

## Resources / required sub-skills

Required sub-skills:

- **`use-repo-code`** — repomix-backed grep of the codebase. Refresh once per sprint at Phase 0.
- **`sprint-watchdog`** — pre/mid/post-phase audits.
- **`ui-validation-loop`** — Playwright-driven UI verification in Phase 4 (UI-facing diffs only).
- **`pre-commit-review-fleet`** — sprint-level review fleet (security, performance, codebase-consistency, simplifier) over the full sprint diff at Phase 7.

Missing any → STOP at Phase 0.

Optional sub-skills:

- **`adversarial-review`** (required under `scheduling: graph`, unused under `sequential`) — applied to the work-graph in Phase 2, **always** in graph mode: the graph-hardening review is hard-wired, not a config toggle. Plan-level adversarial review moved to `team-sprint-planner`; Phase 1 just verifies its provenance stamp and freezes `plan-final.md` — the plan is frozen thereafter; Phase 4's AC reviewer checks impl-vs-plan drift directly.
- **`graphify`** (`graphify != off`) — knowledge-graph codebase intel that **augments**, never replaces, `use-repo-code`/repomix: repomix is fast text grep, graphify answers relationship/coupling questions (`graphify query "what calls X"`, `graphify path A B`). Phase 0 installs/verifies via `$SCRIPTS/graphify_ensure.sh` and builds `graphify-out/graph.json` by invoking the `/graphify` skill; Phase 2 keeps the graph fresh in the integration worktree; Phase 2/4 reviewers may query it to confirm coupling claims. Absent under `graphify: auto` → fail-soft; under `graphify: on` → Phase 0 gate.
- **`recon`** (`recon != off`) — tiers 1–2 of the escalation ladder, routed through `$SCRIPTS/recon.sh`: it normalises the structural intents (`callers`, `callees`, `impact`, `docs`) across codegraph/graphify/repomix/tokensave and names the provider and freshness behind every answer, so a provider that cannot parse the language degrades visibly instead of returning an empty "no callers" that reads as safe. Phase 0 step 9b probes provider health with `--probe`; under `recon: auto` a partial or empty provider set is a WARN + `state.json.recon_degraded=true`, under `recon: on` it is a Phase 0 gate, and under `recon: off` callers go straight to the instruments themselves.

### Required runtime capability — multi-agent (implicit team)

This skill is multi-agent by construction: a team lead plus teammates coordinated through a shared task list (`TaskCreate` / `TaskUpdate` / `TaskList`), direct-child **final agent return** as the default result channel, and `SendMessage` for the one cross-boundary case (see "Agent communication — two channels" below). The runtime provides a **single implicit team per session** — nothing to stand up or tear down; teammates are spawned with the `Agent` tool via `subagent_type`. No `TeamCreate` / `TeamDelete` exists, and `team_name` on `Agent` is deprecated and ignored — older docs naming those predate the implicit-team model.

Final agent return needs no tool at all, but the deferred transport tools some hops still require — the graph-mode node executor's single `SendMessage`, a spawner's `TaskOutput`/`Monitor` block-collect — must be **load-verified before use**, or the call fails `Invalid tool parameters` at the moment of delivery. Phase 0 step 4a self-inspects the lead's own tool list for exactly what the chosen scheduling mode will call: required-but-absent STOPs under `scheduling: graph`, or WARNs and falls back to `scheduling: sequential` (which needs no `SendMessage`). The skill never silently degrades to single-agent execution; sequential mode still spawns children and collects them by final return per `$REF/sendmessage-protocol.md`.

## Phases — overview

Eight phases in order. Phases 3–6 run once per story; everything else runs once per sprint. Each phase's doc lives under `$PHASES/`.

### Phase 0 — Pre-flight (fail loud)

**Goal.** Verify environment, plan path, and resume state. Fail loud, surface offending check, do not advance.

**Gate.** All pre-flight checks pass: tooling, git repo, clean tree, target branch, sub-skills, commands, plan file + path validator, watchdog audit, repomix freshness, crew resolution, and — when `graphify != off` — graphify install + build + verify. Config defaults (per `team-sprint.config.yaml.example`) load here.

**Load `$PHASES/phase-0.md` on entry.**

### Phase 1 — Plan-review provenance gate (thin)

**Goal.** Verify the plan was already driven to adversarial-clean by `team-sprint-planner` (its final phase runs the review loop and stamps the plan), then freeze it as `$ART/plan-final.md`. The review loop itself no longer runs in team-sprint.

**Gate.** Plan carries the `<!-- adversarial-review: status=clean|user-override ... -->` provenance stamp. No stamp → hard STOP: "run `/team-sprint-planner` first".

**Load `$PHASES/phase-1.md` on entry.**

### Phase 2 — Worktree + team

**Goal.** Create the isolated git worktree, refresh repomix inside it, provision the agent fleet, parse `plan-final.md` into per-story task structures.

**Gate.** Worktree exists on `sprint/<worktree_name>` based on `$TARGET_BRANCH`; team provisioned; `$ART/stories.json` populated.

JSON-tail contract for the graph reviewer (mandatory under `scheduling: graph`): `$REF/reviewer-contract.md`.

**Load `$PHASES/phase-2.md` on entry.**

### Phase 3 — TDD + coverage gate (per story)

**Goal.** Drive the current story RED → GREEN with verified failing-for-the-right-reason tests; enforce the new-code coverage gate.

**Workflow.** `$SKILL/workflows/story-executor.workflow.js` owns Phases 3–5 sequencing when the `Workflow` tool is present; the lead stays at the gates (record the run, score the gate) — see the phase doc's guard block.

**Gate.** Tests + typecheck + lint all green; `coverage_check.sh` returns `pass: true` or `gate_status: "disabled"`; sprint-watchdog mid-audit clean.

**Load `$PHASES/phase-3.md` on entry.**

### Phase 4 — AC/DoD review + test validation (per story)

**Goal.** Validate the story mechanically (tests/typecheck/lint), then run a single AC reviewer over *this story's* diff against its acceptance criteria + DoD (plus conditional `ui-validator` for UI-facing diffs), delivered by final agent return. No security/perf review here — that is Phase 7's fleet.

**Workflow.** `$SKILL/workflows/story-executor.workflow.js` owns Phases 3–5 sequencing when the `Workflow` tool is present; the lead stays at the gates (record the run, score the gate) — see the phase doc's guard block.

**Gate.** Test validation green; all spawned reviewers delivered findings to their spawner; aggregated reviewer report exists at `$ART/reviews-<story-id>-round-<N>.md`.

**Load `$PHASES/phase-4.md` on entry.**

### Phase 5 — Fix loop (per story)

**Goal.** Resolve CRITICAL + HIGH findings via TDD micro-cycles; re-run coverage and the Phase-4 reviewer(s) only; iterate up to `review_fix_iterations`.

**Workflow.** `$SKILL/workflows/story-executor.workflow.js` owns Phases 3–5 sequencing when the `Workflow` tool is present; the lead stays at the gates (record the run, score the gate) — see the phase doc's guard block.

**Gate.** Phase-4 reviewer(s) re-run clean (zero CRITICAL/HIGH), OR user overrides at the iteration cap.

**Load `$PHASES/phase-5.md` on entry.**

### Phase 6 — Story commit (per story)

**Goal.** Stage and commit the story with the structured message required for grep-based resume. Entry is acceptance that the Phase 5 fix loop converged; no review runs here.

**Gate.** `git commit` succeeds with the message produced by `build_commit_msg.sh`.

**Load `$PHASES/phase-6.md` on entry.**

### Phase 7 — Sprint-level review fleet, final merge & cleanup

**Goal.** Run `pre-commit-review-fleet` once over the full sprint diff (the sprint's only security/perf review). HIGH findings and **all simplifier findings (any severity — mandatory-fix, per-finding user waiver only)** feed a sprint-level fix loop (TDD micro-cycles; `fix:` commits for HIGH, behaviour-preserving `refactor:` for simplifier; capped at `review_fix_iterations`); then sprint pre-flight, merge into target branch, tear down worktree + team, finalise sprint report.

**Workflow.** `$SKILL/workflows/phase-7.workflow.js` owns steps 1–3 when the `Workflow` tool is present; the lead stays at the gates and runs steps 4–10 — see the phase doc's guard block.

**Gate.** Fleet returns zero unresolved HIGH and zero unresolved simplifier findings; final typecheck/lint/test/coverage pass; `git pull --ff-only` clean; `git merge --no-ff` succeeds; `state.json.done == true`.

**Load `$PHASES/phase-7.md` on entry.**

## Cross-phase invariants

### Per-story test scoping

Per-story/per-node phases (Phase 3 VERIFY, Phase 4 test validation, Phase 5 fix cycles, the Execute integration gate) run **only the current story's tests**, never the whole suite: the test files the test-writer authored in Phase 3 RED plus any pre-existing tests the story's diff modified. Derive paths from the story diff's changed test files (`git diff --name-only`, filtered to test files) or the story's `### Touches:` test globs, and invoke via the runner's path filter (`pytest <paths>`, `jest <paths>`, `bats <files>`, …) — **not** the bare whole-suite `commands.test` string. Coverage stays story-scoped via `coverage_check.sh --story-id`.

The **full** `commands.test` suite runs exactly once, at **Phase 7**, as the sprint's regression gate — cross-story regressions a scoped run can't see are caught there, the deliberate trade for a fast per-story loop.

### `$ART` — per-sprint artifact dir (uniqueness)

All sprint artifacts live under `$ART` (resolution: see Path aliases). The legacy flat `.team-sprint/state.json` layout is retired. Phase 0's path validator guarantees the slug carries the story id, so `$ART` is unique per plan. See `$REF/state-schema.md` for the schema and the concrete file list.

### `state.json` — resume contract

`bash $SCRIPTS/state.sh init|read|update|advance-phase` is the only writer. `$SCRIPTS/state.schema.json` is the machine schema. If a sprint dies mid-flight, the next invocation discovers it by scanning `$ART/../*/state.json` and resumes the one whose `plan_path` matches.

### Agent communication — two channels

Results travel one of two channels, chosen by **who spawned the sender**:

- **Final agent return (default)** — every direct child (Phase 3 test-writer + engineer, Phase 4/5 AC reviewer + `ui-validator`, Phase 2 graph reviewer, Phase 7 fleet) delivers to its direct spawner as its final response, in **both** scheduling modes. No `SendMessage`.
- **SendMessage to `team-lead` (exception)** — only when the recipient is not the sender's direct spawner: the graph-mode node executor's single `done`/`failed`. The only mandatory SendMessage in the skill. `team-lead` is canonical but verified at spawn time; a lead registered under another name injects its actual addressable name via the `<LEAD_RECIPIENT>` placeholder — see `$REF/sendmessage-protocol.md` "Recipient resolution".

The **spawner** owns "block, collect, close": after any `Agent` spawn it blocks until the child is terminal (`TaskOutput`/`Monitor`), collects the return, verifies claimed source files exist, and closes the child's task itself — never the child. Never end a turn with a live child (it sleeps forever — D1). Phase 4/5 reviewer findings persist to the story-keyed `$ART/reviews-<story-id>-round-<N>.md`, the audit record sprint-watchdog verifies at Phase 5 step 1. Findings that reach neither the message log nor the artifact break resume. Full contract: `$REF/sendmessage-protocol.md`.

If a sprint dies mid-flight, needs `--abort`, hits a stuck reviewer/coverage loop, or you find a stale/corrupted worktree or pre-v1.0 layout: load `$REF/failure-modes-resume.md`.

### Defect signals — the ledger

Defects a sprint surfaces about the toolchain itself (not about the code under test) are durable
findings, and prose in a transcript loses them. `$REF/signal-ledger.md` defines the SQLite schema
they persist to — categories, severity, the `dedupe_key` that counts recurrence instead of
re-filing it, and the sweep loop that drains the ledger until two consecutive sweeps find nothing
new. `$REF/signal-audit-brief.md` is the brief handed to an auditing agent to produce those
signals; its seven sweeps are derived from real defects, and sweep 6 (answer honesty — does a
tool ever report "found nothing" when something exists) is the one that catches what fixtures
cannot. Emit signals at Phase 7 alongside the fleet report; never let an agent repair a signal it
also verified.

## Guardrails

- **Worktree isolation is absolute.** Never run sprint operations against the main working tree.
- **Quality gates are not optional.** Plan-review provenance (adversarially reviewed by `team-sprint-planner`), 80% coverage, per-story AC/DoD review, sprint-level pre-commit fleet — all must pass to reach merge. User can override on a per-finding basis but not skip a gate wholesale.
- **Two communication channels.** Final agent return is the default; `SendMessage` to `team-lead` is reserved for the node-executor `done`/`failed` only. Spawners block-collect-close every child; never end a turn with a live child.
- **Source-file existence is verified.** Sprint-watchdog enforces between phases.
- **Conventional Commits on merge.** Subject ≤72 chars, type prefix (`feat:`, `fix:`, `refactor:`, etc.), structured body emitted by `build_commit_msg.sh` (the `Story: <id> — <title>` line is grep-anchored for resume).
- **No force-push, no main-branch writes without explicit user confirmation.** Even on a successful sprint.

If you need the ADR index or design rationale behind this skill: load `$REF/architecture-decisions.md`.

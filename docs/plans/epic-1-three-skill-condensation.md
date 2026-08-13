# Epic 1 — Condense CrewForge to three mechanically-driven skills

## Goal

Reduce CrewForge's per-turn context cost from 24 listed skills to 3 (`init`, `plan`,
`execute`) without losing a single capability, and replace prose orchestration with a
shared state-machine driver plus per-phase gate scripts.

## Context and current state

Measured 2026-08-13 on `main` at `ccd8808`:

| Fact | Value |
| --- | --- |
| Skills in `skills/` | 24 |
| Total `SKILL.md` lines | 3,962 |
| Bundled scripts | 60 (`.sh`/`.py`/`.js`) |
| Cross-references between skills | 84 file-level references across 19 skills |
| Skills already `disable-model-invocation: true` | 10 |

**Verified listing mechanic.** `disable-model-invocation: true` removes a skill from the
per-turn available-skills listing entirely. Evidence: the user config at
`~/.claude/skills/` holds 31 skill directories; exactly two (`master-plan`,
`tech-debt-audit`) set the flag, and exactly those two are absent from the session's
available-skills listing while the other 29 appear. This is the mechanism the epic uses
to hide sub-skills.

**Consequence that drives the design.** A hidden skill is also unreachable via the `Skill`
tool. Every current site that says "invoke the `<X>` skill" must instead resolve `<X>` to a
concrete `SKILL.md` path and read it, or inline it into an `Agent` prompt. There are 84
such reference sites. This is why the resolver (Story 1) lands before the hiding
(Story 6).

### Decisions taken (user-ratified, 2026-08-13)

1. **Sub-skills are hidden, not deleted.** All 21 non-entry skills gain
   `disable-model-invocation: true` and stay on disk, reachable by resolver and by slash
   command.
2. **`ac-validate` is removed from the process.** It is not wired into any of the three
   flows. The skill file stays on disk, hidden.
3. **Mechanism is a state machine plus gate scripts.** Each entry skill is a thin
   `SKILL.md` + `phases/*.md` + a shared driver holding `state.json`, a next-step
   resolver, and a pass/fail gate per phase — the shape `team-sprint` already uses. Prose
   survives only where judgment is genuinely required.

### Capability map — nothing is lost

| Entry skill | Absorbs |
| --- | --- |
| `crewforge:init` | context-hygiene, token-slim, skill-validator, skill-rectifier, agent-validator, agent-rectifier, self-improve, claude-config |
| `crewforge:plan` | grill-me, adhd, master_plan, tech-debt-audit, team-sprint-planner, team-feature, adversarial-review, use-repo-code |
| `crewforge:execute` | team-sprint (and its sub-fleet: sprint-watchdog, pre-commit-review-fleet, code-reviewer, adversarial-review, use-repo-code, playwright-cli), drawio, self-improve |
| Not wired (hidden, slash-only) | ac-validate, plugin-forge |

`plugin-forge` and `claude-config` are authoring tools for this repo itself, not steps in
any of the three flows; `claude-config` is loaded by `init` as house rules, `plugin-forge`
stays slash-only. Nothing is deleted.

### Pre-existing defects this epic must not inherit

- **`preflight_subskills.sh` probes only `$HOME/.claude/skills/<name>/SKILL.md`.** Plugin
  skills do not live there, so the probe is wrong for every plugin-installed run. Fixed in
  Story 1 by routing the probe through the resolver.
- **Working tree is dirty.** `skills/ui-design/` (3 files) is deleted but uncommitted.
  Resolve before the sprint starts — either commit the removal or restore it.

---

## Story 1: Sub-skill resolver

`scripts/flow/subskill_resolve.sh` turns a skill name into an absolute `SKILL.md` path,
so a hidden skill stays reachable without the `Skill` tool.

Search order, first hit wins: `$CREWFORGE_ROOT/skills/<name>/SKILL.md` →
`<repo-root>/.claude/skills/<name>/SKILL.md` → `$HOME/.claude/skills/<name>/SKILL.md`.
Name normalisation maps `_` and `-` interchangeably (`master_plan` vs `master-plan` both
resolve).

### Acceptance Criteria

- `bash scripts/flow/subskill_resolve.sh token-slim` prints the absolute path to
  `skills/token-slim/SKILL.md` and exits 0.
- Resolving a name present in two roots returns the `$CREWFORGE_ROOT` copy; a temp
  fixture with the same skill in a fake repo `.claude/skills/` proves precedence.
- `subskill_resolve.sh master-plan` and `subskill_resolve.sh master_plan` both resolve to
  `skills/master_plan/SKILL.md`.
- An unknown name exits 1 with the searched roots on stderr and nothing on stdout.
- `--probe <name>` exits 0/1 with no stdout, for use as a presence check.
- `preflight_subskills.sh` default probe delegates to the resolver; its existing bats
  suite passes unchanged, plus a new case proving a plugin-root-only skill probes present
  (which fails against `main` today).

### Definition of Done

- ACs pass under `bats scripts/tests` on both GNU and BSD `stat`/`sed` paths.
- `bash scripts/validate_all.sh` exits 0.
- No behaviour change to any skill yet — resolver is additive.

### Touches: scripts/flow/subskill_resolve.sh, skills/team-sprint/scripts/preflight_subskills.sh, scripts/tests/

---

## Story 2: Shared flow driver

Generalise the `team-sprint` state machine into `scripts/flow/` so all three entry skills
share one driver instead of three copies.

- `flow_state.sh` — locked read-modify-write over `<repo>/.crewforge/<flow>/state.json`,
  schema-checked. Lifted from `skills/team-sprint/scripts/state.sh`, with `<flow>` as a
  first argument; `flock` with the existing `mkdir` mutex fallback preserved.
- `flow_next.sh <flow>` — prints the next unblocked phase id and its phase-doc path, or
  `STATUS=DONE`. Pure function of `state.json` plus the flow's `phases.json` manifest.
- `flow_gate.sh <flow> <phase>` — runs that phase's declared gate command, records
  `PASS`/`FAIL` plus the gate's stdout into `state.json`, and exits with the gate's code.

Each flow declares its phases in `skills/<flow>/phases.json`:
`{id, title, doc, gate, required}`.

### Acceptance Criteria

- `flow_state.sh init set phase.0.status ok` then `flow_state.sh init get phase.0.status`
  round-trips through `.crewforge/init/state.json`.
- Two concurrent `flow_state.sh` writers produce a valid final `state.json` with both
  writes present (the existing state.sh concurrency bats case, re-pointed).
- `flow_next.sh init` on a fresh state prints the first phase from `phases.json`; after
  every phase is marked `pass`, it prints `STATUS=DONE`.
- A phase whose gate exits non-zero leaves `state.json` recording `FAIL` and the gate
  stdout, and `flow_next.sh` re-offers the same phase rather than advancing.
- An interrupt between `mktemp` and `mv` leaves no orphan `state.json.tmp.*` (the trap
  case already pinned for `state.sh`).
- `team-sprint`'s own `state.sh` is untouched this story — no regression in its suite.

### Definition of Done

- ACs pass under bats.
- `shellcheck` clean on every new script.
- `scripts/validate_all.sh` exits 0.

### Depends-On: Story 1
### Touches: scripts/flow/flow_state.sh, scripts/flow/flow_next.sh, scripts/flow/flow_gate.sh, scripts/tests/

---

## Story 3: `crewforge:init`

New listed skill: repo and config hygiene, driven by `phases.json`. Every phase is a
gate-backed step over scripts that already exist.

| Phase | Work | Gate |
| --- | --- | --- |
| 0 preflight | Locate config roots, load `claude-config` house rules, require clean tree | `git status --porcelain` empty |
| 1 measure | `token-slim/scripts/baseline.py --out .crewforge/init/baseline.json` | baseline.json exists, non-empty |
| 2 hygiene | `context-hygiene` passes 1–4 against the roots; proposals to scratch files | `scripts/retention_gate.sh <orig> <proposed>` per file |
| 3 slim | `token-slim` trim + split mechanic | `token-slim/scripts/check.sh` per skill, then `sweep.py` totals |
| 4 validate | `validate_all.sh` structural, then `skill-validator`/`agent-validator` per component | zero FAIL |
| 5 rectify | `skill-rectifier`/`agent-rectifier` loop per failing component | re-validate to grade A |
| 6 distil | `self-improve` over the learn ledger | `self-improve/scripts/ceiling.sh check` per target |
| 7 report | Re-measure, write `.crewforge/init/report.md` with before/after | report exists, delta recorded |

Sub-skill bodies are loaded via `subskill_resolve.sh`, never the `Skill` tool. Phases 2–6
fan out one agent per target (skill dirs are disjoint).

### Acceptance Criteria

- `phases.json` lists all 8 phases; every `doc` path and every `gate` command resolves on
  disk (a bats case walks the manifest).
- `SKILL.md` body is ≤ 120 lines and its description ≤ 300 normalised chars.
- Running init against a fixture config dir containing one over-long description produces
  a trimmed description passing `check.sh`, and `report.md` records the char delta.
- A phase-2 proposal that drops a `never`/`always` line is rejected by `retention_gate.sh`
  and the flow does not advance.
- Phase 4 against a fixture agent with a known structural defect reports FAIL; after
  phase 5 the same component validates clean.
- Phase 6 with an empty ledger reports "nothing to distil" and passes rather than
  inventing edits.
- `skill-validator` grades the new skill A (0 failures, ≤2 warnings).

### Definition of Done

- ACs pass under bats.
- `validate_all.sh` exits 0.
- Every capability of context-hygiene, token-slim, both validators, both rectifiers and
  self-improve is reachable through a phase — verified by a checklist in the story's
  review, one line per source skill.

### Depends-On: Story 2
### Touches: skills/init/SKILL.md, skills/init/phases.json, skills/init/phases/, scripts/tests/

---

## Story 4: `crewforge:plan`

New listed skill: goal → adversarial-clean, `/team-sprint`-ready plan file. Merges the
interactive front half of `team-feature` with the audit-grounded back half of
`master_plan`.

| Phase | Work | Gate |
| --- | --- | --- |
| 0 intake | Goal required; no goal → STOP and ask | goal recorded in state.json |
| 1 ground | Refresh repomix pack, `use-repo-code`, `recon.sh` tiers 1–2 | pack fresher than `repomix_max_age_minutes` |
| 2 diverge | `adhd` parallel frames over the open design decisions | ≥1 frame per open decision |
| 3 grill | `grill-me` loop — one `AskUserQuestion` at a time, decisions ratified | every open decision has a recorded answer |
| 4 audit | `tech-debt-audit` → `TECH_DEBT_AUDIT.md` | file exists and is current |
| 5 triage | Impact map + disposition table → `docs/plans/GOAL_IMPACT.md` | every intersecting finding has exactly one disposition |
| 6 draft | `team-sprint-planner` writes the plan file | `validate_plan_path.sh` OK, `plan_readback.sh` OK |
| 7 review | `adversarial-review` loop to clean, then stamp | `<!-- adversarial-review: status=clean ... -->` present |
| 8 verify | `master_plan/scripts/check_coverage.sh GOAL_IMPACT.md <plan>` | reports CLEAN |

Phases 2–3 are interactive, so this skill stays inline — no `context: fork`, no
`agent:` frontmatter. A forked subagent has no user to ask.

### Acceptance Criteria

- `phases.json` lists all 9 phases; every `doc` and `gate` resolves (manifest bats case).
- Phase 0 with no goal argument stops with a question and writes no state beyond intake.
- Phase 3 asks questions one at a time via `AskUserQuestion` — asserted by the skill body
  containing the single-question rule and by `skill-validator` behavioural simulation.
- Phase 6 output passes `validate_plan_path.sh` (filename carries a story/epic id) and
  `plan_readback.sh`.
- Phase 7 refuses to stamp while any finding is open; a fixture plan with one unresolved
  finding does not reach phase 8.
- Phase 8 against a fixture where one finding ID is missing from the debt-coverage table
  reports the missing ID and blocks completion.
- `ac-validate` appears nowhere in the flow — grep over `skills/plan/` returns zero hits.
- `skill-validator` grades the new skill A.

### Definition of Done

- ACs pass under bats.
- `validate_all.sh` exits 0.
- Capability checklist covers grill-me, adhd, master_plan, tech-debt-audit,
  team-sprint-planner, team-feature and adversarial-review, one line each.

### Depends-On: Story 2
### Touches: skills/plan/SKILL.md, skills/plan/phases.json, skills/plan/phases/, scripts/tests/

---

## Story 5: `crewforge:execute`

New listed skill: stamped plan → merged commit, plus diagrams and captured learnings.
`team-sprint`'s eight phases are kept as-is behind the driver; two phases are added.

- Phases 0–7 delegate to `skills/team-sprint/phases/phase-<n>.md`, resolved through
  `subskill_resolve.sh`, with `flow_gate.sh` recording each existing gate's verdict.
- Phase 8 — integration diagram via `drawio`, grounded in the merged code, not from
  memory. Replaces the existing `integration_diagram: off|auto|on` config toggle, which
  becomes this phase's `required` flag.
- Phase 9 — `self-improve` over learnings captured during the run, under `ceiling.sh`.

`team-sprint`'s intake `AskUserQuestion` gate (scope / rigour / on-green) moves to
execute's phase 0, so the entry point stays interactive and team-sprint's body becomes
the phase library.

### Acceptance Criteria

- `phases.json` lists 10 phases; each of 0–7 points at the corresponding existing
  `team-sprint/phases/phase-<n>.md`, verified to exist by the manifest bats case.
- The full existing `team-sprint` bats suite passes unchanged (`scripts/tests/run-all.sh`
  and `skills/team-sprint/scripts/tests/run-all.sh`).
- A sprint driven through execute on the repo's own fixture plan reaches Phase 7 with the
  same gate verdicts as driving `team-sprint` directly — verdicts diffed, not eyeballed.
- Phase 1 still hard-STOPs on a plan with no adversarial-review stamp.
- Phase 8 with `required: false` and no diagram tool available records SKIP and advances;
  with `required: true` and no tool it FAILs.
- Phase 9 with an empty ledger passes without edits.
- `skill-validator` grades the new skill A.

### Definition of Done

- ACs pass under bats.
- `validate_all.sh` exits 0.
- No `team-sprint` phase doc is edited in this story — execute wraps, it does not fork.

### Depends-On: Story 2
### Touches: skills/execute/SKILL.md, skills/execute/phases.json, skills/execute/phases/, scripts/tests/

---

## Story 6: Hide the sub-skills and repoint every reference

The switch-over. Only safe once all three entry points exist and pass.

- Add `disable-model-invocation: true` to the 14 sub-skills that lack it. After this,
  exactly `init`, `plan` and `execute` remain listed.
- Rewrite the 84 cross-reference sites from "invoke the `<X>` skill" to a
  `subskill_resolve.sh` load. Highest-fanout first: `use-repo-code` (12),
  `team-sprint` (11), `team-sprint-planner` (9), `pre-commit-review-fleet` (9),
  `sprint-watchdog` (8), `code-reviewer` (7), `adversarial-review` (6).
  (`ui-validation-loop` and its `ui_loop` config field were already removed on `main`
  before this epic started; `ui-validator` remains a crew reviewer role.)

### Acceptance Criteria

- Every `skills/*/SKILL.md` except `init`, `plan`, `execute` has
  `disable-model-invocation: true` — asserted by a bats case counting listed skills.
- Zero remaining sites instruct a model to `Skill`-invoke a hidden skill: a grep over
  `skills/**/*.md` and `agents/*.md` for the hidden names outside a resolver call
  returns nothing.
- `team-sprint` Phase 0 sub-skill preflight passes with all sub-skills hidden (this is
  the regression the resolver exists to prevent).
- Full bats suite green; `validate_all.sh` exits 0.
- A smoke run of each entry skill reaches its first gate without a "skill not found".

### Definition of Done

- ACs pass.
- Working tree clean at story start and end.
- Each hidden skill still opens by slash command — spot-checked on three of them and
  recorded in the story report.

### Depends-On: Story 3, Story 4, Story 5
### Touches: skills/*/SKILL.md, skills/team-sprint/phases/, skills/team-sprint/reference/, agents/

---

## Story 7: Listing-budget gate

Make the condensation permanent — a gate that fails CI if a fourth skill ever becomes
listed or the three descriptions bloat.

`scripts/listing_budget.sh` counts skills without `disable-model-invocation: true` and
sums their normalised description chars.

### Acceptance Criteria

- Exits 0 on the post-Story-6 tree; prints the listed count and total description chars.
- Exits 1 with the offending skill named when a fixture adds a fourth listed skill.
- Exits 1 when total description chars exceed the ceiling recorded in
  `scripts/listing_budget.json` (ceiling set from the measured post-Story-6 value, no
  slack).
- Wired into `scripts/validate_all.sh`, so its failure fails the existing gate.
- Runs in under 2 seconds on this tree.

### Definition of Done

- ACs pass under bats.
- CI invokes `validate_all.sh` and therefore this gate.
- The recorded ceiling is the measured value, with the before number in the commit
  message.

### Depends-On: Story 6
### Touches: scripts/listing_budget.sh, scripts/listing_budget.json, scripts/validate_all.sh, scripts/tests/

---

## Story 8: Documentation and marketplace surface

`README.md` and `CHANGELOG.md` still describe a 24-skill bundle.

### Acceptance Criteria

- `README.md` documents exactly three entry points with their trigger phrases, and a
  table mapping each hidden sub-skill to the entry point that drives it.
- `CHANGELOG.md` records the condensation with the measured before/after listed-skill
  count and description-char total.
- `.claude-plugin/plugin.json` and `marketplace.json` descriptions match the three-skill
  shape; version bumped.
- No README link points at a path that no longer exists — link check is a bats case.

### Definition of Done

- ACs pass.
- `validate_all.sh` exits 0.

### Depends-On: Story 7
### Touches: README.md, CHANGELOG.md, .claude-plugin/plugin.json, .claude-plugin/marketplace.json

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Hiding a sub-skill breaks a `Skill`-tool call site that grep missed | Story 6 AC greps for every hidden name outside a resolver call, and a smoke run of each entry skill must reach its first gate |
| Slash-command reachability of a hidden skill is assumed, not proven | Story 6 DoD spot-checks three hidden skills by slash command before the story closes; if slash access is also lost, the fallback is to keep the highest-value few listed and re-baseline Story 7's ceiling |
| `execute` drifts from `team-sprint` behaviour | Story 5 forbids editing team-sprint phase docs and diffs gate verdicts against a direct run |
| Interactive phases fail in a forked context | `plan` and `execute` stay inline — no `context: fork`, no `agent:` frontmatter |
| Story 6 is a large single-shot migration | Reference sites are repointed highest-fanout first, each batch gated by the full bats suite |

## Out of scope

- Deleting any skill. Everything stays on disk.
- Wiring `ac-validate` into any flow — removed from the process by decision.
- Rewriting `team-sprint`'s internal phase docs. `execute` wraps them.

---

<!-- adversarial-review: status=unreviewed -->
Run `/team-sprint-planner` (or `/adversarial-review`) over this file to reach a `clean`
stamp before `/team-sprint` will accept it — Phase 1 hard-STOPs on an unstamped plan.

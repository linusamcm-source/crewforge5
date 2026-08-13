# Epic 1 — Condense CrewForge to three mechanically-driven skills

<!-- version: v3 -->

## Goal

Reduce CrewForge's per-turn context cost from **14 listed skills to 3** (`init`, `plan`,
`execute`) without losing a single capability, and replace prose orchestration with a
shared state-machine driver plus per-phase gate scripts.

Ten of the 24 skills are already hidden, so the headline is 14 → 3, not 24 → 3. The
honest measure is the one the repo already gates on:
`bash scripts/budget_check.sh --verbose` reports **4,390 chars (~1,098 tok) across 23
always-loaded entries, 102 tok of headroom under a 1,200 budget**. That number, not the
skill count, is what this epic has to move.

## Context and current state

Measured 2026-08-13 on `main` at `1efff83`:

| Fact | Value | How measured |
| --- | --- | --- |
| Skills in `skills/` | 24 | `ls -d skills/*/ \| wc -l` |
| Agents in `agents/` | 7 | `ls agents/*.md` |
| Total `SKILL.md` lines | 3,960 | `wc -l skills/*/SKILL.md` |
| Bundled scripts | 60 (`.sh`/`.py`/`.js`) | `find skills -type f` |
| Skills already `disable-model-invocation: true` | 10 | `grep -l '^disable-model-invocation: *true' skills/*/SKILL.md \| wc -l` |
| Skills **currently listed** (the number this epic cuts) | 14 | same grep, inverted |
| Skills declaring `context: fork` | 5 | `grep -l '^context: *fork' skills/*/SKILL.md` |
| Always-loaded catalogue | 4,390 chars / ~1,098 tok / 23 entries | `bash scripts/budget_check.sh --verbose` |

**Cross-reference load — the Story 6 migration surface.** Counted three ways,
because the unit matters for scoping:

| Unit | Count |
| --- | --- |
| Distinct (referencing file × referenced skill) pairs | 82 |
| Distinct files containing any cross-reference | 38 |
| Raw text occurrences | 259 |

Story 6 rewrites **occurrences**, so 259 is its scope; 38 files is the review
surface. Highest-fanout referenced skills by pair count: `use-repo-code` (12),
`team-sprint` (11), `team-sprint-planner` (9), `pre-commit-review-fleet` (9),
`sprint-watchdog` (8), `code-reviewer` (7), `adversarial-review` (6).

**Verified listing mechanic — and the repo already knew.** `disable-model-invocation: true`
removes a skill from the per-turn available-skills listing entirely. This epic re-confirmed
it independently (the user config at `~/.claude/skills/` holds 31 skill directories;
exactly two, `master-plan` and `tech-debt-audit`, set the flag, and exactly those two are
absent from the session listing while the other 29 appear), but the finding is not new:
`README.md:39-42` records "verified against a live session, the ten hidden skills do not
appear in the catalogue at all", and `scripts/budget_check.sh:16-19` says the same. The
epic builds on established repo knowledge, not a fresh discovery.

**Consequence that drives the design.** A hidden skill is also unreachable via the `Skill`
tool. Every current site that says "invoke the `<X>` skill" must instead resolve `<X>` to a
concrete `SKILL.md` path and load it. This is why the resolver (Story 1) lands before the
hiding (Story 6).

The repo already treats this fallback as normal: `agents/crew-factory.md:34` reads
"**If the skill cannot run from this subagent context** (nested skill-from-subagent is
not guaranteed), fall back to the non-spawning script". The resolver generalises a
pattern the bundle already relies on.

**The fork trap — why "just Read the body" is wrong.** Five skills declare
`context: fork` plus an `agent:` type: `use-repo-code` (`agent: Explore`),
`agent-validator`, `skill-validator`, `tech-debt-audit`, `ac-validate` (all
`agent: general-purpose`). Those declarations exist precisely so the skill's work does
**not** land in the caller's context — `use-repo-code` greps a whole repomix pack, which
is exactly what must stay out of the main window. Reading such a body inline preserves the
instructions and destroys the isolation, inflating main context and inverting this epic's
entire goal. So the resolver is not "read the file": a fork-declaring skill must be
**spawned via the `Agent` tool** with its declared `agent:` type and its body as the
prompt. Only non-fork skills are safe to read inline. Story 1 owns this distinction.

**Agents are a second always-loaded surface — already budgeted.** The 7 files in `agents/`
publish their descriptions into the agent-types listing every turn, and hiding skills does
nothing to them. `budget_check.sh` already charges them (`crew-factory` 217 tok,
`stack-surveyor` 211, `sprint-watchdog` 210, `scrum-master` 207, `boundary-reviewer` 205,
`architect-reviewer` 167, `code-reviewer` 156), alongside the `sprint-init` command
(104) and the root hook's SessionStart line (77). Four agents also reference skills this
epic hides — `crew-factory` (3 sites), `sprint-watchdog` (2), `architect-reviewer` (1),
`code-reviewer` (1) — so they are inside Story 6's migration surface.

**Naming — `init` collides with a built-in.** Claude Code ships a listed `init` skill
("Initialize a new CLAUDE.md file with codebase documentation"). Plugin skills are
namespaced, so this bundle's entry point is `/crewforge:init` and the two coexist, but a
bare `/init` will never reach it. `plan` and `execute` have no built-in counterpart in
the current catalogue. Story 3 and Story 8 must both use the namespaced form in every
trigger phrase and doc line; anything that tells a user to type `/init` is wrong.

### Decisions taken (user-ratified, 2026-08-13)

1. **Sub-skills are hidden, not deleted.** All 24 existing skills gain
   `disable-model-invocation: true` and stay on disk, reachable by resolver and by slash
   command. `init`, `plan` and `execute` are **new** skills, not renames of existing ones,
   so the tree ends at 27 skill directories with 3 of them listed.
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

Agents are unchanged in role: `crew-factory` and `stack-surveyor` stay part of `execute`
(spawned from team-sprint Phase 0 step 10a.2 on a crew-manifest miss, `phases/phase-0.md:94`),
and the reviewer agents stay available to the fleets. Only their skill references move to
the resolver.

`plugin-forge` and `claude-config` are authoring tools for this repo itself, not steps in
any of the three flows; `claude-config` is loaded by `init` as house rules, `plugin-forge`
stays slash-only. Nothing is deleted.

### Pre-existing defects this epic must not inherit

- **`preflight_subskills.sh` probes only `$HOME/.claude/skills/<name>/SKILL.md`.** Plugin
  skills do not live there, so the probe is wrong for every plugin-installed run. Fixed in
  Story 1 by routing the probe through the resolver.
- **The test harness cannot run on this machine as configured.** Every story's DoD says
  "ACs pass under bats". `command -v bats` finds nothing, and
  `skills/team-sprint/scripts/tests/run-all.sh` aborts at step 1 with
  `shellcheck missing on PATH — install with: brew install shellcheck (>=0.9)`. The bats
  gap is soft — `scripts/tests/lib/bats-fallback.sh` preprocesses `.bats` files to run
  under plain `bash` — but the shellcheck gap is hard and stops the harness before any
  test executes. **Precondition on Story 1:** install `shellcheck` (≥0.9) and preferably
  `bats`, and record which mode the suite ran in. A story reporting green under the
  fallback shim is a weaker claim than one green under real bats, and `run-all.sh`'s own
  step 0 says so.
- **`repomix` is absent too.** `command -v repomix` finds nothing and no
  `.repomix-output.xml` exists, so `use-repo-code`'s pack grep and Story 4's phase-1
  freshness gate cannot run as written. `rtk` **is** present. Install repomix as part of
  Story 1's precondition, or Story 4 phase 1 must degrade visibly to live `Grep` rather
  than silently reporting a fresh pack it never built.

---

## Story 1: Sub-skill resolver

`scripts/flow/subskill_resolve.sh` turns a skill name into an absolute `SKILL.md` path,
so a hidden skill stays reachable without the `Skill` tool.

Search order, first hit wins: `$CREWFORGE_ROOT/skills/<name>/SKILL.md` →
`<repo-root>/.claude/skills/<name>/SKILL.md` → `$HOME/.claude/skills/<name>/SKILL.md`.
Name normalisation maps `_` and `-` interchangeably (`master_plan` vs `master-plan` both
resolve).

It also reports **how the caller must load the skill**, because that differs per skill:
a skill declaring `context: fork` must be spawned through the `Agent` tool with its
declared `agent:` type, never read inline — see the fork trap above.

**Precondition:** `shellcheck` ≥0.9 on PATH, since `run-all.sh` aborts at step 1 without
it. `bats` preferred; the fallback shim covers its absence.

### Acceptance Criteria

- `bash scripts/flow/subskill_resolve.sh token-slim` prints the absolute path to
  `skills/token-slim/SKILL.md` and exits 0.
- Resolving a name present in two roots returns the `$CREWFORGE_ROOT` copy; a temp
  fixture with the same skill in a fake repo `.claude/skills/` proves precedence.
- `subskill_resolve.sh master-plan` and `subskill_resolve.sh master_plan` both resolve to
  `skills/master_plan/SKILL.md`.
- An unknown name exits 1 with the searched roots on stderr and nothing on stdout.
- `--probe <name>` exits 0/1 with no stdout, for use as a presence check.
- `--load-mode <name>` prints `MODE=inline` for a skill with no `context: fork`, and
  `MODE=agent AGENT=<type>` for one that has it — verified against all five fork skills
  (`use-repo-code` → `MODE=agent AGENT=Explore`; `agent-validator`, `skill-validator`,
  `tech-debt-audit`, `ac-validate` → `AGENT=general-purpose`) and against three non-fork
  skills.
- `preflight_subskills.sh` default probe delegates to the resolver; its existing bats
  suite passes unchanged, plus a new case proving a plugin-root-only skill probes present
  (which fails against `main` today).

### Definition of Done

- ACs pass under `bats skills/team-sprint/scripts/tests` and the root `scripts/tests/`
  `.bats` files, on both GNU and BSD `stat`/`sed` paths; the run mode (real bats vs
  fallback shim) is recorded in the story report.
- `bash scripts/validate_all.sh` exits 0.
- No behaviour change to any skill yet — resolver is additive.

### Touches: scripts/flow/subskill_resolve.sh, skills/team-sprint/scripts/preflight_subskills.sh, skills/team-sprint/scripts/tests/, scripts/tests/

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
- Two concurrent `flow_state.sh` writers to **distinct keys** produce a valid final
  `state.json` with both writes present — `skills/team-sprint/scripts/tests/state.bats:200`
  ("concurrent updates of distinct keys both survive"), re-pointed. Same-key contention is
  not covered there and is not in scope here; last-writer-wins is the accepted semantics.
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

Invoked as `/crewforge:init` — bare `/init` reaches Claude Code's built-in CLAUDE.md
initializer, so every trigger phrase and doc line uses the namespaced form.

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
| 1 ground | Refresh repomix pack, `use-repo-code` (`Agent`-spawned, `agent: Explore`), `recon.sh` tiers 1–2 | pack fresher than `repomix_max_age_minutes`, or an explicit DEGRADED verdict naming live `Grep` as the provider |
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
- The full existing `team-sprint` suite passes unchanged via
  `bash skills/team-sprint/scripts/tests/run-all.sh` — the only `run-all.sh` in the repo
  (46 cases in `state.bats` alone). The root `scripts/tests/` holds two standalone `.bats`
  files (`retention_gate.bats`, `sprint_init.bats`) and no runner; run those directly.
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

- Add `disable-model-invocation: true` to the 14 of 24 existing skills that lack it. After
  this, exactly `init`, `plan` and `execute` remain listed out of 27 skill directories.
- Rewrite the 259 cross-reference occurrences (across 38 files) from "invoke the `<X>`
  skill" to a `subskill_resolve.sh` load, honouring `--load-mode`: inline read for
  non-fork skills, `Agent` spawn for the five fork skills. Highest-fanout referenced
  skill first: `use-repo-code` (12 file-pairs), `team-sprint` (11),
  `team-sprint-planner` (9), `pre-commit-review-fleet` (9), `sprint-watchdog` (8),
  `code-reviewer` (7), `adversarial-review` (6).
- Repoint the four agent files that reference hidden skills:
  `agents/crew-factory.md` (3 sites — it already documents the script fallback at line 34,
  which becomes the resolver call), `agents/sprint-watchdog.md` (2),
  `agents/architect-reviewer.md` (1), `agents/code-reviewer.md` (1).
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
- Every fork-declaring skill is reached by `Agent` spawn, not inline read: grep proves no
  call site inline-reads `use-repo-code`, `agent-validator`, `skill-validator`,
  `tech-debt-audit` or `ac-validate`.
- A `crew-factory` spawn against a repo with no crew manifest still reaches grade A —
  it invokes `agent-validator`, so it is the sharpest test that agent-side repointing
  worked.
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

## Story 7: Re-baseline the existing budget gate

**This story writes almost no new code.** `scripts/budget_check.sh` already does what a
listing-budget gate would do, and does it better than a from-scratch version would: it
charges skills *and* agents *and* the `sprint-init` command *and* the root hook's
SessionStart line, and it counts the entry **name** as well as the description, because
the catalogue renders `- <name>: <desc>` (`budget_check.sh:11-14` — measuring descriptions
alone understated this bundle by ~116 tokens, "enough to hide a breach"). Building a
second, weaker gate beside it would be the mistake.

So the work is: re-baseline it to the post-condensation reality, add the one check it
lacks, and wire it into the aggregate validator.

- Lower `BUDGET` from 1200 to the measured post-Story-6 value with no slack. Today's
  reading is ~1,098 tok with 102 tok of headroom; the condensation should collapse that.
- Add a **listed-skill-count** assertion — budget_check measures cost but never asserts
  *which* skills are listed, so a fourth entry point that happens to be cheap slips
  through today.
- Wire `budget_check.sh` into `scripts/validate_all.sh`, which currently runs only the
  structural validators and never calls it.

### Acceptance Criteria

- `bash scripts/budget_check.sh --verbose` exits 0 on the post-Story-6 tree and prints
  the new always-loaded total, with `init`, `plan` and `execute` the only non-hidden
  skills in its per-entry table.
- A fixture adding a fourth listed skill exits 1 naming that skill, **even when the
  added description is small enough to stay under the token budget** — this is the new
  assertion, and it must fail against `budget_check.sh` as it stands today.
- `--budget N` still overrides, and the recorded default is the measured post-Story-6
  value.
- `scripts/validate_all.sh` invokes it and fails when it fails; the existing
  "31 components structurally clean" output gains the budget verdict.
- Runs in under 2 seconds on this tree.

### Definition of Done

- ACs pass under bats.
- CI invokes `validate_all.sh` and therefore this gate.
- The commit message carries before/after: `4390 chars / ~1098 tok / 23 entries` →
  measured new value.
- `README.md:31-42`'s budget paragraph is updated in Story 8 to match the new number.

### Depends-On: Story 6
### Touches: scripts/budget_check.sh, scripts/validate_all.sh, scripts/tests/

---

## Story 8: Documentation and marketplace surface

`README.md` is not naive about the bundle — its budget section (`README.md:31-42`) already
documents the ~1,141-token figure, the 1,200 budget, and the ten skills carrying
`disable-model-invocation: true`, naming all ten. So this story **updates measured
numbers and a named list**, not a rewrite of a wrong claim.

### Acceptance Criteria

- `README.md:31-42` carries the post-condensation figures from Story 7 and the new hidden
  list; no stale "ten skills" or "~1,141 tokens" survives — grep proves both strings gone.
- `README.md` documents exactly three entry points with their trigger phrases, written in
  the namespaced form (`/crewforge:init`, not `/init`, which reaches the built-in), and a
  table mapping each hidden sub-skill to the entry point that drives it.
- `CHANGELOG.md` records the condensation with before/after always-loaded totals from
  `budget_check.sh`, not a hand-counted skill number.
- `.claude-plugin/plugin.json` and `marketplace.json` descriptions match the three-skill
  shape; version bumped from 0.1.0.
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
| A fork-declaring skill gets read inline, moving its context cost into the main window | Story 1 ships `--load-mode`; Story 6 ACs grep to prove all five fork skills are `Agent`-spawned |
| Cost moves from the skill listing to the agent listing | `budget_check.sh` already charges agents, the command and the hook line; Story 7 re-baselines it rather than replacing it |
| A user types `/init` and gets the built-in CLAUDE.md initializer | Every trigger phrase and doc line uses `/crewforge:init`; Story 8 AC greps for the bare form |
| Slash-command reachability of a hidden skill is assumed, not proven | Story 6 DoD spot-checks three hidden skills by slash command before the story closes; if slash access is also lost, the fallback is to keep the highest-value few listed and re-baseline Story 7's ceiling |
| `execute` drifts from `team-sprint` behaviour | Story 5 forbids editing team-sprint phase docs and diffs gate verdicts against a direct run |
| Interactive phases fail in a forked context | `plan` and `execute` stay inline — no `context: fork`, no `agent:` frontmatter |
| Story 6 is a large single-shot migration | Reference sites are repointed highest-fanout first, each batch gated by the full bats suite |

## Out of scope

- Deleting any skill. Everything stays on disk.
- Wiring `ac-validate` into any flow — removed from the process by decision.
- Rewriting `team-sprint`'s internal phase docs. `execute` wraps them.

---

## Open questions

None blocking. Two items the executing agent should carry rather than re-derive:

1. **Slash reachability of a hidden skill is assumed, not proven.** No test in this
   session confirmed that `disable-model-invocation: true` leaves the slash command
   working. Story 6's DoD spot-checks three; if it turns out slash access is lost too,
   the fallback is in the Risks table.
2. **`lint_skill.sh` is hardcoded to the team-sprint layout** and will not lint the three
   new skills. Each of Stories 3–5 carries its own manifest bats case instead, which is
   the equivalent coverage; a generalised linter is deliberately out of scope.

---

<!-- adversarial-review: status=clean rounds=3 reviewer=adversarial-review date=2026-08-13
     findings=17 critical=3 high=4 medium=6 low=4 all-resolved
     instruments=live-Read+Grep (no repomix pack, no graphify — both absent on this host) -->

Reviewed to adversarial-clean over 3 rounds. Round-exit decided mechanically by
`round-gate.sh` each round: `continue`, `continue`, `stop-early`.

# team-sprint v2 — "Ferrari" rewrite plan

**Status:** SUPERSEDED 2026-07-22. The plan was implemented 2026-07-05 as a standalone `lattice-sprint` skill (stories LS5–LS14, bypassing §12's in-place migration path); that skill and all lattice/CLV observability wiring were removed from `$HOME/.claude` on 2026-07-22 — the v2 implementation survives only in git history. `team-sprint` continues as the actively developed v1.1 line (graph-mode hardening D1–D10, Jul 2026). Kept as a design record; §§4–11 remain the reference if workflow-based execution is ever ported into team-sprint. Original status: APPROVED 2026-07-02 — all 14 sections reviewed and accepted (§14); revisions ①–③ applied; Q1–Q7 resolved.
**Baseline:** v1.1 streamline (single AC/DoD reviewer in Phase 4, lean Phase 5 fix loop, commit-only Phase 6, sprint-level `pre-commit-review-fleet` at Phase 7)
**Prime directive:** perfect economics — every token spent buys marginal defect-detection probability that no cheaper mechanism provides.
**Lattice addendum (2026-07-02):** lattice (`~/Development/lattice`) is the observability cornerstone of the lifecycle (team-sprint-planner → crew-factory → team-sprint → lattice). Coupling is deliberately **loose** — file protocol (`.lattice/clv.ndjson`) + shared `CLV_SESSION`; lattice observes, never gates. Folded into §12 step 2b and §13 (Q3/Q5 resolved; risks 7–8 added). Lattice-side work: `docs/plans/lattice-integration-epic.md`.

Each section below is self-contained: rationale → design → acceptance criteria. Review one at a time; §14 is the checklist.

---

## 1. Goals & non-goals

### Rationale

v1.1 fixed the roster problem (4–6 reviewers per story → 1). What remains is structural waste:

- **Orchestration tax.** The lead interprets ~29k tokens of prose (`SKILL.md` 18.8KB + `phases/*.md` 60KB + `reference/*.md` 37KB) on every sprint, and node executors re-load `phase-3/4/5/6.md` (~19KB) per teammate. Control flow lives in markdown a model must re-derive each run.
- **Protocol police.** `sendmessage-protocol.md`, `reviewer-contract.md`, `lead_validator.sh`-style JSON-tail checking, and sprint-watchdog delivery audits all exist because prose asks agents to behave. Behaviour requests fail; the skill then pays again to detect the failure.
- **Context re-purchase.** Every reviewer independently greps `.repomix-output.xml` — the same code context bought N times, cache-hostile.
- **Universe-sized fix loops.** Phase 5 re-runs the full reviewer over the full new diff per iteration, even when one finding on one file changed.

### Five principles

1. **Machines police, models think.** Any contract that can be enforced by a JSON Schema or a `test -f` must never be enforced by prose + audit agents.
2. **Never pay twice for the same context.** Build a story's context package once; share it as an identical prompt prefix across all agents touching that story (prompt-cache hits).
3. **Tests are the cheapest reviewer.** Deterministic gates (test/typecheck/lint/`coverage_check.sh`) cost zero tokens and re-run free. LLM review is reserved for what machines cannot see: AC semantics, design drift, security reasoning.
4. **Risk-priced review.** A ~2k-token classifier call decides which specialists a story deserves, instead of a static roster.
5. **Delta-verification.** After a fix, verify *that finding* was fixed (~5k tokens), not the whole diff again.

### Token targets

| Metric | v1.0 | v1.1 | v2 target |
|---|---|---|---|
| Agent spawns / 5-story sprint | 50–140 | ~25–35 | 20–30 (mostly 5–15k-token micro-agents) |
| Context per reviewer | 30–80k, uncached ad-hoc greps | same shape, fewer | shared cached prefix + curated slice |
| Fix iteration | full reviewer re-run | 1 reviewer re-run | per-finding verify (~5k) |
| Orchestration docs interpreted / run | ~29k tokens | ~20k | ~3k |
| Est. total tokens / 5-story sprint | 5–10M | 1.5–3M | **0.5–1.2M** |

### Non-goals (what stays untouched)

- **Bash script layer.** `state.sh`, `schedule.sh`, `coverage_check.sh`, `per_story_diff.sh`, `build_commit_msg.sh`, `parse_stories.sh`, `validate_plan_path.sh`, `detect_commands.sh`, `repomix_refresh.sh` are already the right layer (deterministic, zero-token). They survive.
- **Worktree isolation.** Per-sprint integration worktree + per-node worktrees, absolute.
- **`state.json` resume contract** at `$ART` (`.team-sprint/sprints/sprint-<slug>/`); `state.sh` remains sole writer.
- **Per-story commits** with `build_commit_msg.sh`'s grep-anchored `Story: <id> — <title>` body; Conventional Commits.
- **Phase 0–2 semantics** (pre-flight, adversarial plan review, worktree+parse). Phase 1's chunked adversarial review gets a Workflow port for its fan-out but keeps its gate (`CRITICAL == 0 && HIGH == 0`).
- **No force-push; no main-branch writes without explicit confirmation.**

### Acceptance criteria

- [ ] Principles agreed as the review bar for every subsequent section.
- [ ] Token targets accepted as success metrics (measured via §11 telemetry, not vibes).
- [ ] Stays-list confirmed — anything on it that should actually change gets flagged now.

---

## 2. Architecture overview

### Rationale

Workflow scripts execute deterministic control flow (loops, gates, fan-out, caps) in the runtime — zero model tokens for orchestration, journal-backed resume. But Workflow scripts have **no filesystem or git access by design** (they run in a sandboxed JS context; only `agent()`/`pipeline()`/`parallel()`/`log()`/`budget` are exposed). Git merges, `state.sh` writes, and worktree management need either an agent or the lead. Merges must be *serialized* and *judged* (conflict resolution is judgment) — that is lead work, not fan-out work.

Hence two layers:

```
┌────────────────────────────────────────────────────────────────────┐
│ LEAD (main loop, Bash + judgment)                                  │
│  • Phase 0 preflight scripts        • schedule.sh wave driving     │
│  • git: worktrees, serialized       • state.sh writes,            │
│    integration merges, final merge    telemetry stamps             │
│  • blocked/deadlock verdict judging • user escalation              │
└───────┬────────────────────────────────────────────┬───────────────┘
        │ Workflow(scriptPath, args)                 │ Bash
        ▼                                            ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│ WORKFLOW LAYER (deterministic)│   │ SCRIPT LAYER (deterministic)  │
│  wave-executor.workflow.js    │   │  state.sh / schedule.sh /     │
│   └─ workflow(story-executor) │   │  coverage_check.sh /          │
│  story-executor.workflow.js   │   │  per_story_diff.sh /          │
│   risk → TDD → gates → review │   │  build_commit_msg.sh / ...    │
│   → delta-fix → verdict       │   │  (unchanged from v1)          │
│  fleet.workflow.js            │   └───────────────────────────────┘
│   chunked fleet → delta-fix   │
└───────────────┬───────────────┘
                │ agent({schema, agentType, effort})
                ▼
┌────────────────────────────────────────────────────────────────────┐
│ AGENTS (the only things that touch fs/git inside a workflow)       │
│  test-writer · engineer · gate-runner (micro) · ac-reviewer ·      │
│  risk-classifier (micro) · fixer (micro) · fix-verifier (micro) ·  │
│  fleet reviewers · packager (micro)                                │
│  All returns schema-forced. All work happens in node worktrees.    │
└────────────────────────────────────────────────────────────────────┘
```

Division of labour rule: **if it needs judgment or serialization → lead; if it's fan-out over items → workflow; if it's deterministic → bash script; if it touches files inside a workflow → agent.**

The "agents run bash gates" pattern: a workflow can't run `coverage_check.sh` itself, so a **gate-runner micro-agent** (low effort) runs the resolved `commands.*` + `coverage_check.sh` in the node worktree and returns a `GATE_RESULT` schema. The script gates on the structured result. Cost: ~3–8k tokens per gate run — the price of keeping the gate inside the workflow loop instead of bouncing back to the lead per iteration.

### Workflow inventory

| Script (under `$SCRIPTS/workflows/`) | Invoked by | Purpose |
|---|---|---|
| `plan-review.workflow.js` | lead, Phase 1 | chunked adversarial fan-out + refute verify |
| `wave-executor.workflow.js` | lead, per wave | runs `workflow(story-executor)` per ready node |
| `story-executor.workflow.js` | wave-executor (1-level nesting) | risk → TDD → gates → review → delta-fix |
| `fleet.workflow.js` | lead, sprint gate | chunked fleet → delta-fix → verdict |

### Acceptance criteria

- [ ] Two-layer split accepted (lead keeps git/state/judgment; workflows own fan-out).
- [ ] Gate-runner micro-agent accepted as the mechanical-gate mechanism inside workflows.
- [ ] Workflow inventory (4 scripts) accepted.

---

## 3. SKILL.md v2

### Rationale

Current `SKILL.md` is 18.8KB (~4.7k tokens) loaded on every trigger, plus phase docs loaded on entry. In v2 the pipeline lives in workflow scripts; `SKILL.md` only needs to tell the lead *what to run and when to judge*. Phase docs (`phases/*.md`, ~60KB) die entirely — their procedural content becomes workflow code, their agent instructions become prompt templates (§5).

### Design — proposed skeleton (~2KB body)

```markdown
---
name: team-sprint
description: <trimmed to trigger phrases + one-line what-it-does; ~400 bytes>
---
Multi-agent sprint: plan → adversarial review → TDD fleet in isolated
worktrees → risk-priced review → sprint fleet gate → merge.

## Config
Load `team-sprint.config.yaml` (defaults in team-sprint.config.yaml.example).
Resolve commands via $SCRIPTS/detect_commands.sh if unset.

## Pipeline (lead runbook)
0. Preflight: bash $SCRIPTS/preflight.sh <plan>   # aggregates v1 phase-0 checks
1. Plan gate: Workflow($SCRIPTS/workflows/plan-review.workflow.js,
   args={plan, chunks}) → revise via apply_findings.sh; loop until clean.
2. Worktree+parse: bash $SCRIPTS/setup_sprint.sh <plan>  # worktree, repomix,
   parse_stories.sh, graph build
3. Execute: repeat — schedule.sh next → build context packages (§packager)
   → Workflow(wave-executor, args={nodes}) → per `done` node: serialized
   integration merge + integration gate → schedule.sh integrate/fail.
   Judge blocked/deadlock verdicts; escalate per escalation table.
4. Sprint gate: Workflow(fleet.workflow.js, args={diff_chunks}) →
   fix commits until clean (cap review_fix_iterations) → merge --no-ff.
5. Finalise: sprint report, telemetry stamp, state.sh done=true.

## Contracts
- Schemas: $SCRIPTS/workflows/schemas.json (all agent returns)
- Prompts:  $SCRIPTS/prompts/*.md (interpolated by workflows)
- State:    state.sh sole writer; graph.json state-of-record in execute
- Escalation table: <blocked|deadlock|cap-hit|budget-exhausted → action>
```

Notes:

- The 1.1KB trigger description in current frontmatter sits in **every session's** skill list; v2 trims it to ~400 bytes of trigger phrases.
- `reference/` shrinks: `sendmessage-protocol.md` + `reviewer-contract.md` deleted (§4), `state-schema.md` split into a 2KB contract + appendix, `clv-protocol.md` referenced only from prompt templates (§13), `subskill-hooks.md` survives with a phase→stage mapping (§13), `plan-path-convention.md` survives unchanged.

### Acceptance criteria

- [ ] SKILL.md ≤ 2.5KB body; frontmatter description ≤ 500 bytes.
- [ ] `phases/*.md` deleted; no doc loaded per teammate/agent beyond its own prompt template.
- [ ] `lint_skill.sh` updated to the new layout (checks workflows/, prompts/, schemas.json exist and parse).

---

## 4. Schema contracts

### Rationale

Every protocol failure mode the current skill polices exists because agent output is free text. Workflow's `schema` option forces the agent through a `StructuredOutput` tool call validated at the tool-call layer — the model retries on mismatch, and `agent()` returns a parsed object. The contract becomes *impossible to skip* rather than *audited after the fact*. This composes with `agentType`, so crew-manifest agents (e.g. `python-developer-93a957`) get the StructuredOutput instruction appended automatically.

### Design — `$SCRIPTS/workflows/schemas.json`

One file, keyed by contract name; workflow scripts inline these as literals (scripts can't read fs — generation step embeds them, or they're pasted into each script; decision: **pasted per script**, schemas.json is the source-of-truth for review + tests).

```json
{
  "RISK": {
    "type": "object",
    "required": ["security", "perf", "ui", "rationale"],
    "properties": {
      "security": {"type": "number", "minimum": 0, "maximum": 1},
      "perf":     {"type": "number", "minimum": 0, "maximum": 1},
      "ui":       {"type": "boolean"},
      "rationale":{"type": "string", "maxLength": 400}
    }
  },
  "TEST_WRITER": {
    "type": "object",
    "required": ["test_files", "red_confirmed", "red_reason"],
    "properties": {
      "test_files":   {"type": "array", "items": {"type": "string"}, "minItems": 1},
      "red_confirmed":{"type": "boolean"},
      "red_reason":   {"type": "string"},
      "ac_coverage":  {"type": "array", "items": {"type": "object",
        "required": ["ac_id", "test_file"],
        "properties": {"ac_id": {"type": "string"}, "test_file": {"type": "string"}}}}
    }
  },
  "ENGINEER_COMPLETION": {
    "type": "object",
    "required": ["files_written", "tests_run", "gates"],
    "properties": {
      "files_written": {"type": "array", "minItems": 1, "items": {"type": "object",
        "required": ["path", "purpose"],
        "properties": {"path": {"type": "string"}, "purpose": {"type": "string"}}}},
      "tests_run": {"type": "object",
        "required": ["command", "passed", "failed"],
        "properties": {"command": {"type": "string"},
          "passed": {"type": "integer"}, "failed": {"type": "integer"}}},
      "gates": {"type": "object",
        "required": ["typecheck", "lint"],
        "properties": {"typecheck": {"enum": ["pass", "fail", "skipped"]},
                        "lint":      {"enum": ["pass", "fail", "skipped"]}}},
      "notes": {"type": "string"}
    }
  },
  "GATE_RESULT": {
    "type": "object",
    "required": ["results", "all_pass"],
    "properties": {
      "all_pass": {"type": "boolean"},
      "results": {"type": "array", "items": {"type": "object",
        "required": ["gate", "command", "exit_code", "pass"],
        "properties": {"gate": {"enum": ["test", "typecheck", "lint", "coverage"]},
          "command": {"type": "string"}, "exit_code": {"type": "integer"},
          "pass": {"type": "boolean"},
          "failures": {"type": "array", "items": {"type": "string"}, "maxItems": 20},
          "coverage_pct": {"type": "number"}}}}
    }
  },
  "REVIEW_FINDINGS": {
    "type": "object",
    "required": ["reviewer", "findings", "ac_verdicts", "dod_verdicts"],
    "properties": {
      "reviewer": {"type": "string"},
      "findings": {"type": "array", "items": {"type": "object",
        "required": ["id", "severity", "file", "issue", "fix"],
        "properties": {"id": {"type": "string"},
          "severity": {"enum": ["CRITICAL", "HIGH", "MEDIUM", "LOW"]},
          "file": {"type": "string"}, "line": {"type": "integer"},
          "issue": {"type": "string"}, "fix": {"type": "string"},
          "ac_ref": {"type": "string"}}}},
      "ac_verdicts": {"type": "array", "items": {"type": "object",
        "required": ["ac_id", "met", "evidence"],
        "properties": {"ac_id": {"type": "string"}, "met": {"type": "boolean"},
          "evidence": {"type": "string"}}}},
      "dod_verdicts": {"type": "array", "items": {"type": "object",
        "required": ["item", "met"],
        "properties": {"item": {"type": "string"}, "met": {"type": "boolean"},
          "evidence": {"type": "string"}}}}
    }
  },
  "FIX_RESULT": {
    "type": "object",
    "required": ["finding_id", "action", "files_touched"],
    "properties": {
      "finding_id": {"type": "string"},
      "action": {"enum": ["fixed", "already_correct", "cannot_fix"]},
      "files_touched": {"type": "array", "items": {"type": "string"}},
      "regression_test": {"type": "string"},
      "notes": {"type": "string"}
    }
  },
  "FIX_VERDICT": {
    "type": "object",
    "required": ["finding_id", "fixed"],
    "properties": {
      "finding_id": {"type": "string"},
      "fixed": {"type": "boolean"},
      "evidence": {"type": "string"},
      "new_issue_introduced": {"type": "boolean"}
    }
  },
  "FLEET_REPORT": {
    "type": "object",
    "required": ["dimension", "chunk_id", "findings"],
    "properties": {
      "dimension": {"enum": ["security", "performance", "consistency", "simplifier"]},
      "chunk_id": {"type": "string"},
      "findings": {"$ref": "#/REVIEW_FINDINGS/properties/findings"}
    }
  }
}
```

### Failure modes mechanised away

| Current failure mode | Current policing | v2 mechanism |
|---|---|---|
| Reviewer describes findings inline, never SendMessages | `sendmessage-protocol.md` + watchdog Phase-5 step 1 + re-spawn loop | impossible — `agent()` returns only via schema |
| Malformed reviewer JSON tail | `reviewer-contract.md` + lead-side validation | schema validation retries at tool layer |
| Impl task "complete" with no source file | watchdog source-file existence audit | `ENGINEER_COMPLETION.files_written[]` + script-side `test -f` by gate-runner |
| Undelivered report breaks resume | prose invariant in SKILL.md | journal.jsonl records every agent return |
| "No error thrown ≠ message accepted" ambiguity | CLAUDE.md guidance per agent | N/A — no SendMessage in the data path |
| Reviewer re-flags already-approved earlier-story work | prose instruction in phase-4.md | context package contains only this story's diff (§5) |
| Findings lost between rounds | `$ART/reviews-round-<N>.md` aggregation by lead | workflow accumulates finding objects in variables; lead persists once per story |

What schemas do **not** fix: agents lying inside valid JSON (e.g. `red_confirmed: true` when tests never ran). Backstops: gate-runner independently re-runs suites (trust-but-verify at zero marginal design cost), and `failed > 0` cross-checks.

### Acceptance criteria

- [ ] All 8 schemas reviewed and accepted (field-level).
- [ ] `sendmessage-protocol.md`, `reviewer-contract.md` deleted in v2; SendMessage remains only for lead↔user-facing teammate chatter, never findings transport.
- [ ] Trust-but-verify rule accepted: every agent-claimed gate result is re-run once by gate-runner before the story verdict.

---

## 5. Context packaging

### Rationale

Current phase-4.md step 2 hands each reviewer a worktree path + diff + "grep the repomix pack" preamble. Every reviewer independently spelunks `.repomix-output.xml` — the same context purchased N times, all cache-misses, unbounded (a reviewer can grep itself into a 80k-token context). v2 builds the story's context **once** and shares it as an **identical prompt prefix**: same string prefix + same agentType system prompt → Anthropic prompt-cache hits across the story's agents, and later iterations of the same story.

### Design

**Packager micro-agent** (low effort), spawned once per story by the lead (before the wave dispatch) or as story-executor's first step:

- Inputs: story section from `$ART/plan-final.md`, `per_story_diff.sh` output, worktree repomix pack, `graphify-out/graph.json` when present.
- Task: select the *relevant* files/excerpts (call sites of changed symbols, interfaces implemented, adjacent tests), cap the total.
- Output: writes `$ART/ctx-<story_id>.md` AND returns it as a string (schema: `{package: string, files_selected: [...], truncated: bool}`).

**Package format** (`$ART/ctx-<story_id>.md`):

```markdown
# CTX <story_id> v<n>
## Story          — verbatim `## Story <id>` section: AC + DoD
## Diff           — per_story_diff.sh output (this story only)
## Relevant code  — packager-curated excerpts, each headed `### <path> [reason]`
## Commands       — resolved test/typecheck/lint/coverage strings
## Ground rules   — paths repo-relative to worktree root; cite file:line;
                    do not re-flag prior-story work (not in this package)
```

**Prompt assembly rule (the cache contract):** every agent prompt for the story = `PACKAGE + "\n---\n" + role_instructions`. Package first, role text last — the shared prefix is what the cache keys on. Role instructions live in `$SCRIPTS/prompts/<role>.md` templates; workflows receive them via `args` (lead reads templates, passes strings — scripts can't read fs).

**Size cap:** package ≤ ~25k tokens. Packager sets `truncated: true` beyond that; reviewers may still grep the repomix pack for *specific* lookups (escape hatch, expected to be rare — telemetry §11 counts it).

**Staleness:** any fix that touches files → gate-runner appends a `## Delta v<n+1>` section (new diff hunks only) rather than rebuilding; cache prefix stays intact, delta rides behind it.

### Acceptance criteria

- [ ] Packager agent + package format accepted.
- [ ] Cache contract (package-first prompt assembly) accepted as a hard rule for all story agents.
- [ ] 25k cap + delta-append staleness rule accepted.

---

## 6. Risk classifier

### Rationale

v1.1 dropped security/perf per story wholesale, backstopped by the sprint fleet. That is the right default but a blunt one: a story that rewrites `auth/session.ts` deserves a security reviewer *now*, not at sprint end. A static roster is wrong in both directions; config trigger-lists (Option 3 from the design discussion) rot. A model call is the right classifier — and it is nearly free at haiku pricing.

### Design

First step of story-executor:

```js
const risk = await agent(
  PACKAGE + '\n---\nClassify this story diff. security: probability it touches ' +
  'attack surface (authn/z, input parsing, secrets, SQL/shell/path construction, ' +
  'crypto, deserialization). perf: probability it touches a hot path (loops over ' +
  'unbounded data, N+1 I/O, allocation in render/request path). ui: does it ' +
  'change user-facing markup/styles/screens?',
  {label: 'risk:' + story.id, model: 'haiku', effort: 'low', schema: RISK})
```

Spawn rules:

| Signal | Threshold | Extra reviewer spawned |
|---|---|---|
| `risk.security` | ≥ 0.5 | crew `security` agent, same package prefix |
| `risk.perf` | ≥ 0.6 | crew `profiler` agent, same package prefix |
| `risk.ui` | `true` && `ui_loop` configured | `ui-validator` (unchanged from v1.1) |

Thresholds are config (`risk_thresholds: {security: 0.5, perf: 0.6}`), tunable from telemetry.

**Cost math.** Classifier: package prefix is cached after first agent (~cheap) + ~300 output tokens ≈ 2k marginal tokens. A default-roster security+perf pair at v1.0 shape cost 2 × 30–80k. Even when the classifier fires *both* specialists it only matches old cost; when it fires neither (most stories) it saves ~60–160k per story.

**False negatives.** A security bug in a file the classifier scored 0.2 skips per-story security review. Backstop: `fleet.workflow.js` (§8) runs the security dimension over the **full sprint diff** regardless. Same late-detection trade v1.1 already accepted — now with a cheap early filter recovering most of the loss. Telemetry tracks fleet-found-HIGHs per dimension; a rising security count = lower the threshold.

### Acceptance criteria

- [ ] Classifier prompt + schema + thresholds accepted.
- [ ] Crew `security`/`profiler` agents (built by crew-factory, unused per-story in v1.1) re-employed here — confirms they stay in the manifest.
- [ ] Telemetry-driven threshold tuning accepted over static config guessing.

---

## 7. Delta-verified fix loop

### Rationale

Phase 5 today: fix all findings, then re-run the reviewer over the whole new diff; iterate ≤ `review_fix_iterations`. The re-review costs a full reviewer context per iteration and invites the known "reviewer keeps flagging the same issue" stall (SKILL.md failure mode, 2-identical-rounds STOP). v2 verifies each finding independently in a micro-context: was *this* finding fixed, yes or no.

### Design

```js
// findings: CRITICAL+HIGH from REVIEW_FINDINGS (MEDIUM/LOW → surfaced, non-blocking)
// FILE-GROUPED: same-file findings run sequentially inside one pipeline item
// (two agents must never edit the same file in the same worktree concurrently);
// cross-file groups run in parallel.
const groups = Object.values(findings.reduce((m, f) => {
  const k = f.file || f.id; (m[k] = m[k] || []).push(f); return m }, {}))
const fixResults = (await pipeline(groups, async group => {
  const out = []
  for (const f of group) {                     // sequential within a file
    const fix = await agent(
      PACKAGE + '\n---\nFix exactly this finding in the worktree at ' + node.worktree +
      '. Finding: ' + JSON.stringify(f) + '\nTDD micro-cycle: write a regression ' +
      'test that catches it (RED), fix (GREEN), run the focused test file. Touch ' +
      'nothing unrelated.',
      {label: 'fix:' + f.id, phase: 'Fix', agentType: CREW.developer, schema: FIX_RESULT})
    const verdict = await agent(
      PACKAGE + '\n---\nVerify finding ' + f.id + ' is resolved. Finding: ' +
      JSON.stringify(f) + '\nFixer claims: ' + JSON.stringify(fix) +
      '\nRead the touched files in the worktree; confirm the defect is gone and no ' +
      'adjacent breakage was introduced. Be adversarial: default fixed=false if unsure.',
      {label: 'verify:' + f.id, phase: 'Verify', effort: 'low', schema: FIX_VERDICT})
    out.push({finding: f, fix, verdict})
  }
  return out
})).flat()
const unresolved = fixResults.filter(Boolean)
  .filter(r => !r.verdict.fixed || r.fix.action === 'cannot_fix')
```

Properties:

- **`pipeline()`, not barrier** — file-group A verifies while group B is still being fixed. Wall-clock = slowest single group, not sum of stages.
- **File-grouping is a hard rule** — same-file findings are chained sequentially (fix→verify per finding) inside one pipeline item; only cross-file work is concurrent. Prevents racing edits to one file in one worktree. Applies identically to the fleet fix loop (§8).
- Verifier is a *different* agent from the fixer (independence), low effort, tiny context (~5k tokens: package prefix cached + finding + touched files).
- After the pipeline drains: **one** gate-runner pass (full suite + coverage re-run, mirroring phase-5.md step 4's `coverage_check.sh` re-run) — deterministic regression net for cross-finding interference, zero LLM re-review.
- `unresolved` non-empty → one retry round for those findings only (cap: `review_fix_iterations`, same config field), then story verdict `blocked` → lead → user. `new_issue_introduced: true` verdicts feed back as fresh findings exactly once.
- The full AC-reviewer re-review happens **zero** times per fix iteration. It ran once in the review stage; the fleet (§8) is the final whole-diff net.

### Acceptance criteria

- [x] Per-finding fixer→verifier pipeline replaces whole-diff re-review in the story loop.
- [x] Single post-drain gate-runner pass accepted as the cross-finding regression net.
- [x] `review_fix_iterations` reused as the per-finding retry cap; STOP semantics unchanged.
- [x] File-grouping rule (same-file sequential, cross-file parallel) — added in review, 2026-07-02.

---

## 8. The sprint workflow scripts

### Rationale

This is where phases 3–6 become code. Two scripts shown: the per-story executor (nested) and the sprint-level fleet. `wave-executor` (§9) wraps the first; `plan-review` (§9 note) is a straightforward port of Phase 1's chunk fan-out and not shown.

### `story-executor.workflow.js` (skeleton)

```js
export const meta = {
  name: 'story-executor',
  description: 'Risk-priced TDD + review + delta-fix for one story node',
  phases: [
    { title: 'Classify' }, { title: 'TDD' }, { title: 'Gates' },
    { title: 'Review' }, { title: 'Fix' }, { title: 'Verify' },
  ],
}
// args: { node: {id, worktree, branch}, package, commands,
//         prompts: {testWriter, engineer, gateRunner, acReviewer, fixer, verifier},
//         crew: {developer, tester, code_reviewer, security, profiler},
//         thresholds: {security, perf}, ui_loop, review_fix_iterations }
const { node, package: PKG, commands, prompts, crew, thresholds } = args
const P = s => PKG + '\n---\n' + s          // cache contract: package-first

// -- Classify ------------------------------------------------------------
const risk = await agent(P(prompts.riskClassifier),
  {label: 'risk:' + node.id, phase: 'Classify', model: 'haiku', effort: 'low',
   schema: RISK})

// -- TDD: RED ------------------------------------------------------------
const red = await agent(P(prompts.testWriter.replace('{{WORKTREE}}', node.worktree)),
  {label: 'red:' + node.id, phase: 'TDD', agentType: crew.tester,
   schema: TEST_WRITER})
if (!red || !red.red_confirmed) return { node: node.id, verdict: 'blocked',
  reason: 'RED not confirmed: ' + (red ? red.red_reason : 'agent died') }

// -- TDD: GREEN ----------------------------------------------------------
const green = await agent(P(prompts.engineer.replace('{{WORKTREE}}', node.worktree)),
  {label: 'green:' + node.id, phase: 'TDD', agentType: crew.developer,
   schema: ENGINEER_COMPLETION})
if (!green || green.tests_run.failed > 0) return { node: node.id,
  verdict: 'blocked', reason: 'GREEN failed' }

// -- Mechanical gates (trust-but-verify; agent runs bash, script gates) ---
let gates = await agent(P(prompts.gateRunner), {label: 'gates:' + node.id,
  phase: 'Gates', effort: 'low', schema: GATE_RESULT})
if (!gates || !gates.all_pass) {
  // one bounce back to the engineer with the failure list, then re-gate
  await agent(P(prompts.engineerFixGates + JSON.stringify(gates && gates.results)),
    {label: 'green2:' + node.id, phase: 'TDD', agentType: crew.developer,
     schema: ENGINEER_COMPLETION})
  gates = await agent(P(prompts.gateRunner), {label: 'gates2:' + node.id,
    phase: 'Gates', effort: 'low', schema: GATE_RESULT})
  if (!gates || !gates.all_pass) return { node: node.id, verdict: 'blocked',
    reason: 'gates failing after retry', gates: gates && gates.results }
}

// -- Review fan-out (risk-priced) -----------------------------------------
const reviewers = [() => agent(P(prompts.acReviewer),
  {label: 'ac:' + node.id, phase: 'Review', agentType: crew.code_reviewer,
   schema: REVIEW_FINDINGS})]
if (risk && risk.security >= thresholds.security)
  reviewers.push(() => agent(P(prompts.securityReviewer),
    {label: 'sec:' + node.id, phase: 'Review', agentType: crew.security,
     schema: REVIEW_FINDINGS}))
if (risk && risk.perf >= thresholds.perf)
  reviewers.push(() => agent(P(prompts.perfReviewer),
    {label: 'perf:' + node.id, phase: 'Review', agentType: crew.profiler,
     schema: REVIEW_FINDINGS}))
if (risk && risk.ui && args.ui_loop)
  reviewers.push(() => agent(P(prompts.uiValidator),
    {label: 'ui:' + node.id, phase: 'Review', schema: REVIEW_FINDINGS}))
// barrier justified: fix stage needs the deduped union of ALL reviewers
const reviews = (await parallel(reviewers)).filter(Boolean)
const acFail = reviews.flatMap(r => r.ac_verdicts).filter(v => !v.met)
let findings = reviews.flatMap(r => r.findings)
  .filter(f => f.severity === 'CRITICAL' || f.severity === 'HIGH')
// unmet AC = CRITICAL finding by definition
findings = findings.concat(acFail.map((v, i) => ({id: 'ac-' + i,
  severity: 'CRITICAL', file: '', issue: 'AC not met: ' + v.ac_id + ' — ' +
  v.evidence, fix: 'implement to satisfy AC'})))
const surfaced = reviews.flatMap(r => r.findings)
  .filter(f => f.severity === 'MEDIUM' || f.severity === 'LOW')

// -- Delta-verified fix loop (§7; FILE-GROUPED: same-file sequential) ------
const byFile = fs => Object.values(fs.reduce((m, f) => {
  const k = f.file || f.id; (m[k] = m[k] || []).push(f); return m }, {}))
let round = 0
while (findings.length && round < args.review_fix_iterations) {
  const results = (await pipeline(byFile(findings), async group => {
    const out = []
    for (const f of group) {                 // never 2 editors on 1 file
      const fix = await agent(P(prompts.fixer + JSON.stringify(f)),
        {label: 'fix:' + f.id, phase: 'Fix', agentType: crew.developer,
         schema: FIX_RESULT})
      const v = await agent(P(prompts.verifier + JSON.stringify({f, fix})),
        {label: 'verify:' + f.id, phase: 'Verify', effort: 'low',
         schema: FIX_VERDICT})
      out.push({f, fix, v})
    }
    return out
  })).flat()
  findings = results.filter(Boolean)
    .filter(r => !r.v.fixed || (r.fix && r.fix.action === 'cannot_fix'))
    .map(r => r.f)
  round += 1
  log('fix round ' + round + ': ' + findings.length + ' unresolved')
}
if (findings.length) return { node: node.id, verdict: 'blocked',
  reason: 'unresolved findings after ' + round + ' rounds', findings, surfaced }

// -- Post-drain regression net + coverage (one bounce, like mid-gates) -----
// preserves v1's coverage-iteration spirit at a 1-bounce cap; telemetry
// `gates.bounces` decides whether the cap ever needs raising
let finalGates = await agent(P(prompts.gateRunnerWithCoverage),
  {label: 'final-gates:' + node.id, phase: 'Gates', effort: 'low',
   schema: GATE_RESULT})
if (!finalGates || !finalGates.all_pass) {
  await agent(P(prompts.engineerFixGates + JSON.stringify(finalGates && finalGates.results)),
    {label: 'green3:' + node.id, phase: 'TDD', agentType: crew.developer,
     schema: ENGINEER_COMPLETION})
  finalGates = await agent(P(prompts.gateRunnerWithCoverage),
    {label: 'final-gates2:' + node.id, phase: 'Gates', effort: 'low',
     schema: GATE_RESULT})
  if (!finalGates || !finalGates.all_pass) return { node: node.id,
    verdict: 'blocked', reason: 'post-fix gates/coverage failing after retry',
    gates: finalGates && finalGates.results }
}

return { node: node.id, verdict: 'committed_ready', risk, surfaced,
  files: green.files_written.map(x => x.path) }
```

The **commit itself stays with the lead** — DECIDED 2026-07-02: the lead runs `build_commit_msg.sh` + `git commit` against the node worktree when resolving the node, before `schedule.sh commit`. Commits are serialization points; the lead is already there for the integration merge. No commit micro-agent.

### `fleet.workflow.js` (skeleton)

```js
export const meta = {
  name: 'sprint-fleet',
  description: 'Sprint-level pre-commit fleet over the full sprint diff, chunked',
  phases: [{ title: 'Fleet' }, { title: 'Fix' }, { title: 'Verify' }],
}
// args: { chunks: [{id, diff}], whole_diff?, package, prompts, crew,
//         review_fix_iterations }
const DIMS = ['security', 'performance', 'consistency', 'simplifier']
const { chunks, prompts, crew } = args
const P = s => args.package + '\n---\n' + s
const dimAgent = d => d === 'security' ? crew.security
  : d === 'performance' ? crew.profiler : undefined
// fan out dimension × chunk; barrier justified: dedup across full result set
const jobs = chunks.flatMap(c => DIMS.map(d => () =>
  agent(P(prompts.fleet[d] + '\n## Chunk ' + c.id + '\n' + c.diff),
    {label: d + ':' + c.id, phase: 'Fleet', agentType: dimAgent(d),
     schema: FLEET_REPORT})))
// Q6 (DECIDED): cross-chunk security net — lead supplies whole_diff only when
// the total sprint diff fits (~≤25k tokens); telemetry decides if it stays
if (args.whole_diff) jobs.push(() =>
  agent(P(prompts.fleet.security + '\n## Whole-diff pass\n' + args.whole_diff),
    {label: 'security:whole', phase: 'Fleet', agentType: crew.security,
     schema: FLEET_REPORT}))
const reports = (await parallel(jobs)).filter(Boolean)
const seen = new Set()
let findings = reports.flatMap(r => r.findings)
  .filter(f => f.severity === 'HIGH' || f.severity === 'CRITICAL')
  .filter(f => { const k = f.file + ':' + (f.line || 0) + ':' + f.issue.slice(0, 40)
    if (seen.has(k)) return false; seen.add(k); return true })
// delta-fix pipeline, same shape as story-executor §7 — FILE-GROUPED:
// same-file findings sequential, cross-file groups parallel (§7 hard rule)
const byFile = fs => Object.values(fs.reduce((m, f) => {
  const k = f.file || f.id; (m[k] = m[k] || []).push(f); return m }, {}))
let round = 0
while (findings.length && round < args.review_fix_iterations) {
  const results = (await pipeline(byFile(findings), async group => {
    const out = []
    for (const f of group) {
      const fix = await agent(P(prompts.fixer + JSON.stringify(f)),
        {label: 'fix:' + f.id, phase: 'Fix', agentType: crew.developer,
         schema: FIX_RESULT})
      const v = await agent(P(prompts.verifier + JSON.stringify({f, fix})),
        {label: 'verify:' + f.id, phase: 'Verify', effort: 'low',
         schema: FIX_VERDICT})
      out.push({f, v, fix})
    }
    return out
  })).flat()
  findings = results.filter(Boolean)
    .filter(r => !r.v.fixed).map(r => r.f)
  round += 1
}
return { verdict: findings.length ? 'blocked' : 'clean',
  unresolved: findings,
  surfaced: reports.flatMap(r => r.findings)
    .filter(f => f.severity === 'MEDIUM' || f.severity === 'LOW') }
```

Chunking: lead pre-computes chunks by story-commit boundaries (`git log --grep='^Story: '` anchors, per_story diff slices), each ≤ ~2k diff lines; `chunks` arrive via `args`, plus `whole_diff` when the total fits (Q6). Fleet fixes land as `fix(sprint):` commits by the **lead** between fleet rounds (same commit-ownership decision as above — DECIDED: lead).

Constraint compliance notes (both scripts): meta is a pure literal; no `Date.now`/`Math.random`/argless `new Date` (timestamps stamped by the lead after return); no fs access (packages and prompts arrive via `args`; agents do all file work); `pipeline()` default, barriers only where the next stage needs the full union (review fan-in, fleet dedup); `budget` guards omitted here for brevity — §10 adds them.

### Acceptance criteria

- [x] story-executor flow accepted stage-by-stage (classify → RED → GREEN → gates → review → fix → final gates); final-gates gains a one-bounce coverage retry (review finding ②).
- [x] Unmet-AC-becomes-CRITICAL-finding rule accepted.
- [x] fleet.workflow.js chunk×dimension fan-out + dedup + delta-fix accepted; performance dimension uses `crew.profiler` (review finding ③); whole-diff security net added (Q6).
- [x] Commit ownership DECIDED 2026-07-02: **lead** at node resolution — commits are serialization points and the lead is already there for the integration merge.

---

## 9. Wave scheduling

### Rationale

The execute macro-phase (`phases/phase-execute.md`) already has the right division: `schedule.sh` owns deterministic graph transitions (`frontier/next/status/claim/commit/integrate/fail/reset-orphans/simulate`), `graph.json` is the durable state-of-record, and the lead performs serialized integration merges. v2 keeps all of it — the only change is *what the lead spawns per wave*: instead of prose-driven teammates running Phases 3–6 from markdown, one `Workflow(wave-executor)` per wave.

### Design

Lead loop (unchanged skeleton, new step 3):

1. `schedule.sh status $ART/graph.json` → `running|complete|blocked|deadlock`.
2. `schedule.sh next` → ready node ids (capped by `max_parallel_agents`).
3. For each id: `schedule.sh claim`, branch node worktree off current integration HEAD, copy repomix pack in, run packager (§5). Then **one** `Workflow(scriptPath: wave-executor.workflow.js, args: {nodes: [...], ...})` for the whole batch.
4. wave-executor: `const results = await parallel(args.nodes.map(n => () => workflow({scriptPath: args.storyExecutorPath}, {node: n, ...})))` — **one-level nesting only**: story-executor must never call `workflow()` itself (it doesn't; it only calls `agent()`). Returns per-node verdicts.
5. Lead resolves each verdict serially: `committed_ready` → build_commit_msg.sh + commit in node worktree → `schedule.sh commit <id> <sha>` → `git merge --no-ff` into integration branch → integration gate (bash) → `schedule.sh integrate <id> <merge-sha>` → tear down node worktree. `blocked` → `schedule.sh fail <id> "<reason>"`; engine cascades blocks; rest of frontier unaffected.
6. Loop to 1.

Alternative considered and rejected: skip wave-executor, lead invokes `Workflow(story-executor)` once per node. Rejected because Workflow invocations return via task-notification to the lead's context — N concurrent workflow results churn the lead's context more than one wave-level aggregate. Wave-executor also gives a single `resumeFromRunId` handle per wave.

**Resume.** Two state stores now exist; precedence is explicit:

- `graph.json` remains the **authority** on node lifecycle (pending/in_progress/committed/done/failed), exactly as today (`reset-orphans` on resume, re-attempt integration for `committed` nodes, no Phase 3–6 re-run).
- Workflow's journal (`resumeFromRunId`) is a **cache**, not state: on mid-wave death, the lead may resume the wave run (unchanged prefix of `agent()` calls returns cached results instantly) — but only if `graph.json` still shows those nodes `in_progress`. If `reset-orphans` already bumped them to `pending`, start a fresh wave run and let cached-irrelevant work be re-done. Rule: **graph.json wins every conflict; journals are an optimization.**

### Acceptance criteria

- [ ] `schedule.sh` + `graph.json` retained unchanged as scheduler + state-of-record.
- [ ] One-Workflow-per-wave (not per-node) accepted.
- [ ] Resume precedence rule (graph.json authoritative, workflow journal opportunistic) accepted.

---

## 10. Budget elasticity

### Rationale

Thoroughness is currently a constant (same roster, same iterations, every sprint). Workflow's `budget` global (`budget.total` from a user "+2M"-style directive, `budget.spent()`, `budget.remaining()`) makes it a dial. Perfect economics: marginal spend goes to the highest-marginal-value check, and stops when the budget says stop.

### Design — depth tiers

| Tier | Condition (at story review stage) | What runs |
|---|---|---|
| **Floor** | always | mechanical gates, AC-reviewer, delta-fix loop, sprint fleet (security dimension never elided) |
| **Standard** | `!budget.total \|\| budget.remaining() > 150k` | + risk-priced specialists (§6), ui-validator |
| **Rich** | `budget.total && budget.remaining() > 400k` | + adversarial refute pass on HIGH findings (2 refuters per finding, majority kills false positives before fixers spend on them), + simplifier sweep per story |
| **Starved** | `budget.remaining() < 60k` | stop spawning; return `blocked: budget` verdicts; lead surfaces to user (extend budget / accept floor-only / abort) |

Script wiring (story-executor, inserted at the review stage):

```js
const tier = !budget.total ? 'standard'
  : budget.remaining() > 400000 ? 'rich'
  : budget.remaining() > 150000 ? 'standard'
  : budget.remaining() > 60000  ? 'floor' : 'starved'
if (tier === 'starved') return { node: node.id, verdict: 'blocked',
  reason: 'budget exhausted', spent: budget.spent() }
if (tier === 'rich') {
  // refute pass: kill plausible-but-wrong findings before paying fixers
  const votes = await pipeline(findings, f =>
    parallel([0, 1].map(i => () => agent(P('Refute finding #' + i + ': ' +
      JSON.stringify(f) + ' Default refuted=true if uncertain.'),
      {label: 'refute:' + f.id + ':' + i, phase: 'Verify', effort: 'low',
       schema: FIX_VERDICT}))).then(vs => ({f, refuted:
         vs.filter(Boolean).filter(v => !v.fixed).length >= 2})))
  findings = votes.filter(Boolean).filter(x => !x.refuted).map(x => x.f)
}
```

Notes: the budget pool is shared across the main loop and all workflows, so wave-executor passes no per-story allocation — every story reads the same live pool; ordering effects (early stories spend, late stories starve) are accepted and visible in telemetry. Guard every dynamic loop on `budget.total` (no target → `remaining()` is `Infinity`).

### Acceptance criteria

- [ ] Four tiers + thresholds accepted (numbers tunable via config `budget_tiers`).
- [ ] Security fleet dimension exempt from elision at every tier.
- [ ] Refute-before-fix at rich tier accepted (spend verification tokens to save fixer tokens).

---

## 11. Telemetry

### Rationale

F1 teams don't guess where lap time goes. Every tuning decision in this plan (risk thresholds §6, budget tiers §10, which stage to convert next §12) should come from measured tokens, not intuition. `budget.spent()` gives per-workflow output-token deltas for free; the lead stamps them into state.

### Design — `state.json.telemetry` (written by `state.sh update`, lead-side)

```json
{
  "telemetry": {
    "schema_version": 1,
    "totals": { "tokens": 0, "spawns": 0, "wall_minutes": 0 },
    "stages": {
      "plan_review":  { "tokens": 0, "spawns": 0, "rounds": 0 },
      "packaging":    { "tokens": 0, "spawns": 0 },
      "classify":     { "tokens": 0, "spawns": 0 },
      "tdd":          { "tokens": 0, "spawns": 0 },
      "gates":        { "tokens": 0, "spawns": 0, "bounces": 0 },
      "review":       { "tokens": 0, "spawns": 0,
                        "specialists_fired": {"security": 0, "perf": 0, "ui": 0} },
      "fix":          { "tokens": 0, "spawns": 0, "findings": 0,
                        "unresolved_at_cap": 0 },
      "fleet":        { "tokens": 0, "spawns": 0,
                        "highs_by_dimension": {"security": 0, "performance": 0,
                                               "consistency": 0, "simplifier": 0} }
    },
    "per_story": [
      { "story_id": "", "tokens": 0, "spawns": 0, "risk": {"security": 0,
        "perf": 0, "ui": false}, "fix_rounds": 0, "repomix_escapes": 0 }
    ]
  }
}
```

Mechanics: lead records `budget.spent()` before/after each Workflow call (workflow return values carry per-stage spawn counts; the journal has per-agent granularity if needed). Wall-clock and timestamps stamped by the lead (`date -u`), never inside scripts. `repomix_escapes` counts §5's escape-hatch greps — a rising count means packages are curated too thin.

### The three-sprint tuning loop

After 3 sprints of data:

| Observation | Action |
|---|---|
| `fleet.highs_by_dimension.security` consistently > 2 | lower `risk_thresholds.security` (per-story security firing too rarely) |
| `fleet` highs ≈ 0 across sprints | fleet is over-insured → drop a dimension or chunk coarser |
| `fix.unresolved_at_cap` > 0 recurring | findings too vague → tighten reviewer prompt template, not iterations |
| `gates.bounces` high | engineer prompt missing gate commands → fix prompt, save a bounce per story |
| `tdd.tokens` dominates totals | consider effort-tier drop for test-writer, or smaller packages |
| `repomix_escapes` rising | packager under-curating → raise cap or improve selection prompt |

### Acceptance criteria

- [ ] Telemetry schema accepted; `state.sh` extended with a `telemetry-merge` subcommand (jq deep-merge) so stamps stay atomic.
- [ ] Tuning table adopted as the standing review ritual after each sprint (1 minute of lead time, end of Phase 7-equivalent).
- [ ] Telemetry lands in **v1.1 first** (§12 step 2) so v2 conversion decisions are data-backed.

---

## 12. Migration path

### Rationale

Never build the whole F1 car before you have lap times. Each step is independently shippable, independently revertible, and produces the data that justifies (or kills) the next step.

### Step 1 — v1.1 streamline. **Status: shipped.**

Single AC/DoD reviewer (Phase 4), lean fix loop (Phase 5), commit-only Phase 6, sprint-level fleet (Phase 7), doc hygiene.
**Exit criteria met when:** one real sprint completes on v1.1 with fleet finding ≤ 2 HIGHs. **Rollback:** git revert in the skill repo (baseline commit exists).

### Step 2 — telemetry + observability on v1.1

Two additive tracks, both fail-soft:

**2a — telemetry.** Add §11's `state.json.telemetry` + `state.sh telemetry-merge`; lead stamps rough per-phase token estimates (spawn counts exact; token numbers coarse until Workflow arrives — record spawn×estimated-context as a proxy, flagged `estimated: true`).

**2b — lattice observability** (coupling stays loose: file protocol + shared `CLV_SESSION`; lattice observes, never gates — a missing/broken lattice must never block a sprint). Lattice (`~/Development/lattice`) already implements the collector (tails `<repo>/.lattice/clv.ndjson`), live roster, `authored_by` attribution, and node status colours; its `AGENT_PROTOCOL.md` §9 already specs team-sprint wiring. What team-sprint adds:

- **Direct-append sink.** The CLV injection block instructs agents to append lines directly (`echo '#CLV1 …' >> <repo>/.lattice/clv.ndjson`) instead of relying on an external stdout→sink bridge (which nothing owns today). Collector already handles concurrent appends, partial lines, truncation.
- **`clv` default flips `off` → `auto`** when `.lattice/` exists in the target repo (config can still force either way).
- **Node-id discipline in prompt templates.** Status/test events must carry lattice ids (`type:path:symbol`, e.g. `fn:src/auth/login.rs:authenticate`) against real files — unknown ids are silently dropped by the collector. One mandatory template line + a telemetry counter for dropped-id suspicion.
- **Instrument the Phase 7 fleet with CLV** (reverses the v1.1 note "fleet is not CLV-instrumented" — under the lattice-cornerstone model every reviewer is observable).
- **Role-table sync.** Canonical role→agent-id table lives in lattice `docs/orignal_specs/AGENT_PROTOCOL.md` §3; team-sprint's `clv-protocol.md` and crew-factory's baked-in blocks reference it rather than fork it. (Companion lattice-side work: `docs/plans/lattice-integration-epic.md`.)

**Entry:** step 1 exit. **Exit:** 2–3 sprints of comparable telemetry AND one sprint observed live in lattice (roster shows the fleet, TDD red→green flips visible, `authored_by` edges land on real code nodes).
**Rollback:** both tracks additive; telemetry is an ignorable field, CLV is fail-soft by contract.
**Effort:** small-medium (one script subcommand, injection-block edit, template line, doc pointer fixes).

### Step 3 — convert Phase 4/5 (review + fix loop) to Workflow

Highest ROI, most self-contained: replace phase-4.md/phase-5.md prose with a `review-fix.workflow.js` (the §8 story-executor's Review+Fix+Verify stages only; TDD stays prose). Requires: schemas (§4, review/fix subset), packager (§5), risk classifier (§6). Phase docs 4/5 shrink to "invoke the workflow, judge the verdict".
**Entry:** step 2 exit (baseline telemetry exists for before/after comparison).
**Exit:** 2 sprints where `review+fix` tokens drop ≥ 50% vs step-2 baseline with fleet HIGHs not rising.
**Rollback:** phase-4/5.md prose retained in git; config flag `review_engine: workflow|prose` for one release.
**Effort:** the big one — schemas + prompts + workflow + testing (bats tests for arg-assembly, `simulate`-style dry runs).

### Step 4 — full migration (execute loop + fleet + plan review as workflows)

Port wave-executor (§9), fleet.workflow.js (§8), plan-review.workflow.js; delete phase docs; SKILL.md v2 (§3); budget tiers (§10).
**Entry:** step 3 exit criteria met AND telemetry shows orchestration/doc overhead still material (if step 3 already hits the 0.5–1.2M target, stop — done is done).
**Exit:** one full sprint end-to-end on v2 ≤ 1.2M tokens with gates equivalent-or-better.
**Rollback:** v1.1 branch preserved; `state.json.schema_version` gates which engine resumes a stranded sprint (a v1.1 sprint must be finished by v1.1 — no cross-version resume).
**Effort:** large; only justified by data.

### Acceptance criteria

- [ ] Four-step order accepted; explicit stop-condition at step 4 entry accepted.
- [ ] No cross-version sprint resume accepted as a hard rule.
- [ ] Step 3's `review_engine` config flag accepted as the canary mechanism.

---

## 13. Risks & open questions

### Risks

1. **Improvisation loss.** A prose lead adapts mid-sprint to weirdness (flaky infra, half-configured repos); a script does what it says. Mitigation: every workflow returns `blocked` verdicts with structured reasons — judgment stays with the lead; scripts never dead-end silently. Residual risk: novel situations produce `blocked` storms that a prose lead would have quietly absorbed. Accept + observe in early sprints. Lattice softens the blast: with §12 step 2b wired, stalls and blocked nodes are visible in the live roster as they happen — the user intervenes mid-sprint instead of discovering at the end (observation, not prevention).
2. **Risk-classifier false negatives** (§6). Security bug in an innocently-scored file waits for the fleet. Same trade v1.1 accepted; now with early-filter recovery + telemetry-tuned thresholds + security-dimension-never-elided fleet. Residual: a sprint whose fleet chunking splits a cross-chunk vulnerability. Open question below.
3. **Dual-state drift** (graph.json vs workflow journals). Mitigated by the §9 precedence rule; residual risk is a lead bug resuming a journal against a reset graph — `reset-orphans` bumps `attempts`, so the mismatch is detectable (assert journal-node-set ⊆ in_progress set before resuming).
4. **Schema-gaming.** Valid JSON, false content (`red_confirmed: true`, tests never ran). Mitigation: trust-but-verify gate-runner re-runs (§4). Residual: gate-runner itself lies — but it's a low-effort agent whose only job is command execution; cross-check is `exit_code` plausibility + telemetry `gates.bounces`. CLV adds a second, pid-correlated evidence channel: `test` events in the sink can be cross-checked against claimed gate results (agents could lie there too, but two independent channels raise the bar; lattice's machine-emitted hot-edge tracer would be a third once wired — LAT-4).
5. **Prompt-template drift.** Phase docs die; prompts become the behavioural surface. A vague prompt now fails silently into schema-valid-but-useless returns. Mitigation: prompt templates live under `$SCRIPTS/prompts/` and get bats smoke tests (interpolation produces non-empty, marker-complete strings); telemetry `unresolved_at_cap` flags vague-finding prompts.
6. **Workflow runtime caps.** Concurrency `min(16, cores-2)` per workflow; 1000-agent lifetime cap; 4096-item fan-out cap. A 5-story sprint is nowhere near these; a 40-story mega-sprint could hit wave-level concurrency queuing (fine — queued, not lost). No action.
7. **Work-graph render gap (lattice).** Lattice renders only parsed-source nodes; the sprint work-graph (`graph.json` stories/nodes) has no ingestion path, so the *plan* layer is invisible — only code-level attribution shows. Mitigation: none needed on the team-sprint side; external-graph ingestion is a lattice epic (`docs/plans/lattice-integration-epic.md` LAT-3), never a sprint gate. Residual: users may expect story-level progress in the UI before that lands — set expectation in the sprint report.
8. **Node-id discipline (lattice).** CLV `test`/`status` events with ids not matching lattice's `type:path:symbol` convention are silently dropped — a mis-templated prompt produces a dark sprint with no error. Mitigation: mandatory template line (§12 step 2b) + telemetry counter; lattice-side dropped-event metric proposed in the epic (LAT-6).

### Open questions (need answers before step 3)

| # | Question | Leaning |
|---|---|---|
| Q1 | Commit ownership: micro-agent inside workflow vs lead at node resolution (§8)? | **RESOLVED 2026-07-02: lead** — commits are serialization points; lead is already there for the merge |
| Q2 | **crew-factory compatibility:** crew manifests name agents (e.g. `python-developer-93a957`) — `agentType` resolves from the same registry, and `schema` composes (StructuredOutput appended). But crew agents' prompts contain SendMessage delivery instructions that v2 makes vestigial. Regenerate crews without the protocol boilerplate, or tolerate dead instructions? | **RESOLVED 2026-07-02: tolerate through step 3**; update the crew-factory template once, regenerate at step 4 |
| Q3 | **CLV protocol fate** (`clv` config, `$REF/clv-protocol.md`) | **RESOLVED — core transport.** Lattice is the observability pane of the lifecycle (planner → crew-factory → team-sprint → lattice); CLV is how sprints appear in it. Keep; default `auto` when `.lattice/` present; direct-append sink; docs collapse into the one reference file pointing at lattice's canonical `AGENT_PROTOCOL.md`. See §12 step 2b |
| Q4 | **subskill_hooks fate:** hooks fire at phase boundaries; v2 has stages, not numbered phases. Map `phase-0/2` → lead preflight/setup (unchanged), `phase-3/4` → pre/post `Workflow(wave)` per wave?, `phase-6` → post-commit per node, `phase-7` → pre-merge. Or freeze hooks at sprint-level boundaries only? | **RESOLVED 2026-07-02: sprint-level only** (preflight, post-setup, pre-merge, post-merge); per-story hooks retire |
| Q5 | **sprint-watchdog fate:** delivery audits die (§4); source-file fraud dies (§4); what survives: Phase-0 clean-tree/branch sanity (bash preflight), wall-clock budget warning (lead timer), stale-worktree detection (preflight). Retire the agent, keep three checks as script lines? | **RESOLVED — retire agent**; fold checks into `preflight.sh` + lead timer. Retirement de-risked by lattice: the live roster (idle 5s → inactive, 60s → reclaimed) replaces stuck-agent monitoring in real time |
| Q6 | Fleet chunk boundaries: per-story slices can split cross-story vulnerabilities (e.g. story-2 endpoint calling story-4 helper). Add one whole-diff security pass at coarse granularity when total diff ≤ 25k tokens? | **RESOLVED 2026-07-02: yes when it fits** (wired into fleet.workflow.js `whole_diff` arg, §8); telemetry decides if it stays |
| Q7 | Phase 1 plan-review workflow: port in step 3 alongside review-fix, or step 4? | **RESOLVED 2026-07-02: step 4** — Phase 1 runs once per sprint; low ROI |

### Acceptance criteria

- [x] Risk register accepted (esp. #1 improvisation loss and #4 schema-gaming mitigations).
- [x] Q1–Q7 answered — all resolved 2026-07-02 (Q3/Q5 via lattice addendum; Q1/Q2/Q4/Q6/Q7 ratified in section review).

---

## 14. Per-section review checklist

Review completed 2026-07-02. Findings applied: ① file-grouped fix loops (no concurrent editors on one file/worktree, §7+§8); ② final-gates one-bounce coverage retry (§8); ③ fleet performance dimension uses `crew.profiler` (§8).

| § | Section | Verdict (accept / revise / discuss) |
|---|---|---|
| 1 | Goals & non-goals | ACCEPT |
| 2 | Architecture overview (two-layer, gate-runner) | ACCEPT |
| 3 | SKILL.md v2 (~2KB, phase docs die) | ACCEPT |
| 4 | Schema contracts (8 schemas, protocol deletion) | ACCEPT |
| 5 | Context packaging (packager, cache contract, 25k cap) | ACCEPT |
| 6 | Risk classifier (haiku, thresholds, backstop) | ACCEPT |
| 7 | Delta-verified fix loop (fixer→verifier pipeline) | ACCEPT with revision ① |
| 8 | Workflow scripts (story-executor, fleet) | ACCEPT with revisions ①②③ + Q1/Q6 wired |
| 9 | Wave scheduling (graph.json authority, one-workflow-per-wave) | ACCEPT |
| 10 | Budget elasticity (4 tiers, security never elided) | ACCEPT |
| 11 | Telemetry (schema, 3-sprint tuning loop) | ACCEPT |
| 12 | Migration path (4 steps, stop-condition) | ACCEPT (lattice-amended) |
| 13 | Risks & open questions (Q1–Q7) | ACCEPT — all questions resolved |

# Workflow adoption sprint 1 — story executor, phase-7 fleet, prose demotion

Extends team-sprint's use of the Claude Code `Workflow` tool from two phases (1, 4–5) to the
full per-story execution path and the sprint-level fleet, and demotes the duplicated prose in
the affected phase docs to a fallback contract. Architecture principle (ratified in the
2026-07-29 design discussion): **workflows between gates, lead at the gates** — no
`AskUserQuestion` inside a workflow; caps and failures return outcomes the lead branches on,
following the `cap_reached` + `residuals` pattern already implemented in
`workflows/phase-1.workflow.js`. Out of scope (sprint 2): graph-mode DAG executor,
`schedule.sh` / `$REF/sendmessage-protocol.md` changes, `budget.total` integration.

Grounding: all claims below verified against the live tree this session — `phases/phase-1.md`
lines 5–20 (the Workflow-path guard block pattern), `phases/phase-3.md` (crew-resolution
precedence steps 1–2, provisional `wip(<story-id>)` commit step 4, coverage-iteration cap
step 5), `phases/phase-7.md` (steps 1/1b/2/3 are workflow-shaped; steps 4–10 are lead git/state
work), `workflows/phase-4-5.workflow.js` (existing VERIFY/FINDINGS/FIX/COVERAGE schemas,
`readArgs` string-args guard, MAX_* bounds), `scripts/tests/lib/workflow-harness.mjs` (stubbed
runner: `node workflow-harness.mjs <wf.js> <args-json> [<responses-json>]` → `{ok, result,
calls, logs}`), `scripts/tests/workflow_doc_drift.bats` (marker parity mechanism; the
"every workflow has a paired phase doc" test hard-codes the pairing list at its final test),
`scripts/state.schema.json` (`additionalProperties: true`), and
`skills/team-feature/SKILL.md` Phase 4 (default plan path `docs/plans/<feature-slug>.md`).

## Story WA1: Extend phase-4-5.workflow.js into story-executor.workflow.js (RED→GREEN through coverage)

Rename `workflows/phase-4-5.workflow.js` to `workflows/story-executor.workflow.js` and prepend
the Phase 3 stages, so one `Workflow` call drives a story from RED to coverage-green. New
stages, ahead of the existing Verify/Review/Fix/Coverage:

- **RED** — test-writer agent. The workflow takes resolved agent names as args
  (`testWriterAgent`, `engineerAgent`); the *lead* resolves them before invocation using the
  Phase 2 precedence documented in `phases/phase-3.md` steps 1–2 (explicit config agent >
  `state.json.crew.*` > static default) — the workflow never reads `state.json`.
- **RED-verify** — a separate measurement agent confirms the new tests fail *for the right
  reason* (missing implementation, not import/collection errors), per phase-3.md step 1.
  Bounded by `maxRedAttempts` (default 2): failing wrong → one bounce back to the test-writer,
  then `blocked_red` outcome.
- **GREEN** — engineer agent; schema requires `source_files` (non-empty array), mirroring the
  existing FIX schema's declared-files contract.
- **WIP commit** — an agent runs `git add -A && git commit -m "wip(<story-id>): phase-3 green"`
  in the worktree before any diff consumer runs, exactly as phase-3.md step 4 requires
  (`per_story_diff.sh` and `coverage_check.sh --mode new` read `BASE...HEAD`; without the
  commit both see an empty diff). The coverage-retry path repeats the wip commit before
  re-measuring, per phase-3.md step 5.
- **Coverage loop** — the existing Coverage stage becomes a bounded loop (`maxCoverageIters`,
  default 3 per phase-3.md step 5): `pass: false` → dispatch test-writer+engineer fix pass →
  wip commit → re-run `coverage_check.sh`. Exhaustion → `coverage_cap_reached` outcome with
  the uncovered-files list as residuals.

Existing behaviour is preserved: `readArgs` string-args guard, VERIFY/FINDINGS/FIX/COVERAGE
schemas, MAX_VERIFY/MAX_REVIEW_RESPAWN/MAX_FIX_ROUNDS/MAX_INNER_FIX bounds, and the
`iterations.review_fix` persist-counter step. New outcome vocabulary adds `ready_to_commit`
(everything green — the lead proceeds to Phase 6) alongside the existing
`blocked_verify`/`cap_reached`/`clean` statuses; `clean` is renamed `ready_to_commit` so the
Phase 6 entry condition reads unambiguously. Tag every new step with `// wf:<id>` markers
matching `<!-- wf:<id> -->` markers added to phases/phase-3.md (WA3 rewrites the surrounding
prose; this story only inserts the markers at the steps it implements).

### Depends On: none
### Touches:
- skills/team-sprint/workflows/story-executor.workflow.js
- skills/team-sprint/workflows/phase-4-5.workflow.js
- skills/team-sprint/scripts/tests/workflow_smoke.bats
- skills/team-sprint/scripts/tests/workflow_doc_drift.bats
- skills/team-sprint/phases/phase-3.md

### Acceptance Criteria
- `node --check skills/team-sprint/workflows/story-executor.workflow.js` exits 0, and
  `workflows/phase-4-5.workflow.js` no longer exists (git mv).
- Harness run with no args (`node scripts/tests/lib/workflow-harness.mjs
  workflows/story-executor.workflow.js ''`) returns `ok: false` with an error naming the
  required args, which include `storyId`, `artDir`, `scriptsDir`, `planPath`,
  `testWriterAgent`, `engineerAgent`.
- Harness run with a stringified-JSON args value (the `readArgs` path) behaves identically to
  the object form: both produce the same first agent call label.
- Harness run with responses driving the happy path (RED verified failing-right, GREEN with
  source_files, verify green, review zero gating findings, coverage pass) returns
  `result.status == "ready_to_commit"`, and the ordered `calls` list shows RED before
  RED-verify before GREEN before the wip-commit call before Verify.
- The RED-verify stage's agent call uses a label distinct from RED and its prompt contains the
  phrase "right reason"; when the responses map makes RED-verify report wrong-reason failures
  `maxRedAttempts` times, `result.status == "blocked_red"`.
- The GREEN stage's agent call carries `agentType` equal to the `engineerAgent` arg, and the
  RED stage's carries the `testWriterAgent` arg (asserted via the harness `calls[].agentType`).
- The wip-commit agent prompt contains the literal commit subject `wip(` and runs before the
  first coverage call; when the responses map fails coverage `maxCoverageIters` times,
  `result.status == "coverage_cap_reached"` and the calls list shows a wip-commit call between
  consecutive coverage calls.
- `workflow_doc_drift.bats` passes with the pairing list updated: `story-executor.workflow.js`
  is a registered pairing (phase-3.md and phase-5.md markers both checked against it) and
  `phase-4-5.workflow.js` is removed from the hard-coded case list in the final test.
- All pre-existing `workflow_smoke.bats` assertions that exercised phase-4-5 behaviour pass
  against the renamed file (updated paths only, not weakened assertions).

### Definition of Done
- New bats tests written RED-first via the harness; whole `scripts/tests/` suite green
  (`bash scripts/tests/run-all.sh`).
- `bash scripts/lint_skill.sh` clean.
- No references to `phase-4-5.workflow.js` remain anywhere in the skill
  (`grep -r "phase-4-5.workflow" skills/team-sprint/` returns nothing).

## Story WA2: New phase-7.workflow.js — regression gate, fleet, bounded fix loop

New `workflows/phase-7.workflow.js` covering phases/phase-7.md steps 1, 1b, 2, and 3. The
merge, push, cleanup, report, and state finalisation (steps 4–10) remain lead-side — they
need git authority and the no-merge-without-confirmation guardrail. Shape:

1. **Full-suite regression gate** — one agent runs the resolved full `commands.test` +
   typecheck + lint + coverage from the worktree (phase-7.md step 3 moved first: no point
   reviewing a red tree). Red → `blocked_regression` outcome with the failing evidence.
2. **Fleet fan-out** — four parallel reviewers (security, performance, codebase-consistency,
   simplifier) over `$ART/diff-sprint.patch`, each with a FINDINGS-style schema that also
   requires `artifact_path`: the reviewer writes its own
   `$ART/reviews-sprint-round-<N>-<reviewer>.md` so a lost return stays recoverable
   (phase-7.md step 1b). A null return (agent died/skipped) → exactly one re-spawn; still
   null → `blocked_fleet` outcome naming the missing lane. A reviewer with zero findings still
   returns and still writes its artifact — "delivered, zero findings" and "never delivered"
   stay distinguishable.
3. **Triage + fix loop** — gating set = HIGH findings from any lane **plus every simplifier
   finding regardless of severity** (phase-7.md gate). Fix agents: HIGH → TDD micro-cycle
   (regression test RED → fix GREEN), simplifier → behaviour-preserving refactor with
   tests/typecheck/lint kept green; commit subjects `fix:` / `refactor:` per phase-7.md
   step 2. Then re-run the fleet over the regenerated sprint diff. Loop bounded by
   `reviewFixIterations` (default 3); exhaustion → `cap_reached` with the unresolved findings
   as residuals — per-finding user waivers are the lead's job after return, never asked
   in-workflow.
4. **Return** — `{status: clean|blocked_regression|blocked_fleet|cap_reached, rounds,
   residuals, artifacts}`; on `clean` the lead proceeds to phase-7.md step 4 (merge).

Tag steps with `// wf:` markers paired to new `<!-- wf: -->` markers in phases/phase-7.md
(fleet-completeness, simplifier-mandatory, regression-first, cap-residuals at minimum).

### Depends On: none
### Touches:
- skills/team-sprint/workflows/phase-7.workflow.js
- skills/team-sprint/scripts/tests/workflow_smoke.bats
- skills/team-sprint/scripts/tests/workflow_doc_drift.bats
- skills/team-sprint/phases/phase-7.md

### Acceptance Criteria
- `node --check` exits 0; harness run with no args fails naming required args (`artDir`,
  `scriptsDir`, `planPath`, `targetBranch`, `worktree`); stringified args behave as objects.
- Happy path under the harness (regression green, four fleet lanes each returning zero
  findings with artifact_paths) returns `status == "clean"` and the calls list contains
  exactly one regression-gate call followed by four fleet calls whose labels name the four
  lanes.
- With the responses map returning null for one lane, the calls list shows exactly one
  re-spawn of that lane; null twice → `status == "blocked_fleet"` and the result names the
  lane.
- A MEDIUM simplifier finding (and no HIGH anywhere) still enters the gating set: the calls
  list shows a fix call for it, and its prompt contains "behaviour-preserving".
- With responses that keep one HIGH finding unresolved every round,
  the workflow stops after `reviewFixIterations` rounds with `status == "cap_reached"` and
  the finding in `residuals` — total fleet rounds observable in `calls` equals
  `reviewFixIterations + 1` at most (initial + re-runs).
- A red regression gate short-circuits: `status == "blocked_regression"` and zero fleet calls
  in `calls`.
- `workflow_doc_drift.bats` registers the phase-7.md ↔ phase-7.workflow.js pairing and passes;
  the marker set includes at least `wf:fleet-completeness`, `wf:simplifier-mandatory`, and
  `wf:cap-residuals`.

### Definition of Done
- Bats tests written RED-first via the harness; full `scripts/tests/` suite green.
- `bash scripts/lint_skill.sh` clean.
- phases/phase-7.md steps 4–10 unchanged by this story (prose rewrite is WA3's).

## Story WA3: Demote prose to fallback contract in phase docs 3, 4, 5, 7 (+ align 1)

Rewrite the affected phase docs to the agreed stance: the `.workflow.js` is the source of
truth for *sequencing*; the prose keeps only the **fallback contract** — entry/exit
conditions, gates, bounds, outcome vocabulary, artifacts, and the still-executable minimal
step list for environments where the `Workflow` tool is absent (the guard's fact-check rule
in phase-1.md:5–6 stays verbatim: "a fact to check, not a preference to weigh").

- phases/phase-3.md, phase-4.md, phase-5.md: add the Workflow-path guard block (phase-1.md
  lines 5–20 pattern) pointing at `story-executor.workflow.js` with its full args signature;
  collapse duplicated sequencing prose; keep the wip-commit rationale (D6), crew-resolution
  precedence (now feeding workflow args), per-story test scoping, and watchdog/subskill-hook
  steps, which remain lead-side. The lead-side steps around the workflow call (hooks,
  mid-audit, state advance) are listed explicitly as "lead before/after the call".
- phases/phase-7.md: guard block pointing at `phase-7.workflow.js`; steps 1–3 collapse to the
  contract + markers; steps 4–10 (merge onward) remain full prose — they have no workflow.
- phases/phase-1.md: replace the closing "prose steps below remain the reference
  implementation" sentence (lines 19–20) with the same fallback-contract stance, so the two
  guarded docs don't state two different philosophies.
- SKILL.md phase-3/4/5/7 sections: one line each naming the workflow path and the
  lead-at-the-gates rule.
- Every `<!-- wf: -->` marker inserted by WA1/WA2 survives the rewrite (the drift suite
  enforces this mechanically).

### Depends On: WA1, WA2, WA4
### Touches:
- skills/team-sprint/phases/phase-1.md
- skills/team-sprint/phases/phase-3.md
- skills/team-sprint/phases/phase-4.md
- skills/team-sprint/phases/phase-5.md
- skills/team-sprint/phases/phase-7.md
- skills/team-sprint/SKILL.md

### Acceptance Criteria
- Each of phase-3.md, phase-4.md, phase-5.md, phase-7.md contains a `> **Workflow path.**`
  guard block that names its workflow file and full args, and contains the literal phrase
  "a fact to check, not a preference to weigh".
- `grep -c "reference implementation" phases/*.md` returns 0 — the demoted stance replaces it
  everywhere, including phase-1.md.
- The guard blocks in phase-3/4/5/7 document the lead-side workflow-run recording and journal
  copy from WA4 (contain `workflow_runs.` and `journal`).
- `workflow_doc_drift.bats` fully green after the rewrite (marker parity both directions for
  all three pairings).
- Combined line count of phases/phase-3.md + phase-4.md + phase-5.md + phase-7.md is at least
  25% below the pre-story baseline (509 lines → ≤ 380), measured by `wc -l` — the demotion
  must actually shrink the docs, not re-shuffle them.
- `bash scripts/tests/run-all.sh` green (parse/plan-contract suites unaffected).

### Definition of Done
- `bash scripts/lint_skill.sh` clean.
- No phase doc instructs an agent to `AskUserQuestion` inside a workflow; cap behaviour is
  described as returned outcomes (grep for "AskUserQuestion" in phases/phase-3,4,5,7 returns
  nothing in workflow-path context).

## Story WA4: state.sh workflow-run recording + journal capture

Give the lead a durable record of each phase's `Workflow` run so a same-session retry can use
`resumeFromRunId` and the watchdog can audit against the journal.

- `state.sh update` with dotted keys already works for existing parents
  (`iterations.adversarial=N` per phase-1.workflow.js); **open question to settle test-first:**
  whether a dotted write creates a missing parent object (`workflow_runs.phase-3=wf_x` when
  `workflow_runs` is absent). If it does not, extend `update` to create intermediate objects.
- Add `workflow_runs` to `scripts/state.schema.json` as an object of string values keyed
  `phase-<n>` (schema is `additionalProperties: true`, so this is documentation +
  validation, not a migration), and document it in `reference/state-schema.md`.
- New `state.sh` subcommand `record-workflow <plan_path> <phase> <run_id>` (thin wrapper over
  the dotted update, validating `run_id` against the `wf_[a-z0-9-]{6,}` shape the Workflow
  tool documents) so phase docs can cite one canonical call.
- Journal capture is lead-side instruction text (landed in WA3's guard blocks): after a
  workflow completes, copy its `<transcriptDir>/journal.jsonl` to
  `$ART/journal-phase-<n>.jsonl`. This story ships the contract only in
  `reference/state-schema.md` (artifact list) — no script wraps the copy, since the
  transcript dir is only known to the lead at run time.

### Depends On: none
### Touches:
- skills/team-sprint/scripts/state.sh
- skills/team-sprint/scripts/state.schema.json
- skills/team-sprint/scripts/tests/state.bats
- skills/team-sprint/reference/state-schema.md

### Acceptance Criteria
- `state.sh record-workflow <plan> phase-3 wf_abc123` writes
  `state.json.workflow_runs["phase-3"] == "wf_abc123"` on a state file with no pre-existing
  `workflow_runs` key, and the result passes schema validation.
- A second `record-workflow` for the same phase overwrites (latest run wins); a run id not
  matching `^wf_[a-z0-9-]{6,}$` exits non-zero with a usage message and writes nothing.
- `record-workflow` with a missing state.json exits with the script's documented
  state-missing code, consistent with existing subcommands.
- `state.bats` covers all three behaviours plus the dotted-parent-creation question RED-first.
- `reference/state-schema.md` documents `workflow_runs` semantics and lists
  `$ART/journal-phase-<n>.jsonl` in the artifact inventory.

### Definition of Done
- Full `scripts/tests/` suite green; `shellcheck scripts/state.sh` clean (matching the repo's
  existing shellcheck gate in lint_skill.sh).
- `state.schema.json` change is backward-compatible: `state.sh read` on a pre-existing
  state.json without `workflow_runs` still validates.

## Story WA5: team-feature plan slug + explicit handoff to team-sprint-planner

Close the deferred finding from the 2026-07-28 skill validation: team-feature's Phase 4
default path `docs/plans/<feature-slug>.md` fails team-sprint's
`validate_plan_path.sh` (check 2 requires a digit or `BUG-`/`EPIC-`/`bug-`/`epic-`/`sprint-`
token in the filename, per lines 62–75).

- Phase 4 default filename becomes `docs/plans/<feature-slug>-1.md`, incrementing the numeric
  suffix if the file exists (`-2`, `-3`, …) — the digit satisfies check 2 and the increment
  satisfies check 3's clobber guard for repeat plans of the same feature.
- Phase 4's delivery step gains an explicit handoff offer, after the summary and inside the
  existing "do not implement" stop: if the user wants the plan executed by `/team-sprint`,
  invoke the `team-sprint-planner` skill with the plan file and decision ledger as source
  docs — the planner owns story decomposition and the parse contract; team-feature does not
  emit `## Story` headings itself.
- The ledger filename follows the plan: `<feature-slug>-1-decisions.md`.

### Depends On: none
### Touches:
- skills/team-feature/SKILL.md
- skills/team-sprint/scripts/tests/plan_contract.bats

### Boundaries:
- skills/team-sprint/scripts/validate_plan_path.sh (produces the filename contract this story must satisfy),
- skills/team-sprint-planner/SKILL.md (the handoff consumer; its intake expects a goal plus source docs)

### Acceptance Criteria
- `bash skills/team-sprint/scripts/validate_plan_path.sh docs/plans/example-feature-1.md`
  (run from a clean temp dir) prints `STATUS=OK` — the documented default pattern passes the
  real validator.
- `skills/team-feature/SKILL.md` Phase 4 names the `-<n>` increment rule and no longer
  documents a default filename without an id token (`grep -E '<feature-slug>\.md' SKILL.md`
  returns nothing).
- Phase 4 contains the handoff instruction naming `team-sprint-planner` and both inputs (plan
  + decision ledger), placed before the final stop; the grill-me "do not implement until the
  user confirms" rule survives verbatim.
- A `plan_contract.bats` test pins the cross-skill contract: the default filename pattern
  documented in team-feature's SKILL.md passes `validate_plan_path.sh` (test extracts the
  pattern by grep, instantiates an example, runs the validator).

### Definition of Done
- Full `scripts/tests/` suite green.
- team-feature still passes structural validation:
  `bash skills/skill-validator/scripts/validate_structure.sh skills/team-feature` reports no
  FAIL lines.

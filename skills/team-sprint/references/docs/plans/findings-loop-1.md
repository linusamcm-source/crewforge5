# Findings-loop hardening — fix the team-sprint defects exposed by sprint-recon-harness-1

**Status:** specification, not yet built.
**Source:** the Phase 1 adversarial run of `sprint-recon-harness-1` (2026-07-27). Its plan
(`.team-sprint/sprints/sprint-recon-harness-1/plan-v4.md`) ended the loop carrying 64 embedded
`<!-- FINDING ... -->` markers — 29.6KB of a 58.4KB file — because the skill annotates findings
but never folds them. Every defect below was verified against the live tree this session
(2026-07-28); citations are to files as they exist now.

## Context and problem

The Phase 1 loop is: review → validate → apply findings → next round. Four defects broke it in
practice, and two adjacent defects corrupted state and nearly executed the wrong plan:

1. **The loop cannot converge.** `apply_findings.sh` only inserts HTML-comment markers above the
   quoted evidence (`apply_findings.sh:165-166`); nothing in `phases/phase-1.md` or
   `workflows/phase-1.workflow.js:292-296` ever folds a marker into revised prose. Each round
   re-reviews a plan that is progressively more comment than content, and reviewers start filing
   findings about findings.
2. **The phase doc lies about the scripts.** `phase-1.md:128` claims `apply_findings.sh`
   "rewrites the plan paragraph-by-paragraph". Its pseudocode also inverts both script
   contracts: `phase-1.md:65` calls `lead_validator.sh "$aggregate" "$current_plan"` (actual:
   `<plan_path> [<findings_json>]`, `lead_validator.sh:29`) and `phase-1.md:74` calls
   `apply_findings.sh "$aggregate" "$current_plan" > plan-vN+1` (actual: three positional args
   `<current_plan> <findings_json> <out_plan>`, `apply_findings.sh:37`, and it writes the file
   itself).
3. **The parser silently truncates wrapped bullets.** `parse_stories.sh` keeps only the
   bullet-match line (`ITEM_RE.match` at parse_stories.sh:104-106); 13 of plan-v4's 39
   acceptance criteria came out mid-sentence (verified 2026-07-27, obs 19009; finding BND-X4).
4. **The validator false-rejects grounded findings.** `_quoted_in_plan` is a byte-exact
   substring test (`lead_validator.sh:151-160`). Round 4 rejected 5 findings whose evidence was
   verbatim-present — line-wrap and marker-interrupted prose broke the match (obs 18973/18974).
   Separately, evidence that matches only *inside* an embedded FINDING marker is accepted today,
   grounding findings in text that folding will delete.
5. **State writes resolved to the wrong sprint dir.** `lib.sh` `art_dir()` derives the sprint
   dir from the plan *basename* via `validate_plan_path.sh --slug-only` (lib.sh:82-102), so
   `state.sh update .../sprint-recon-harness-1/plan-v4.md ...` tried to write
   `sprints/sprint-plan-v4/state.json` and failed exit 2 (obs 18980).
6. **No plan-of-record gate.** The sprint config pointed at the original 7-story
   `recon-harness-1.md` while four review rounds ran against the 6-story `plan-v4.md`; nothing
   in Phase 0/1/2 asserts the reviewed plan and the plan-of-record are the same document, so
   Phase 2 would have executed the wrong plan and discarded every finding (obs 18983/18988).
   A user script also overwrote the workflow's `plan-v4.md` in place with no generation guard,
   destroying applied round-3 revisions (obs 18949).

### Decisions (made for this plan; flag disagreement before Phase 2)

- **Markers stay; a fold step is added.** Mechanical prose rewriting from a free-text
  `recommendation` is not implementable in bash. The annotate-markers design is kept as the
  anchor mechanism, and the loop gains an explicit model-driven fold step plus a mechanical
  zero-markers gate. The alternative (apply_findings emits a worklist JSON and never touches the
  plan) was rejected as a larger change to shipped, tested behaviour.
- **Recon-harness content findings are out of scope.** Findings in plan-v4 that direct the
  recon-harness stories themselves (BND-Z1/Z2, BND-06/08/10, R1/R2/R3-C1/C2-\*, H-1..H-5,
  RH6-01..03, etc.) belong to that sprint and are not re-planned here. Also out of scope:
  `lint_skill.sh --skill-dir` parameterisation (RH6-02 resolves it by narrowing that DoD) and
  the `union.md` tracking question (BND-B02 — a `.gitignore` whitelist decision for the user).

## Story FL1: parse_stories.sh joins wrapped bullets and ignores marker lines

Fix the silent AC/DoD truncation. In `parse_body` (parse_stories.sh:95-147), a line that does
not itself match `ITEM_RE`, is not blank, and follows a bullet is a continuation of that bullet:
join it to the current item with a single space. HTML comment lines (`<!-- ... -->`, including
multi-line comments) inside section bodies are skipped entirely — they are neither items, nor
continuations, nor prose for the un-bulleted fallback at parse_stories.sh:107-109.

### Depends On: none
### Touches:
- skills/team-sprint/scripts/parse_stories.sh
- skills/team-sprint/scripts/tests/parse_stories.bats

### Boundaries:
- `skills/team-sprint/scripts/chunk_stories.sh`, `build_graph.sh`, `lead_validator.sh` (consume the stories.json shape — field names and story ordering must not change)
- `.team-sprint/sprints/sprint-recon-harness-1/plan-v4.md` (the real-world worst case: wrapped bullets AND embedded markers; use excerpts as fixtures, do not reference the live file from tests)

### Acceptance Criteria
- A two-line AC bullet ("- returns exactly one\n  STATUS line.") parses as the single item "returns exactly one STATUS line." with no truncation.
- A `<!-- FINDING ... -->` line between a bullet's first line and its continuation neither appears in any parsed item nor breaks the join — the item text is identical to the marker-free parse.
- A comment-only line inside an un-bulleted AC section does not appear in the joined prose item.
- A blank line or a new bullet/heading terminates continuation joining (the following bullet parses as its own item).
- All pre-existing `parse_stories.bats` cases pass unchanged.

### Definition of Done
- [ ] `shellcheck scripts/parse_stories.sh` clean.
- [ ] `parse_stories.bats` green under `bash scripts/tests/run-all.sh`, including new cases for: wrapped bullet, marker-interrupted bullet, marker in prose-mode section, and the terminator rule.
- [ ] Header comment (parse_stories.sh:1-27) documents the continuation-join and comment-skip rules.

## Story FL2: apply_findings.sh inserts at block boundaries and refuses silent overwrite

Two changes to `apply_findings.sh`. First, insertion placement: instead of inserting the marker
directly above the line containing the quote's first character (apply_findings.sh:150-166), scan
back to the start of the enclosing block — the nearest preceding blank line, heading, or
bullet-start at or above the quote line — and insert there, so a quote anchored on a wrapped
continuation line no longer splits a sentence (the damage visible at plan-v4.md:86-87 and :93).
Idempotency and replace-in-place checks (apply_findings.sh:155-163) must scan all consecutive
marker lines above the block, not just the single previous line, since markers now stack at
block boundaries. Second, a generation guard: if `<out_plan>` already exists, fail with exit 3
and a message naming the file, unless `--force` is given (obs 18949: an existing plan-v4.md was
silently clobbered).

### Depends On: none
### Touches:
- skills/team-sprint/scripts/apply_findings.sh
- skills/team-sprint/scripts/tests/apply_findings.bats

### Boundaries:
- `workflows/phase-1.workflow.js:292-296` and `phases/phase-1.md:74` (the callers; FL3 updates their invocations — this story must keep the 3-arg CLI shape and exit codes 0/2 unchanged, adding only exit 3)
- `apply_findings.sh` skipped-sidecar contract (`<out_plan>.skipped.json`, apply_findings.sh:55) — unchanged

### Acceptance Criteria
- A finding whose quoted_evidence starts on a wrapped continuation line of a bullet gets its marker inserted above the bullet's first line, not between the bullet's lines.
- A finding whose quote sits mid-paragraph gets its marker inserted above the paragraph's first line (after the preceding blank line or heading).
- Re-running with identical inputs and `--force` is byte-identical (existing idempotency contract holds at the new insertion point, including when two markers stack above one block).
- With `<out_plan>` already existing and no `--force`, the script exits 3, writes nothing, and stderr names the existing file.
- `--force` overwrites and exits 0.

### Definition of Done
- [ ] `shellcheck scripts/apply_findings.sh` clean.
- [ ] `apply_findings.bats` green, with new cases for block-boundary insertion (bullet, paragraph, stacked markers), exit-3 guard, and `--force`.
- [ ] Header comment updated: insertion rule, exit code 3, `--force`.

## Story FL3: fold gate — the loop revises prose and proves zero markers remain

Make the loop converge. New script `skills/team-sprint/scripts/findings_gate.sh <plan>` that
counts `<!-- FINDING ` markers and emits `STATUS=OK COUNT=0` (exit 0) or
`STATUS=FAIL COUNT=<n>` with each marker's line number on stderr (exit 1), in the
header/STATUS/exit-code style of `graphify_ensure.sh:1-38`. Then rewrite Phase 1's revise step
in BOTH implementations, keeping them in sync per phase-1.md:20:

- `phases/phase-1.md`: fix the pseudocode arg orders (line 65 → `lead_validator.sh
  "$current_plan" "$aggregate"`; line 74 → `apply_findings.sh "$current_plan" "$accepted_json"
  "$ART/plan-v<N+1>.md"`); replace the false "rewrites the plan paragraph-by-paragraph" claim
  (line 128) with the real contract: annotate via apply_findings.sh, then the lead folds every
  marker into revised prose (apply the recommendation, delete the marker), then
  `findings_gate.sh` must pass on the revised plan before the next round is spawned. Add the
  gate to the exit condition: `plan-final.md` passes `findings_gate.sh`.
- `workflows/phase-1.workflow.js`: the Revise agent prompt gains the fold instruction and ends
  by running `findings_gate.sh`; the `REVISED` schema gains required integer
  `remaining_markers`; the loop treats `remaining_markers > 0` as `outcome = 'fold_failed'` and
  stops rather than spawning a review round against a marker-laden plan. The clean branch
  (workflow line 259-265) runs `findings_gate.sh` on the plan before copying to plan-final.md.

### Depends On: FL2
### Touches:
- skills/team-sprint/scripts/findings_gate.sh
- skills/team-sprint/phases/phase-1.md
- skills/team-sprint/workflows/phase-1.workflow.js
- skills/team-sprint/scripts/tests/findings_gate.bats
- skills/team-sprint/scripts/tests/workflow_doc_drift.bats

### Boundaries:
- `tests/workflow_doc_drift.bats` (the bidirectional drift detector added 2026-07-27 — any new `wf:` marker or doc claim must be registered there or the suite fails; this story owns keeping it green)
- `scripts/lint_skill.sh` (structural lint over phase docs — the phase-1.md rewrite must not break its checks)
- `$REF/reviewer-contract.md` (reviewer-side contract — NOT edited; the fold step is lead-side only)

### Acceptance Criteria
- `findings_gate.sh` on a marker-free plan prints `STATUS=OK COUNT=0` and exits 0.
- `findings_gate.sh` on a plan with 3 markers prints `STATUS=FAIL COUNT=3`, lists three line numbers on stderr, and exits 1.
- `phase-1.md` contains no invocation of `lead_validator.sh` or `apply_findings.sh` whose argument order contradicts the scripts' own usage blocks (assert by grepping the doc for the corrected forms).
- The string "paragraph-by-paragraph" no longer appears in `phase-1.md`; the revise section names apply → fold → gate as three distinct steps.
- `phase-1.workflow.js` `REVISED` schema requires `remaining_markers`, and `node --check` passes on the edited file.
- `workflow_doc_drift.bats` and `lint_skill.sh` pass after the edits.

### Definition of Done
- [ ] `shellcheck scripts/findings_gate.sh` clean.
- [ ] `findings_gate.bats` green under `run-all.sh`.
- [ ] Prose steps and workflow verified in sync for the revise step (the phase-1.md:20 contract) — drift suite green.

## Story FL4: lead_validator.sh tolerant quote matching and marker-only-evidence rejection

Extend `_quoted_in_plan` (lead_validator.sh:151-161) to a three-outcome match against the plan
text **with all `<!-- FINDING ... -->` marker lines stripped first**: (a) exact substring →
accept as today; (b) whitespace-normalised match (collapse every run of whitespace, including
newlines, to one space in both needle and haystack) → accept, adding `"match":"normalized"` to
the finding; (c) no match either way → reject `quoted_evidence_not_in_plan`. A quote that
matches the raw plan but NOT the marker-stripped plan was grounded only inside a marker comment
— reject it with new reason `evidence_only_in_findings_marker` (round 4's BND-Y4 case, obs
18973), because folding deletes that text.

### Depends On: none
### Touches:
- skills/team-sprint/scripts/lead_validator.sh
- skills/team-sprint/scripts/tests/lead_validator.bats

### Boundaries:
- `phase-1.md:123` reject-rate escalation (consumes the accept/reject split — reasons are additive, existing reason strings unchanged)
- `workflows/phase-1.workflow.js` VALIDATED schema (counts only — unaffected by the added `match` field on accepted findings)
- `$REF/reviewer-contract.md` quoted_evidence rules (reviewer side unchanged; this is lead-side tolerance)

### Acceptance Criteria
- A quote wrapped across two plan lines ("exactly one\nSTATUS line") is accepted with `"match":"normalized"` when the plan carries the same words split by a newline plus indentation.
- A quote interrupted in the plan by an inserted marker line between its words is accepted via the normalised match against the marker-stripped text.
- A quote appearing ONLY inside a `<!-- FINDING ... -->` line is rejected with reason `evidence_only_in_findings_marker`.
- A quote appearing nowhere is still rejected with `quoted_evidence_not_in_plan`.
- Exact-match acceptances carry no `match` field (output byte-stable for the existing green cases).
- `--reject-rate` mode is unaffected (rates computed over the new split).

### Definition of Done
- [ ] `shellcheck scripts/lead_validator.sh` clean.
- [ ] `lead_validator.bats` green with new cases for all four outcomes above; all pre-existing cases pass unchanged.
- [ ] Header comment documents the match ladder and the new reject reason.

## Story FL5: art_dir resolves revision artifacts to their real sprint dir

Fix the state-write path bug. In `lib.sh` `art_dir()` (lib.sh:82-102), before deriving a slug
from the basename: canonicalise `plan_path`'s directory and, if it already IS
`<repo_root>/.team-sprint/sprints/sprint-<slug>` (directly — not a deeper descendant), use that
sprint dir. Only otherwise fall back to the existing `validate_plan_path.sh --slug-only`
derivation. This makes `state.sh update <sprint-dir>/plan-v4.md ...` land in
`<sprint-dir>/state.json` instead of inventing `sprint-plan-v4` (obs 18980: exit 2,
"state.json missing").

### Depends On: none
### Touches:
- skills/team-sprint/scripts/lib.sh
- skills/team-sprint/scripts/tests/lib.bats

### Boundaries:
- `validate_plan_path.sh` (still the sole slug authority for plans OUTSIDE a sprint dir; its Check 3 clobber semantics are untouched)
- `state.sh`, `schedule.sh`, every `art_dir` caller (inherit the fix; no call-site changes)
- `state_tmp_leak.bats`, `art_dir.bats` (existing behaviour contracts that must stay green)

### Acceptance Criteria
- In a temp repo with `.team-sprint/sprints/sprint-foo-1/state.json`, `art_dir sprints/../.team-sprint/sprints/sprint-foo-1/plan-v9.md` echoes the sprint-foo-1 dir (not sprint-plan-v9).
- `state.sh update <that-plan-path> iterations.adversarial=4` exits 0 and the counter lands in `sprint-foo-1/state.json` (regression test for obs 18980). (The object form `iterations='{"adversarial":4}'` must NOT be prescribed: it replaces the whole object, drops `.coverage`/`.review_fix`, and fails state.sh's schema check with exit 1.)
- A plan at the repo root (`docs/plans/foo-1.md`) still resolves through the slug derivation exactly as before.
- A plan in a NON-sprint subdirectory of `.team-sprint/` falls through to slug derivation (the in-sprint-dir test is exact, not prefix).

### Definition of Done
- [ ] `shellcheck scripts/lib.sh` clean.
- [ ] New cases in `lib.bats` (or `art_dir.bats`, whichever holds the existing art_dir cases) green; full `run-all.sh` green.
- [ ] `art_dir` comment block (lib.sh:77-81) documents the in-sprint-dir short-circuit.

## Story FL6: plan-of-record gate — the reviewed plan is provably the executed plan

Close the split that nearly executed a 7-story plan after reviewing a 6-story one (obs
18983/18988). Add `state.sh record-plan <plan_path> <file>` (stores `plan_of_record.path` and
`plan_of_record.sha256` of `<file>` into state.json) and `state.sh check-plan <plan_path>
<file>` (recomputes and compares; stdout `STATUS=OK` exit 0, or `STATUS=FAIL` with both hashes
on stderr, exit 1). Wire the phases: Phase 1 records `plan-final.md` at promotion (both
`phases/phase-1.md` exit condition and the workflow's finalise step, workflow lines 259-265);
`phases/phase-2.md` entry gate runs `check-plan` against `$ART/plan-final.md` and additionally
asserts that the configured `plan_path` resolves (via `art_dir`) to the same sprint dir as the
plan under execution — STOP on mismatch with a message naming both paths. Extend
`state.schema.json` with the `plan_of_record` object (the schema must be edited explicitly —
`additionalProperties: true` would otherwise let the field pass silently, the RH5-noted trap).

### Depends On: FL5
### Touches:
- skills/team-sprint/scripts/state.sh
- skills/team-sprint/scripts/state.schema.json
- skills/team-sprint/phases/phase-1.md
- skills/team-sprint/phases/phase-2.md
- skills/team-sprint/workflows/phase-1.workflow.js
- skills/team-sprint/scripts/tests/state.bats

### Boundaries:
- `sha256` tooling: use `shasum -a 256` (present on macOS; `sha256sum` is GNU-only) via a lib.sh helper if one does not exist
- `tests/workflow_doc_drift.bats` (the phase-1.md/workflow edits must keep the drift suite green — FL3 lands first on phase-1.md; this story rebases on its text)
- `phases/phase-0.md` (NOT edited; the plan-path config read stays where it is — the gate lives at the Phase 2 entry, the last moment before execution)

### Acceptance Criteria
- `state.sh record-plan` writes `plan_of_record.path` and a 64-hex `plan_of_record.sha256` into state.json, and state.json still validates against `state.schema.json`.
- `state.sh check-plan` against an unmodified file prints `STATUS=OK` and exits 0.
- After a single-byte edit to the file, `check-plan` prints `STATUS=FAIL`, shows recorded vs actual hashes on stderr, and exits 1.
- `check-plan` with no recorded `plan_of_record` prints `STATUS=FAIL` with reason `no-record` and exits 1 (an unrecorded plan is not a pass).
- `phase-2.md` entry section instructs the STOP branch on `STATUS=FAIL` and on sprint-dir mismatch, in the same STATUS-branch style as the existing `graphify_ensure.sh` steps in phase-0.md:40-53.

### Definition of Done
- [ ] `shellcheck scripts/state.sh` clean; `state.bats` green with cases for all four AC outcomes.
- [ ] `state.schema.json` change covered by the existing schema-validation test path in `state.bats`.
- [ ] `lint_skill.sh` and `workflow_doc_drift.bats` green after the phase-doc and workflow edits.

## Open questions

1. **Fold quality is model-judged.** `findings_gate.sh` proves markers are gone, not that the
   fold honoured each recommendation. A per-finding fold audit (diff the folded plan against the
   recommendation list) would be a follow-on story if folded-but-ignored recommendations show up
   in practice.
2. **Normalised matching may admit near-miss quotes.** FL4's whitespace-collapse cannot confuse
   distinct sentences, but it will accept quotes whose only defect was reflow — which is the
   point. If reviewers start leaning on it, tighten the reviewer-contract's quoting rules
   instead of the validator.
3. **plan-v4.md itself still carries 64 markers.** This plan fixes the machinery; the
   recon-harness sprint still needs its plan folded (by the FL3 fold step, run manually once, or
   by re-entering Phase 1 after this sprint lands) before it can execute.

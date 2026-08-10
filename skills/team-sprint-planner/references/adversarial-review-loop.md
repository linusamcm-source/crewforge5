# Adversarial review loop (planner's final phase)

Moved here from team-sprint's Phase 1: the plan is driven to adversarial-clean **before** it is handed to `/team-sprint`, which now only verifies the provenance stamp (its thin Phase 1 gate) and deploys. Clean means the close-out sweep reports **zero NEW CRITICAL/HIGH findings** against the final text — or the user explicitly overrides after the close-out cap.

## How it runs — dynamic Workflow

The loop runs as a **per-run, dynamically-authored `Workflow` script**. The authoring contract — schemas, script template, effort tiering, artifacts — lives in [dynamic-review-workflow.md](dynamic-review-workflow.md); the invoking session authors a concrete script per run with the plan path, repo roots, and story IDs baked in as constants. There is no saved script to invoke.

Core inversion: **the unit of iteration is the finding, not the plan revision.** Whole-plan review happens exactly twice — discovery and close-out — never once per round. Depth is fixed; only width scales.

1. **Discovery** — one parallel wave: chunk reviewers (≤5 stories each, low effort) plus one boundary reviewer over the whole plan and both repo roots (high effort). Stories are parsed in-script by regex on `## Story <id>:` headings. Every reviewer returns findings via **schema**, machine-enforced at the tool layer: cross-story findings use `story_id: "PLAN"`; `evidence` is `{file, line, quote}` quoting the **code**, never the plan; `plan_anchor` is a free-text pointer the skeptic judges — nothing is substring-matched against the plan.
2. **Adjudication** — per-finding skeptic pipeline, prompted to REFUTE by reading the cited code and plan section. Only a refutation kills a finding — typography cannot. In-script ledger dedup merges refilings instead of bouncing them; `unverifiable` findings are collected for the user, never dropped.
3. **Apply + fold-verify** — per accepted finding: a minimal-edit fixer (standing instruction: prefer deleting a wrong claim over adding a caveat paragraph), then a fold-checker with one bounce before the finding surfaces to the user. An in-script bloat gate compresses the plan if it grew >15% during folds.
4. **Close-out sweep** — a fresh boundary reviewer and a whole-plan reviewer over the **final** text, seeded with the ledger digest, reporting only NEW CRITICAL/HIGH.

## Gate

- **Zero NEW CRITICAL/HIGH from the close-out sweep** → `status=clean`. MEDIUM/LOW findings are applied in the same pass but never gate and never trigger re-review. `UNVERIFIED` findings are report-only.
- New CRITICAL/HIGH at close-out → one more adjudicate/apply cycle for those findings only. **Hard cap: 2 close-out cycles.** Not dry after that → the user decides — extend, fix manually, or accept (→ `status=user-override`) — with the severity trend and token spend printed in the ask. The workflow never overrides itself.

Exactly two human interrupt points, both batched after the workflow returns: the `unverifiable` findings (plus any twice-failed folds) as one AskUserQuestion batch, and the override ask (only if close-out was not dry). Never ask mid-run.

**Cross-boundary gate (additional, per story).** A story does not exit the loop until its
round-1 boundary reviewer produced both mandatory sections from `adversarial-review` Steps 2a/2b:

1. **Assumption Inversion** table — every input the story's correctness depends on, its
   producing component by file path, and whether that producer can emit the assumed value.
   A producer named `Unknown` is a finding, not a blank. Any row where the producer cannot
   emit the assumed value is CRITICAL by default.
2. **Deployment Reality** Q1/Q2/Q3 — each answered with a `file:line` citation. `N/A` is
   permitted **only** with a citation justifying it (`N/A — no env-gated path; handler
   registered unconditionally at server.go:88`). A bare `N/A` is a blank and fails the gate.

A blank Q1/Q2/Q3 **fails** the story — it does not warn. Rationale: every high-severity miss
in the `spot-paywall-SP1` post-mortem was an unstated assumption at a boundary the review
never crossed; more claim-validation rounds do not help, because none of them were false claims.

Reviewers may cite **absolute paths outside the plan's repo** — the repomix pack is
repo-root-scoped, so a companion repo is physically unreachable through it, and Q2 usually
cannot be answered without reading the real caller live.

## Reproduction gate (bugfix plans only)

When the plan's premise is "X is broken", it must carry a reproduction against the **deployed
configuration**, not merely a code trace — a probe artifact is the evidence
(`PROBE status=402 body={"error":"spot_cap_exceeded",...}`). A code trace cannot produce it
when the defect is that the *deployed* config never mints the value the code branches on.
Requiring it at plan time moves that discovery from mid-sprint to here. Not applicable to
greenfield/feature plans — skip with a one-line statement, do not fabricate a probe.

## Finalise: stamp + hand off

The stamp goes on **after** a dry verifying sweep, never on a just-folded text; the canonical
plan file is byte-identical to the last verified revision.

1. **Stamp.** Insert the provenance stamp on the line directly under the plan's `#` title:
   ```
   <!-- adversarial-review: status=<clean|user-override> rounds=<N> date=<YYYY-MM-DD> reviewer=team-sprint-planner -->
   ```
   team-sprint's Phase 1 greps exactly this line; a plan without it is hard-STOPPED at sprint time. The stamp shape is an invariant — do not change it.
2. **Artifacts.** Exactly three files in `<plan-dir>/<plan-stem>-review/` (e.g. `docs/plans/config-unify-9-review/` for `docs/plans/config-unify-9.md`): `review-ledger.json` (every finding with verdicts, adjudication, and fix status), `plan-final.md` (byte-identical copy of the stamped plan), `report.md` (run summary). Keep the dir in place — it is the audit trail team-sprint WARNs about if missing.
3. **Report:** stamp line, close-out cycles run, any user-waived findings (only possible on `status=user-override`), and the review dir path.

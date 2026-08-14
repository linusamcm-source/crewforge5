# Phase 1 — Plan-review provenance gate (thin)

**Goal.** Verify the plan has already been driven to adversarial-clean by `team-sprint-planner` **before** the sprint spends a single agent on it. The review loop itself no longer runs here — it is the planner's final phase (chunked reviewers, boundary reviewer, cross-boundary gate, apply/fold/gate revision discipline all run planner-side; see References). This phase only verifies provenance, proves the plan is marker-free, freezes it as `$ART/plan-final.md`, and records it as the plan of record.

## Entry condition

Phase 0 complete. `$ART/state.json.current_phase == 1`. `$plan_path` exists; `$ART` exists.

## Gate

The plan carries a valid adversarial-review provenance stamp (below) AND passes the findings gate (no unfolded `<!-- FINDING ... -->` markers). No stamp → **hard STOP** — do not review the plan yourself, do not warn-and-continue. Surface:

> Plan has no adversarial-review provenance. Run `/team-sprint-planner` over it first — its final phase reviews the plan to adversarial-clean and stamps it. team-sprint only deploys reviewed plans.

## Provenance stamp contract

`team-sprint-planner`'s review loop ends by inserting one HTML comment on the line directly under the plan's `#` title:

```
<!-- adversarial-review: status=clean rounds=2 date=2026-08-01 reviewer=team-sprint-planner -->
```

- `status` — `clean` (loop exited with zero accepted findings of any severity — all fixes applied) or `user-override` (user accepted residual findings at the iteration cap). Both pass this gate; `user-override` is surfaced to the user as a reminder of what they waived.
- `rounds` — review rounds the planner ran; copied into `state.json.iterations.adversarial` for provenance.
- Review artifacts (round reports, rejected findings, revision diffs) live planner-side in `<plan-dir>/<plan-stem>-review/`; if that dir is missing next to a stamped plan, WARN (stamp is authoritative, artifacts are audit trail) but do not stop.

## Steps

1. **Check the stamp.**
   ```bash
   grep -m1 -E '^<!-- adversarial-review: status=(clean|user-override) ' "$plan_path"
   ```
   No match → STOP with the gate message above. `status=user-override` → echo the stamp line and the residual findings location (`<plan-dir>/<plan-stem>-review/`) so the user re-confirms context before deployment.
2. **Findings gate.** `bash "$SCRIPTS/findings_gate.sh" "$plan_path"` must print `STATUS=OK COUNT=0`. `STATUS=FAIL COUNT=<n>` means the planner's fold step left unresolved `<!-- FINDING ... -->` markers in the plan — STOP and send it back to the planner; a marker-laden plan must never reach execution.
3. **Freeze the reviewed plan.** `cp "$plan_path" "$ART/plan-final.md"` — Phase 2's entry condition. The plan is frozen from here; Phase 4's AC reviewer checks impl-vs-plan drift directly.
4. **Record the plan of record.**
   ```bash
   bash "$SCRIPTS/state.sh" record-plan "$plan_path" "$ART/plan-final.md"
   ```
   Stores `plan_of_record.{path,sha256}` — the Phase 2 entry gate's `check-plan` proves the reviewed plan is the executed plan (obs 18983/18988: a sprint once executed a different plan than the one reviewed).
5. **Persist provenance.** Copy the stamp's `rounds` value into the shared counter (the Phase 2 graph reviewer keeps incrementing it):
   ```bash
   bash "$SCRIPTS/state.sh" update "$plan_path" iterations='{"adversarial":<rounds>,"coverage":0,"review_fix":0}'
   ```

## Exit condition

`$ART/plan-final.md` exists and passes `bash $SCRIPTS/findings_gate.sh "$ART/plan-final.md"` (`STATUS=OK COUNT=0`); plan of record recorded via `state.sh record-plan`; stamp provenance persisted to `state.json.iterations.adversarial`. Advance:
```bash
bash "$SCRIPTS/state.sh" advance-phase "$plan_path" 2
```

## Artifacts produced

- `$ART/plan-final.md` (verbatim copy of the stamped plan)
- `state.json.plan_of_record` (path + sha256)

## Scripts referenced

- `$SCRIPTS/findings_gate.sh`
- `$SCRIPTS/state.sh` (`record-plan` at freeze; `advance-phase` at exit)

## References

- `team-sprint-planner`'s `references/adversarial-review-loop.md` — the review loop that used to live here (chunked parallel reviewers + boundary reviewer, cross-boundary gate, lead-side validation, apply/fold/gate revision discipline, reproduction gate for bugfix plans) now runs as the planner's Phase 7, with a stricter gate: zero accepted findings of any severity (all fixes applied) or explicit user override. Its Workflow mechanisation lives planner-side too.
- `$REF/reviewer-contract.md` — the JSON reviewer return contract, still used by the Phase 2 graph reviewer (mandatory under `scheduling: graph`).

## Extensions

<!-- subskill-hooks:phase-1 -->
RESERVED — `subskill_hooks.phase-1` is NOT active in v1.0. Users who add a `phase-1` block to their config will see an INFO log line `subskill_hooks.phase-1 unsupported in v1.0; block ignored` at Phase 0; the block is NOT persisted into `state.json.subskill_hooks`. See `$REF/subskill-hooks.md` for rationale.

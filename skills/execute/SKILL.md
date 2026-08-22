---
name: execute
model: opus
description: Drive a reviewed plan to a merged commit — TDD agent fleet in an isolated worktree, coverage, AC/DoD and review-fleet gates, then an integration diagram and distilled learnings. Use on /crewforge5:execute, "run a sprint", "execute this plan"
---
You are running `crewforge5:execute`: a stamped plan in, a merged commit out. The eight phases that do the work are `team-sprint`'s, unchanged and loaded from where they live; this skill is the state machine that offers them one at a time, records each gate's verdict, and adds the two phases team-sprint never had — an integration diagram of what actually merged, and a distillation pass over what the run taught.

The plan must already be adversarial-clean. Reviewing it is `crewforge5:plan`'s job, and Phase 1 hard-STOPs a plan nobody reviewed.

## Path aliases

- `$FLOW` — `${CREWFORGE5_ROOT}/scripts/flow/`, the shared driver: `flow_next.sh`, `flow_gate.sh`, `flow_state.sh`, `subskill_resolve.sh`.
- `$SKILL` — this skill's install dir, holding `phases.json` and `scripts/phase_gate.sh`.

## Intake gate — ask before Phase 0

Call **AskUserQuestion** once for any run-shape answer the invocation and a repo-root `team-sprint.config.yaml` do not already settle — only the open questions. "Other" free text beats the mapped default.

- **Scope** — `All in the plan` / `A named subset` / `Single story` → what Phase 0 parses.
- **Rigour** — `Full — 80% coverage + full Phase 7 fleet (Recommended)` / `Fast — 60% coverage, security-only fleet` / `Prototype — coverage gate off` → `coverage_threshold` + the Phase 7 fleet.
- **On green** — `Merge into target branch (Recommended)` / `Open a PR, don't merge` / `Leave the worktree for me to inspect` → Phase 7 merge behaviour + `target_branch`.

Then claim a subject for this sprint and record the plan and the answers, in that order, before gating anything:

```bash
bash $FLOW/flow_state.sh execute use --from <plan-path>
bash $FLOW/flow_state.sh execute set plan <plan-path> scope <answer> rigour <answer> on_green <answer>
```

`use` first, because flow state is keyed by subject and the default one is shared: a second sprint in this repo would otherwise resume into the first sprint's phase statuses and find them passed. `flow_state.sh execute list` shows the sprints this repo already holds.

`plan` is the key Phase 0's and Phase 1's gates read. Without it they fail closed rather than guessing which plan is under sprint.

## The loop

```bash
bash $FLOW/flow_next.sh execute        # STATUS=NEXT PHASE=<id> DOC=<absolute path>
#   → load DOC, do exactly what it says
bash $FLOW/flow_gate.sh execute <id>   # STATUS=PASS|FAIL, recorded in state.json
```

Repeat until `flow_next.sh` prints `STATUS=DONE`. A failed gate is re-offered, not advanced past — fix what it reported and gate again. Driver state lives at `<repo-root>/.crewforge5/execute/<subject>/state.json`; resuming a sprint is just running `flow_next.sh` again.

## Who owns phase progress

For phases 0–7, **team-sprint's own `state.json` is the authority, not the driver's.** The manifest declares a `status_source` — `scripts/sprint_status.sh` — which reads `$ART/state.json` and answers `PHASE=<current_phase>` plus `DONE=1` once the sprint is finalised. `flow_next.sh` treats every phase before that as passed.

This is why the per-story loop works at all. team-sprint has tracked `current_story_id`, `story_commits[]` and `iterations{}` since long before this driver existed, and Phase 6 puts `current_phase` back to 3 for the next story. A driver keeping its own copy could only record "phase 3 passed" once, and had no way to be sent back — so a resumed sprint lost its place across exactly the four phases that do the work.

The driver's own state still decides phases 8 and 9, which team-sprint has never heard of, and it still records every gate verdict. A status source that exits non-zero — no plan recorded yet, no sprint state on disk — has no opinion, and the driver's state decides alone.

## Phases

`phases.json` is the manifest — id, title, doc, gate, required, plus the optional `when` and the manifest-level `status_source` — and it is the authority on what runs. Phases 0–7 point at team-sprint's own docs and are unmodified by this skill.

**The phase list depends on `scheduling`.** Under `sequential`, phases 3–6 run once per story as team-sprint states. Under `graph` — the shipped default — team-sprint replaces them with the wave loop in `phase-execute.md` and sets `current_phase: "execute"`, so those four phases carry a `when` that excludes them and the `execute` phase carries one that includes it. `sprint_status.sh --mode` answers which, preferring the sprint's recorded `scheduling` over the config, because Phase 0 step 4a downgrades `graph` to `sequential` when the lead has no `SendMessage`.

| Phase | Doc | Gate |
| --- | --- | --- |
| 0 Pre-flight | team-sprint `phase-0.md` | plan path contract + required sub-skills present |
| 1 Plan-review provenance | team-sprint `phase-1.md` | adversarial-review stamp + findings gate |
| 2 Worktree + team | team-sprint `phase-2.md` | judgment, stated by the doc |
| 3 TDD + coverage | team-sprint `phase-3.md` | judgment, stated by the doc — sequential mode only |
| 4 AC/DoD review | team-sprint `phase-4.md` | judgment, stated by the doc — sequential mode only |
| 5 Fix loop | team-sprint `phase-5.md` | judgment, stated by the doc — sequential mode only |
| 6 Story commit | team-sprint `phase-6.md` | judgment, stated by the doc — sequential mode only |
| execute Wave loop | team-sprint `phase-execute.md` | judgment, stated by the doc — graph mode only |
| 7 Review fleet, merge | team-sprint `phase-7.md` | judgment, stated by the doc |
| 8 Integration diagram | `phases/phase-8.md` | diagram tool + recorded diagram, else SKIP |
| 9 Distil learnings | `phases/phase-9.md` | empty ledger passes; otherwise `ceiling.sh check` |

Phases 3–6 run once per story under `scheduling: sequential`, exactly as team-sprint states; the `execute` wave loop replaces them under `scheduling: graph`; everything else runs once per sprint.

**Judgment phases hold their gate anyway.** A blank `gate` in the manifest means no script can decide it, not that the bar moved: the phase doc states the exit condition and you hold it before gating. Gate a phase you did not finish and the sprint walks past its own quality bar with a green light.

## Loading a sub-skill

Every sub-skill this flow uses is hidden from the catalogue and unreachable through the `Skill` tool. Resolve it instead:

```bash
bash $FLOW/subskill_resolve.sh --load-mode use-repo-code   # MODE=agent AGENT=Explore
bash $FLOW/subskill_resolve.sh use-repo-code               # the absolute SKILL.md path
```

`MODE=inline` → read the body and follow it here. `MODE=agent` → spawn it with the `Agent` tool using the named type, never inline: a skill that declares `context: fork` does so to keep its work out of this window, and reading it inline destroys exactly the isolation it asked for.

## Guardrails

- **Worktree isolation is absolute.** Sprint operations never touch the main working tree.
- **A gate verdict is recorded, not remembered.** `flow_gate.sh` writes it to `state.json`; a verdict announced in prose and not gated did not happen.
- **Spawners block-collect-close every child.** Never end a turn with a live child — it sleeps forever.
- **Phase 1 has no override.** An unstamped plan goes back to `crewforge5:plan`.
- **No force-push and no main-branch writes** without explicit user confirmation.

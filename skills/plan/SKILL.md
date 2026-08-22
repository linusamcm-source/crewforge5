---
name: plan
model: opus
description: Goal to an adversarial-clean, /team-sprint-ready plan file. Use on /crewforge5:plan, "plan this feature", "write a sprint plan"
---

# crewforge5:plan

You take a goal and hand back a plan file that `crewforge5:execute` will run
without argument: grounded in citations, ratified by the user, honest about the
debt it inherits, and stamped adversarial-clean.

Invoke it as **`/crewforge5:plan`**. Bare `/plan` is not this skill.

## How this runs

A state machine, not a script you read top to bottom. `phases.json` declares
nine phases as `{id, title, doc, gate, required}`; the shared driver holds the
state and decides what comes next, so an interrupted planning session resumes
where it stopped instead of starting over.

State is keyed by subject — `.crewforge5/plan/<subject>/state.json` — and phase 0
claims one from the confirmed goal. Planning a second feature therefore starts at
phase 0 rather than resuming into the first plan's verdicts. `flow_state.sh plan
list` names the planning runs this repo holds; `use` returns to one.

```bash
bash "${CREWFORGE5_ROOT:-.}/scripts/flow/flow_next.sh" plan     # STATUS=NEXT PHASE=<id> DOC=<path>
# …read DOC, do the phase's work…
bash "${CREWFORGE5_ROOT:-.}/scripts/flow/flow_gate.sh" plan <id>  # STATUS=PASS|FAIL, recorded
```

A `FAIL` is not a suggestion. `flow_next.sh` re-offers the same phase until its
gate passes, which is the whole reason the gates are scripts and not prose.

## Phases

| # | Phase | Doc | What the gate proves |
| --- | --- | --- | --- |
| 0 | Intake | `phases/phase-0.md` | a confirmed goal is in `state.json` |
| 1 | Ground | `phases/phase-1.md` | a fresh pack, or a recorded DEGRADED verdict |
| 2 | Diverge | `phases/phase-2.md` | every `D<n>` section offers ≥2 frames, or a `Skip:` reason |
| 3 | Grill | `phases/phase-3.md` | every framed `D<n>` carries a `**Chosen:**` line |
| 4 | Audit | `phases/phase-4.md` | ID-carrying table rows, or a `No findings.` claim |
| 5 | Triage | `phases/phase-5.md` | every ID known, unique, and dispositioned |
| 6 | Draft | `phases/phase-6.md` | filename carries a story id; the plan parses |
| 7 | Review | `phases/phase-7.md` | no open finding, and a stamp |
| 8 | Verify | `phases/phase-8.md` | every finding ID covered exactly once |

## The interactive rule

Phases 2 and 3 need a human. In phase 3 you **ask one question at a time** with a
single `AskUserQuestion` call and wait for the answer before writing the next
one — the follow-up worth asking always depends on the answer you have not got
yet, so a batch of pre-written questions is a form, not a grilling.

That is also why this skill declares no `context: fork` and no `agent:`
frontmatter: a forked subagent has no user to ask. The one heavy sub-skill,
`adversarial-review`, forks the other way — phase 7 spawns each review round as
an agent so its ~24k-char body loads in the reviewer's window, while the fold,
the stamp and the user-override conversation stay here with the user.

## Loading the sub-skills

The skills this flow drives are hidden from the catalogue, so the `Skill` tool
cannot reach them. Resolve a path and load it — and ask how, because a
`context: fork` skill has to be spawned through the `Agent` tool rather than read
inline, or the isolation it exists for is destroyed:

```bash
bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code
```

| Capability | Source skill | Reached in |
| --- | --- | --- |
| Repo grounding from a pack | `use-repo-code` | phase 1 (Agent-spawned) |
| Parallel divergent frames | `adhd` | phase 2 |
| Relentless questioning loop | `grill-me` | phase 3 |
| Interactive ratification front half | `team-feature` | phases 0–3 |
| Existing-debt inventory | `tech-debt-audit` | phase 4 (Agent-spawned) |
| Impact map and coverage check | `master_plan` | phases 5 and 8 |
| Plan contract and story shape | `team-sprint-planner` | phase 6 |
| Review-to-clean loop and stamp | `adversarial-review` | phase 7 (Agent-spawned rounds) |

## Done

Phase 8 reports `CLEAN` and `flow_next.sh plan` prints `STATUS=DONE`. Tell the
user the plan is deployable and name the next command: `/crewforge5:execute`.

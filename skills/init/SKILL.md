---
name: init
model: opus
description: Gated config hygiene — measure, slim, validate, rectify and report a Claude setup's skills, agents and CLAUDE.md. Use on /crewforge5:init, "clean up my Claude config", "audit context load", "rightsize the environment"
---

# crewforge5:init — config hygiene as a gated state machine

Invoke as **`/crewforge5:init`**. A bare slash-init reaches Claude Code's own
CLAUDE.md initializer, which is a different tool doing a different job; the
namespaced form is the only one that reaches this skill.

Eight phases take a Claude config root from "nobody has looked at this in
months" to measured, slimmed, validated and reported. Each phase is a doc plus a
gate, and a phase that cannot pass its gate does not advance — so the run ends
with a verdict rather than an impression.

## Mechanism

State and sequencing come from the shared flow driver, not from this file:

```bash
FLOW="${CREWFORGE5_ROOT}/scripts/flow"
"$FLOW/flow_next.sh"  init            # STATUS=NEXT PHASE=<id> DOC=<phase doc>
"$FLOW/flow_gate.sh"  init <phase>    # runs that phase's gate, records the verdict
"$FLOW/flow_state.sh" init get <key>  # read anything a phase recorded
```

**One thing runs before that driver.** The dependency check is step 0 of phase
0 and is invoked directly, because `flow_next.sh` and `flow_gate.sh` both exit
early when `jq` is missing — the flow cannot report its own missing tooling
through machinery that needs the tooling:

```bash
bash "${CREWFORGE5_ROOT}/skills/init/scripts/init_gate.sh" deps
```

`phases.json` is the manifest — `{id, title, doc, gate, required}` per phase.
Every gate is one subcommand of `scripts/init_gate.sh`, which reads the config
root and returns `STATUS=OK` or `STATUS=FAIL` in `KEY=VALUE` on stdout. It
never edits anything: a gate that could repair what it measures would always
pass.

Two locations, both overridable:

| Variable | Meaning | Default |
| --- | --- | --- |
| `INIT_TARGET` | config root under audit (holds `skills/`, `agents/`) | repo root |
| `INIT_STATE` | where baseline, proposals and report live | `.crewforge5/init/` |

## Phases

| # | Phase | Doc | Gate |
| --- | --- | --- | --- |
| 0 | Preflight | `phases/phase-0.md` | dependencies present, clean tree, config root resolved |
| 1 | Measure | `phases/phase-1.md` | `baseline.json` exists and records skills |
| 2 | Hygiene | `phases/phase-2.md` | `retention_gate.sh` per proposal pair |
| 3 | Slim | `phases/phase-3.md` | token-slim `check.sh` per skill, then `sweep.py` |
| 4 | Validate | `phases/phase-4.md` | zero FAIL across agents and skills |
| 5 | Rectify | `phases/phase-5.md` | every component grades A |
| 6 | Distil | `phases/phase-6.md` | `ceiling.sh check`, or an empty ledger |
| 7 | Report | `phases/phase-7.md` | report carries the re-measured char delta |

Read the phase doc before doing the phase. This file says what the machine is;
the docs say what the work is.

## Loading a sub-skill

The sub-skills this flow drives are hidden from the per-turn catalogue, which
also puts them out of reach of the `Skill` tool. Resolve a name to a path
instead, and ask how to load it:

```bash
RESOLVE="${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh"
"$RESOLVE" --load-mode <name>   # MODE=inline | MODE=agent AGENT=<type>
"$RESOLVE" <name>               # absolute path to its SKILL.md
```

Check `--load-mode` every time. `MODE=agent` means the skill declares
`context: fork`, and it declares that precisely so its work stays out of the
caller's context — spawn it through the `Agent` tool with the declared type.
Reading such a body inline keeps the instructions and destroys the isolation,
which is the opposite of what this flow is for. `skill-validator` and
`agent-validator` are both `MODE=agent`.

## What each phase drives

| Phase | Sub-skill it drives |
| --- | --- |
| 0 | `claude-config` — the house rules every later proposal is judged against |
| 1 | `token-slim` — `baseline.py`, the immutable before-picture |
| 2 | `context-hygiene` — passes 1–4 over CLAUDE.md, rules, hooks, MCP |
| 3 | `token-slim` — the trim and split mechanic |
| 4 | `skill-validator`, `agent-validator` — structural then behavioural |
| 5 | `skill-rectifier`, `agent-rectifier` — fix catalogue per finding |
| 6 | `self-improve` — ledger distilled under a byte ceiling |
| 7 | `token-slim` re-measure plus the bundle's own budget gate |

Phases 2–6 fan out one agent per target: skill directories and agent files are
disjoint, so nothing serialises that does not have to.

## Stopping rules

- **A missing required tool stops phase 0 before anything else.** Offer to
  install only what needs no `sudo`, and ask before running it. Otherwise hand
  over the gate's copy-paste block, wait for the user, re-run
  `init_gate.sh deps`, and loop until `STATUS=OK` or the user calls it off.
  Optional tools missing is a documented degradation, not a stop.
- **A dirty tree stops phase 0.** Say so; do not commit on the user's behalf.
- **A retention breach stops phase 2.** Re-propose keeping the reported line.
  Losing a `never` is the failure this flow exists to prevent, and it is
  exactly what a length-driven trim removes first.
- **An empty ledger passes phase 6.** Do not invent an edit to have produced
  one.
- **A gate's verdict is the verdict.** If a check is genuinely wrong for a
  component, record that in the report and leave it. A suppressed check is a
  lie the next run inherits.

The whole flow is covered by `${CREWFORGE5_ROOT}/scripts/tests/init_flow.bats`,
which walks `phases.json`, exercises every `init_gate.sh` check against fixture
config roots, and proves a rejected phase-2 proposal leaves the flow where it
was.

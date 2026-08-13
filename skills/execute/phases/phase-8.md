# Phase 8 — Integration diagram

**Goal.** One diagram of how the merged sprint actually fits together, drawn from the code that landed rather than from the plan that predicted it. A plan is a forecast; by Phase 7 the forecast has been edited by seven phases of reality, and a diagram traced from the forecast documents a system nobody merged.

This phase replaces team-sprint's retired `integration_diagram: off|auto|on` config toggle. `off`/`auto` is `"required": false` in `phases.json`; `on` is `"required": true`. Nothing else changed: an optional phase still skips cleanly, a required one still stops the flow.

## Entry condition

Phase 7 recorded `PASS` — the sprint is merged and the worktree is torn down, so the diagram describes the target branch and not a scratch tree.

## Steps

1. **Resolve the diagram skill.** `bash $ROOT/scripts/flow/subskill_resolve.sh drawio` — `--load-mode` reports `MODE=inline`, so read the body rather than spawning an agent. Nothing resolves → the gate records `SKIP REASON=no-diagram-tool` when the phase is optional, and fails when it is required.
2. **Ground the diagram in merged code.** `drawio`'s own "Diagramming a codebase" rule holds here and is the reason this phase exists at Phase 8 rather than Phase 0: derive every box and arrow from the sprint diff and the files it touched (`git diff --stat <base>..HEAD`, then the resolver's `use-repo-code` for anything the diff only references). Never from memory, never from the plan's prose.
3. **Write the diagram** into the flow's artifact dir — `.crewforge/execute/integration.drawio` — and record where it went:
   ```bash
   bash $ROOT/scripts/flow/flow_state.sh execute set diagram_path .crewforge/execute/integration.drawio
   ```
   The path is recorded relative to the repo root, which is where the gate runs.

## Gate

`bash $ROOT/scripts/flow/flow_gate.sh execute 8`, which runs `scripts/phase_gate.sh 8`:

| Situation | `required: false` | `required: true` |
| --- | --- | --- |
| `drawio` resolves nowhere | `SKIP REASON=no-diagram-tool`, flow advances | `FAIL REASON=no-diagram-tool` |
| No `diagram_path`, or the file is missing | `SKIP REASON=no-diagram`, flow advances | `FAIL REASON=no-diagram` |
| The recorded file exists | `PASS` | `PASS` |

A SKIP exits 0 on purpose: `flow_next.sh` re-offers any phase that is not passed, so an optional phase that reported failure would park the sprint on itself forever. The skip is still recorded in `state.json`, so nobody has to guess afterwards whether a diagram was drawn or dodged.

## Exit condition

`state.json` records phase 8 as `PASS`, with the reason line naming a diagram file or the skip that stood in for it.

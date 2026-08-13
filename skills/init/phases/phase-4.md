# Phase 4 — Validate

Prove every component in the config root is structurally sound before the
rectifier is allowed to touch anything.

## Work

Run the structural half first, since it is mechanical and needs no model:

```bash
bash "${CREWFORGE_ROOT}/scripts/validate_all.sh"
```

That sweep is pinned to the plugin's **own** tree — it resolves its root from
its own location and takes no target — so it proves CrewForge is clean, not the
config root under audit. `INIT_TARGET` is covered by the per-component pass
below, which the gate re-runs. Both are needed: a broken plugin cannot be
trusted to judge anything else.

Then the behavioural half, one component at a time. Both validators declare
`context: fork`, so the resolver answers `MODE=agent AGENT=general-purpose` for
them — spawn each through the `Agent` tool with the resolved body as the prompt
and never read it inline:

```bash
RESOLVE="${CREWFORGE_ROOT}/scripts/flow/subskill_resolve.sh"
"$RESOLVE" --load-mode skill-validator    # MODE=agent AGENT=general-purpose
"$RESOLVE" --load-mode agent-validator    # MODE=agent AGENT=general-purpose
```

`skill-validator` covers skills, `agent-validator` covers agents. Components are
disjoint, so fan out.

Record every finding as `FAIL [component]: …` / `WARN [component]: …` so
`grade.sh` can score it, and so phase 5 knows exactly what it is repairing.

## Gate

`init_gate.sh validate` — zero FAIL across every agent and skill under
`INIT_TARGET`. Warnings are reported but do not block here; they are phase 5's
bar, not this one's.

# Phase 4 — Validate

Prove every component in the config root is structurally sound before the
rectifier is allowed to touch anything.

## Work

Run the structural half first, since it is mechanical and needs no model:

```bash
bash "${CREWFORGE5_ROOT}/scripts/validate_all.sh" --unless "$INIT_TARGET"
```

That sweep is pinned to the plugin's **own** tree — it resolves its root from
its own location and takes no target — so it proves CrewForge5 is clean, not the
config root under audit. `INIT_TARGET` is covered by the per-component pass
below, which the gate re-runs. Both are needed: a broken plugin cannot be
trusted to judge anything else.

`--unless "$INIT_TARGET"` is what keeps that from being the same work twice.
`INIT_TARGET` defaults to the repo root, so auditing CrewForge5 with itself made
the two sweeps identical — same scripts, same components. The flag skips the
first when they are the same tree and changes nothing when they differ.

Then the behavioural half, one component at a time. Both validators declare
`context: fork`, so the resolver answers `MODE=agent AGENT=general-purpose` for
them — spawn each through the `Agent` tool with the resolved body as the prompt
and never read it inline:

```bash
RESOLVE="${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh"
"$RESOLVE" --load-mode skill-validator    # MODE=agent AGENT=general-purpose
"$RESOLVE" --load-mode agent-validator    # MODE=agent AGENT=general-purpose
```

`skill-validator` covers skills, `agent-validator` covers agents. Components are
disjoint, so fan out.

Each validator agent **writes its findings to a file the gate reads**, one per
component:

```
$INIT_STATE/findings/skill.<skill-name>.md
$INIT_STATE/findings/agent.<agent-name>.md
```

Each line is `FAIL [component]: …`, `WARN [component]: …` or
`SKIPPED [component]: …`, which is what `grade.sh` scores and what phase 5 reads
to know exactly what it is repairing.

**The file is the deliverable, not the message back.** The gate re-derives the
structural findings itself — it will not take those on trust, for the same
reason phase 2 demands a `.orig` beside every `.proposed` — but the behavioural
half is the half no script can reach, and until the gate read these files a
fleet of validator agents could report failures the gate then passed straight
over. A **missing** file fails the gate: a validator that did not run must not
be indistinguishable from one that found nothing. A validator that genuinely
found nothing writes an empty file, which is a claim rather than an absence.

## Gate

`init_gate.sh validate` — a findings file present for every component, then zero
FAIL across every agent and skill under `INIT_TARGET`, structural and
behavioural together. Warnings are reported but do not block here; they are
phase 5's bar, not this one's.

The structural half is cached on component content, so phase 5's re-walk after
each repair only re-validates what actually changed. `CACHED=<n>` in the gate's
output is how many components were answered from cache; `INIT_CACHE=off`
disables it.

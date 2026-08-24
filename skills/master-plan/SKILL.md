---
name: master-plan
model: opus
description: Audit-grounded /team-sprint-ready planning — tech-debt-audit, debt triage, then team-sprint-planner. Use on /master_plan or when the user asks for a "master plan". Does not auto-invoke
disable-model-invocation: true
---

# Master Plan

Turns a goal into a /team-sprint-ready implementation plan grounded in a fresh tech-debt audit, with debt resolution written in as verifiable stories — not left as a side report.

## When to use

Use when the user invokes /master_plan, asks for a "master plan", or wants a full audit-grounded sprint plan that fixes technical debt alongside a feature goal. Does not auto-invoke. The run starts with tech-debt-audit (which refreshes the repomix pack by default and refreshes/uses graphify for structural questions when available), triages every intersecting debt finding into fix-first/fold-in/defer dispositions, then feeds goal + audit + impact map to team-sprint-planner for a /team-sprint-ready plan in which debt fixes are verifiable stories.

The goal arrives as the skill's arguments. If no goal was passed, stop and ask what to plan before doing anything.

**When `/crewforge5:plan` phase 5 loads this body, run Phase 2 only.** That flow
already owns the audit (its phase 4), the plan draft (phase 6) and the coverage
check (phase 8) — this skill's Phases 1, 3 and 4 are those phases under other
names, and re-running them from inside phase 5 re-enters a flow that is already
gated.

Finding IDs are the currency throughout: they flow audit → impact map → stories → coverage table without being re-described in prose, so nothing drifts between hops.

Success criteria for the whole run: (1) `TECH_DEBT_AUDIT.md` exists and is current, (2) `docs/plans/GOAL_IMPACT.md` maps the goal against graph + audit findings with a disposition for every intersecting finding, (3) team-sprint-planner has produced a plan file with testable ACs, per-story DoD, and a Depends-On/Touches graph, (4) the plan's debt-coverage table accounts for every intersecting finding ID exactly once — verified mechanically in Phase 4.

## Phase 1 — Ground truth

Run tech-debt-audit over the current repo. It is hidden from the catalogue, so the `Skill` tool cannot reach it — `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode tech-debt-audit` answers `MODE=agent`, so spawn it through the `Agent` tool with the type its frontmatter names rather than reading its body inline. It refreshes the repomix pack by default, and refreshes/uses graphify for structural questions when its tools are available (fail-soft), then writes `TECH_DEBT_AUDIT.md` with ID'd, file:line-cited findings. Do NOT invoke /graphify separately — the audit already handles it when needed; a second build wastes minutes.

## Phase 2 — Goal impact map + debt triage

Using the freshly built graph, map the goal's blast radius: `graphify query "<subsystem the goal touches>"` and `graphify path` between affected modules. Write `docs/plans/GOAL_IMPACT.md` containing:

1. **Touched modules/files** — what the goal will change, plus what depends on those files (blast radius from the graph).
2. **Disposition table** — every audit finding whose file/module intersects the touched set, triaged into exactly one of:
   - **fix-first** — Critical/High severity on a file the goal touches. Becomes its own story that `Depends-On`-blocks the feature stories touching the same files. You don't build on a file you know is broken.
   - **fold-in** — Medium severity, S/M effort, on a file a feature story already touches. Becomes a named task inside that story: one checkout, one review, no separate story overhead.
   - **defer** — Low severity, or outside the goal path. Listed with a one-line reason. Not stuffed into this plan; it stays in `TECH_DEBT_AUDIT.md` for the next audit's repeat-run mode.

Table columns: `Finding ID | File:Line | Severity | Effort | Disposition | Rationale`.

## Phase 3 — Plan

Load team-sprint-planner — hidden from the catalogue, so resolve it: `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode team-sprint-planner` answers `MODE=inline`, so read the body it names and follow it here. Give it the goal plus these source docs: `TECH_DEBT_AUDIT.md`, `docs/plans/GOAL_IMPACT.md`, `graphify-out/GRAPH_REPORT.md`. Requirements for the plan it produces:

- Feature stories with testable acceptance criteria, per-story DoD, and a Depends-On/Touches graph.
- Every **fix-first** finding becomes a story whose acceptance criterion is the finding's detection command, inverted — the grep/graphify query/analyzer rule that found the debt is re-run and must come back clean. The audit's evidence command IS the story's acceptance test: mechanically re-runnable, no judgment. Refactor stories use TDD shape — characterization test pins current behaviour first, then the fix, tests stay green.
- Every **fold-in** finding becomes a named task with its own AC inside the feature story that touches its file, citing the finding ID.
- Every fix-first and fold-in story's DoD includes: "finding re-verified gone via its detection command."
- The plan ends with a **debt-coverage table**: `Finding ID → story ID | fold-in task | deferred + reason`. Every intersecting finding ID from GOAL_IMPACT.md appears exactly once.
- Final story in the plan: re-run /tech-debt-audit. Repeat-run mode marks fixed findings RESOLVED in `TECH_DEBT_AUDIT.md`, closing the loop — the audit document is the living debt register the next /master_plan starts from.

## Phase 4 — Verify and hand off

Run the bundled coverage check — a mechanical diff, not a judgment call:

```bash
bash "${CREWFORGE5_ROOT}/skills/master-plan/scripts/check_coverage.sh" docs/plans/GOAL_IMPACT.md <plan-file>
```

It extracts finding IDs from GOAL_IMPACT.md's disposition table and the plan's debt-coverage table, then reports any ID missing from the plan or listed more than once. Fix the plan until the script reports CLEAN.

Then report the plan file path and a 5-line summary. Name the next command —
`/crewforge5:execute` — and stop; running it is the user's call, and the plan
must carry an adversarial-review stamp before execute will accept it.

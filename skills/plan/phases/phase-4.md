# Phase 4 — Audit

**Goal of the phase:** know what is already broken in the ground the plan is
about to build on, before deciding what the plan will do about it.

## Steps

1. Resolve and load the audit skill. It declares `context: fork`, so it is
   spawned through the `Agent` tool with the type its frontmatter names:

   ```bash
   bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" --load-mode tech-debt-audit
   ```

2. Run it over the repo and have it write `TECH_DEBT_AUDIT.md` at the repo root.
3. Every finding carries a stable ID (`F001`, `SEC1`, …) in a markdown table row.
   Phase 5 and phase 8 both match on those IDs, so a finding recorded only in
   prose is a finding that will silently escape coverage. An audit that finds
   nothing says so with a literal `No findings.` line — a claim the gate can
   read, where an empty table is indistinguishable from an audit that never ran.

## Currency

An audit older than the working tree is a fiction. If `TECH_DEBT_AUDIT.md`
predates the commits this goal is being planned against, regenerate it rather
than reusing it — the gate proves the file is there, not that it is honest.

## Gate

`plan_gate.sh audit` — at least one ID-carrying table row (the same ID pattern
`check_coverage.sh` matches in phase 8), or the explicit `No findings.` claim.
The file merely existing — the old gate — proved the audit was touched, not that
it produced anything phases 5 and 8 can consume.

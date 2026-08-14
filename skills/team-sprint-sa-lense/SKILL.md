---
name: team-sprint-sa-lense
model: opus
description: Assess a struggling Azure data migration (Synapse + dbt + DevOps) in a rescue engagement — gap analysis, prioritised recovery path, capability assessment, architecture diagrams. Pairs with team-sprint-pm-lense, which audits the project management.
---

# Team Sprint SA Lense (Rescue Skill)

## Purpose

This skill supports a rescue-style consulting engagement: a client's data
migration to Azure (Synapse + dbt + DevOps) has gone sideways, and they need
a diagnosis plus a recovery path. The output is an assessment, not a
greenfield design. It centres on gap analysis across technology, process/
governance, and team capability, and feeds a consistent set of architecture
diagrams via the existing draw.io skill.

## Assessment Lenses

Work every finding through three lenses:

1. **Technical gap** — where the migration is actually stuck across the
   Synapse, dbt, and DevOps layers. Business logic and stored procs in the
   dedicated pool, distribution/indexing decisions, dbt model structure and
   test coverage, CI/CD deployment discipline.
2. **Process & governance gap** — documentation, data lineage, orchestration
   (Azure Data Factory / Synapse Pipelines), governance and lineage in Purview,
   and downstream BI/semantic-model wiring. This is where migrations blow out;
   people underestimate everything around the SQL.
3. **Capability gap** — can the current team operate and maintain the target
   state? Assess the operating model, not individuals (see below).

## Capability Assessment (handle with care)

Frame around the work, not the people.

- **Anchor to roles the target state demands**, not named staff. E.g. "running
  dbt in production needs an owner for testing, CI, and model ownership." Then
  mark each capability as present / thin / missing. It becomes a coverage map,
  not a report card.
- **Frame gaps as risk, not blame.** Not "X can't do this" but "single point of
  failure — only one person understands the orchestration, a delivery risk."
- **Pair every capability gap with a path**: uplift via training, augment with a
  contractor, or simplify the architecture so it needs less specialist knowledge.
  The assessment becomes a plan, not a verdict.

## Diagram Outputs (via draw.io skill)

Three diagrams, one visual language across all of them.

1. **Current-state with heat** — the Synapse/dbt/DevOps flow, trouble spots
   coloured. Tells the "here's where it hurts" story at a glance.
2. **Target-state with migration path** — desired architecture annotated with
   the transition sequence and dependencies, so it reads as a route, not just a
   destination.
3. **Capability overlay** — the target diagram mapped with who owns what and
   where coverage gaps sit. Same visual, people-risk lens.

## Visual Language & Prioritisation Grid

Palette, effort tags, shapes, and the severity-vs-effort prioritisation grid
are defined once in [references/rescue-visual-language.md](references/rescue-visual-language.md) — load it before producing tables, findings, or diagrams.

## Notes

- dbt deployment specifics are project-dependent; slot in the client's actual
  deployment pattern.
- A workshop to place items on the grid with the client is a later-stage
  activity, not part of the initial diagnosis.

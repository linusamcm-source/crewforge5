---
name: team-sprint-pm-lense
model: opus
description: Run a project-management assurance lens over a struggling data migration — audit PM artefacts (charter, schedule, RAID log, governance, change control, reporting) and recommend fixes. Pairs with team-sprint-sa-lense, which diagnoses the technology.
disable-model-invocation: true
---

# PM Assurance Assessment (Rescue Skill)

## Purpose

This skill runs a project-management assurance lens over an existing, struggling
migration. Where the team-sprint-sa-lense skill audits the technical
architecture, this one audits the project's management artefacts and processes:
is the project on track, is it following correct procedures, and where has the
PM discipline broken down. The output is a diagnosis plus solution-based
recommendations, in the same style and visual language as the assessment skill.

In migrations that have gone south, the PM side is often where the rot started —
no risk register, no change control, no clear decision log. Assess against the
artefacts, not the people.

## Core PM Artefacts (the audit surface)

Six artefacts form the backbone. Assess each as present / thin / missing.

1. **Project charter & scope** — is there a clear, agreed definition of what the
   migration is delivering? A fuzzy scope is often the original sin.
2. **Schedule & milestones** — a real plan with dependencies, or just a wishlist
   of dates? Are milestones tracked and honest?
3. **RAID log** — risks, assumptions, issues, dependencies. The beating heart of
   assurance. If it's absent or stale, the project is flying blind.
4. **Governance & decision-making** — steering cadence, decision log, clear roles
   and a RACI so people know who owns what.
5. **Change control** — is there a change process, or does scope creep get
   absorbed until the project drowns?
6. **Status reporting** — honest, regular reporting, or has it gone quiet?
   Silence usually means trouble.

## Assessment Treatment

Run every artefact through the same three-state treatment used in the assessment
skill:

- **Present** — exists and is current/fit for purpose.
- **Thin** — exists but stale, incomplete, or not actually used.
- **Missing** — absent entirely.

Pair every gap with a solution-based recommendation: what to stand up, how to
make it lightweight enough to actually be maintained, and who should own it
(by role, not by name).

## Diagram Outputs (via draw.io skill)

Use the existing draw.io skill to render, with the same visual language as the
technical assessment. Three diagrams:

1. **Artefact heat-map** — the six core PM artefacts laid out and coloured
   green / amber / red for present / thin / missing. The at-a-glance "where the
   project management is broken" picture, mirroring the current-state heat
   diagram in the technical skill.
2. **Governance & decision flow** — how decisions, changes, and escalations are
   meant to move (steering, change control, RAID review cadence), with the
   broken or missing links highlighted. Shows where governance actually stalls.
3. **Target operating model overlay** — the healthy PM process annotated with
   who owns each artefact and cadence (by role, not name), and where ownership
   gaps sit. The people/accountability lens, matching the capability overlay in
   the technical skill.

## Visual Language & Prioritisation Grid

Palette, effort tags, shapes, and the severity-vs-effort prioritisation grid are shared with the technical assessment — load /home/linusmcmanamey/.claude/skills/team-sprint-sa-lense/references/rescue-visual-language.md and keep them identical so the two skills read as one deliverable.

## Notes

- Frame every finding as risk to delivery, not blame on individuals.
- This skill is a matched pair with team-sprint-sa-lense; run them together
  for a full technical-plus-governance picture of a rescue engagement.
- Workshop-style validation of findings with the client is a later-stage activity.

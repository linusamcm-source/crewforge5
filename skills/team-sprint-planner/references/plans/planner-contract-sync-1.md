# Planner contract sync — resolve drift findings, lock the cross-skill contract

Version: v2 — adversarial round 1 applied.

Six drift findings surfaced when reviewing `team-sprint-planner` against team-sprint at
`ab82272` (post graph-mode-hardening pull). Root cause: `references/plan-contract.md` is a
hand-copied snapshot of four authoritative sources — `parse_stories.sh`, `validate_plan_path.sh`,
`build_graph.sh`, `reference/plan-path-convention.md` — with no mechanism keeping the copy
honest. Commit `5b96e17` (transitive-ordering check, D2) changed `build_graph.sh` semantics
without touching the planner; that is the drift class this plan eliminates. Done state:
contract doc factually correct, the one plan-breaking trap (inline brace globs) documented,
and a golden-template contract test in team-sprint's bats suite that fails at commit time if
the parser and the documented template ever diverge again.

Grounding: all findings verified this session against
`skills/team-sprint/scripts/parse_stories.sh` (inline-touches comma split + brace-glob bullet
rule, header lines 24–25), `validate_plan_path.sh` (generic-name blacklist :62–68, id-token
rule :71), `build_graph.sh` (hybrid transitive-skip :16–22 and :143–144, natural-key ordering
:90–91 and :145, prefix-overlap semantics :104–111, both-non-empty touches requirement :139,
duplicate-id exit :72–73), and `scripts/tests/` (existing `parse_stories.bats`,
`validate_plan_path.bats`, `build_graph.bats`). No existing test exercises the planner's
documented template end-to-end: `scripts/tests/fixtures/` holds only `.gitkeep`, and
`parse_stories.bats:256–263` smoke-parses a real plan doc through the parser alone — nothing
drives one fixture through parse → path-validate → graph. Note: transitive-skip mechanics
are already unit-covered by `build_graph.bats` (":104 transitive declared ordering suppresses
the inferred conflict edge", ":125 growing-graph check") — Story 3 deliberately does not
re-prove them.

## Story 1: Correct factual drift in plan-contract.md

Fixes findings 2 and 3 (stale inferred-edge rule; misdocumented filename token set).
Doc-only change to `references/plan-contract.md`.

### Depends On: none
### Touches: skills/team-sprint-planner/references/plan-contract.md

### Acceptance Criteria
- The "Dependency graph" section states that under `hybrid`, an overlap pair already
  transitively ordered (either direction) in the effective graph gets **no** inferred edge,
  matching `build_graph.sh:16–22`; the unconditional "overlap and no declared edge → edge"
  wording is removed.
- The section states inferred-edge direction uses natural-key ordering of story ids
  (numeric-aware, `build_graph.sh:90–91`), not plain string comparison.
- The "Filename / path slug" section states the exact accept rule — filename contains a digit
  OR one of the prefixes `BUG-`, `EPIC-`, `bug-`, `epic-`, `sprint-`
  (`validate_plan_path.sh:71`) — and lists the full generic-name blacklist:
  `plan, story, stories, fix, fixes, untitled, readme, todo, tasks` (`:63`).
- The misleading "recognized id token (`mech-9`, `GS-4`, `1-23`)" wording is replaced with
  wording making clear those examples pass because they contain digits.

### Definition of Done
- Each statement above grep-verifiable in the updated doc; no remaining section contradicts it.
- Diff touches only `plan-contract.md` (no script changes).

## Story 2: Touches guidance + checklist gaps in planner docs

Fixes findings 1, 5, 6 (brace-glob trap; subtree overlap semantics; empty-Touches and
duplicate-id gaps). Touches the planner `SKILL.md` template and the contract doc.

### Depends On: none
### Touches: skills/team-sprint-planner/SKILL.md, skills/team-sprint-planner/references/plan-contract.md

### Acceptance Criteria
- The plan template's `### Touches:` guidance states: brace-expansion globs (e.g.
  `src/{a,b}/**`) must go on their own bullet line — the parser splits inline lists on
  commas/whitespace and shatters them (`parse_stories.sh:24–25`).
- The contract doc documents overlap semantics: two globs overlap when they share a
  path-component prefix (subtree rule, `build_graph.sh:104–111`); therefore over-broad globs
  like `src/**` serialize against everything under `src/` — declare the narrowest true globs.
- The contract doc states a story with empty `Touches` never receives inferred edges
  (`build_graph.sh:139`), so every story should declare its `Touches`.
- The self-verification checklist gains an item: story ids unique across the plan
  (duplicate id → `build_graph.sh` exit 2, `:72–73`).

### Definition of Done
- Statements grep-verifiable in both files.
- A concrete instantiation of the SKILL.md template — a scratch copy with the
  angle-bracket placeholders filled — parses through `parse_stories.sh` with the documented
  field shapes. The raw template is not parsed directly (placeholders are not valid plan
  content); the Story-3 golden fixture satisfies this check permanently once it exists.

## Story 3: Golden-template contract test in team-sprint

The mechanical drift lock (consumer-contract pattern): a fixture plan authored exactly per the
planner's documented template, driven through the real scripts by a new bats file. Future
parser/graph changes that break the documented template fail the suite at commit time.

### Depends On: none
### Touches: skills/team-sprint/scripts/**

### Acceptance Criteria
- A fixture plan exists under `scripts/fixtures/` (the existing fixtures dir every bats file
  references as `$FIX`; `scripts/tests/fixtures/` holds only `.gitkeep`) authored per the
  planner template:
  multi-story, `## Story <id>: <title>` headings, inline `### Depends On:` list, inline
  comma-separated `### Touches:` on one story, a brace-expansion glob on its own bullet line
  on another, digit-bearing filename.
- New `plan_contract.bats`: `parse_stories.sh` on the fixture yields the expected story ids,
  acceptance criteria, `depends_on[]`, and `touches[]` — the brace glob preserved verbatim.
- `validate_plan_path.sh` on the fixture filename returns `STATUS=OK`.
- `build_graph.sh` (hybrid) on the parsed fixture emits the expected integrated graph:
  declared edges authoritative, exactly one inferred conflict edge (lower natural-key id
  first), no inferred edges for the empty-`touches[]` node, acyclic topo order. This asserts
  the end-to-end result only — transitive-skip mechanics stay unit-covered by
  `build_graph.bats:104–144` and are not re-proved here.
- Full suite green via `scripts/tests/run-all.sh`; existing test files unmodified (additive only).

### Definition of Done
- `bats scripts/tests/plan_contract.bats` passes; `run-all.sh` passes.
- Fixture documented in the bats file header as the canonical template example.

## Story 4: Deduplicate plan-contract.md against authoritative sources

Shrinks the drift surface: each contract section names its source of truth and drops prose
that merely restates it; the golden fixture from Story 3 becomes the canonical example.

### Depends On: 1, 2, 3
### Touches: skills/team-sprint-planner/references/plan-contract.md

### Acceptance Criteria
- Each section of `plan-contract.md` names its authoritative source (script path + header
  lines) so a future reader checks the script, not the prose.
- Parser-leniency detail the planner never emits (`## NEW Story`, `### <id> amendment`
  headings, prose-AC joining) is reduced to a one-line "parser also accepts" note.
- The doc cites the Story-3 golden fixture as the canonical worked example **when
  team-sprint is installed alongside**; the doc's own inline template remains the
  standalone example, so no hard read-time dependency on the team-sprint install path is
  introduced (consistent with the efficiency note below).
- The standalone manual checklist is retained — the planner must remain usable when
  team-sprint is not installed.
- Final doc length ≤89 lines — its pre-plan length (`wc -l` = 89 at plan time). Stories 1–2
  add lines first; Story 4 reclaims the excess via the dedup.

### Definition of Done
- All referenced paths exist; doc reads standalone.
- No factual claim in the doc lacks either a source citation or coverage by the Story-3 test.

## Efficiency review — accepted duplications (no story)

- **graphify bootstrap** appears in both skills' docs but both delegate to the shared
  `scripts/graphify_ensure.sh` (whose header names both skills as callers) — the script is
  the dedup; prose stays.
- **`plan-path-convention.md` vs plan-contract.md** cover the same naming contract for
  different audiences (sprint lead vs plan author). Story 4 adds a cross-pointer; merging
  them would couple the planner to a team-sprint install path at read time.
- **Planner self-verify dogfooding of team-sprint validators** is intentional and stays —
  it is the cheap early copy of the Phase 0/2 gates.

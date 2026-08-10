# team-sprint plan contract

The exact rules `/team-sprint` uses to parse and validate a plan; violations STOP at Phase 0
or mis-parse at Phase 2. **Source of truth is team-sprint's code, not this prose** — each
section cites its governing script lines. When team-sprint is installed alongside,
`scripts/fixtures/golden-template-1.md` is the canonical worked example, locked to the
scripts by `scripts/tests/plan_contract.bats`; this skill's SKILL.md template remains the
standalone reference.

## Filename / path slug (`validate_plan_path.sh:61–75`)

- The filename **must contain a digit or one of the prefixes** `BUG-`, `EPIC-`, `bug-`,
  `epic-`, `sprint-` (`:71`). Ids like `mech-9`, `GS-4`, `1-23` pass because they contain
  digits — a digit-free name (`auth-refactor-mech.md`) fails.
- Blacklisted generic stems (`:63`): `plan`, `story`, `stories`, `fix`, `fixes`, `untitled`,
  `readme`, `todo`, `tasks` — each returns `STATUS=FAIL` with a rename hint.
- The slug keys the sprint's artifact dir (`.team-sprint/sprints/sprint-<slug>/`) — unique
  per plan. `STATUS=RESUME` = sprint for this exact plan exists; `STATUS=OK` = fresh.

Recommended: `docs/plans/<feature>-<id>.md`, e.g. `docs/plans/config-unify-9.md`.

## Multi-story vs single-story (auto-detected)

- **Multi-story**: one `## Story <id>: <title>` per story, each with its own
  `### Acceptance Criteria` + `### Definition of Done`. One commit per story.
- **Single-story**: no `## Story` headings → whole plan = one implicit story keyed by filename.

## Heading grammar (`parse_stories.sh:7–26`)

Per story it extracts:

| Field | Source heading | Notes |
| --- | --- | --- |
| `story_id` | `## Story <id>: <title>` | `<id>` is the token before the colon |
| `acceptance_criteria[]` | `### Acceptance Criteria` | bullet list under the heading |
| `definition_of_done[]` | `### Definition of Done` | bullet list under the heading |
| `depends_on[]` | `### Depends On:` | comma/whitespace-separated ids; `none` or absent → `[]` |
| `touches[]` | `### Touches:` | inline lists split on commas/whitespace — brace globs (`src/{a,b}/**`) go on their own bullet line or they shatter (`parse_stories.sh:24–25`) |

Heading levels matter: stories `##`, sub-sections `###`; wrong level → not parsed. (The
parser also accepts `## NEW Story` / `### <id> amendment` headings and prose AC/DoD —
leniencies the planner never relies on.)

## Dependency graph (`build_graph.sh`)

`build_graph.sh` synthesizes a DAG from the stories. Default `dependency_source: hybrid`:

- **Declared edges** from `### Depends On:` are authoritative.
- **Inferred edges**: two stories whose `### Touches:` globs overlap and that are **not
  already transitively ordered** (either direction) in the effective graph get an inferred
  conflict-ordering edge — lower `story_id` first by natural-key (numeric-aware) ordering.
  A pair already ordered via declared or earlier inferred edges gets no edge and no
  `inferred_deps[]` entry (`:16–22`).

The graph must be **acyclic** — the validator exits non-zero on a cycle, a self-edge, a
duplicate story id, or a `Depends On:` id not present in the plan (`:72–88`, `:174–196`). So:

- If two stories must be serialized but neither logically depends on the other, give them
  overlapping `Touches:` globs (or an explicit `Depends On:`) so the scheduler orders them.
- Overlap = shared path-component prefix (subtree rule, `:104–111`): `src/**` overlaps
  everything under `src/` and serializes against it — declare the narrowest true globs.
  A story with empty `Touches` never receives inferred edges (`:139`), so every story
  should declare its `Touches`.

## Acceptance criteria → tests

Phase 3 turns each AC into a RED test (TDD), so each must be observable and assertable: a
return value, a status code, an emitted error, a created file, a state change. Aspirational
ACs ("is robust") get flagged. Coverage gate: 80% on new code by default.

## Adversarial review (planner Phase 7)

Reviewers try to **refute** every concrete claim against the live codebase — nonexistent
code, self-contradictions, drift, impossible requirements, missing edge cases — looping
until zero accepted findings of any severity — every accepted CRITICAL/HIGH/MEDIUM/LOW is
applied, not just the blockers. Citation-backed claims survive; hence recon (SKILL.md phase 2).
The loop runs in THIS skill (see `adversarial-review-loop.md`), not in team-sprint. On exit
it stamps the plan on the line under the `#` title:

```
<!-- adversarial-review: status=<clean|user-override> rounds=<N> date=<YYYY-MM-DD> reviewer=team-sprint-planner -->
```

team-sprint's Phase 1 greps for that exact stamp and hard-STOPs any plan without it.

## Self-verification checklist (manual fallback)

Use when team-sprint's validators aren't installed to dogfood:

1. **Filename** has a digit or `BUG-`/`EPIC-`/`bug-`/`epic-`/`sprint-` prefix; not a generic stem.
2. **Each story** has `## Story <id>: <title>`, `### Acceptance Criteria`, `### Definition of Done`.
3. **Heading levels** correct: `##` stories, `###` sub-sections.
4. **ACs** are each testable/observable, not aspirational.
5. **Graph**: every `Depends On:` id exists; story ids unique; no self-edges; no cycles.
6. **Touches** declared on every story, narrowest true globs; brace globs on own bullet line.
7. **Grounding**: every codebase claim traces to a Read/Grep this session; unknowns stay open questions.
8. **Story size**: each is one coherent, independently testable commit.

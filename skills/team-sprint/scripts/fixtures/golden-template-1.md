# Golden template fixture — canonical planner-template plan

Canonical instantiation of the team-sprint-planner plan template
(team-sprint-planner/references/plan-contract.md). Consumed by
tests/plan_contract.bats, which drives it end-to-end through
parse_stories.sh -> validate_plan_path.sh -> build_graph.sh. Edit only
together with that test and the planner's contract doc.

## Story 1: Extend config loader

Touches a subtree via an inline comma-separated list.

### Depends On: none
### Touches: src/config/**, tests/test_config.py

### Acceptance Criteria
- Loading a malformed config raises `ConfigError` naming the offending key.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 2: Add config schema validation

Declared dependency on Story 1; touches inside the same subtree.

### Depends On: 1
### Touches: src/config/schema.py

### Acceptance Criteria
- `validate(schema)` rejects an unknown field with exit code 2.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 3: Wire schema into loader

Transitively ordered behind Story 1 via Story 2 — its overlap with Story 1
must NOT produce an inferred edge.

### Depends On: 2
### Touches: src/config/loader.py

### Acceptance Criteria
- Loader rejects configs failing schema validation before any file write.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 4: Format tooling refresh

Brace-expansion glob on its own bullet line, per the template rule.

### Depends On: none
### Touches:
- tools/{fmt,lint}/**

### Acceptance Criteria
- `tools/fmt/run --check` exits 0 on a clean tree.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 5: Formatter CLI flags

Incomparable overlap with Story 4 — expects exactly one inferred edge,
lower natural-key id (4) first.

### Depends On: none
### Touches: tools/fmt/cli.py

### Acceptance Criteria
- `--quiet` suppresses the summary line on success.

### Definition of Done
- Story tests green; typecheck + lint clean.

## Story 6: Update contributor docs

No Touches section — must receive no inferred edges.

### Depends On: none

### Acceptance Criteria
- CONTRIBUTING.md documents the fmt/lint workflow.

### Definition of Done
- Docs reviewed; links valid.

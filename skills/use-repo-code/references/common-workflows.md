## Common workflows

### A) Pre-implementation safety check

1. Parse task: "Add handler `POST /v1/foo`".
2. Grep pack for `POST /v1/foo` routes and `FooHandler`-style symbols.
3. If hit: report — "Handler exists at `<file>:<line>`. Extend, do not re-create."
4. If miss: verify layer/language correct, give green light.

### B) File-list verification (code review)

For every entry in a story's File List or PR file list:

1. Grep `<file path="path">` in the pack.
2. Confirm path exists and belongs to the layer the story names.
3. Flag orphaned entries and drift.

### C) Schema drift detection (multi-language shared contract)

When a schema definition (Zod / Pydantic / Protobuf / JSON Schema) changes:

1. Grep the pack for matching generated types in dependent languages.
2. Report regen needed or not.

### D) Multi-agent grounding

When invoked from a multi-agent skill (`/team-sprint`, `/bmad-party-mode`, etc.),
each subagent grepping the same pack file produces consistent, citation-grounded
opinions. The pack must be regenerated at sprint start so all agents work from the
same snapshot.

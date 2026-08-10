## Architecture & decisions

ADRs under `docs/adr/`. See `docs/adr/README.md` for numbering + tiebreaker.

- [ADR-001 — Sub-skill extension surface](docs/adr/001-subskill-extension-surface.md)

(Paths above are relative to the skill root, i.e. one level up from this reference/ file.)

### Why this skill exists

Consolidates the per-repo team-sprint skeleton (TDD → AC/DoD review → commit), parameterises stack-specific bits, and adds three gates: plan-review provenance before code (the adversarial review itself runs in `team-sprint-planner`; Phase 1 hard-STOPs an unstamped plan), a hard coverage gate, `pre-commit-review-fleet` over the full sprint diff at Phase 7 — all in an isolated git worktree, so a sprint can never poison the main tree and failed sprints stay inspectable + restartable.

**Review economics.** Per-story review is one AC/DoD reviewer (plus conditional UI validation) with mechanical test validation; security and performance are reviewed once per sprint by the Phase 7 fleet.

**Test economics.** Per-story phases run only the current story's tests, the full suite once at Phase 7 — see SKILL.md → **Per-story test scoping** under Cross-phase invariants.

# Plan quality bar

## What good looks like

- Filename carries a story-id slug; Phase 0 validator returns `STATUS=OK`.
- Every story parses: title, `### Acceptance Criteria`, `### Definition of Done` present; optional
  `### Depends On:` / `### Touches:` where relevant.
- ACs read as test assertions, not aspirations.
- The dependency graph is acyclic and reflects real file/interface coupling found in recon.
- Every concrete claim about the codebase is traceable to a Read/Grep from this session —
  nothing for the adversarial reviewers to refute.
- Every decision the plan encodes was put to the user in the grill phase and answered — the
  user confirmed shared understanding before decomposition began, and no grill answer was
  dropped on the floor.
- Stories are one-commit-sized and independently testable.
- The Phase 7 review loop ran to `status=clean` (or an explicit user override) and the plan
  carries the `<!-- adversarial-review: ... -->` provenance stamp under its title — team-sprint
  hard-STOPs without it.
- The Phase 8 dot-point read-back ran (`scripts/plan_readback.sh <plan-path>`) and its output
  was shown to the user **verbatim** — the user saw the plan as bullets, not prose.
- The Phase 8 diagram question was **asked via AskUserQuestion and answered** — a draw.io
  system-context diagram was emitted (how the plan fits the existing code: touched components,
  inputs, outputs, resulting behaviour — not a story dependency graph), or "diagram: declined"
  is in the report. Reporting done without asking is a process failure, not a shortcut.

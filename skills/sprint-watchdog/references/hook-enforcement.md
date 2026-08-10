# Optional: Hook-Based Enforcement — Detail

For projects that want mechanical enforcement, the same checks can be wired as Claude Code hooks in `.claude/settings.json`:

| Hook event | Matcher | Script | What it enforces |
|-----------|---------|--------|------------------|
| `UserPromptSubmit` | (any prompt) | `pre-sprint-gate.js` | On `/team-sprint` triggers, blocks if working tree dirty or branch is `main` / `dev` / detached. |
| `PreToolUse` | `Bash` | `pre-commit-qg.js` | If command is `git commit`, runs the project's quality gate; blocks on red. |
| `PreToolUse` | `TaskUpdate` | `verify-task-complete.js` | Blocks `status: completed` if predicted files missing OR a reviewer task's findings artifact (`$ART/reviews-*.md`) is missing or empty. |
| `PostToolUse` | `TaskCreate` | `track-task-create.js` | Mirrors task contract (role, predictedFiles, requiresReport) to a state file. |
| `PostToolUse` | `SendMessage` | `track-send-message.js` | Credits the node-executor `done`/`failed` signal per node id. Reviewer delivery is credited by artifact presence at `TaskUpdate` (row above), not by the message log. |

> These `.js` hook scripts are project-supplied; the contract each enforces is defined by the SKILL.md rows above. This skill edits only the contract, not any specific project's hook implementation.

Each project supplies its own hook scripts pointing at its quality-gate command. Common bypass envs (use sparingly):

- `SPRINT_WATCHDOG_SKIP_QG=1` — skip the quality gate for one commit (documented bypass only).
- `SPRINT_WATCHDOG_ALLOW_DIRTY=1` — allow sprint start on a dirty tree.
- `SPRINT_WATCHDOG_ALLOW_PROTECTED=1` — allow sprint start on a protected branch.

A typical state directory is `.claude/sprint-state/` (gitignored). Each task gets a JSON contract written at `TaskCreate` time and amended with delivery markers.

---
name: ac-validate
model: sonnet
context: fork
agent: general-purpose
description: Playwright-driven acceptance criteria validation for user stories against the running app. Use when the user asks to "validate acceptance criteria", "run AC validation", "check if ACs pass", "playwright validate", or "validate the sprint".
---

# AC Validate — Playwright-Driven Story Validation

Validate that completed user stories' acceptance criteria are correctly implemented
by testing the live application with Playwright. Produces a report a fix agent can use
to address any failures.

## Guard Rails

- This skill is READ-ONLY — do not modify any source code, configs, or story files. Modifications during validation corrupt the evidence trail and make FAIL reports unreliable for fix agents.
- Take a screenshot for every AC result (pass, fail, or blocked) — visual evidence is cheap and invaluable.

## When to Use

Reads a sprint backlog file, identifies completed UI-facing stories, and validates each
acceptance criterion against the running application using the /playwright-cli skill.
Generates a structured report a fix agent can act on.

- After a sprint completes and you want to verify the UI matches the stories
- When the user points at a `*-backlog.md` file and wants AC validation
- Before marking a sprint as truly "done" — this is the QA gate
- Also trigger on "test the UI against stories", "verify stories are implemented",
  "check the UI", or "are the stories done", or when the user mentions validating a
  backlog file against the live app

## Arguments

- `{backlog-file}` — path to a `*-backlog.md` file (e.g., `docs/stories/feature-x-backlog.md`)
- `{story-file}` — path to a single story file. Validates this story directly, bypassing backlog parsing and status filtering. Use this mode when invoking from `/team-sprint` Phase 4 where the story is still in-progress.

## Workflow

### Phase 1: Parse the Input

**Mode A — Backlog file** (argument ends in `*-backlog.md`):
1. Read the backlog file provided by the user
2. Extract the story list — each row links to a story file
3. For each story, read the story file from the same directory as the backlog
4. Filter to stories with `**Status:** done` — skip stories with other statuses
5. If no stories have status "done", report this and stop

**Mode B — Single story file** (any other `.md` file):
1. Read the story file directly — no backlog parsing, no status filtering
2. This mode exists for `/team-sprint` integration where the story is still in-progress
3. Treat this single story as the full validation scope
4. Report output path uses the story filename: `docs/playwright_cli_US_validate/{story-id}-report.md`

### Phase 2: Classify Acceptance Criteria

For each story, read its Acceptance Criteria section and classify each AC:

**UI-testable** — visible/interactive in the browser:
- Element visibility, text content, layout
- User interactions (click, type, select, navigate)
- Visual state changes (loading, error, success)
- Component rendering, routing, navigation
- Keyboard shortcuts that produce visible results

**Backend-only** — server-side only:
- Method signatures, return values, error types
- File system operations
- Mutex/concurrency behavior
- Event emission (unless the UI reacts visibly)
- Data encoding, MIME types

**Mixed** — both backend and frontend. Test only the frontend-observable assertion.

### Phase 3: Start the Application

Verify the `/playwright-cli` skill is available. If missing, fall back to Playwright MCP tools directly.

Detect how to start the dev server. Look for a `dev` script in `package.json`, a `dev` recipe in `justfile`/`Makefile`, or a project-specific docs entry. Common patterns:

| Stack | Command | Default URL |
|-------|---------|-------------|
| Vite/Next/React | `npm run dev` (or `bun dev`/`pnpm dev`) | `http://localhost:3000` or `5173` |
| Wails desktop | `wails dev` | `http://localhost:34115` |
| Expo web | `npx expo start --web` | `http://localhost:8081` |

If you can't infer it, ask the user.

1. Check if dev server is already running on the expected port: `curl -s <url> > /dev/null 2>&1`
2. If not running, start it as a background process; record the PID
3. Wait for the app to be ready (poll `curl` every 2 seconds, timeout 60s)
4. If it doesn't start, report the error and stop

If the server was already running, don't kill it at the end. If the skill started it, offer to stop it when done.

### Phase 4: Validate UI-Testable ACs

For each story with UI-testable ACs, invoke `/playwright-cli` to validate.

The validation loop for each AC:

1. **Invoke `/playwright-cli`** for browser automation
2. **Navigate** to the relevant page (infer from AC context)
3. **Set up state** if the AC requires specific conditions
4. **Assert** — take a snapshot, check elements/text/behavior
5. **Screenshot** as evidence
6. **Record**: PASS, FAIL, or BLOCKED

For FAIL results, capture diagnostic information for the fix agent:
- Expected vs actual
- Page snapshot (DOM state) at failure
- Screenshot path
- CSS selectors / element references checked
- Console errors (use `browser_console_messages`)
- Exact AC text that failed

For BLOCKED results, explain why test state couldn't be set up.

### Phase 5: Generate the Report

Write the report to `docs/playwright_cli_US_validate/{backlog-name}-report.md` (Mode A) or `{story-id}-report.md` (Mode B). Create the directory if needed.

Use the report template in [`references/report-template.md`](references/report-template.md) — it defines exact structure for PASS, FAIL, BLOCKED, and BACKEND-ONLY sections.

### Phase 6: Wrap Up

1. Save the report
2. Print summary table to user
3. If skill started the dev server, ask if user wants to stop it
4. If FAILs exist, recommend a fix agent with the report path

## Screenshot Storage

Save screenshots to `docs/playwright_cli_US_validate/screenshots/{story-id}/`:
- `{story-id}_AC{N}_pass.png`
- `{story-id}_AC{N}_fail.png`

## Error Handling

- If `/playwright-cli` is not available, fall back to Playwright MCP tools
- If app crashes during validation, log the AC, restart, continue
- If a single AC validation times out (>30s), mark BLOCKED and move on
- Network errors → retry once, then BLOCKED

## Inter-agent Communication

If invoked as part of a multi-agent sprint (e.g., from `/team-sprint`), write the report
file, then deliver its path and verdict in the structured final return — that return is
the delivery. Use `SendMessage` only when the recipient is not the spawner (per CLAUDE.md
and the team-sprint SendMessage protocol).

## Developer Notes

- Read each story's **Developer Notes** section — file paths and context enrich FAIL reports
- The report format is machine-parseable — keep it consistent for automated fix workflows

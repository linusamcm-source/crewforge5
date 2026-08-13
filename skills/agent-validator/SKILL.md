---
name: agent-validator
model: sonnet
context: fork
agent: general-purpose
description: Grades a .claude/agents/*.md file pass/fail; agent-rectifier auto-fixes below grade A. Use on "validate an agent", "check my agent", "audit an agent", "debug this agent", or an agent misbehaving
disable-model-invocation: true
---

# Agent Validator

Validates a target agent definition through five phases: structural integrity, tool coherence,
efficiency analysis, instruction compliance diagnosis, and behavioral simulation. Produces a
graded report saved to `./docs/agent_reports/`.

## When to use

Also trigger on "test if my agent works", "verify agent quality", "why isn't my agent working",
"agents aren't following instructions", or when the user wants to ensure an agent definition is
production-ready, or reports that an agent behaved inconsistently. Produces a structured
pass/fail report with actionable fixes. Part of the agent-validator / agent-rectifier
self-healing loop — if the grade is below A, the agent-rectifier is automatically invoked to
fix all issues without user confirmation.

## Why This Exists

Agent definitions are deceptively simple — a single markdown file with frontmatter and
instructions. But small issues cascade into large behavioral problems: a missing tool
declaration means the agent silently can't perform actions it's told to; a vague role statement
causes the agent to improvise its identity; buried instructions get ignored. This validator
catches these problems before they reach production.

## What Makes Agents Different from Skills

Skills are directories with SKILL.md + bundled resources. Agents are single `.md` files in
`.claude/agents/` with this structure:

```yaml
---
name: agent-name
description: "When to invoke this agent and what it does"
tools: Read, Write, Edit, Bash, Glob, Grep  # tools the agent can access
color: blue  # UI color identity
---

# Body: role statement, workflows, instructions, completion gates
```

Key validation concerns unique to agents:
- **Tool declaration completeness** — an agent can only use tools listed in `tools:`. If instructions reference `Bash` but `tools:` omits it, the agent silently fails.
- **Description triggering** — the description determines when the Agent tool spawns this agent type. Poor descriptions mean the agent never gets invoked.
- **Role framing** — agents perform dramatically better with a clear identity statement ("You are a senior Go developer...") in the first lines of the body.
- **Completion gates** — without exit criteria, agents report tasks as done prematurely.
- **Context budget** — the entire agent file loads into context every invocation. Bloated agents waste tokens on every spawn.

## Workflow

### Step 0: Identify the Target Agent

Determine which agent to validate. The user will provide one of:
- A path to an agent file (e.g., `.claude/agents/golang-pro.md`)
- An agent name (search `.claude/agents/` for it)
- "this agent" or "the one I just made" (use the most recently modified agent file)

Confirm the path with the user before proceeding.

### Step 1: Structural Validation

Run the bundled validation script for mechanical checks:
```bash
bash ${CREWFORGE_ROOT}/skills/agent-validator/scripts/validate_agent.sh <agent-file-path>
```

Then supplement with these manual checks:

**Required (FAIL if missing):**
- Agent `.md` file exists
- YAML frontmatter present (delimited by `---` lines)
- `name` field present and non-empty
- `description` field present and non-empty
- Body content (below frontmatter) is non-empty

**Structural integrity (WARN or FAIL):**
- `name` matches the filename (e.g., `golang-pro.md` should have `name: golang-pro`) (WARN)
- No sensitive content in the file (API keys, tokens, credentials) (FAIL)
- File is located in `.claude/agents/` directory (WARN if elsewhere)

**Frontmatter quality (WARN):**
- Description is substantive (> 30 words) — short descriptions cause undertriggering
- Description includes trigger contexts ("Use when...", "Use this agent whenever...")
- Description includes `<example>` blocks showing user/assistant/commentary interaction patterns — these dramatically improve triggering accuracy
- `tools` field is present and non-empty
- `color` field is present — gives the agent visual identity in UI

### Step 2: Tool Coherence Validation

This is unique to agents and catches one of the most common silent failures. Check declared vs
referenced tools, referenced skills on disk, and subagent-spawning coherence.

Full check tables: [references/validation-checks.md](references/validation-checks.md) — load once before running Steps 2-5.

### Step 3: Efficiency Analysis

Agent files load entirely into context on every invocation. Efficiency matters more here than
for skills because agents may be spawned many times per session. Check size metrics, content
bloat, and instruction quality.

Check tables: [references/validation-checks.md](references/validation-checks.md) — load before running this step.

### Step 4: Instruction Compliance Diagnosis

Identifies why the agent might not follow its own instructions at runtime. Sub-steps:

1. **4a Instruction Extraction** — extract every concrete instruction; categorize as Critical / Quality / Guard.
2. **4b Failure Mode Analysis** — evaluate each critical instruction against the seven failure modes.
3. **4c Compliance Test Matrix** — build the instruction vs failure-mode matrix; mark each cell OK / WARN / FAIL.
4. **4d Generate Fixes** — write a specific fix for every WARN or FAIL cell.

Category definitions, the seven failure modes, matrix format, and fix patterns: [references/validation-checks.md](references/validation-checks.md) — load before running this step.

### Step 5: Behavioral Simulation

Test whether the agent's instructions actually produce correct behavior: generate 2-3 realistic
trigger prompts, spawn a test agent that adopts the definition and self-reports compliance,
evaluate against the Step 4a instruction list, and record results.

Test procedure and spawn-prompt template: [references/validation-checks.md](references/validation-checks.md) — load when running this step.

If subagents are not available, skip this step and note it as SKIPPED.

### Step 6: Generate Report

Write a structured markdown report to `./docs/agent_reports/agent-validation-{agent-name}-{date}.md`.

Full report template, including summary table and grade scale: [references/report-template.md](references/report-template.md) — load when writing the report.

### Step 7: Auto-Rectify Until Grade A

Show the user the summary table and overall grade. Then:

1. **If grade is A** (all pass, 0-2 warnings): the agent is production-ready. Stop here.

2. **If grade is below A** (B, C, D, or F): automatically hand off to **agent-rectifier**
   with this validation report and the target agent path. It is hidden from the catalogue,
   so the `Skill` tool cannot reach it — resolve it with
   `bash "${CREWFORGE_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode agent-rectifier`
   and honour the answer (`MODE=inline` — read the body and follow it here).
   Do not ask the user for confirmation — this is mandatory. The rectifier applies fixes
   and then re-runs this validator for full re-validation. This creates a self-healing
   loop:

   ```
   agent-validator finds issues → agent-rectifier fixes them → agent-validator re-checks → repeat
   ```

   The loop continues until grade A is achieved. The only exit conditions are:
   - Grade A reached (success)
   - A rectification round produces zero fixable issues and all remaining items need
     human judgment (escalate to user with clear explanation)

3. After the loop completes, present the final grade A confirmation with the total number
   of rounds and fixes applied.

The agent-rectifier is at `${CREWFORGE_ROOT}/skills/agent-rectifier/` — it handles the full fix
workflow including before/after diffs and deferred items that need human review.

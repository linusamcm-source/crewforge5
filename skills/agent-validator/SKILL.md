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

Create the findings ledger first — every later step, scripts and your own judgment findings
alike, appends to it, and Step 6's grade is computed from it mechanically:

```bash
LEDGER=$(mktemp)
bash ${CREWFORGE5_ROOT}/skills/agent-validator/scripts/validate_agent.sh <agent-file-path> | tee -a "$LEDGER"
```

Treat the script's FAIL/WARN lines as findings verbatim — do not re-derive them by hand. Its
`INFO` lines never count toward the grade; they are there to be read, not scored.

Then supplement with these manual checks, appending each finding to the ledger in the prose
form `echo 'WARN [structural]: ...' >> "$LEDGER"`:

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
- Description includes trigger contexts ("Use when...", "Trigger on...") in phrasing a user
  would plausibly type — trigger phrases are the one part that must never be trimmed away
- Description stays at trigger phrases plus one line of purpose. It is always-loaded rent:
  it renders into the catalogue every session whether or not the agent is ever spawned, and
  an agent has no `disable-model-invocation` escape the way a hidden skill does. Never
  recommend padding a description to hit a word count, and never recommend adding
  `<example>` blocks for their own sake — an expressive description carries the same
  semantics for a fraction of the cost. `${CREWFORGE5_ROOT}/scripts/budget_check.sh` charges this exact string
  against the release gate, so a longer description can turn CI red.
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

Then apply the `context-hygiene` principles as judgment checks — judge the file against the
principle, do not pattern-match for keywords:

- **Judgment over rules.** Is the agent constrained where judgment would serve better? Rules
  written to compensate for a weaker model are the target. Guards on irreversible or costly
  actions are not — the script exempts them from the directive tally and reports them as
  `directive_safety_exempt`; never propose softening one.
- **One home over repetition.** Does anything the agent states already have an authoritative
  home in CLAUDE.md, a rules file, or a skill the agent loads anyway? Restated guidance drifts
  apart from its source; point at the home instead of copying it.
- **Progressive disclosure.** Detail the agent needs only occasionally belongs behind a
  reference the agent reads on demand, not inline in a file that loads on every spawn.
- **Auto-memory over prose state.** Facts about the user or the work (preferences, dates,
  decisions) sitting as prose in the agent body belong in the memory system.
- **Rich references over prose specs.** Where the agent steers a build with a markdown
  description, a higher-fidelity reference — a function signature, a test suite, a rubric —
  is worth more per token.

What never gets flagged for removal: security and irreversible-action guards, genuine repo
gotchas, exact commands, versions and error strings, and the description's trigger phrases.

Check tables: [references/validation-checks.md](references/validation-checks.md) — load before running this step.

### Step 4: Instruction Compliance Diagnosis

Identifies why the agent might not follow its own instructions at runtime. Sub-steps:

1. **4a Instruction Extraction** — extract every concrete instruction; categorize as Critical / Quality / Guard.
2. **4b Failure Mode Analysis** — evaluate each critical instruction against the seven failure modes.
3. **4c Compliance Test Matrix** — build the instruction vs failure-mode matrix; mark each cell OK / WARN / FAIL.
4. **4d Generate Fixes** — write a specific fix for every WARN or FAIL cell.

Category definitions, the seven failure modes, matrix format, and fix patterns: [references/validation-checks.md](references/validation-checks.md) — load before running this step.

Append every WARN/FAIL cell from the matrix to the ledger in the same form
(`echo 'FAIL [compliance]: ...' >> "$LEDGER"`) so it counts toward the grade.

### Step 5: Behavioral Simulation

Test whether the agent's instructions actually produce correct behavior: generate 2-3 realistic
trigger prompts, spawn a test agent that adopts the definition and self-reports compliance,
evaluate against the Step 4a instruction list, and record results.

Test procedure and spawn-prompt template: [references/validation-checks.md](references/validation-checks.md) — load when running this step.

Append each skipped or misinterpreted instruction to the ledger
(`FAIL [simulation]: ...` / `WARN [simulation]: ...`). If subagents are not available, append
`SKIPPED [simulation]: no subagents` and move on — a SKIPPED phase does not block grade A,
but must be listed next to the grade.

### Step 6: Generate Report

Compute the grade mechanically — never tally or grade by hand:

```bash
bash ${CREWFORGE5_ROOT}/skills/skill-validator/scripts/grade.sh "$LEDGER"   # grade= fails= warns= skipped=
```

`grade.sh` is shared with `skill-validator` rather than copied: one scale, one home, no drift.
It counts both the scripts' JSON findings and the prose lines you appended.

Write a structured markdown report to `./docs/agent_reports/agent-validation-{agent-name}-{date}.md`
(create the directory first: `mkdir -p ./docs/agent_reports`). Include the `grade.sh` output
block and the full ledger verbatim — the rectifier parses them.

Full report template, including summary table and grade scale: [references/report-template.md](references/report-template.md) — load when writing the report.

### Step 7: Auto-Rectify Until Grade A

**Report-only mode:** if this validation was invoked by agent-rectifier as a re-validation
round (the invoking prompt contains "report-only" or "re-validation"), stop after Step 6.
Return the report path and overall grade, and do not invoke agent-rectifier — the rectifier
already owns the fix-and-revalidate loop, and invoking it from here nests a second loop
inside the first.

Otherwise, show the user the summary table and overall grade. Then:

1. **If grade is A** (all pass, 0-2 warnings): the agent is production-ready. Stop here.

2. **If grade is below A** (B, C, D, or F): automatically hand off to **agent-rectifier**
   with this validation report and the target agent path. It is hidden from the catalogue,
   so the `Skill` tool cannot reach it — resolve it with
   `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode agent-rectifier`
   and honour the answer (`MODE=inline` — read the body and follow it here).
   Do not ask the user for confirmation — this is mandatory. Pass on one condition with the
   report: any fix that makes the agent file **shorter** must clear the retention gate
   before it is applied, because a trim is measured by how much shorter it got and the
   lines worth the most tokens are usually the ones worth keeping:

   ```bash
   bash "${CREWFORGE5_ROOT}/scripts/retention_gate.sh" <agent-file> /tmp/agent-proposed.md
   ```

   It fails the proposal if any `never`/`always`/`must` line, backticked command, path,
   version or quoted error string stopped appearing anywhere. It reads two files and
   returns a verdict; it cannot edit, so the decision stays with the rectifier.

   Hand off **exactly once**. **The rectifier owns the loop from here**: it applies fixes,
   re-runs this validator in report-only mode, and repeats until grade A or escalation. Do
   not re-enter this step after handing off, and do not duplicate the loop logic here.

3. After the loop completes, present the final grade A confirmation with the total number
   of rounds and fixes applied.

The agent-rectifier is at `${CREWFORGE5_ROOT}/skills/agent-rectifier/` — it handles the full fix
workflow including before/after diffs and deferred items that need human review.

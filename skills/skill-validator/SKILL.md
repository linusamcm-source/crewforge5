---
name: skill-validator
model: sonnet
context: fork
agent: general-purpose
description: Grades a Claude Code skill structurally and behaviourally, with fixes. Use on "validate a skill", "audit a skill", "check if my skill works", "why isn't my skill working"
disable-model-invocation: true
---

# Skill Validator

Validates a target skill through five phases: structural integrity, functional correctness,
efficiency analysis, instruction compliance diagnosis, and agent simulation. Produces a
graded report saved to `./docs/agent_reports/`.

## When to use

Also use when the user asks to "test a skill", "verify skill quality", "debug this skill",
or says "agents aren't following the skill"; when a user reports that an agent ignored
skill instructions, produced wrong output, or didn't trigger the skill at all; or when the
user wants to ensure a skill is production-ready.

## Why Each Phase Matters

Skills fail silently. An agent that ignores a skill instruction doesn't throw an error — it
just does the wrong thing. The most common failures aren't structural (missing files) but
behavioral: the agent triggers the skill but doesn't follow key instructions, or the skill
loads but its instructions are ambiguous enough that the agent improvises. This validator
catches both categories.

## Workflow

### Step 0: Identify the Target Skill

Determine which skill to validate. The user will provide one of:
- A path to a skill directory (e.g., `$CLAUDE_CONFIG_DIR/skills/my-skill/`)
- A skill name (search `$CLAUDE_CONFIG_DIR/skills/` and `.claude/skills/` for it)
- "this skill" or "the one I just made" (use the most recently modified skill directory)

State the resolved path explicitly before proceeding; if multiple candidates match,
pick the most recently modified one and record that assumption in the report.

### Step 1: Structural Validation

Create the findings ledger first — every phase (scripts AND your own judgment findings)
appends `FAIL [phase]: ...` / `WARN [phase]: ...` / `SKIPPED [phase]: ...` lines to it,
and Step 7's grade is computed from it mechanically:

```bash
V="${CREWFORGE5_ROOT}/skills/skill-validator/scripts"
LEDGER="$(mktemp "${TMPDIR:-/tmp}/skill-validator-ledger.XXXXXX")"; echo "LEDGER=$LEDGER"
bash "$V/validate_structure.sh" <target-skill-path> | tee -a "$LEDGER"
bash "$V/baseline-drift.sh"     <target-skill-path> | tee -a "$LEDGER"
```

Each Bash call is a fresh shell: `$V` and `$LEDGER` do not survive between tool
calls. Note the `LEDGER=` path this step prints and substitute it literally
wherever a later step says `"$LEDGER"`; redefine `V` the same way in each block.

`validate_structure.sh` covers the mechanical checks: SKILL.md existence, frontmatter
fields, name format and directory match, description length, body/size limits,
referenced-file existence, orphan files, sensitive filenames, directory conventions,
script executability/shebang/syntax, and directive count. `baseline-drift.sh` checks the
skill against its token-slim baseline entry when one exists (drift = WARN; the fix may be
refreshing the baseline, not reverting the skill). Treat their FAIL/WARN lines as findings
verbatim — do not re-derive them by hand.

Then supplement with the checks that need judgment:

**Frontmatter quality (WARN):**
- Description includes trigger contexts ("Use when...", "Trigger on...") and realistic
  user phrases
- No stale/placeholder text in name or description
- `context: fork` is only used for autonomous report-producing skills — a skill with an
  interactive loop or user questions must stay inline (FAIL if violated)

**Manual follow-ups on script output:**
- For any `suspect_filenames` WARN, read the flagged files and confirm they contain no
  real secrets (upgrade to FAIL if they do)
- Skim referenced paths outside `scripts/`/`references/`/`assets/` (absolute paths,
  cross-skill references) and spot-check that they exist — the script skips these

### Step 2: Functional Validation

```bash
V="${CREWFORGE5_ROOT}/skills/skill-validator/scripts"
bash "$V/functional.sh" <target-skill-path> | tee -a "$LEDGER"
```

Covers what the structural script didn't: Python import/dependency dry-runs and
`references/` validity (non-empty, JSON/YAML parseable, long files have section headers).
Script output is canonical — do not re-count by hand. What stays yours: actually reading
a sampled reference file to confirm it's navigable and current.

### Step 3: Efficiency Analysis

```bash
V="${CREWFORGE5_ROOT}/skills/skill-validator/scripts"
bash "$V/efficiency.sh" <target-skill-path> | tee -a "$LEDGER"
```

Emits the size/token metrics, directive counts, and progressive-disclosure findings
(large inline blocks/tables) mechanically — counting is the script's job, not yours.
What stays yours: judging whether inline content the script flagged is genuinely
conditional (move it) or always-executed (keep it). Check definitions for Steps 2-3
live in [references/check-tables.md](references/check-tables.md) — the scripts implement
them; load only if you need the rationale.

### Step 4: Instruction Compliance Diagnosis

This phase identifies why agents might not follow the skill's instructions. It's the
difference between a skill that looks correct and one that actually works in practice.

#### 4a: Instruction Extraction

Read SKILL.md and extract every concrete instruction — things the agent is told to do,
produce, or avoid. Categorize each as:
- **Critical**: Instructions that define the skill's core purpose (output format, workflow steps, required actions)
- **Quality**: Instructions that improve output but aren't essential (style, naming, explanations)
- **Guard**: Instructions that prevent bad behavior (don't edit files, don't skip steps)

#### 4b: Failure Mode Analysis

For each critical instruction, evaluate the seven common failure modes: ambiguity, buried
instructions, conflicting instructions, missing "why", scope overload, implicit
assumptions, and output format drift. Detailed criteria per mode:
[references/check-tables.md](references/check-tables.md) — load before running this step.

#### 4c: Compliance Test Matrix

Build a matrix of critical instructions vs. failure modes and mark each cell OK,
WARN (might fail), or FAIL (likely to fail). Example matrix:
[references/check-tables.md](references/check-tables.md) — load when building the matrix.

#### 4d: Generate Fixes

For each WARN or FAIL in the compliance matrix, write a specific fix:
- Rewrite ambiguous instructions with concrete examples
- Move buried instructions to prominent positions
- Resolve conflicts by picking one approach and removing the other
- Add rationale to instructions missing "why"
- Split overloaded skills into focused sub-skills or phases
- Replace implicit assumptions with explicit statements
- Add output templates where format is underspecified

**Don't just report problems** — record each fix concretely; Step 7's rectifier loop applies them automatically.

Append every WARN/FAIL cell from the matrix to the ledger in the same format
(`echo 'FAIL [compliance]: ...' >> "$LEDGER"`) so it counts toward the grade.

### Step 5: Agent Simulation

The most important test — does the skill actually work when an agent uses it?

1. **Extract or generate test prompts**: Look for test cases in the skill directory (`evals/`, `tests/`). If none exist, generate 2-3 realistic user prompts based on the skill's description.

2. **Spawn a test agent**: Launch a subagent with the skill loaded, asked to complete the task and self-report which instructions it followed, skipped, or found confusing. Exact prompt template: [references/check-tables.md](references/check-tables.md) — load before spawning.

3. **Evaluate compliance**: Compare the agent's self-report against the instruction list from Step 4a:
   - Which critical instructions were followed? (PASS)
   - Which were skipped? (FAIL — investigate why)
   - Which were misinterpreted? (WARN — instruction needs rewriting)
   - Did the agent add steps not in the skill? (WARN — skill may be underspecified)

4. **Record**: prompt, instructions followed/skipped/misinterpreted, output quality, time
   — and append each skipped/misinterpreted instruction to the ledger
   (`FAIL [simulation]: ...` / `WARN [simulation]: ...`).

Subagents are unavailable only when the `Agent` tool is absent from your own tool
list — that is the test, not an impression of the environment. When it is absent,
append `SKIPPED [simulation]: no subagents` to the ledger and move on.

### Step 6: Generate Report

Compute the grade mechanically — never tally or grade by hand:

```bash
V="${CREWFORGE5_ROOT}/skills/skill-validator/scripts"
bash "$V/grade.sh" "$LEDGER"    # grade= fails= warns= skipped=
```

Write a structured markdown report to `./docs/agent_reports/skill-validation-{skill-name}-{date}.md`
(create the directory first: `mkdir -p ./docs/agent_reports`). Include the grade.sh
output block and the full ledger verbatim in the report — the rectifier parses them.
Full report template: [references/report-template.md](references/report-template.md) —
load when writing the report.

### Step 7: Present and Hand Off to the Rectifier

**Report-only mode:** if this validation was invoked by skill-rectifier as a
re-validation round (the invoking prompt contains "report-only" or "re-validation"),
stop after Step 6. Return the report path and overall grade, and do NOT invoke
skill-rectifier — the rectifier already owns the fix-and-revalidate loop, and invoking
it from here would nest a second loop inside the first. If you cannot tell whether
the rectifier invoked you, do not hand off — end with the report. And never hand off
when the target is skill-validator, skill-rectifier, agent-validator or
agent-rectifier itself: a rectifier editing the loop it is executing is not
recoverable, so those four are always report-only.

Otherwise, show the user the summary table and overall grade. Then:

1. **If grade is A** (all pass, 0-2 warnings): state plainly that the skill is
   production-ready. A SKIPPED phase (e.g., agent simulation without subagents) does not
   block grade A, but must be listed next to the grade. Stop here.

2. **If grade is below A** (B, C, D, or F): hand off to **skill-rectifier** exactly once,
   passing the validation report path and the target skill path. It is hidden from the
   catalogue, so the `Skill` tool cannot reach it — resolve it with
   `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode skill-rectifier`
   and honour the answer (`MODE=inline` — read the body and follow it here).
   Do not ask the user — this is mandatory. **The rectifier owns the loop
   from here**: it applies fixes, re-runs this validator in report-only mode, and
   repeats until grade A, a 5-round cap, or escalation. Do not re-enter this step after
   handing off, and do not duplicate the loop logic here.

**Why grade A, not B:** A skill below grade A will cause agents to behave inconsistently.
The bar is "production-ready" — 0 failures, 0-2 warnings, as computed by grade.sh from
the ledger (the full scale lives in grade.sh's header). The model never rounds a grade:
if your prose summary and grade.sh disagree, grade.sh wins. Warnings that persist through
multiple rounds indicate instructions that genuinely need human judgment, at which point
the rectifier escalates rather than spinning forever.

The skill-rectifier is at `${CREWFORGE5_ROOT}/skills/skill-rectifier/` — it handles the full
fix workflow including before/after diffs, the re-validation loop, and deferred items
that need human review.

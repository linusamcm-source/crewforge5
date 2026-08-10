# Per-Category Check Tables (Steps 2-5)

Detailed check lists for Steps 2-5 of the skill-validator workflow. Load the section for the step you are executing.

**Note:** the Step 2 and Step 3 tables are now implemented mechanically by
`scripts/functional.sh` and `scripts/efficiency.sh` — script output is canonical.
These sections remain as the definition of what those scripts check.

## Step 2 checks: Functional Validation

**Scripts (`scripts/` directory):**
For each script found:
- Check file is executable (`chmod +x` permission)
- Check for proper shebang line (`#!/usr/bin/env python3`, `#!/bin/bash`, etc.)
- For Python scripts: run `python3 -c "import ast; ast.parse(open('SCRIPT').read())"` to verify syntax
- For shell scripts: run `bash -n SCRIPT` to check syntax
- For Python scripts: attempt a dry-run import check with 5s timeout to catch missing deps
- Record: script name, executable status, syntax check result, import check result

**References (`references/` directory):**
- Each reference file should be valid (non-empty, parseable if JSON/YAML)
- Large reference files (> 300 lines) should have a table of contents or section headers

## Step 3 checks: Efficiency Analysis

**Size metrics:**
- Count SKILL.md total lines and estimate tokens (~0.75 tokens per word)
- Flag if SKILL.md exceeds 500 lines (WARN) or 1000 lines (FAIL)
- Sum total skill directory size (all files)

**Progressive disclosure:**
- Content that could live in `references/` but is inline in SKILL.md (WARN if large code blocks or data tables > 50 lines are inline)
- Reference files loaded eagerly instead of on-demand

**Instruction quality (heuristic checks):**
- Count heavy-handed directives (MUST, ALWAYS, NEVER, IMPORTANT in all-caps)
- Flag if > 10 such directives (WARN — explaining "why" is more effective)
- Check for imperative voice (good) vs passive constructions (less effective)
- Look for explained rationale ("because", "this matters because", "the reason is")

## Step 4b checks: Failure Mode Analysis

For each critical instruction, evaluate these common failure modes:

**1. Ambiguity** — Can the instruction be interpreted multiple ways?
- Bad: "Format the output nicely" (what does "nicely" mean?)
- Good: "Format output as a markdown table with columns: Name, Status, Score"
- Check: Does the instruction specify exact format, file paths, or expected values?

**2. Buried instructions** — Is the instruction easy to miss?
- Instructions buried deep in a long SKILL.md (past line 200) get less attention
- Instructions inside code blocks, nested lists, or footnotes are easily skipped
- Check: Are critical instructions near the top, in headers, or visually prominent?

**3. Conflicting instructions** — Does the skill contradict itself?
- "Always use typed structs" but later "Return a map[string]interface{} for flexibility"
- Check: Search for instructions that say opposite things about the same topic

**4. Missing "why"** — Does the agent understand the purpose?
- Instructions without rationale get deprioritized when they conflict with the agent's defaults
- "Use log.Printf not fmt.Printf" is weaker than "Use log.Printf because fmt.Printf doesn't include timestamps, which makes production debugging impossible"
- Check: Do critical instructions explain their reasoning?

**5. Scope overload** — Is the skill trying to do too much?
- Skills with 20+ instructions across 5+ different workflows overwhelm the agent
- The agent will follow the first few instructions well and start improvising on the rest
- Check: Can the skill's instructions be summarized in 3-5 core rules?

**6. Implicit assumptions** — Does the skill assume context the agent won't have?
- "Use the standard project layout" (what standard? which project?)
- "Follow the existing patterns" (the agent may not have read those patterns)
- Check: Would a brand-new agent with no prior context understand every instruction?

**7. Output format drift** — Is the expected output underspecified?
- If the skill says "generate a report" but doesn't show the exact template, every agent will produce a different format
- Check: Is there a concrete example or template for every output the skill produces?

## Step 4c example: Compliance Test Matrix

| Instruction | Ambiguity | Buried | Conflict | Missing Why | Overload | Implicit | Drift |
|-------------|-----------|--------|----------|-------------|----------|----------|-------|
| "Save report to docs/" | Clear | Line 45 | None | None | - | Clear path | Template provided |
| "Run validation script" | Clear | Line 12 | None | None | - | Assumes script exists | - |

Mark each cell as: OK, WARN (might fail), FAIL (likely to fail)

## Step 5: test-agent prompt template

2. **Spawn a test agent**: Launch a subagent with the skill loaded. The prompt should be:
   ```
   You have access to the skill at <path>. Read it and use it to accomplish this task:
   <test prompt>
   Save all outputs to <workspace>/test-outputs/
   After completing the task, write a brief summary of:
   - Which skill instructions you followed
   - Which instructions you skipped or couldn't follow (and why)
   - Any instructions that were confusing or ambiguous
   ```

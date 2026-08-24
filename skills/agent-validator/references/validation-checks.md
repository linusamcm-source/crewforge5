# Agent Validator — Check Tables (Steps 2-5)

Load this file when executing Steps 2-5 of the agent-validator workflow. Content relocated
verbatim from SKILL.md.

## Step 2: Tool Coherence Validation

**Tool declaration analysis:**
1. Parse the `tools:` field from frontmatter into a list of declared tools
2. Scan the body for every tool reference — look for tool names (Read, Write, Edit, Bash, Glob, Grep, Agent, Skill, TaskCreate, etc.) mentioned in instructions
3. For each tool referenced in instructions but NOT in the `tools:` declaration: **FAIL** — the agent will be told to use a tool it cannot access
4. For each tool in the `tools:` declaration but never referenced in instructions: **WARN** — unnecessary tool access wastes the permission budget

**Skill invocation analysis:**
- Scan for `/skill-name` patterns and `Skill tool` references in the body
- Verify each referenced skill resolves:
  `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --probe <name>` — it
  searches the plugin tree, then `.claude/skills/`, then `$HOME/.claude/skills/`, the
  same order everything else uses. A `$HOME`-only check false-WARNs every plugin skill.
- WARN if a referenced skill doesn't resolve

**Agent spawning analysis:**
- If the body references spawning subagents (Agent tool), verify that `Agent` is accessible
- Check that subagent prompts described in instructions are self-contained

## Step 3: Efficiency Analysis

**Size metrics:**
- Count total lines and estimate tokens (~0.75 tokens per word)
- Flag if file exceeds 300 lines (WARN) or 500 lines (FAIL)
- Agents should be leaner than skills — they're loaded repeatedly

**Content analysis:**
- Large code blocks (> 30 lines) that could be extracted to a skill reference (WARN)
- Duplicate information — same instruction stated multiple ways (WARN)
- Inline data tables or examples that could be in a referenced skill (WARN)

**Instruction quality (heuristic checks):**
- Count heavy-handed directives (MUST, ALWAYS, NEVER, IMPORTANT in all-caps)
- Flag if > 10 such directives (WARN — explaining "why" is more effective)
- Check for explained rationale ("because", "this matters because", "the reason is")

## Step 4: Instruction Compliance Diagnosis

#### 4a: Instruction Extraction

Read the agent body and extract every concrete instruction. Categorize each as:
- **Critical**: Instructions defining the agent's core behavior (role, workflow steps, output format, required actions)
- **Quality**: Instructions improving output but not essential (style, naming, verbosity)
- **Guard**: Instructions preventing bad behavior (don't skip steps, don't edit certain files)

#### 4b: Failure Mode Analysis

For each critical instruction, evaluate these failure modes:

**1. Ambiguity** — Can the instruction be interpreted multiple ways?
- Check: Does the instruction specify exact actions, formats, or expected values?

**2. Buried instructions** — Is the instruction easy to miss?
- Instructions past line 150 in an agent file get significantly less attention
- Critical instructions inside code blocks or deep nesting are easily skipped

**3. Conflicting instructions** — Does the agent contradict itself?
- Common: "always use X" in one section, "use Y for flexibility" in another

**4. Missing "why"** — Does the agent understand the purpose?
- Instructions without rationale get deprioritized against the agent's defaults

**5. Scope overload** — Is the agent trying to do too much?
- Agents with 20+ instructions across 5+ domains overwhelm the context
- The agent follows early instructions well and starts improvising on the rest

**6. Implicit assumptions** — Does the agent assume context it won't have?
- "Follow the project conventions" — a spawned agent may not have read the project

**7. Role drift** — Is the agent's identity consistent throughout?
- The opening role statement should align with every instruction in the body
- If the role says "senior Go developer" but instructions cover Go + Svelte + Docker + CI, the agent's behavior becomes unpredictable

#### 4c: Compliance Test Matrix

Build a matrix of critical instructions vs. failure modes:

| Instruction | Ambiguity | Buried | Conflict | Missing Why | Overload | Implicit | Role Drift |
|-------------|-----------|--------|----------|-------------|----------|----------|------------|
| "Run tests before reporting done" | Clear | Line 110 | None | Explained | - | Clear | Aligned |

Mark each cell as: OK, WARN (might fail), FAIL (likely to fail)

#### 4d: Generate Fixes

For each WARN or FAIL in the compliance matrix, write a specific fix:
- Rewrite ambiguous instructions with concrete examples
- Move buried instructions to prominent positions
- Resolve conflicts by picking one approach
- Add rationale to instructions missing "why"
- Split overloaded agents into focused roles
- Replace implicit assumptions with explicit statements
- Realign drifted instructions with the role statement

## Step 5: Behavioral Simulation

1. **Generate test prompts**: Create 2-3 realistic user prompts that would trigger this agent based on its description.

2. **Spawn a test agent** (if subagents available):
   ```
   You have access to the agent definition at <path>. Read it, adopt its role and
   instructions, then accomplish this task:
   <test prompt>
   After completing the task, report:
   - Which instructions you followed
   - Which instructions you skipped or couldn't follow (and why)
   - Any instructions that were confusing or ambiguous
   ```

3. **Evaluate compliance**: Compare the agent's self-report against the instruction list from Step 4a.

4. **Record**: prompt, instructions followed/skipped/misinterpreted, quality assessment

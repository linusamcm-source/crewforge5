# Per-Category Fix Catalogs (Steps 2-5)

Load this file when applying fixes for findings in the matching category.

### Step 2: Apply Structural Fixes

These are mechanical — apply without asking.

**Missing or broken frontmatter:**
- No `---` delimiters → wrap existing content, add frontmatter with name derived from filename
- Missing `name` → derive from filename (kebab-case, strip `.md`)
- Missing `description` → generate from body content (role statement + "Use this agent when..." trigger list)
- Empty body → leave a TODO comment (this needs human input)

**Short description (< 30 words):**
- Read the agent body to understand what it does
- Expand the description to include: what the agent does, when to trigger it, and 3-5 example user phrases
- Short descriptions cause undertriggering — the Agent tool never selects this agent type when it should

**Missing trigger context in description:**
- Add "Use this agent whenever..." phrases based on the agent's role and instructions
- Include both obvious triggers ("build a Go service") and non-obvious ones ("fix this error" when it's a Go error)

**Missing `<example>` blocks in description:**
- Generate 2-3 example blocks showing realistic user/assistant/commentary interactions
- These dramatically improve triggering accuracy — the model pattern-matches on examples
- Format:
  ```
  <example>
  Context: Brief situation description
  user: "Realistic user message"
  assistant: "Brief response showing what the agent would do"
  <commentary>
  When to invoke this agent based on the example pattern.
  </commentary>
  </example>
  ```

**Name/filename mismatch:**
- If `name:` doesn't match the filename (without `.md`), update `name:` to match
- The filename is the canonical identifier — it's what the Agent tool's `subagent_type` uses

**Sensitive content:**
- Do NOT delete — flag in the rectification report for human review
- If API keys or tokens are hardcoded in examples, replace with `<YOUR_API_KEY>` placeholders

### Step 3: Apply Tool Coherence Fixes

This is the most impactful agent-specific fix category.

**Tools referenced in body but missing from `tools:` declaration:**
- Add each missing tool to the `tools:` field
- This is a FAIL-level fix — without the tool declared, the agent silently cannot perform
  actions its instructions tell it to do. The agent will either skip the step or hallucinate
  having done it.

**Tools declared but never referenced in body:**
- Remove unnecessary tools from the `tools:` field
- Fewer declared tools = tighter permission scope = more predictable agent behavior
- Exception: keep `Read` and `Glob` even if not explicitly referenced — agents often need
  them implicitly for navigation

**Missing `tools:` field entirely:**
- Analyze the body to determine which tools the agent needs
- Look for: file reading (Read), file writing (Write, Edit), command execution (Bash),
  file search (Glob, Grep), subagent spawning (Agent), skill invocation (Skill)
- Add a `tools:` field with the identified set

**Skill references pointing to nonexistent skills:**
- If a `/skill-name` reference doesn't exist on disk, add a comment in the body noting it's
  unavailable: `<!-- Note: /skill-name not found on disk — remove or install -->`
- Do not silently delete the reference — the user may need to install the skill

**Missing `color:` field:**
- Add a `color:` field based on the agent's domain:
  - Go/backend agents: `blue`
  - Frontend/design agents: `magenta`
  - Testing/QA agents: `green`
  - Security/ops agents: `red`
  - General-purpose agents: `cyan`

### Step 4: Apply Efficiency Fixes

**Agent file too long (> 300 lines):**
- Identify sections that are reference material (large examples, lookup tables, API docs)
- These belong in a skill's `references/` directory, not in an agent definition
- Extract large reference sections and replace with: "Invoke `/skill-name` for detailed <topic>"
- If no corresponding skill exists, note it as a deferred item for human action

**Too many heavy directives (> 10 MUST/ALWAYS/NEVER):**
- For each directive, rewrite to explain the reasoning:
  - Before: `MUST run tests before reporting done`
  - After: `Run tests before reporting done — untested code that "looks right" has caused regressions in this project before`
- Agents respond better to explained reasoning than to shouted commands

**Duplicate instructions:**
- If the same instruction appears in multiple sections (e.g., "run tests" in both TDD Workflow and Completion Gate), consolidate to one location and reference it
- Keep the version in the more prominent position (earlier in file, under a clear header)

### Step 5: Apply Instruction Compliance Fixes

**Missing role statement:**
- Add a clear role/identity statement as the first paragraph of the body
- Format: "You are a [seniority] [domain] [role] specializing in [specific areas]."
- Derive from the description and existing body content
- Role statements dramatically improve instruction following — the agent reasons from its
  identity when making judgment calls about ambiguous instructions

**Missing completion gate:**
- Add a `## Completion Gate` or `## ⛔ COMPLETION GATE` section near the end of the body
- Include concrete exit criteria based on what the agent does:
  - For code agents: tests pass, build clean, self-review diff
  - For design agents: build passes, visual verification
  - For analysis agents: report generated, findings summarized
- Without a completion gate, agents report tasks as done prematurely

**Ambiguous instructions:**
- Rewrite with concrete specifics
- Before: "Format the output properly"
- After: "Format output as a markdown table with columns: File, Issue, Fix, Status"
- Add an example of expected output wherever possible

**Buried instructions:**
- Move critical instructions to the first 100 lines of the body
- If an instruction is inside a code block, footnote, or deep nesting, promote it
- Critical instructions that appear after line 150 in an agent file are frequently ignored

**Conflicting instructions:**
- Identify the pair that conflicts
- Determine which aligns with the agent's role statement
- Remove or rewrite the conflicting one
- Add a brief note explaining the resolution

**Missing rationale ("why"):**
- For each critical instruction without a "why", add one sentence of context
- Template: `<instruction> — <why it matters>`
- Focus on consequences: what goes wrong if the agent skips this instruction?

**Implicit assumptions:**
- Replace "follow the standard pattern" with the actual pattern
- Replace "use the existing convention" with the specific convention
- A spawned agent has no prior context — every instruction must be self-contained

**Role drift:**
- If instructions cover domains outside the role statement, either:
  - Expand the role statement to include those domains
  - Remove the out-of-scope instructions (they belong in a different agent)
- Consistency between role and instructions is more important than coverage

# Fix Catalog — Steps 2-5

Per-category fix instructions for the rectification workflow. Load this when applying
fixes in Steps 2-5 of SKILL.md.

### Step 2: Apply Structural Fixes

These are mechanical — apply them without asking.

**Missing or broken frontmatter:**
- No `---` delimiters → wrap existing content, add frontmatter with name derived from directory name
- Missing `name` → derive from directory name (kebab-case)
- Missing `description` → generate from SKILL.md body content (first paragraph + "Use when..." trigger list)
- Empty body → leave a TODO comment (this needs human input)

**Short description (< 30 words):**
- Read the skill body to understand what it does
- Expand the description to include: what the skill does, when to trigger it, and 3-5 example user phrases
- Because short descriptions cause undertriggering — agents never see the skill when they should

**Dead references:**
- File referenced in SKILL.md but doesn't exist on disk → two options:
  - If the reference describes something the skill clearly needs (a script, a template), create a stub file with a TODO comment
  - If the reference looks like a copy-paste artifact or typo, remove the reference from SKILL.md
- Use judgment: a reference to `scripts/validate.sh` in a validation skill probably needs a stub; a reference to `references/old_notes.md` is probably stale

**Orphan files:**
- Files in the skill directory that SKILL.md never mentions
- Add a reference to each orphan file in an appropriate section of SKILL.md
- Because orphan files confuse agents — they might read them expecting instructions that contradict the main skill

**Sensitive files:**
- Do NOT delete them (they might be intentional)
- Add them to `.gitignore` if one exists in the skill directory
- Add a WARN comment in the rectification report

**Non-standard directories:**
- Rename to conventions if the intent is clear (e.g., `docs/` → `references/`, `bin/` → `scripts/`)
- If unclear, leave as-is and add a note explaining the directory in SKILL.md

### Step 3: Apply Functional Fixes

**Scripts not executable:**
```bash
chmod +x <script-path>
```

**Missing shebang:**
- `.py` files → add `#!/usr/bin/env python3`
- `.sh` / `.bash` files → add `#!/usr/bin/env bash`
- Add as first line, preserving existing content

**Syntax errors:**
- For Python: read the file, identify the syntax error, attempt to fix it
- For shell: run `bash -n` to get error details, fix common issues (unclosed quotes, missing `fi`/`done`)
- If the fix isn't obvious, add a `# FIXME: syntax error — needs human review` comment and log it in the report
- Because automated syntax fixes can change semantics — be conservative

**Missing dependencies:**
- If a Python script imports a non-stdlib module, add a comment at the top:
  `# Requires: pip install <package>`
- Add a compatibility note to SKILL.md if not already present

### Step 4: Apply Efficiency Fixes

**SKILL.md too long (> 500 lines):**
- Identify sections that are reference material (large examples, data tables, detailed API docs)
- Extract them to `references/<section-name>.md`
- Replace inline content with: "For detailed <topic>, read `references/<section-name>.md`"
- Because the SKILL.md body loads into context every time the skill triggers — keep it lean

**Too many heavy directives (> 10 MUST/ALWAYS/NEVER):**
- For each directive, rewrite it to explain the reasoning:
  - Before: `MUST use log.Printf not fmt.Printf`
  - After: `Use log.Printf instead of fmt.Printf — fmt.Printf doesn't include timestamps, which makes production debugging impossible`
- Because agents respond better to explained reasoning than to shouted commands. An agent that understands why will make the right call even in edge cases the instruction didn't cover.

**Large inline code blocks (> 50 lines):**
- Move to `scripts/` if executable, or `references/` if documentation
- Replace with a reference and brief summary

### Step 5: Apply Instruction Compliance Fixes

This is the most impactful phase. Each fix addresses a specific failure mode from the
compliance diagnosis.

**Ambiguous instructions:**
- Rewrite with concrete specifics
- Before: "Format the output nicely"
- After: "Format output as a markdown table with columns: Check, Status (PASS/WARN/FAIL), Detail"
- Add an example of the expected output whenever possible — examples are worth more than paragraphs of description

**Buried instructions:**
- Move critical instructions to be near the top of their section, under a clear header
- If an instruction is in a code block, footnote, or deeply nested list, promote it
- The first 100 lines of a skill get the most attention from agents — put critical stuff there

**Conflicting instructions:**
- Identify the pair that conflicts
- Determine which one aligns with the skill's primary purpose
- Remove or rewrite the conflicting instruction
- Add a brief note explaining the resolution

**Missing rationale ("why"):**
- For each critical instruction without a "why", add one sentence of context
- Template: `<instruction> — <why it matters>`
- Example: "Save reports to ./docs/agent_reports/ — because this directory is gitignored in most projects and keeps generated files out of source control"
- Focus on consequences: what goes wrong if the agent skips this instruction?

**Scope overload:**
- If the skill has > 15 distinct instructions, look for groups that can be collapsed
- Create a "Core Rules" section at the top with the 3-5 most important instructions
- Move everything else under "Detailed Steps" or into references
- Because agents prioritize early instructions — front-load what matters most

**Implicit assumptions:**
- Replace every "follow the standard pattern" with the actual pattern
- Replace "use the existing convention" with the specific convention
- Replace "check the usual places" with exact file paths
- Because the agent has no prior context — every instruction must be self-contained

**Missing output templates:**
- If the skill says "generate a report" or "produce output" without showing the format:
  - Read the skill's purpose and design an appropriate template
  - Add it as a markdown code block in SKILL.md
  - Include placeholder values so the agent can see the structure
- Because underspecified output is the #1 cause of inconsistent agent behavior

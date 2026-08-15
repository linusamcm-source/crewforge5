---
name: skill-rectifier
model: sonnet
description: Use when the user says "fix this skill", "rectify the validation failures", "apply the recommended fixes", "repair the skill issues", or "make this skill pass validation", or when a skill-validator report shows failures or warnings. Re-validates in a loop until grade A.
disable-model-invocation: true
---

# Skill Rectifier

Reads a skill-validator report, applies every safe fix to the target skill, and
re-validates in a loop until grade A (0 failures, 0-2 warnings). Pairs with
**skill-validator** — it diagnoses, this repairs. Also triggers when skill-validator's
Step 7 offers to fix issues and the user accepts. Never asks for confirmation
mid-loop.

**Loop: follow [references/rectify-loop.md](references/rectify-loop.md)** (Steps 0-9,
including the bounded exit conditions) with the parameters below.

## Parameters for the loop

- **Target**: a skill directory — SKILL.md plus optional `scripts/`, `references/`,
  `assets/`.
- **Validator**: `/skill-validator`. Structural script (Step 6):
  `bash ~/.claude/skills/skill-validator/scripts/validate_structure.sh <skill-path>`
- **Fix catalog** (Steps 2-5): [references/fix-catalog.md](references/fix-catalog.md).
  Category order: structural → functional → efficiency → instruction compliance.
- **Report** (Step 7): `./docs/agent_reports/skill-rectification-{skill-name}-{date}.md`,
  template [references/report-template.md](references/report-template.md).
- **Matching validation reports** (Step 0): `skill-validation-*` files in
  `./docs/agent_reports/`.

## Skill-specific notes

- Fixes may span multiple files (SKILL.md, scripts, references). In Step 6, also
  confirm no reference link went dead as a result of a fix.
- Instruction-compliance rewrites (ambiguous, buried, missing rationale) are the
  highest-impact category — they account for ~80% of "agents don't follow my skill"
  complaints.

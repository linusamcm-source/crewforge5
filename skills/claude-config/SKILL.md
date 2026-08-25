---
name: claude-config
model: opus
description: House rules for editing a Claude config repo — .gitignore whitelist, skill and agent frontmatter, size budgets. Use when adding or editing a skill, agent, hook, command, or settings.json
disable-model-invocation: true
---

# Editing a Claude config

House rules for any config root under edit — a user's `$CLAUDE_CONFIG_DIR`, a project's
`.claude/`, or this plugin's own tree. `/crewforge5:init` phase 0 loads this as the bar
every later proposal is judged against. These are the non-obvious constraints; everything
else is inferable from the tree.

## The repo

Read the target root's `.gitignore` before staging anything — it is the source of truth
for what syncs, and config repos commonly use a **whitelist** (`/*` ignores everything at
root, `!/name` re-includes entries). In a whitelist repo, tracking a NEW root file needs
its `!/<name>` rule first — otherwise `/*` hides it and `git add` silently skips it
(`git add -f` stages it once but doesn't persist intent).

If the root carries a `settings.json` that syncs across machines, keep it portable — no
machine-specific paths, and name the install step for any tool a hook needs.

## Frontmatter

- `model:` by judgment tier — haiku = mechanical, sonnet = structured work, opus =
  judgment/taste.
- `context: fork` + `agent:` only for autonomous report-producing skills. Anything with an
  AskUserQuestion intake gate or an interactive loop must stay inline, since a forked
  subagent has no user to ask.
- `disable-model-invocation: true` when a skill is an expensive deliberate ritual — it drops
  from the always-loaded catalog and `/<name>` still works. Check first that no other skill
  invokes it programmatically via the Skill tool; several do.
- `tools:` — quote the wildcard as `"*"`. Bare `*` is a YAML alias and does not parse.

## Size

`description:` loads in every session; the body does not. Keep descriptions under ~200
chars, keep the double-quoted trigger phrases (they drive matching), and put detail in the
body or `references/`.

Project-specific agents belong in that project's `.claude/agents/`, not in a user-level
`agents/` — a user-level agent costs its description in every session in every repo.

`bash "${CREWFORGE5_ROOT}/skills/self-improve/scripts/ceiling.sh" check` holds every
skill and agent to a recorded byte budget; run it after editing one.
`ceiling.sh record <target>` moves a budget deliberately, in a reviewable diff. See
`self-improve` for the loop these budgets exist to brake.

## Gates

Run after any edit to this plugin's own tree — all three must pass before a change ships:

```bash
bash "${CREWFORGE5_ROOT}/scripts/budget_check.sh"    # always-loaded context within budget
bash "${CREWFORGE5_ROOT}/scripts/name_check.sh"      # names match paths
bash "${CREWFORGE5_ROOT}/scripts/validate_all.sh"    # structural pass over every component
```

Agent definitions must not restate CLAUDE.md or a rules file — duplicates drift and
contradict; point at the one home instead.

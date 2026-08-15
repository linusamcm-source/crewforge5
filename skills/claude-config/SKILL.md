---
name: claude-config
model: opus
description: House rules for editing a Claude config repo — .gitignore whitelist, skill and agent frontmatter, size budgets. Use when adding or editing a skill, agent, hook, command, or settings.json
disable-model-invocation: true
---

# Editing this Claude config

Applies when working inside `$CLAUDE_CONFIG_DIR`. These are the non-obvious constraints;
everything else is inferable from the tree.

## The repo

`$CLAUDE_CONFIG_DIR` is a tracked git repo on `main`. `.gitignore` is a **whitelist**: `/*` ignores
everything at root, then `!/name` re-includes specific entries.

- To track a NEW root file you MUST add `!/<name>` to `.gitignore` — otherwise `/*` hides
  it and `git add` silently skips it. `git add -f` stages it once but doesn't persist
  intent; still add the `!` rule.
- `.gitignore` is the source of truth for what syncs — read it rather than any list.
  Machine-local (NOT synced): the whole `plugins/` tree.
- `settings.json` syncs across machines — keep it portable. No machine-specific paths; the
  rtk hook needs `brew install rtk` on each machine.

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

Project-specific agents belong in that project's `.claude/agents/` — or `agents-parked/`
here, installed with `just crew-install <family> <project>`. An agent in `agents/` costs its
description in every session in every repo.

`just ceilings` holds every skill and agent to a recorded budget; run it after editing one.
`ceiling.sh record <target>` moves a budget deliberately, in a reviewable diff. See
`/self-improve` for the loop these budgets exist to brake.

## Gates

`just lint-agents` catches agent definitions restating CLAUDE.md — duplicates drift and
contradict. `bats hooks/tests/` and `bats skills/*/scripts/tests/` cover the shell.

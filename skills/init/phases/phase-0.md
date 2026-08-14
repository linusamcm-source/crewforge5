# Phase 0 — Preflight

Establish where init is operating and on what, before anything is measured or
rewritten.

## Work

1. **Resolve the config root.** `INIT_TARGET` is the directory holding the
   `skills/` and `agents/` this run audits. Default is the repo root. Export it
   if the config lives elsewhere, and record it:
   `flow_state.sh init set target "<abs path>"`.
2. **Load the house rules.** `claude-config` is the standing statement of how
   this bundle wants skills, agents and hooks written, and every later phase
   proposes edits against it. Load it inline:

   ```bash
   RESOLVE="${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh"
   "$RESOLVE" --load-mode claude-config     # MODE=inline
   "$RESOLVE" claude-config                 # path to read
   ```

   Check `--load-mode` before reading any sub-skill body. A skill answering
   `MODE=agent AGENT=<type>` declares `context: fork` and must be spawned
   through the `Agent` tool with that type — reading such a body inline keeps
   its instructions and destroys the isolation it forks for.
3. **Require a clean tree.** Every later phase rewrites config files. An
   unrelated uncommitted edit makes the diff that proves what init changed
   unreadable, so this is a stop rather than a warning.

## Gate

`init_gate.sh preflight` — inside a git repo, `INIT_TARGET` exists, and
`git status --porcelain` is empty.

If the tree is dirty, stop and say so. Do not commit on the user's behalf: the
uncommitted work is theirs and they have not been asked about it.

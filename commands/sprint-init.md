---
description: Install CrewForge's rule files into this repo (or your user config) by symlink, after reporting what exists and what contradicts.
argument-hint: "[report|install|uninstall] [--user]"
---

Run the rules installer for CrewForge and report what it did.

Current state:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sprint_init.sh" report ${ARGUMENTS:+$ARGUMENTS}`

Then:

1. If the report names a **CONFLICT**, stop and show the user both sides — the
   rule of theirs and the rule of ours. Installing is their call, and resolving
   it by overwriting is never the answer. `install` will refuse anyway.
2. If the report shows anything **BLOCKED** (a real file where a link would go),
   say which and leave it alone.
3. Otherwise run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sprint_init.sh" install $ARGUMENTS --yes`
   and report the links made. Default scope is this project's `.claude/rules/`;
   `--user` installs into the user config instead.

`uninstall` removes only links this plugin made, and leaves anything else in
place. Re-running `install` is idempotent.

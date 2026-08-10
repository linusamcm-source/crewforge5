---
description: Git and shell hygiene: stage explicit paths, check status before tree-entangling commands, never find from / or ~.
---

## Git and shell hygiene

- Stage explicit paths (`git add <file>`). Never `git add -A` or `git add .` unless told to.
- Run `git status` before anything that entangles with tree state — commit, branch,
  worktree, stash, revert. An ordinary edit in a dirty tree is normal; don't gate on it.
- CWD may be `~` when no project is active. Confirm you are inside the target repo before
  any git/build/test command — use absolute paths or an explicit `cd <repo>`.
- Never run `find` from `/` or `~`. Scope it to the project tree.
- For any UI change, screenshot before AND after. Do not assume the change landed.


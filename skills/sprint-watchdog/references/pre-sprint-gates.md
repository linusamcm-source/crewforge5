# Pre-Sprint Gates — Detail

Full detail bodies for the four pre-sprint gates. Load this file before executing any gate.

### Gate 1 — Clean Working Tree

```bash
# repo_preflight.sh runs Gate 1 (clean tree) AND Gate 2 (branch sanity) in one
# read-only pass. Exit: 0 ok · 1 dirty · 2 protected branch · 3 not a repo.
# Bypass envs: SPRINT_WATCHDOG_ALLOW_DIRTY=1 / SPRINT_WATCHDOG_ALLOW_PROTECTED=1.
scripts/repo_preflight.sh --repo .
```

If output is non-empty, **stop**. Surface to user:

```
Sprint blocked: working tree dirty. Uncommitted/untracked files:
<list>
Commit, stash, or discard before starting the sprint, or confirm you want to proceed anyway.
```

### Gate 2 — Branch Sanity

```bash
# Branch sanity is already covered by scripts/repo_preflight.sh in the Gate 1
# block above (it prints branch/upstream/ahead-count and exits 2 on a protected
# branch). Use --json for a machine-readable object when wiring into a hook.
scripts/repo_preflight.sh --repo . --json
```

Confirm the current branch is the intended sprint branch. If you're on `main` / `master` / `dev` / `develop`, **stop** and ask before continuing.

### Gate 3 — Baseline Quality

Run the project's quality gate before agents start so you have a known baseline. Detect the command from the project:

| Found in | Likely command |
|----------|---------------|
| `justfile` recipe `qg` or `validate` | `just qg` or `just validate` |
| `package.json` script `validate` | `npm run validate` (or `bun run validate`, `pnpm validate`) |
| `package.json` scripts `typecheck` + `lint` + `test` | run all three |
| `Makefile` target `check` / `test` / `validate` | `make <target>` |
| `pyproject.toml` with `tox`/`nox` | `tox` / `nox` |
| Go project | `go vet ./... && golangci-lint run && go test ./...` |
| Cargo project | `cargo check && cargo clippy && cargo test` |

If baseline is red, **stop**. Agents need a green starting point or you cannot tell which failures they introduced.

### Gate 4 — Agent Role Contracts Loaded

Confirm each agent in the sprint has access to:

- `TaskUpdate` for task-state transitions
- `SendMessage` only for a genuine cross-boundary sender — under `/team-sprint` that is the graph-mode node executor's `done`/`failed` signal. Reviewers/auditors deliver by **final agent return** to their spawner and the spawner persists a findings artifact; they do NOT require `SendMessage`.
- `Read` / `Edit` / `Write` / `Bash` per their role

Only **stop** for a missing `SendMessage` when the role is a genuine cross-boundary sender (the graph-mode node executor). A reviewer/auditor whose listed tools omit `SendMessage` is **not** a failure — its final agent return plus the spawner-persisted artifact is the delivery (the final-return delivery contract); the crew-resolved `code-reviewer` legitimately carries no `SendMessage`. The old failure mode (perf-auditor/spec-reviewer aborting for lack of `SendMessage`) is dissolved by the final-return contract, not worked around.

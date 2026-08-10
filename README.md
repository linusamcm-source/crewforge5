# CrewForge

Agents and skills are a resource with a cost. This plugin generates them where
they belong, executes work with them, and stops them rotting.

```
detect stack → crew-factory generates the crew INTO the repo
             → team-sprint executes a plan with that crew
             → ceilings + validators stop the generated artefacts rotting
             → self-improve distils lessons back into the crew
```

## Install

```bash
claude plugin marketplace add linusmcmanamey/crewforge   # or a local path
claude plugin install crewforge@crewforge
```

Restart the session. `claude plugin details crewforge` shows what you now carry.

## What it costs you

Skill and agent descriptions load into **every** session whether or not you use
them. That is the plugin's rent, and it is measured rather than asserted:

```bash
bash "$CREWFORGE_ROOT/scripts/budget_check.sh" --verbose
```

The bundle is **~1,141 tokens** always-loaded across 24 catalogue entries,
against a budget of **1,200**. Ten skills carry
`disable-model-invocation: true` — `team-sprint`, `token-slim`,
`context-hygiene`, `master_plan`, `self-improve`, `team-feature`,
`tech-debt-audit`, `grill-me`, `plugin-forge`, `claude-config` — so they cost
nothing until you call them by name (`/crewforge:team-sprint`). That discipline
is the only reason a bundle this size is affordable, and `budget_check.sh` fails
the build over the budget rather than moving it.

`claude plugin details crewforge` reports a larger always-on number because its
projection charges hidden skills too. Verified against a live session, the ten
hidden skills do not appear in the catalogue at all; `budget_check.sh` measures
what the session actually carries, including the one line the root hook prints.

## `$CREWFORGE_ROOT`

Plugin skills document commands that live inside the plugin tree, and the
install path contains a marketplace name and a version — nothing you would
guess. A `SessionStart` hook prints the path once per session and writes it to
`$XDG_STATE_HOME/crewforge/root`. Expand `$CREWFORGE_ROOT` to that path when a
skill hands you a command:

```bash
export CREWFORGE_ROOT="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/crewforge/root")"
```

## The opinionated hooks are OFF by default

CrewForge ships three hooks that would otherwise change how your session
behaves without asking:

| Hook | Event | What it does |
| --- | --- | --- |
| `bash-guard` | `PreToolUse(Bash)` | **Denies** `git add -A`, `git add .`, and `find` from `/` or `~` |
| `learn-capture` | `PostToolUse(Bash)` | Appends a ledger line when a skill's own script reports a failure |
| `learn-nudge` | `SessionStart` | One line when the ledger has ≥5 undistilled entries |

All three exit immediately unless you opt in:

```bash
export CREWFORGE_HOOKS=1
```

A fourth hook, `sprint-watchdog-guard`, is always registered but inert: it does
nothing until a sprint arms it with an activation file in the repo, and goes
inert again at teardown.

## Dependencies

**Required:** `bash`, `git`, `python3`, `jq`. Four scripts hard-require `jq`
(`crew_check.sh`, `coverage_check.sh`, `detect_language.sh`,
`preflight_subskills.sh`) — it is a base dependency, not an optional extra.

**Optional, and degrade visibly when absent:** `rtk`, `just`, `repomix`,
`shellcheck`, `bats`, `graphify`, `codegraph`. Absent tooling is reported by
name; nothing fails silently. `graphify` is not shipped as a skill — it needs a
`uv`-installed binary, and a plugin that hard-fails on a missing external tool
is a bad first impression.

## State

Nothing is written to your `CLAUDE.md`, ever. Runtime state lands in
`${XDG_STATE_HOME:-~/.local/state}/crewforge/` (or `$CLAUDE_PLUGIN_DATA` where
the harness provides it). No `ceilings.json` is shipped — the budgets in one are
byte sizes of one machine's files, so it is generated on first `record`.
`team-sprint.config.yaml` is machine-local too; copy
`skills/team-sprint/team-sprint.config.yaml.example` if you want to change a
default.

## Rules

Several skills cite house rules — the recon escalation ladder, verification
discipline, git hygiene, the subagent delivery contract. Those ship as files in
`rules/`, and they are installed by an explicit command, never written into your
`CLAUDE.md` by a plugin:

```bash
bash "$CREWFORGE_ROOT/scripts/sprint_init.sh" report      # what exists, what conflicts
bash "$CREWFORGE_ROOT/scripts/sprint_init.sh" install     # symlink into .claude/rules/
bash "$CREWFORGE_ROOT/scripts/sprint_init.sh" uninstall   # remove the links
```

`report` reads your existing `CLAUDE.md` and rules and names contradictions
before anything is linked — a rule of yours saying "stage with `git add -A`"
against `bash-guard`'s denial of exactly that, for instance.

## Tests

641 bats cases cover the shell toolchain:

```bash
bash skills/team-sprint/scripts/tests/run-all.sh
bash scripts/budget_check.sh     # always-loaded context budget
bash scripts/name_check.sh       # frontmatter name matches path
```

## Support

This is a large plugin and it invites issues. If that turns out to be more than
can be carried, the honest alternative is a starter-config repo you fork — far
less machinery, no maintenance promise.

## License

MIT. See [LICENSE](LICENSE).

# CrewForge5

Agents and skills are a resource with a cost. This plugin generates them where
they belong, executes work with them, and stops them rotting.

```
/crewforge5:init    → measure, slim and validate the config you already have
/crewforge5:plan    → a goal becomes an adversarially-reviewed plan file
/crewforge5:execute → that plan becomes a merged commit, crew and gates included
```

Three commands is the whole surface. Everything underneath — the crew factory,
the review fleet, the recon tooling, the distillation pass — is a sub-skill one
of those three loads when its phase needs it.

## Install

```bash
claude plugin marketplace add linusamcm-source/crewforge5   # or a local path
claude plugin install crewforge5@crewforge5
```

Restart the session. `claude plugin details crewforge5` shows what you now carry.

## The three entry points

Always write the namespaced form. A bare `slash-init` reaches Claude Code's own
CLAUDE.md initializer — a different tool doing a different job — and the bare
forms of the other two are ambiguous in the same way.

| Command | What it does | Also triggers on |
| --- | --- | --- |
| `/crewforge5:init` | Gated config hygiene — measure, slim, validate, rectify and report a Claude setup's skills, agents and CLAUDE.md | "clean up my Claude config", "audit context load", "rightsize the environment" |
| `/crewforge5:plan` | A goal becomes an adversarial-clean, execute-ready plan file | "plan this feature", "write a sprint plan" |
| `/crewforge5:execute` | A reviewed plan becomes a merged commit — TDD agent fleet in an isolated worktree, coverage, AC/DoD and review-fleet gates, then an integration diagram and distilled learnings | "run a sprint", "execute this plan" |

Each one is a state machine over a `phases.json` manifest: a phase is offered,
its gate is run, and the verdict is written to state before the next phase is
offered. A gate announced in prose and never run did not happen.

State lives at `<repo>/.crewforge5/<flow>/<subject>/state.json` — **keyed by the
thing the run is about**, not by the flow alone, so a second plan or a second
sprint in one repo starts at phase 0 instead of resuming into the first one's
verdicts. Each flow claims its own subject in phase 0 —
`flow_state.sh <flow> use --from "<goal | config root | plan path>"` derives a
slug from what the run is about — so this is not something you have to do by
hand. `flow_state.sh <flow> list` names the runs a repo holds, `use <subject>`
switches between them, and `reset` discards one to start it over.

A manifest may also name a `status_source` — a command that answers how far the
run has got — and give a phase a `when` that decides whether it is in this run at
all. `crewforge5:execute` uses both: team-sprint owns phases 0–7 and their
per-story loop, so the driver asks it rather than keeping a second, coarser copy,
and the per-story phases swap for the graph-mode wave loop under
`scheduling: graph`.

### What drives which sub-skill

The sub-skills stay on disk and stay callable by name; they are just no longer
in the catalogue, so a flow reaches one through
`scripts/flow/subskill_resolve.sh` rather than through the `Skill` tool.

| Sub-skill | Driven by | Reached in |
| --- | --- | --- |
| `claude-config` | `/crewforge5:init` | phase 0, resolving the live config |
| `token-slim` | `/crewforge5:init` | phases 1, 3 and 7 — baseline, trim, re-measure |
| `context-hygiene` | `/crewforge5:init` | phase 2, passes 1–4 over CLAUDE.md, rules, hooks, MCP |
| `skill-validator` | `/crewforge5:init` | phase 4 |
| `agent-validator` | `/crewforge5:init` | phase 4 |
| `skill-rectifier` | `/crewforge5:init` | phase 5 |
| `agent-rectifier` | `/crewforge5:init` | phase 5 |
| `use-repo-code` | `/crewforge5:plan`, `/crewforge5:execute` | plan phase 1; execute's preflight and recon |
| `adhd` | `/crewforge5:plan` | phase 2, parallel divergent frames |
| `grill-me` | `/crewforge5:plan` | phase 3, the questioning loop |
| `team-feature` | `/crewforge5:plan` | phases 0–3, the interactive ratification half |
| `tech-debt-audit` | `/crewforge5:plan` | phase 4 |
| `master-plan` | `/crewforge5:plan` | phases 5 and 8 — impact map, coverage check |
| `team-sprint-planner` | `/crewforge5:plan` | phase 6, plan contract and story shape |
| `adversarial-review` | `/crewforge5:plan`, `/crewforge5:execute` | plan phase 7; execute phase 2 under `scheduling: graph` |
| `team-sprint` | `/crewforge5:execute` | phases 0–7 are its phase docs, wrapped unchanged |
| `sprint-watchdog` | `/crewforge5:execute` | phase 0, the pre-sprint audit |
| `pre-commit-review-fleet` | `/crewforge5:execute` | phase 7, over the sprint diff |
| `drawio` | `/crewforge5:execute` | phase 8, the integration diagram |
| `self-improve` | `/crewforge5:execute` | phase 9, distilling the ledger |
| `ac-validate` | — | assigned to a generated crew member by `crew-factory`; no phase drives it |
| `code-reviewer` | — | same — a crew-assignable skill, distinct from the `code-reviewer` agent |
| `playwright-cli` | — | same, for frontend AC verification |
| `plugin-forge` | — | nothing drives it; reachable by name only |
| `graphify` | `/crewforge5:plan`, `/crewforge5:execute` | plan phase 1 and execute phase 0 — the knowledge-graph half of recon |

## What it costs you

Skill and agent descriptions load into **every** session whether or not you use
them. That is the plugin's rent, and it is measured rather than asserted:

```bash
bash "$CREWFORGE5_ROOT/scripts/budget_check.sh" --verbose
```

The bundle is **~495 tokens** always-loaded across 11 catalogue entries, against
a budget of **600** — one description's worth of headroom, so rewording a
trigger phrase does not turn the build red, while a whole new listed surface
still cannot slip in unpriced. The other **25 skills** carry
`disable-model-invocation: true`, so they cost nothing until a flow resolves one
or you call it by name. That discipline is the only reason a bundle this size is
affordable, and `budget_check.sh` fails the build over the budget rather than
moving it.

Cost is only half of what the gate asserts. It also checks *which* skills are
listed: exactly `init`, `plan` and `execute`. A fourth entry point with a short
description used to pay its tokens and walk through unnoticed.

`claude plugin details crewforge5` reports a larger always-on number because its
projection charges hidden skills too. Verified against a live session, hidden
skills do not appear in the catalogue at all; `budget_check.sh` measures what
the session actually carries, including the one line the root hook prints.

## `$CREWFORGE5_ROOT`

Plugin skills document commands that live inside the plugin tree, and the
install path contains a marketplace name and a version — nothing you would
guess. A `SessionStart` hook prints the path once per session and writes it to
`$XDG_STATE_HOME/crewforge5/root`. Expand `$CREWFORGE5_ROOT` to that path when a
skill hands you a command:

```bash
export CREWFORGE5_ROOT="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/crewforge5/root")"
```

## The opinionated hooks are OFF by default

CrewForge5 ships three hooks that would otherwise change how your session
behaves without asking:

| Hook | Event | What it does |
| --- | --- | --- |
| `bash-guard` | `PreToolUse(Bash)` | **Denies** `git add -A`, `git add .`, and `find` from `/` or `~` |
| `learn-capture` | `PostToolUse(Bash)` | Appends a ledger line when a skill's own script reports a failure |
| `learn-nudge` | `SessionStart` | One line when the ledger has ≥5 undistilled entries |

All three exit immediately unless you opt in:

```bash
export CREWFORGE5_HOOKS=1
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

`/crewforge5:init` checks this list before it does anything else, and it is the
one check that answers on a machine without `jq` — every other gate, and the
flow driver itself, exits early there, so reaching them first would report one
missing tool and hide the rest:

```bash
bash "$CREWFORGE5_ROOT/skills/init/scripts/init_gate.sh" deps
```

A missing required tool stops the run: init offers to install what needs no
`sudo`, hands you a copy-paste block for anything else, and waits — re-checking
and re-listing until every required tool is there. Optional tools missing are
named and carried.

## State

Nothing is written to your `CLAUDE.md`, ever. Runtime state lands in
`${XDG_STATE_HOME:-~/.local/state}/crewforge5/` (or `$CLAUDE_PLUGIN_DATA` where
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
bash "$CREWFORGE5_ROOT/scripts/sprint_init.sh" report      # what exists, what conflicts
bash "$CREWFORGE5_ROOT/scripts/sprint_init.sh" install     # symlink into .claude/rules/
bash "$CREWFORGE5_ROOT/scripts/sprint_init.sh" uninstall   # remove the links
```

`/crewforge5:rules-install` is the same installer as a slash command — it runs
`report` first and refuses to resolve a conflict by overwriting. It is a
utility, not a fourth workflow: the three commands above remain the whole
planning-and-execution surface.

`report` reads your existing `CLAUDE.md` and rules and names contradictions
before anything is linked — a rule of yours saying "stage with `git add -A`"
against `bash-guard`'s denial of exactly that, for instance.

## Trimming your CLAUDE.md safely

`context-hygiene` will help you cut a bloated `CLAUDE.md`, but a trim is judged
by how much shorter it got — and the lines costing the most tokens are usually
the ones worth keeping. Check any proposal before you apply it:

```bash
bash "$CREWFORGE5_ROOT/scripts/retention_gate.sh" CLAUDE.md proposed.md
```

It fails if any `never`/`always`/`must` line, backticked command, path, pinned
version or quoted error string stopped appearing anywhere in the proposal.
Reorganising passes; losing does not. It reads two files and prints a verdict —
it cannot edit anything, so applying stays your decision.

## Tests

866 bats cases cover the shell toolchain and the plugin's own scripts. CI runs
them on Ubuntu and macOS, plus four gates and a degradation job:

**Check the exit code, not the tally.** `run-all.sh` runs shellcheck, then bats,
then `lint_skill.sh` — and only the middle step prints `ok` / `not ok` lines. A
green-looking count with a red suite is exactly how a dangling `$REF` citation
survived a full review here. `echo $?` is the signal.

```bash
bash skills/team-sprint/scripts/tests/run-all.sh   # 656 — the toolchain
bats scripts/tests/                                # 236 — flow driver, gates, docs surface, validator grading
bash scripts/budget_check.sh       # always-loaded context budget
bash scripts/name_check.sh         # frontmatter name matches path
bash scripts/validate_all.sh       # every skill and agent passes its own validator
bash scripts/verify_degradation.sh # every entry point survives the base set alone
```

Two claims cannot be tested without a real session, so they ship as probes you
run by hand rather than as sentences you have to take on trust:

```bash
bash scripts/verify_rule_scoping.sh   # a paths:-scoped rule loads ONLY on a matching read
```

That one is the assertion the whole rules design rests on. It runs two headless
sessions against an `InstructionsLoaded` hook and checks both directions — a
rule that loads when it shouldn't costs every unrelated session its whole body,
and one that never loads is a convention the model never sees.

On a Mac, also run this before you trust a green suite:

```bash
bash scripts/verify_gnu_portability.sh   # the suite under GNU-semantics stat
```

`stat` is the richest source of works-on-my-Mac bugs here, and it fails
silently. `stat -f %m "$f" || stat -c %Y "$f"` reads as "BSD, else GNU" and is
neither: GNU takes `-f` as `--file-system` and `%m` as the mount point, exits 0,
and the fallback never runs. That one inversion cost 80 failing tests on
ubuntu-latest and zero on macOS. The shim reproduces it in seconds. It models
`stat` only — merged-usr `/bin`, `sed -i`, and flag ordering still need the
Linux CI job.

## Support

This is a large plugin and it invites issues. If that turns out to be more than
can be carried, the honest alternative is a starter-config repo you fork — far
less machinery, no maintenance promise.

## Credits

Not all of this was written here. Five of the shipped skills started as someone
else's work and were adapted; four external projects are driven rather than
vendored. Both lists are below, because a skill you can read is a skill whose
origin you should be able to check.

**Adapted skills.** Each row was matched against the upstream file, not
guessed — a verbatim frontmatter description, a distinctive trigger token, or an
install line still present in the vendored copy.

| Skill | Upstream | Owner | Licence |
| --- | --- | --- | --- |
| `skills/adhd` | [UditAkhourii/adhd](https://github.com/UditAkhourii/adhd) | UditAkhourii | MIT |
| `skills/grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills) — `productivity/grilling` | Matt Pocock | MIT |
| `skills/drawio` | [jgraph/drawio-mcp](https://github.com/jgraph/drawio-mcp) — `plugins/claude-code/skills/drawio` | JGraph Ltd (draw.io) | Apache-2.0 |
| `skills/playwright-cli` | [microsoft/playwright](https://github.com/microsoft/playwright) — `packages/playwright-core/src/tools/skills/playwright-cli` | Microsoft | Apache-2.0 |
| `skills/tech-debt-audit` | [ksimback/tech-debt-skill](https://github.com/ksimback/tech-debt-skill) | ksimback | **none declared** |

`tech-debt-skill` ships no `LICENSE`, so its redistribution terms are unstated.
It is credited here on that basis, and would be the first thing to remove if the
author asked.

`skills/adhd` links its own upstream in `references/companion.md` — the skill is
this repo's in-Claude implementation of a spec whose prose lives there, and the
companion `adhd-agent` CLI is the author's.

**External projects the skills drive.** These are installed by you, not shipped
here, and each degrades visibly when absent (see [Dependencies](#dependencies)).

| Tool | Project | Owner | Licence | Used by |
| --- | --- | --- | --- | --- |
| `repomix` | [yamadashy/repomix](https://github.com/yamadashy/repomix) | yamadashy | MIT | `use-repo-code`, the recon ladder |
| `graphify` (`graphifyy` on PyPI) | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | Graphify-Labs | Apache-2.0 | `team-sprint` Phase 0/2/4 recon |
| `drawio` desktop CLI, `drawio-mcp` | [jgraph/drawio-mcp](https://github.com/jgraph/drawio-mcp) | JGraph Ltd | Apache-2.0 | `drawio` export and live-viewer paths |
| `playwright-cli` | [microsoft/playwright](https://github.com/microsoft/playwright) | Microsoft | Apache-2.0 | `playwright-cli`, `ac-validate` |

Everything else under `skills/`, `agents/`, `hooks/` and `scripts/` is original
to this repo.

## License

MIT. See [LICENSE](LICENSE).

# Changelog

## 0.4.2 — 2026-08-15

### Fixed

- Restored the plugin-relative path adaptations that the 0.4.0 upstream import
  reverted. Shipped skills, references and hooks referenced `~/.claude/...` and
  `/Users/...`, which resolve to nothing in a plugin install; executable paths now
  use `${CREWFORGE5_ROOT}`, user-config paths use `$HOME/.claude`, and the
  historical design docs under `skills/team-sprint/references/docs/plans/` no
  longer cite one machine's absolute paths. Restores the "No path coupling to one
  machine" release gate.
- `graphify_ensure.sh` and `lib.sh` are clean under shellcheck 0.9.0, the declared
  minimum: two `A && B || true` command substitutions became `... || var=""`
  (SC2015). Behaviour is unchanged; only 0.9 flagged them, and CI installs 0.9 on
  Linux by design.

### Removed

- `docs/plans/epic-1-three-skill-condensation.md`, a superseded planning document.

## 0.4.1 — 2026-08-15

### Fixed

- `crew-factory` security-role roster row now reuses the registry `security-reviewer`
  (stack-agnostic, all security surfaces) instead of the retired `api-security-audit`,
  whose removal left the reuse reference unresolvable.
- Restored `rule_emit.sh` and guarded the test suite against writes to the live
  repository tree (test-isolation leak into `.gitignore`).

## 0.4.0 — 2026-08-15

Picks up the upstream development tree — a reorganised `team-sprint`, four new
sub-skills — and re-applies the packaging layer that the import had flattened.

### Added

- `graphify` ships as a hidden sub-skill: the knowledge-graph half of recon,
  driven from `/crewforge5:plan` phase 1 and `/crewforge5:execute` phase 0
  alongside the repomix pack rather than instead of it.
- `ui-polish-loop`, `team-sprint-pm-lense` and `team-sprint-sa-lense` — three
  crew-assignable skills with no phase driving them, reached by name.

### Changed

- `skills/master_plan` is now `skills/master-plan`, matching every other
  directory in the bundle. The resolver already normalised `_` and `-`, so both
  spellings still resolve; only the hardcoded `check_coverage.sh` paths in
  `/crewforge5:plan` phases 5 and 8 had to move.
- `team-sprint`'s tree is regrouped: phase docs, ADRs, plans and reference notes
  under `references/`, the schemas under `scripts/schemas/`, the vocabulary under
  `assets/data/`. `/crewforge5:execute` phases 0–7, the watchdog guard hook and
  `crew-factory` follow the new paths.
- `crew_copy.sh` is gone with its tests. `crew_check.sh` reports
  `WORKTREE_AGENTS=ok|not_git|ignored|untracked:<names>` instead: a generated
  agent reaches a sprint worktree by being tracked in git, not by being copied
  into each one. No phase doc consumes that signal yet.
- `run-all.sh` now snapshots the checkout before the bats step and fails the run
  if it changed — a fixture that writes into the live tree instead of its temp
  dir is otherwise silent, and one did, editing this repo's `.gitignore`. Both
  leak shapes are covered: a file the run newly dirties (named in the failure)
  and a write into a file that was already dirty (caught by a diff digest).

### Fixed

Everything below is the same defect: the imported tree predates the packaging
work, so re-importing it wholesale reverted fixes 0.3.1 and 0.3.2 had already
made. Each is restored with the test that proves it.

- **The three entry points were deleted.** `skills/init`, `skills/plan` and
  `skills/execute` are back, so the plugin ships the commands its manifests
  advertise. `skills/adhd` is a real directory again rather than a symlink
  pointing outside the repo, and `claude-config`, `self-improve` and
  `plugin-forge` — all reachable from the entry points or the ledger hooks —
  are back with it.
- **Every skill body pointed at `~/.claude`.** Sub-skill call sites resolve
  through `scripts/flow/subskill_resolve.sh` and `${CREWFORGE5_ROOT}` again
  rather than assuming the user's config directory, which is what makes the
  bundle work as an installed plugin at all.
- **Every non-entry-point skill was catalogue-listed.** All 28 carry
  `disable-model-invocation: true` again; the always-loaded cost is back to
  ~543 tok across 12 entries against the 600 budget, from ~2,280 across 38.
- **`stat -f` ran before `stat -c`** in `lib.sh`, `recon.sh`, `pack.sh`,
  `evidence-fresh.sh` and four bats helpers. GNU `stat` reads `-f` as
  *filesystem*, so the BSD-first form fed a mount-point report into arithmetic
  and `set -u` killed the caller with `File: unbound variable`.
- **`build_commit_msg.sh` forced `LC_ALL=en_US.UTF-8`**, which a box that
  generates only `C.utf8` answers with a `setlocale` warning on stdout —
  straight into the commit subject. It picks an installed UTF-8 locale again.
- **`preflight_subskills.sh` probed `$HOME` alone**, declaring every
  plugin-installed sub-skill missing; it delegates to the resolver again.
- **`grade.sh` counted only prose findings**, grading a skill A while its own
  structural script reported failures in JSON on the same ledger. Both
  validators and their report templates are restored.
- **`rule_emit.sh` went with the import**, leaving `crew-factory` Phase 5 calling
  a script that no longer existed and a definition-of-done demanding a file
  nothing could write. The script, its bats contract and `crew_check.sh`'s
  `RULE_FILE=present|missing` signal are all back — informational like `STALE`,
  so a crew that predates rule files is never rebuilt for the sake of one
  document.

## 0.3.2 — 2026-08-15

Closes the gap 0.3.1 fixed by hand: the validators now check that frontmatter
**parses**, not merely that it has delimiters.

### Added

- `scripts/frontmatter_check.sh`, called by `validate_structure.sh` and
  `validate_agent.sh`. Every other check in both scripts asks whether a field
  appears in the text; a block that does not parse has no fields at all, so
  those checks read a broken manifest as a clean one. That is precisely how
  0.3.1's `skills/init/SKILL.md` defect reached a release with
  `validate_all.sh` calling it structurally clean.

  Three states, because *does not parse* and *parses but silently drops the tail
  of a value* are different failures: exit 1 with `FAIL:`, exit 0 with `WARN:`,
  exit 0 silent.

  **No YAML library, deliberately.** `python3` is a declared dependency but
  PyYAML is not, and a gate stricter on the maintainer's laptop than in CI is
  one people learn to bypass. The reserved-character set was measured against
  PyYAML one character at a time rather than reasoned out — `&` and `?` lead
  valid plain scalars and are absent for that reason, `[` and `{` are checked
  for balance rather than banned, since `tools: [Read, Write]` is legal. 28
  constructed cases, zero disagreements with PyYAML, all 35 shipped manifests
  clean.

### Fixed

- The init flow's own *repaired* fixture carried an `<example>` block whose
  `Context: ` broke the same way. The test asserting a structurally clean
  component was asserting it over a manifest that loaded empty.
- `validate_agent.sh` emitted unescaped quotes in its JSON `detail` strings — it
  had no `json_escape` at all. Nothing had exposed it until parse-failure
  messages started quoting the offending value, at which point `init_gate.sh`
  truncated the line at the first bare quote.

`bats scripts/tests/` is now 236.

## 0.3.1 — 2026-08-15

Bug fixes to the validators' mechanical half. No interface change.

### Fixed

- **`skills/init/SKILL.md` frontmatter did not parse.** The description was an
  unquoted YAML scalar containing `: `, so the whole block failed to load and
  the plugin's main entry point ran with **empty metadata — name, model and
  description all silently dropped**. `claude plugin tag` refuses to tag over
  it; `validate_all.sh` called the same file structurally clean, because the
  repo's own gate never parsed the YAML it validates. Colon replaced with an
  em dash. This was the only such file of 35 checked.
- **`grade.sh` counted nothing the scripts reported.** `validate_structure.sh`
  and `validate_agent.sh` emit JSON; `grade.sh` grepped for prose lines, so a
  skill graded A while its own structural script reported two warnings on the
  same file. The mechanical half of a grade whose skill says "grade.sh wins"
  was scoring only what the model had typed by hand. It now counts both shapes.
- **The grade scale lived in three places and two had drifted a full grade.**
  1 failure read D in both report templates and C in `grade.sh`; 3 read F on
  paper and D in code. The prose copies are deleted in favour of `grade.sh`'s
  header — the code that applies the scale — and pinned by tests.
- **Description checks were floors beside a gate that punishes length.** Every
  agent in the tree warned `description is only 20 words (recommend > 30)` and
  `lacks <example> blocks`, while `budget_check.sh` — run by the same
  `validate_all.sh` invocation — charges those strings against a 600 token
  budget with 57 of headroom. Both validators now warn on descriptions over the
  ~200 char house limit `claude-config` already sets, and an absent
  `<example>` block is no longer a defect.
- **The heavy-directive tally flagged safety guards.** Directives about
  credentials, force pushes, deletes, production and spend are exempt and
  reported separately, so the rectifier is never pushed to soften the one line
  that prevents damage.
- **`agent-validator` and `agent-rectifier` each owned a rectify loop**, so a
  re-validation round nested a second loop inside the first and each round
  doubled. The validator gains the report-only mode `skill-validator` already
  had; the rectifier now names it in the spawn prompt.

### Added

- `agent-validator` gains the findings ledger and mechanical grading
  `skill-validator` had, reusing its `grade.sh` rather than copying it, and
  applies `context-hygiene`'s principles as judgment checks. Any fix that
  shortens an agent file must clear `retention_gate.sh` first.
- `context-hygiene` principle 7, **mechanical over prose**: a deterministic
  check belongs in a script whose output is canonical, and every mechanical
  check needs a test asserting it counts what it claims — an unexercised script
  is prose with extra steps.
- `scripts/tests/validator_grading.bats` — 17 cases over both validators and
  the grader, including a test that no report template restates the grade scale
  in prose. `bats scripts/tests/` is now 227.

## 0.3.0 — 2026-08-14

Renamed to `crewforge5`. This is a breaking rename, not a cosmetic one: the
command namespace, the environment contract and the per-repo state directory
all move, and nothing forwards from the old names.

### Changed

- The three entry points are `/crewforge5:init`, `/crewforge5:plan` and
  `/crewforge5:execute`. The old `/crewforge:*` names resolve to nothing.
- `CREWFORGE_ROOT` is now `CREWFORGE5_ROOT`, and `CREWFORGE_HOOKS` is now
  `CREWFORGE5_HOOKS`. Anything exporting the old names — a shell profile, a CI
  job, a wrapper script — sets a variable nothing reads.
- The per-repo state directory is `.crewforge5/` rather than `.crewforge/`.
- `hooks/crewforge-root.sh` is `hooks/crewforge5-root.sh`, and `hooks.json`
  points at the new path.
- The always-loaded catalogue measures **2172 chars / ~543 tok / 12 entries** —
  two tokens more than 0.2.0, entirely from the longer name in the three
  descriptions. `BUDGET` is unchanged at 600, so the gate passes with 57 tokens
  of headroom.
- `scripts/tests/init_flow.bats` guarded against a bare `/init` with
  `[^:a-z]/init`, which the digit in `.crewforge5/init/` trips. The class
  admits digits.

### Migration

A repo already onboarded under the old name keeps its history in a directory
nothing looks at. Move it before the next flow runs:

```bash
mv .crewforge .crewforge5
```

An installed copy of the plugin is registered under the old marketplace and
plugin name. Remove it and install `crewforge5` from the renamed repository —
there is no in-place upgrade path across a name change.

## 0.2.0 — 2026-08-13

Condensed to three entry points. The always-loaded catalogue went from
**4390 chars / ~1,098 tok / 23 entries** to
**2165 chars / ~541 tok / 12 entries** — both figures from
`scripts/budget_check.sh`, which is what a session actually carries, not a
count of directories under `skills/`.

The distinction matters, because a raw skill count would tell the wrong story:
ten skills already carried `disable-model-invocation: true` before any of this
work, so the headline is not "25 skills became 3" — nothing was deleted, and
all 27 skills are still on disk and still callable by name.

### Added

- `/crewforge5:init`, `/crewforge5:plan`, `/crewforge5:execute` — the only three
  skills left in the catalogue. Each is a state machine over a `phases.json`
  manifest, driven by the shared `scripts/flow/` driver: a phase is offered,
  its gate is run, and the verdict is written to state before the next phase.
- `scripts/flow/subskill_resolve.sh` — resolves a hidden skill to its
  `SKILL.md` path and reports how to load it (`--load-mode` answers `inline`
  or `agent`). A skill declaring `context: fork` must be spawned through the
  `Agent` tool; reading it inline destroys the isolation it asked for.
- `scripts/flow/flow_state.sh`, `flow_next.sh`, `flow_gate.sh` — one driver, so
  the three entry skills share phase advance and gate recording rather than
  each reimplementing it.

### Changed

- The other 24 skills carry `disable-model-invocation: true` and are reached
  through the resolver by whichever flow needs them — or by name, which still
  works. `README.md` carries the full map of sub-skill to driving entry point.
- `scripts/budget_check.sh` now asserts *shape* as well as cost: `init`, `plan`
  and `execute` are the only listed skills, checked in both directions. A
  fourth entry point with a cheap description used to pay its tokens and walk
  straight through. `BUDGET` is 600 against a measured 541 — one description's
  worth of headroom, bounded by `scripts/tests/budget_check.bats` so it cannot
  quietly become a blank cheque, and a whole new listed surface still cannot
  slip in unpriced.
- `scripts/validate_all.sh` invokes `budget_check.sh`, so one command answers
  the whole release question instead of a local run reporting every component
  clean on a tree that was over budget.
- Every reference to a now-hidden skill — in skills, phase docs and agents —
  points at the resolver instead of at the `Skill` tool, which cannot reach a
  hidden skill at all. `scripts/tests/subskill_refs.bats` holds that line.

### Not changed

- Nothing was deleted. Every skill and agent that shipped in 0.1.0 is still on
  disk, still validated, still invocable by its own name.
- `team-sprint`'s phase docs are untouched. `/crewforge5:execute` wraps them and
  adds two phases at the end (integration diagram, distilled learnings) rather
  than forking their content.

## 0.1.0 — 2026-08-10

First packaged release. The toolchain existed as a personal `~/.claude` config;
this is the half of it that is general, extracted so it installs anywhere.

### Added

- 25 skills and 7 agents, namespaced under `crewforge5:`. No skill was renamed —
  the plugin name is already the prefix.
- `rules/` — the recon ladder, verification discipline, git hygiene and the
  subagent delivery contract, as plugin-owned files. Installed by
  `/crewforge5:sprint-init`, by symlink, only when asked. Nothing is ever written
  to your `CLAUDE.md`.
- `scripts/budget_check.sh` — release gate on always-loaded context. The bundle
  measures ~1,141 tokens against a 1,200 budget. Three skills were hidden behind
  `disable-model-invocation` to pay for the entries the plan's estimate missed:
  the catalogue renders the component *name* alongside the description, and the
  root hook's line is rent too. Both are now counted.
- `scripts/name_check.sh` — every shipped skill and agent is invocable under the
  name its path implies.
- `scripts/sprint_init.sh` — report / install / uninstall for the rule files,
  with a contradiction check that refuses to install over a conflicting rule.
- `hooks/crewforge5-root.sh` — publishes the install path once per session as
  `$CREWFORGE5_ROOT`, because `${CLAUDE_PLUGIN_ROOT}` is not visible to the Bash
  tool.
- `crew_copy.sh` — carries `.claude/agents/` and `.claude/crews/` into **each**
  worktree at node start. A sprint that generates its crew after a node worktree
  was cut used to fail at spawn, per node; a copy made once at setup does not fix
  it, because `worktree_strategy: per-node` is the default. One way, and it
  refuses to overwrite a newer in-worktree agent.
- `rule_emit.sh` — writes `.claude/rules/<lang>.md` with `paths:` frontmatter
  scoped to the stack, so the body loads only when a file of that stack is read.
  `crew_check.sh` now reports `RULE_FILE=present|missing` the way it reports
  `STALE`: informational, never gating. A missing rule file must not mean
  REBUILD — every crew that predates rule files lacks one, and rebuilding them
  all costs ~470s apiece to produce a document written in place.
- `scripts/validate_all.sh` and `.github/workflows/ci.yml` — the suite runs on
  Ubuntu and macOS; the budget, name, structural-validator and path-coupling
  gates run on every push.

### Changed

- All `~/.claude` and `/Users/...` coupling removed from shipped skills, agents
  and hooks — 42 files at the start, none at the end.
- `ledger.sh` writes to `${XDG_STATE_HOME:-~/.local/state}/crewforge5/ledger`
  rather than assuming a `~/.claude` exists; `ceiling.sh` resolves its targets
  from the tree it ships in.
- `agents/architect-review.md` → `architect-reviewer.md`, matching the name its
  frontmatter always declared.
- Tests that were anchored to the originating repo's git history now skip
  outside it, rather than failing; `recon_config.bats` skips when no
  machine-local `team-sprint.config.yaml` exists.

### Fixed

- `code-reviewer` and `plugin-forge` both failed the plugin's own
  `skill-validator`: their SKILL.md cited reference files and scripts that were
  never in the tree. A bundle whose pitch is "stops your agents rotting" cannot
  ship components that fail its own gate.

### Not shipped

- `graphify` — needs a `uv`-installed binary. Held for a post-1.0 optional
  add-on.
- Six fallback agents (`api-security-audit`, `github-actions-expert`,
  `golang-pro`, `python-mcp-expert`, `python-pro`, `typescript-pro`) — they cost
  ~249 tokens, which would put the bundle at ~1,373 against a 1,200 budget.
  Revisit only if something else is hidden to pay for them.
- No `ceilings.json` and no `team-sprint.config.yaml`: both are one machine's
  state. Generated on first use.

### Verified this release

- **`paths:`-scoped rules load only on a matching read** —
  `scripts/verify_rule_scoping.sh`. Two headless sessions against an
  `InstructionsLoaded` hook: reading a non-matching file produced 0 load events,
  reading a matching one produced 1, `memory_type=Project
  load_reason=path_glob_match`. This is the AC of P0.1 and P3.1 and nothing in
  the tree asserted it before now.
- **The bundle degrades instead of dying** — `scripts/verify_degradation.sh`.
  On the base set alone, with rtk, just, repomix, graphify, codegraph, shellcheck
  and bats all unreachable: `detect_language` STATUS=OK, `crew_check`
  STATUS=REBUILD, `recon` STATUS=DEGRADED REASON=not-installed, both gates PASS,
  and ledger/ceiling work with no user config directory.
- **`sprint_init.sh` now has tests** — ten cases, including both contradiction
  directions. They found a real bug: `uninstall` exited non-zero when it
  correctly spared a rule file that was not ours.

### Portability — five defects found only by publishing

CI's first real runs found five bugs, every one invisible on the development
machine. They are listed because the pattern matters more than any single fix:
each looked correct locally, and four were unfalsifiable on macOS by
construction.

- **The BSD/GNU `stat` fallback was inverted everywhere.** `stat -f %m ||
  stat -c %Y` reads as "BSD, else GNU" and is neither: GNU takes `-f` as
  `--file-system` and `%m` as the mount point, EXITS 0, and the fallback never
  runs. The mount point reaches `$(( ))`, bash parses its leading word as a
  variable, and `set -u` kills the script frames away. One root cause, 80 failing
  tests on ubuntu-latest, zero on macOS. Fixed in 4 shipped scripts and 5 bats
  files; `mtime_epoch` now validates the result is an integer.
- **SC2015 under shellcheck 0.9**, which Ubuntu's apt ships and Homebrew's 0.11
  does not flag. The repo declares `shellcheck >=0.9`, so the code is now clean
  under both rather than CI being pinned newer to hide it.
- **A no-python3 fixture leaked python3 back in on merged-usr Linux**, where
  `/bin` IS `/usr/bin`, so a "link everything from /bin" sweep undid itself.
- **`mapfile` in a CI step** — bash 4+, and macOS runners are bash 3.2.
- **A heredoc's `@test` registered a phantom test** in the enclosing file. Older
  bats aborted that file: 655 of 656 tests ran, zero failures reported, exit 1.

### Known gaps

- Not yet run end to end on a repo the author has never seen (plan P4.3).
- **`ci.yml` has never executed on a runner.** The repo has no remote, so every
  "green on Ubuntu" statement above describes code that was read and locally
  simulated, not a job that passed. Publishing is what converts them.
- **Local `bats` is less strict than CI's.** bats 1.14 does not fail a test when
  a mid-body `[[ ]]` returns false; bare `[ ]` and failing commands do fail
  correctly. 295 assertions are affected. All 295 were verified to pass under
  enforcement, so nothing is hiding behind them — but a future regression in one
  would be invisible locally. `run-all.sh` probes its own strictness and warns.
- **`team-sprint/SKILL.md` is 13,923 bytes against a 12,288 target.** Going lower
  breaks contracts the suite pins to that file: `recon_distribution.bats` AC12
  requires the four recon keys in its config block in a fixed column format, and
  `wa3_demotion.bats` requires literal `### Phase N` sections naming their
  workflow files. Both were attempted and both went red. The target was set
  against the 25 KB file without enumerating what the tests hold there.
- **P3.4 (CLAUDE.md slimming retention gate) is unimplemented.** Nothing claims
  otherwise in the README — it is a plan item, not a shipped promise.
- Ubuntu is now in CI but has not yet run against a real GitHub remote. The
  `stat -f` audit is done: all 10 sites carry GNU fallbacks, and there are no
  `sed -i ''` invocations left.
- The `skill-validator` / `agent-validator` **behavioural** grade is not in CI —
  it needs a model. The structural half runs on every push
  (`scripts/validate_all.sh`, 32 components clean).

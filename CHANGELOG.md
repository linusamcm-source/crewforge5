# Changelog

## 0.1.0 — 2026-08-10

First packaged release. The toolchain existed as a personal `~/.claude` config;
this is the half of it that is general, extracted so it installs anywhere.

### Added

- 25 skills and 7 agents, namespaced under `crewforge:`. No skill was renamed —
  the plugin name is already the prefix.
- `rules/` — the recon ladder, verification discipline, git hygiene and the
  subagent delivery contract, as plugin-owned files. Installed by
  `/crewforge:sprint-init`, by symlink, only when asked. Nothing is ever written
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
- `hooks/crewforge-root.sh` — publishes the install path once per session as
  `$CREWFORGE_ROOT`, because `${CLAUDE_PLUGIN_ROOT}` is not visible to the Bash
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
- `ledger.sh` writes to `${XDG_STATE_HOME:-~/.local/state}/crewforge/ledger`
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

### Known gaps

- Not yet run end to end on a repo the author has never seen (plan P4.3).
- **`ci.yml` has never executed on a runner.** The repo has no remote, so every
  "green on Ubuntu" statement above describes code that was read and locally
  simulated, not a job that passed. Publishing is what converts them.
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

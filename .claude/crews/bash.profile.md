# bash stack profile — crewforge5

Verified 2026-08-11 against the live tree at commit `1fa2245`.

Every command below was executed in this repo during the survey. Anything not
run is marked explicitly as *not verified*; nothing here is recalled.

## Language and runtime

| Fact | Value | How it was verified |
| --- | --- | --- |
| Language | bash (POSIX-ish shell) | `detect_language.sh` → `STATUS=OK LANG=bash` |
| Interpreter on PATH | GNU bash 3.2.57(1) arm64-apple-darwin26 at `/bin/bash` | `bash --version` |
| Shebang convention | `#!/usr/bin/env bash` in 23 of 23 scripts | `head -1 skills/team-sprint/scripts/*.sh` |
| Shell scripts | 62 `*.sh` | `find . -name '*.sh'` |
| Test files | 44 `*.bats` | `find . -name '*.bats'` |
| Skills | 25 | `ls skills/` |

macOS ships bash 3.2 — no associative arrays, no `${var^^}`, no `mapfile`.
CI runs ubuntu-latest **and** macos-latest, so BSD/GNU differences (`stat -f`,
`sed -i ''`, flag order) are load-bearing, not cosmetic.

## Tooling actually installed

| Tool | Version | Path |
| --- | --- | --- |
| bats-core | 1.14.0 | `/opt/homebrew/bin/bats` |
| shellcheck | 0.11.0 | `/opt/homebrew/bin/shellcheck` |
| jq | 1.8.2 | `/opt/homebrew/bin/jq` |
| git | 2.50.1 (Apple Git-155) | `/usr/bin/git` |
| python3 | present | used by `crew_check.sh` for date arithmetic |
| **shfmt** | **NOT INSTALLED** | `command -v shfmt` → not found |

There is no formatter in this toolchain and no type checker — shell has
neither. Do not invent one.

## Verified commands

Run and observed this session:

```bash
# Tests — 655 passing, 0 failing
bats skills/team-sprint/scripts/tests/*.bats

# Lint — clean, exit 0, both script trees
shellcheck skills/team-sprint/scripts/*.sh
shellcheck scripts/*.sh

# Release gates (all PASS)
bash scripts/budget_check.sh      # always-loaded context ceiling
bash scripts/name_check.sh        # component names match their paths
bash scripts/validate_all.sh      # 32 components structurally clean
```

`bash scripts/budget_check.sh` printed:

```
always-loaded: 4564 chars (~1141 tok) across 24 descriptions; 10 skills hidden
budget: 1200 tok
PASS: 59 tok of headroom
```

### The aggregate suite was RED at survey time — since fixed

```bash
bash skills/team-sprint/scripts/tests/run-all.sh   # exited 1 at commit 1fa2245
```

Steps 1 (shellcheck) and 2 (bats, 654/654 at survey time) passed; step 3 failed because
`SKILL.md` cited `$REF/config-reference.md`, a file that had been created and
then removed during a slim while the citation stayed behind. `lint_skill.sh`
check2 caught it.

**Worth knowing why it survived as long as it did:** the bats cases all pass and
only `lint_skill.sh` fails, *after* them — so anyone counting `ok` / `not ok`
lines sees a green suite. `run-all.sh`'s exit code is the only honest signal.
Check `$?`, not the tally.

Fixed at the next commit; the citation is gone and `run-all.sh` exits 0.

Note also that `lint_skill.sh` re-runs the **entire** bats suite nested inside
step 3, so `run-all.sh` executes the suite twice and takes several minutes.
Prefer running `bats` directly during a tight loop.

## No coverage, no typecheck

- **coverage**: none for this repo. `coverage_check.sh` exists in the toolchain
  but it measures *target* projects a sprint runs against, not this repo's own
  shell scripts. There is no shell coverage instrument installed.
- **typecheck**: not applicable to shell. `detect_commands.sh` reports it as an
  ambiguity rather than inventing one.

`detect_commands.sh` on this repo returns `confidence: low` with all four
command slots empty — it does not recognise a bats/shellcheck shell toolchain.
The commands above were recovered from `.github/workflows/ci.yml` and then run.

## House conventions

Non-obvious only — anything you would learn by reading two scripts is omitted.

- **stdout is a machine contract.** Scripts print `KEY=VALUE` lines
  (`STATUS=CACHED`, `REASON=manifest_missing`, `PATH=...`). Callers parse these.
  Human commentary goes to stderr, never stdout, or you break the caller.
- **Exit codes are three-valued**: `0` success, `1` error, `2` usage. Usage
  text is printed to stderr.
- **`set -euo pipefail`** in 17 of 23 toolchain scripts. Four use `set -uo
  pipefail` *deliberately* — they need to inspect a non-zero exit rather than
  die on it. Do not "fix" a missing `-e` without reading why it is absent.
- **Schema validation is pure jq.** `crews.schema.json` is the human-readable
  statement; the enforcing copy is jq inside `crew_check.sh`. Change one and you
  must change the other.
- **No machine-specific paths** in `skills/`, `agents/`, `hooks/`, `rules/`. CI
  greps for `~/.claude` and `/Users/` and fails the build. Use
  `${CREWFORGE5_ROOT}`.
- **Always-loaded context is a release gate.** Adding an unhidden skill without
  paying for it fails `budget_check.sh`. Headroom is currently 59 tokens.
- **bats tests carry a fallback.** They source
  `skills/team-sprint/scripts/tests/lib/bats-fallback.sh` so they can run under
  plain `bash <file>` when bats is absent.
- Tests live beside the code they cover, in
  `skills/team-sprint/scripts/tests/*.bats`.

## Anti-patterns in this repo

- Reaching for bash 4+ features (associative arrays, `mapfile`, `${x^^}`) —
  breaks the macOS 3.2 runner.
- GNU-only flags (`sed -i` without an argument, `stat -c`, `readlink -f`) —
  breaks the macOS leg of CI.
- Writing prose to stdout in a script another script parses.
- Duplicating a rule in prose that already lives in a script — the repo has been
  bitten by two prose copies of the language marker table drifting apart.

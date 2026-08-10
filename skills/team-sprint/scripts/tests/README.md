# `scripts/tests/` — local test harness for the team-sprint skill

Every script in `scripts/` (including the pre-existing `validate_plan_path.sh`)
has at least one `.bats` fixture in this directory. The harness runs locally —
no `.github/workflows/` exists in the skill repo yet.

## How to run

```bash
bash scripts/tests/run-all.sh
```

The harness performs two steps and aborts on the first failure:

1. **shellcheck** every `$SCRIPTS/*.sh` (top-level scripts only; the test
   helper at `tests/lib/bats-fallback.sh` is intentionally excluded from this
   pass).
2. **bats** every `tests/*.bats` file. If `bats` is on PATH, the real
   `bats` binary runs the suite. Otherwise the harness invokes each
   `.bats` file as plain `bash <file>`; the fallback works because
   every fixture sources `tests/lib/bats-fallback.sh` at the top of the
   file (see the bats-vs-fallback contract below).

Exit code is `0` on full success, non-zero on any failure.

## Pinned versions (recommended)

| Tool       | Minimum version | Install                           |
|------------|-----------------|-----------------------------------|
| bats-core  | `≥ 1.10`        | `brew install bats-core`          |
| shellcheck | `≥ 0.9`         | `brew install shellcheck`         |
| repomix    | `≥ 1.14`        | `npm i -g repomix` or `bun add -g repomix` |

`lib.sh::require_repomix` includes the `(≥ 1.14)` constraint in its install
hint.

## Adding a new `.bats` fixture

Template — copy into `scripts/tests/<script-name>.bats`:

```bash
#!/usr/bin/env bats
# <script-name>.bats — fixtures for scripts/<script-name>.sh

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  SCRIPT="$SCRIPTS/<script-name>.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() {
  rm -rf "$TMP"
}

@test "describes what the assertion verifies" {
  run "$SCRIPT" --some-flag
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected substring"* ]]
}
```

Rules:

- The `source ".../lib/bats-fallback.sh"` line MUST be the first
  executable line of the file (it is what makes plain-bash invocation
  work). The `BATS_TEST_FILENAME` env var is set by real bats; the
  `BASH_SOURCE[0]` fallback covers plain-bash invocation.
- Test bodies should prefer plain shell tests (`[ ... ]`, `[[ ... ]]`)
  over the bats-assert helpers. The shim defines the bats-assert API as
  a backstop, but the existing suite uses `[ ]` and runs under both
  modes without depending on bats-assert being installed.
- Use `run "$SCRIPT" ...` to capture exit code into `$status` and
  combined stdout+stderr into `$output` (matches bats semantics under
  both modes).
- Create your tmp working dir inside `setup()` and clean it up in
  `teardown()`. Tests that need a git repo should `git init` in setup —
  see `state.bats` for the canonical pattern.
- Drop fixture artefacts (sample plans, coverage files, JSON inputs)
  under `scripts/tests/fixtures/<script-name>/` so they're committed
  alongside the test that owns them.

## The bats-vs-fallback contract

`tests/lib/bats-fallback.sh` has two modes:

- **Real bats mode** (when `BATS_VERSION` is set in the environment):
  the file just defines assert helpers (`assert_equal`, `assert_success`,
  `assert_failure`, `assert_output`, `assert_stderr`, `refute_output`,
  `refute_stderr`, `assert_line`, `refute_line`, `assert_regex`,
  `assert_not_equal`) and returns. bats supplies `run`, `setup`,
  `teardown`, `$status`, `$output`, `$lines` natively. If the host has
  `bats-assert` installed, those library functions take precedence
  (the shim only defines a name when no prior definition exists).
- **Plain-bash mode** (when `BATS_VERSION` is unset and the caller is a
  `.bats` file): the shim preprocesses the calling file — rewriting
  every `@test "name" { … }` into a function and appending a runner
  that calls `setup` → test → `teardown` per test — then `exec`s the
  rewritten script. The shim also defines `run` and the assert helpers
  before the rewrite executes.

Because the fixtures only use the assertions listed above, the same
`.bats` files run identically under either mode.

## Coverage

After running the harness you should see one bats output line per `@test`
across every fixture (one fixture per script in `scripts/`, plus the
`validate_plan_path.bats` backfill).

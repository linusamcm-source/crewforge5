#!/usr/bin/env bash
# run-all.sh — local CI harness for the team-sprint skill.
#
# Step 1: shellcheck every $SCRIPTS/*.sh (excludes scripts/tests/lib/*.sh).
# Step 2: run every $SCRIPTS/tests/*.bats — under real `bats` if installed,
#         otherwise via `bash <file>` (the .bats files source bats-fallback.sh
#         which preprocesses + re-execs themselves under plain bash).
# Step 3: run $SCRIPTS/lint_skill.sh — structural lint over the skill layout.
#         (wired in by mech-14b; runs AFTER bats so a green test suite is a
#         prerequisite for the lint pass.)
#
# Aborts on the first failure of any step. Exit 0 on full success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$SCRIPT_DIR"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '[run-all] %s\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Step 0: is this bats strict enough to be believed?
#
# Nearly every assertion in this suite is a bare `[[ … ]]` in the middle of a
# test body. Some bats/bash combinations do NOT fail a test when one of those
# returns false — they fail on `false` and on a failing command, but a mid-body
# `[[ ]]` slips through, and only the LAST command decides the verdict. On such
# a host a test asserting five things effectively asserts one.
#
# That is not hypothetical: it hid a real contract violation here. The suite was
# green on macOS (bats 1.14) and the same commit failed on ubuntu-latest, where
# the assertion was enforced and a provider genuinely never answered.
#
# So the harness probes its own strictness and says so. It does NOT fail — a
# permissive bats still runs every test and still catches most breakage — but a
# green run on such a host is a weaker claim than a green run in CI, and the
# person reading the output deserves to know which one they have.
# ---------------------------------------------------------------------------
_probe_bats_strictness() {
  local probe rc
  probe="$(mktemp -d)/strict.bats"
  cat > "$probe" <<'PROBE'
@test "mid-body [[ ]] must fail the test" {
  true
  [[ "abc" == *"zzz"* ]]
  true
}
PROBE
  if ! command -v bats >/dev/null 2>&1; then rm -rf "$(dirname "$probe")"; return 0; fi
  bats "$probe" >/dev/null 2>&1 && rc=0 || rc=1
  rm -rf "$(dirname "$probe")"
  if [ "$rc" -eq 0 ]; then
    warn "[run-all] WARNING: this bats does NOT fail a test on a mid-body \`[[ ]]\`."
    warn "[run-all] Assertions that are not the last command in their test are being"
    warn "[run-all] skipped silently. A green run here is weaker than a green run in"
    warn "[run-all] CI (ubuntu-latest enforces them). Trust CI over this."
  fi
}
_probe_bats_strictness

# ---------------------------------------------------------------------------
# Step 1: shellcheck every script in $SCRIPTS (top level only, not tests/lib).
# ---------------------------------------------------------------------------
info "shellcheck pass over $SCRIPTS/*.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
  red "shellcheck missing on PATH — install with: brew install shellcheck (>=0.9)"
  exit 1
fi

shopt -s nullglob
sh_files=("$SCRIPTS"/*.sh)
shopt -u nullglob

if [ "${#sh_files[@]}" -eq 0 ]; then
  red "no .sh files found under $SCRIPTS"
  exit 1
fi

for f in "${sh_files[@]}"; do
  if ! shellcheck "$f"; then
    red "shellcheck failed for $f"
    exit 1
  fi
done
green "shellcheck OK (${#sh_files[@]} files)"

# ---------------------------------------------------------------------------
# Step 2: run bats fixtures.
# ---------------------------------------------------------------------------
shopt -s nullglob
bats_files=("$TESTS_DIR"/*.bats)
shopt -u nullglob

if [ "${#bats_files[@]}" -eq 0 ]; then
  red "no .bats files found under $TESTS_DIR"
  exit 1
fi

if command -v bats >/dev/null 2>&1; then
  info "running bats over ${#bats_files[@]} fixture(s) via real bats"
  if ! bats "${bats_files[@]}"; then
    red "bats run failed"
    exit 1
  fi
else
  info "bats not on PATH — falling back to plain-bash invocation (bats-fallback.sh)"
  for f in "${bats_files[@]}"; do
    info "  bash $f"
    if ! bash "$f"; then
      red "fallback run failed for $f"
      exit 1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Step 3: lint_skill.sh — structural lint (mech-14b wire-in).
# ---------------------------------------------------------------------------
info "running lint_skill.sh"
if ! bash "$SCRIPTS/lint_skill.sh"; then
  red "lint_skill.sh failed"
  exit 1
fi
green "lint_skill.sh OK"

green "all checks passed"
exit 0

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

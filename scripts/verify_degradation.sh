#!/usr/bin/env bash
# verify_degradation.sh — prove the bundle reaches a verdict on the declared base
# set alone, with every optional tool unreachable.
#
#   verify_degradation.sh
#
# THE STORY THIS CLOSES. "Optional tooling degrades visibly, never fails
# silently" was asserted in a README and tested by nothing. Worse, CI installed
# bats, jq AND shellcheck on every runner, so the suite proved the opposite
# condition: every optional tool present, every time.
#
# METHOD. Build a PATH containing only the base set — bash, git, python3, jq and
# the POSIX coreutils the scripts call — with rtk, just, repomix, graphify,
# codegraph, shellcheck and bats absent. Then assert each entry point still
# prints a verdict rather than dying at a `require_*`.
#
# jq STAYS. It is not optional and must never be described as such: crew_check.sh,
# coverage_check.sh, detect_language.sh and preflight_subskills.sh all hard-require
# it. A run that removed jq would be testing a configuration the plugin does not
# claim to support.
#
# WHY THE PATH IS BUILT FROM ABSOLUTE PATHS. `command -v grep` returns a bare word
# when grep is a shell function — which it is in some interactive setups — and
# `ln -s` on that makes a self-referential symlink. The resulting exec failure
# looks exactly like the degradation bug this script hunts, so the fixture
# verifies itself before it judges anything.
#
# Exits 0 when every entry point reaches a verdict, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$(mktemp -d)"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$BIN" "$FAKE_HOME"' EXIT

BASE_TOOLS="bash sh git python3 jq sed grep awk cat ls mkdir rm find sort head tail
            wc tr cut date dirname basename env mktemp cp mv chmod uname xargs uniq
            realpath readlink stat touch expr sleep comm paste seq tee diff pwd rmdir ln"

for t in $BASE_TOOLS; do
  for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
    if [ -x "$d/$t" ]; then ln -sf "$d/$t" "$BIN/$t"; break; fi
  done
done

broken="$(find "$BIN" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
if [ "$broken" -ne 0 ]; then
  echo "FAIL: the fixture itself has $broken dangling symlink(s) — fix the harness before trusting its verdict"
  find "$BIN" -type l ! -exec test -e {} \; -print
  exit 1
fi

present=""
for t in rtk just repomix graphify codegraph shellcheck bats; do
  PATH="$BIN" command -v "$t" >/dev/null 2>&1 && present="$present $t"
done
if [ -n "$present" ]; then
  echo "FAIL: optional tool(s) reachable in the fixture PATH —$present"
  exit 1
fi
echo "optional tools confirmed absent: rtk just repomix graphify codegraph shellcheck bats"
echo

fail=0

verdict() { # $1 label  $2… command
  local label="$1"; shift
  local out
  out="$(PATH="$BIN" HOME="$FAKE_HOME" "$@" 2>&1)"
  if printf '%s' "$out" | grep -qE '^(STATUS=|PASS|FAIL)'; then
    echo "  ok       $label — $(printf '%s' "$out" | head -1)"
  else
    echo "  NO VERDICT $label — died without printing one:"
    printf '%s\n' "$out" | head -3 | sed 's/^/             /'
    fail=1
  fi
}

echo "entry points on the base set alone:"
verdict "detect_language" bash "$ROOT/skills/team-sprint/scripts/detect_language.sh" "$ROOT"
verdict "crew_check"      bash "$ROOT/skills/team-sprint/scripts/crew_check.sh" check bash --project-dir "$ROOT"
verdict "recon"           bash "$ROOT/skills/team-sprint/scripts/recon.sh" text 'require_jq' "$ROOT"
verdict "budget_check"    bash "$ROOT/scripts/budget_check.sh"
verdict "name_check"      bash "$ROOT/scripts/name_check.sh"

echo
echo "runtime state with no user config directory:"
if PATH="$BIN" HOME="$FAKE_HOME" bash "$ROOT/skills/self-improve/scripts/ledger.sh" add demo hook "degradation smoke" >/dev/null 2>&1; then
  echo "  ok       ledger.sh wrote to the state dir"
else
  echo "  FAIL     ledger.sh could not write with no user config dir"
  fail=1
fi

# Captured, not piped: `ceiling.sh check` exits 1 by design when a target has no
# budget, and under `set -o pipefail` that status would sink the whole pipeline
# even when grep matched — reporting a failure for the exact behaviour being
# asserted.
ceiling_out="$(PATH="$BIN" HOME="$FAKE_HOME" bash "$ROOT/skills/self-improve/scripts/ceiling.sh" check team-sprint 2>&1)"
if printf '%s' "$ceiling_out" | grep -q 'no recorded budget'; then
  echo "  ok       ceiling.sh reports 'no recorded budget' rather than crashing"
else
  echo "  FAIL     ceiling.sh did not bootstrap cleanly on a fresh install"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS: every entry point reaches a verdict on the base set alone"
else
  echo "FAIL: something died instead of degrading — see above"
fi
exit "$fail"

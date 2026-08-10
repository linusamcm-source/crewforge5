#!/usr/bin/env bash
# name_check.sh — assert every shipped skill and agent is invocable under the
# name its path implies.
#
# Frontmatter `name` drives invocation, not the filename. When the two disagree
# the component still works, but every reference to it by path is a lie and
# `crew-factory`'s manifest — which addresses agents by name — silently misses.
# One shipped agent got this wrong before the plugin existed, which is why this
# is asserted mechanically rather than by eye.
#
# A deliberate divergence is recorded in scripts/name-exceptions.txt as
# `<path>:<name>` and passes; anything else fails.
#
# Exits 0 when every name matches, 1 with one MISMATCH line per offender.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
EXCEPTIONS="$HERE/name-exceptions.txt"

fail=0

check() { # $1 file  $2 expected name
  local declared
  declared="$(sed -n '/^---$/,/^---$/p' "$1" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d '\r')"
  local rel="${1#"$ROOT"/}"
  if [ -z "$declared" ]; then
    echo "MISSING  $rel declares no frontmatter name"
    fail=1
    return
  fi
  [ "$declared" = "$2" ] && return
  if [ -f "$EXCEPTIONS" ] && grep -qxF "$rel:$declared" "$EXCEPTIONS"; then
    echo "ALLOWED  $rel declares '$declared' (recorded exception)"
    return
  fi
  echo "MISMATCH $rel declares '$declared', path implies '$2'"
  fail=1
}

for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  check "$f" "$(basename "$(dirname "$f")")"
done

for f in "$ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  check "$f" "$(basename "$f" .md)"
done

[ "$fail" -eq 0 ] && echo "PASS: every shipped skill and agent matches its path"
exit "$fail"

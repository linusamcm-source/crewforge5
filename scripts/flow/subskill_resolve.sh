#!/usr/bin/env bash
# subskill_resolve.sh — turn a skill name into an absolute SKILL.md path, so a
# skill hidden from the catalogue stays reachable without the `Skill` tool, and
# report how the caller must load what it found.
#
# Usage:
#   subskill_resolve.sh <name>              print the absolute SKILL.md path
#   subskill_resolve.sh --probe <name>      presence check; exit 0/1, no stdout
#   subskill_resolve.sh --load-mode <name>  MODE=inline | MODE=agent AGENT=<type>
#
# A skill carrying `disable-model-invocation: true` is absent from the per-turn
# catalogue AND unreachable through the `Skill` tool, so every "invoke the <X>
# skill" instruction has to become "resolve <X> to a path and load it".
#
# Search order, first hit wins:
#   1. $CREWFORGE_ROOT/skills/<name>/SKILL.md   (plugin tree; defaults to the
#      root two levels above this script, so an uninstalled checkout works)
#   2. <repo-root>/.claude/skills/<name>/SKILL.md   (project catalogue)
#   3. $HOME/.claude/skills/<name>/SKILL.md         (user catalogue)
# The plugin copy wins because a plugin ships its own sub-skills and must not be
# hijacked by a same-named skill in whatever repo it happens to be pointed at.
#
# `-` and `_` are interchangeable in a name: `master-plan` and `master_plan`
# both reach skills/master_plan. Directory names in this bundle disagree with
# each other on the separator and every call site would otherwise have to
# memorise which is which.
#
# stdout is one bare absolute path, not a KEY=VALUE line, so a caller can write
# `p="$(subskill_resolve.sh <name>)"` and read it. --load-mode is KEY=VALUE
# because it answers two things at once.
#
# HOW the caller loads what it resolved is not cosmetic. A skill declaring
# `context: fork` declares it precisely so its work does NOT land in the
# caller's context window — `use-repo-code` greps a whole repomix pack. Reading
# such a body inline keeps the instructions and destroys the isolation, which
# inverts the reason the skill forks. --load-mode reports which of the two a
# given skill needs; `context:` is read from the YAML frontmatter only, since
# several skill bodies discuss `context: fork` in prose without declaring it.
#
# Exit codes: 0 resolved, 1 not found, 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CREWFORGE_ROOT:-$(cd "$HERE/../.." && pwd)}"

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

MODE="path"
NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --probe)     [ $# -ge 2 ] || usage; MODE="probe";     NAME="$2"; shift 2 ;;
    --load-mode) [ $# -ge 2 ] || usage; MODE="load-mode"; NAME="$2"; shift 2 ;;
    -h|--help)   usage ;;
    -*)          usage ;;
    *)           [ -z "$NAME" ] || usage; NAME="$1"; shift ;;
  esac
done

[ -n "$NAME" ] || usage

# `git rev-parse` is the honest answer to "which repo am I in"; $PWD is the
# fallback for a caller outside any repo.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || REPO_ROOT="$PWD"

ROOT_1="$PLUGIN_ROOT/skills"
ROOT_2="$REPO_ROOT/.claude/skills"
ROOT_3="${HOME:-}/.claude/skills"

# Separator variants. Duplicates are harmless — they re-test the same path —
# so no dedup, which keeps this readable under bash 3.2 (no associative arrays).
NAME_1="$NAME"
NAME_2="${NAME//-/_}"
NAME_3="${NAME//_/-}"

resolve() {
  local root cand path
  for root in "$ROOT_1" "$ROOT_2" "$ROOT_3"; do
    for cand in "$NAME_1" "$NAME_2" "$NAME_3"; do
      path="$root/$cand/SKILL.md"
      if [ -f "$path" ]; then
        printf '%s\n' "$path"
        return 0
      fi
    done
  done
  return 1
}

RESOLVED="$(resolve)" || {
  if [ "$MODE" != "probe" ]; then
    printf 'subskill_resolve.sh: no SKILL.md for "%s"\n' "$NAME" >&2
    printf 'searched: %s\n' "$ROOT_1" "$ROOT_2" "$ROOT_3" >&2
  fi
  exit 1
}

case "$MODE" in
  probe)
    exit 0
    ;;

  path)
    printf '%s\n' "$RESOLVED"
    ;;

  load-mode)
    # Frontmatter only: the first `---`-delimited block, CRs stripped.
    FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$RESOLVED" | tr -d '\r')"
    if printf '%s\n' "$FRONTMATTER" | grep -q '^context:[[:space:]]*fork[[:space:]]*$'; then
      AGENT="$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^agent:[[:space:]]*//p' | head -1)"
      if [ -n "$AGENT" ]; then
        printf 'MODE=agent AGENT=%s\n' "$AGENT"
      else
        printf 'MODE=agent\n'
      fi
    else
      printf 'MODE=inline\n'
    fi
    ;;
esac

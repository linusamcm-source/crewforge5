#!/usr/bin/env bash
# sprint_init.sh — install the plugin's rule files into a target, by symlink.
#
#   sprint_init.sh report     [--user|--project DIR]   what exists, what conflicts
#   sprint_init.sh install    [--user|--project DIR] [--yes]
#   sprint_init.sh uninstall  [--user|--project DIR]
#
# WHY SYMLINKS, AND WHY A COMMAND. A plugin cannot ship `.claude/rules/`, and it
# must never write to anyone's CLAUDE.md — so the rules land as links the user
# asks for and can see. A link also means a plugin update updates the rule, and
# `uninstall` leaves nothing behind but the empty directory it found.
#
# `report` runs first and refuses to install over a contradiction: a rule of
# yours that says the opposite of one of ours is a decision for you to make, not
# something to resolve by overwriting.
#
# Exits 0 on success, 1 on a refused install, 2 on usage error.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
RULES="$ROOT/rules"

MODE="${1:-report}"
shift || true
SCOPE="project"
TARGET_DIR="$PWD"
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    SCOPE="user"; shift ;;
    --project) SCOPE="project"; TARGET_DIR="${2:?--project needs a directory}"; shift 2 ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    *) echo "usage: sprint_init.sh {report|install|uninstall} [--user|--project DIR] [--yes]" >&2; exit 2 ;;
  esac
done

if [ "$SCOPE" = "user" ]; then
  DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules"
  CLAUDE_MD="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
else
  DEST="$TARGET_DIR/.claude/rules"
  CLAUDE_MD="$TARGET_DIR/CLAUDE.md"
fi

[ -d "$RULES" ] || { echo "no rules/ directory at $RULES" >&2; exit 2; }

# --------------------------------------------------------------------------
# Contradictions. Each entry is `<pattern-we-fear>|<the rule it contradicts>`.
# The patterns are deliberately few and specific: a report that cries wolf is
# one nobody reads, and a false positive here blocks an install.
# --------------------------------------------------------------------------
# `::` separates the two fields, not `|` — the patterns are extended regexes and
# are full of alternation.
contradictions() { # $1 = file to read
  [ -f "$1" ] || return 0
  local found=0 line pat rule
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pat="${line%%::*}"
    rule="${line#*::}"
    if grep -qiE "$pat" "$1"; then
      echo "  CONFLICT  $(basename "$1"): matches /$pat/"
      echo "            against CrewForge's $rule"
      found=1
    fi
  done <<'EOF'
git add (-A|--all|\.)([^A-Za-z0-9]|$)::git-hygiene rule — stage explicit paths (bash-guard denies exactly this)
find[[:space:]]+(/|~|\$HOME)([[:space:]]|$)::git-hygiene rule — never run find from / or ~
EOF
  return "$found"
}

listing() {
  local f
  for f in "$RULES"/*.md; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done
}

case "$MODE" in
  report)
    echo "target: $DEST"
    echo "rules to install:"
    listing | while read -r f; do
      n="$(basename "$f")"
      if [ -L "$DEST/$n" ]; then
        echo "  linked    $n -> $(readlink "$DEST/$n")"
      elif [ -e "$DEST/$n" ]; then
        echo "  BLOCKED   $n (a real file is already there)"
      else
        echo "  new       $n"
      fi
    done
    echo "existing instructions: $CLAUDE_MD"
    if [ -f "$CLAUDE_MD" ]; then
      if contradictions "$CLAUDE_MD"; then
        echo "  no contradictions found"
      fi
    else
      echo "  (none)"
    fi
    ;;

  install)
    if [ -f "$CLAUDE_MD" ] && ! contradictions "$CLAUDE_MD"; then
      echo "refusing to install over a contradiction — resolve it, or edit the rule you disagree with." >&2
      exit 1
    fi
    if [ "$ASSUME_YES" -ne 1 ]; then
      echo "about to link $(listing | wc -l | tr -d ' ') rule file(s) into $DEST"
      printf 'proceed? [y/N] '
      read -r ans
      case "$ans" in y|Y|yes|YES) ;; *) echo "aborted"; exit 1 ;; esac
    fi
    mkdir -p "$DEST" || { echo "cannot create $DEST" >&2; exit 1; }
    rc=0
    listing | while read -r f; do
      n="$(basename "$f")"
      if [ -e "$DEST/$n" ] && [ ! -L "$DEST/$n" ]; then
        echo "  skipped   $n (a real file is already there)"
        continue
      fi
      ln -sfn "$f" "$DEST/$n" && echo "  linked    $n"
    done
    exit "$rc"
    ;;

  uninstall)
    listing | while read -r f; do
      n="$(basename "$f")"
      if [ -L "$DEST/$n" ] && [ "$(readlink "$DEST/$n")" = "$f" ]; then
        rm -f "$DEST/$n" && echo "  removed   $n"
      elif [ -e "$DEST/$n" ]; then
        echo "  left      $n (not ours)"
      fi
    done
    rmdir "$DEST" 2>/dev/null && echo "  removed   $DEST (empty)"
    ;;

  *)
    echo "usage: sprint_init.sh {report|install|uninstall} [--user|--project DIR] [--yes]" >&2
    exit 2 ;;
esac

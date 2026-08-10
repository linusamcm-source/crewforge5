#!/usr/bin/env bash
# pack-grep.sh <pattern> [extra grep flags...] — search the repomix pack with the
# canonical fallback chain: rtk grep (token-filtered, grouped by file) when on
# PATH, else bounded grep -nE. Always includes -B 2 so each hit carries its
# owning <file path="..."> tag. Respects $REPOMIX_PACK.
set -euo pipefail

PAT="${1:?usage: pack-grep.sh <pattern> [extra grep flags...]}"
shift || true
PACK="${REPOMIX_PACK:-.repomix-output.xml}"
[ -f "$PACK" ] || { echo "error=no pack at $PACK — run pack.sh first" >&2; exit 1; }

# rtk grep is BRE-only: patterns using ERE metachars (alternation, groups,
# intervals) must go to grep -nE or they silently miss / error.
case "$PAT" in
  *'('*|*'|'*|*'{'*|*'+'*|*'?'*)
    grep -nE -B 2 -m 40 "$@" -- "$PAT" "$PACK"
    ;;
  *)
    if command -v rtk >/dev/null 2>&1; then
      rtk grep "$PAT" "$PACK" -B 2 "$@"
    else
      grep -nE -B 2 -m 40 "$@" -- "$PAT" "$PACK"
    fi
    ;;
esac

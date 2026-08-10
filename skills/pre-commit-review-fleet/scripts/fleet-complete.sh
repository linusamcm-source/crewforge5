#!/usr/bin/env bash
# fleet-complete.sh <artifact-dir> <reviewer>... — Step 3 completeness check,
# mechanised. A reviewer is accounted for only if an artifact matching
# *<reviewer>*.json or *<reviewer>*.md exists in <artifact-dir> AND (for .json)
# parses with a findings array. Missing/invalid reviewers are listed; exit 1 if
# any — re-spawn them rather than aggregating an incomplete fleet.
set -euo pipefail

DIR="${1:?usage: fleet-complete.sh <artifact-dir> <reviewer>...}"
shift
[ $# -gt 0 ] || { echo "error=no reviewers named" >&2; exit 2; }
[ -d "$DIR" ] || { echo "complete=no"; echo "missing=$*"; echo "reason=artifact dir $DIR does not exist"; exit 1; }

missing=""
for r in "$@"; do
  # shellcheck disable=SC2012  # ls, not find, is correct here: the two globs must
  # be sorted TOGETHER so the newest artifact wins regardless of extension, and a
  # find rewrite would sort .json and .md as separate groups. The names are
  # generated artifact filenames in a directory this script created, never user
  # input, so the non-alphanumeric hazard SC2012 warns about cannot arise.
  f="$(ls -1 "$DIR"/*"$r"*.json "$DIR"/*"$r"*.md 2>/dev/null | tail -1 || true)"
  if [ -z "$f" ]; then
    missing="$missing $r"
    continue
  fi
  case "$f" in
    *.json)
      if python3 -c "
import json, sys
d = json.load(open('$f'))
sys.exit(0 if isinstance(d.get('findings'), list) else 1)
" 2>/dev/null; then
        echo "ok=$r artifact=$f"
      else
        missing="$missing $r"
        echo "invalid=$r artifact=$f (no findings array / bad JSON)"
      fi
      ;;
    *)
      echo "ok=$r artifact=$f"
      ;;
  esac
done

if [ -n "$missing" ]; then
  echo "complete=no"
  echo "missing=${missing# }"
  exit 1
fi
echo "complete=yes"

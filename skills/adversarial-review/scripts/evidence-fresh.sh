#!/usr/bin/env bash
# evidence-fresh.sh <artifact> [compare-file] — mechanised snapshot freshness check (SKILL.md § Evidence Rules).
# An artifact (.repomix-output.xml, graphify-out/graph.json) is FRESH only if it is
# newer than (a) the newest tracked source file in the repo and (b) the compare-file
# (usually the spec/plan under review) when given.
# Prints key=value lines; exit 0 fresh, 1 stale/missing.
set -euo pipefail

ART="${1:?usage: evidence-fresh.sh <artifact> [compare-file]}"
CMP="${2:-}"

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

[ -f "$ART" ] || { echo "fresh=no"; echo "reason=artifact missing: $ART"; exit 1; }
am="$(mtime "$ART")"
now="$(date +%s)"
echo "artifact=$ART"
echo "artifact_age_s=$((now - am))"

stale=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  newest=0
  newest_f=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in "$ART"|graphify-out/*|.repomix*) continue;; esac
    m="$(mtime "$f")"
    if [ "$m" -gt "$newest" ]; then newest="$m"; newest_f="$f"; fi
  done < <(git ls-files)
  echo "newest_source=$newest_f"
  echo "newest_source_age_s=$((now - newest))"
  [ "$am" -lt "$newest" ] && stale="artifact older than $newest_f"
else
  echo "newest_source=UNKNOWN (not a git repo — compare manually)"
fi

if [ -n "$CMP" ] && [ -f "$CMP" ]; then
  cm="$(mtime "$CMP")"
  echo "compare_file_age_s=$((now - cm))"
  [ "$am" -lt "$cm" ] && stale="${stale:+$stale; }artifact older than $CMP"
fi

if [ -n "$stale" ]; then
  echo "fresh=no"
  echo "reason=$stale — refresh the artifact or fall back to live Read/Grep"
  exit 1
fi
echo "fresh=yes"

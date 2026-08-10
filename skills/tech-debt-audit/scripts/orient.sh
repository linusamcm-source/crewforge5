#!/usr/bin/env bash
# orient.sh [scope-dir] — Phase 1 steps 4-6, mechanised: churn, size, and the
# size×churn intersection where debt usually hides. Also emits the LOC-based
# findings-budget band. Run from the repo root.
set -euo pipefail

SCOPE="${1:-.}"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error=not a git repo" >&2; exit 1; }

TMPL="$(mktemp)"; TMPC="$(mktemp)"; trap 'rm -f "$TMPL" "$TMPC"' EXIT

# top 20 largest tracked text files by line count
git ls-files -- "$SCOPE" \
  | grep -vE '\.(png|jpg|jpeg|gif|ico|pdf|zip|gz|woff2?|ttf|otf|mp4|lock)$|package-lock\.json|bun\.lockb' \
  | while IFS= read -r f; do [ -f "$f" ] && printf '%s\t%s\n' "$(wc -l <"$f" | tr -d ' ')" "$f"; done \
  | sort -rn | head -20 > "$TMPL"

echo "== top 20 largest files (lines<TAB>path) =="
cat "$TMPL"

# top 20 most-modified in the last 6 months
git log --since="6 months ago" --name-only --pretty=format: -- "$SCOPE" \
  | grep -vE '^$' | sort | uniq -c | sort -rn | head -20 > "$TMPC"

echo "== top 20 most-modified files, 6 months (commits<SPACE>path) =="
cat "$TMPC"

echo "== intersection: large AND hot (debt usually hides here) =="
inter=0
while IFS=$'\t' read -r _ f; do
  if grep -qF " $f" "$TMPC"; then echo "$f"; inter=$((inter + 1)); fi
done < "$TMPL"
[ "$inter" -eq 0 ] && echo "(none)"

loc=$(git ls-files -- "$SCOPE" \
  | grep -vE '\.(png|jpg|jpeg|gif|ico|pdf|zip|gz|woff2?|ttf|otf|mp4|lock)$|package-lock\.json' \
  | while IFS= read -r f; do [ -f "$f" ] && wc -l <"$f"; done | awk '{s+=$1} END{print s+0}')
files=$(git ls-files -- "$SCOPE" | wc -l | tr -d ' ')
echo "repo_loc=$loc"
echo "tracked_files=$files"
if [ "$loc" -lt 5000 ]; then echo "findings_budget=10-30 (small repo)"
elif [ "$loc" -lt 50000 ]; then echo "findings_budget=30-80 (medium repo)"
else echo "findings_budget=see references/large-repos.md (large repo)"; fi

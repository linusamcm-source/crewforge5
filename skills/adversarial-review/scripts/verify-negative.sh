#!/usr/bin/env bash
# verify-negative.sh <term> [dir] — mechanised triple verification of negative claims (SKILL.md § Evidence Rules).
# Runs ALL THREE required searches for a negative claim ("X does not exist"):
#   1. exact-string match        (git grep -F, fallback grep -rF)
#   2. case-insensitive match    (git grep -Fi)
#   3. filename glob             (git ls-files | grep -i)
# Prints each search's count and up to 5 sample hits — quote this output verbatim
# as the finding's evidence. Exit 0 = negative CONFIRMED (all three zero),
# exit 1 = negative REFUTED (something matched).
set -euo pipefail

TERM="${1:?usage: verify-negative.sh <term> [dir]}"
DIR="${2:-.}"
cd "$DIR"

if git rev-parse --git-dir >/dev/null 2>&1; then
  exact="$( (git grep --untracked -nF "$TERM" -- . 2>/dev/null || true) | head -5)"
  ci="$( (git grep --untracked -nFi "$TERM" -- . 2>/dev/null || true) | head -5)"
  exact_n="$( (git grep --untracked -nF "$TERM" -- . 2>/dev/null || true) | wc -l | tr -d ' ')"
  ci_n="$( (git grep --untracked -nFi "$TERM" -- . 2>/dev/null || true) | wc -l | tr -d ' ')"
  files="$( (git ls-files -co --exclude-standard | grep -i -- "$TERM" || true) | head -5)"
  files_n="$( (git ls-files -co --exclude-standard | grep -ci -- "$TERM") || true)"
else
  exact="$( (grep -rnF "$TERM" . 2>/dev/null || true) | head -5)"
  ci="$( (grep -rnFi "$TERM" . 2>/dev/null || true) | head -5)"
  exact_n="$( (grep -rnF "$TERM" . 2>/dev/null || true) | wc -l | tr -d ' ')"
  ci_n="$( (grep -rnFi "$TERM" . 2>/dev/null || true) | wc -l | tr -d ' ')"
  files="$( (find . -iname "*$TERM*" -not -path './.git/*' 2>/dev/null || true) | head -5)"
  files_n="$( (find . -iname "*$TERM*" -not -path './.git/*' 2>/dev/null || true) | wc -l | tr -d ' ')"
fi
files_n="${files_n:-0}"

echo "term=$TERM"
echo "search_1_exact_hits=$exact_n"
[ -n "$exact" ] && printf '%s\n' "$exact" | sed 's/^/  exact: /'
echo "search_2_case_insensitive_hits=$ci_n"
[ -n "$ci" ] && printf '%s\n' "$ci" | sed 's/^/  ci: /'
echo "search_3_filename_glob_hits=$files_n"
[ -n "$files" ] && printf '%s\n' "$files" | sed 's/^/  glob: /'

if [ "$exact_n" -eq 0 ] && [ "$ci_n" -eq 0 ] && [ "$files_n" -eq 0 ]; then
  echo "negative_confirmed=yes"
  exit 0
fi
echo "negative_confirmed=NO — the claim 'does not exist' is FALSE"
exit 1

#!/usr/bin/env bash
# capture-diff.sh [scope-path...] — Step 1 mechanised: capture the staged diff,
# emit stats, and classify triviality (the documented skip conditions).
# Writes the patch to $PRECOMMIT_PATCH (default /tmp/pre-commit-diff.patch).
# Exit 1 when nothing is staged. trivial=yes is advisory — the model confirms.
set -euo pipefail

PATCH="${PRECOMMIT_PATCH:-/tmp/pre-commit-diff.patch}"

if git diff --cached --quiet; then
  echo "staged=no"
  echo "error=No staged changes — stage with git add first."
  exit 1
fi

if [ $# -gt 0 ]; then
  git diff --cached -- "$@" > "$PATCH"
else
  git diff --cached > "$PATCH"
fi

files=0 ins=0 del=0
while IFS=$'\t' read -r a d _; do
  files=$((files + 1))
  [ "$a" != "-" ] && ins=$((ins + a))
  [ "$d" != "-" ] && del=$((del + d))
done < <(git diff --cached --numstat -- "$@")

echo "patch=$PATCH"
echo "files=$files"
echo "insertions=$ins"
echo "deletions=$del"
git diff --cached --name-only -- "$@" | sed 's/^/file=/'

# triviality: every changed file is docs/lockfile/snapshot, or the diff is tiny
nontrivial=0
while IFS= read -r f; do
  case "$f" in
    *.md|*.txt|*.rst|LICENSE*|*.lock|package-lock.json|yarn.lock|bun.lockb|*.snap) ;;
    *) nontrivial=$((nontrivial + 1));;
  esac
done < <(git diff --cached --name-only -- "$@")

if [ "$nontrivial" -eq 0 ]; then
  echo "trivial=yes"
  echo "trivial_reason=all changed files are docs/lockfiles/snapshots"
elif [ $((ins + del)) -lt 30 ]; then
  echo "trivial=maybe"
  echo "trivial_reason=diff under 30 lines — fleet is optional unless security-relevant paths changed"
else
  echo "trivial=no"
fi

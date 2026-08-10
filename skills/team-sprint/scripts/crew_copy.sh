#!/usr/bin/env bash
# crew_copy.sh — carry the repo's agent crew into a worktree.
#
#   crew_copy.sh <main-tree> <worktree>
#
# THE FAILURE THIS EXISTS TO PREVENT. A sprint's Phase 0 can generate a crew
# AFTER a worktree was cut from a base ref that predates the crew commit. The
# worktree then lacks the very agents the manifest promises, and it does not
# fail at Phase 0 — it fails at spawn, mid-sprint, per node.
#
# WHY PER-WORKTREE. `worktree_strategy: per-node` is the default and
# `schedule.sh` derives a distinct path per node, so a copy that runs once at
# sprint setup leaves every node worktree crewless. This runs at the creation of
# EACH worktree — the integration worktree in Phase 2, each node worktree at
# claim time in Phase execute.
#
# ONE WAY, AND NEVER BACKWARDS. The main tree is authoritative, so copies cannot
# drift within a sprint. The single exception is a destination file NEWER than
# its source: a node that regenerated its own agent mid-sprint has something the
# main tree does not, and clobbering it would silently discard work.
#
# Output: STATUS=OK|NO_CREW, plus COPIED= and SKIPPED_NEWER= counts.
# Exits 0 when the crew landed or there was none to land, 1 on a real error.
set -uo pipefail

MAIN="${1:-}"
WT="${2:-}"

if [ -z "$MAIN" ] || [ -z "$WT" ]; then
  echo "usage: crew_copy.sh <main-tree> <worktree>" >&2
  exit 1
fi
[ -d "$MAIN" ] || { echo "STATUS=FAIL"; echo "REASON=main-tree-missing"; exit 1; }
[ -d "$WT" ]   || { echo "STATUS=FAIL"; echo "REASON=worktree-missing"; exit 1; }

copied=0
skipped=0
found=0

copy_dir() { # $1 = relative dir under .claude
  local src="$MAIN/.claude/$1" dst="$WT/.claude/$1" f base
  [ -d "$src" ] || return 0
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    found=$((found + 1))
    base="$(basename "$f")"
    mkdir -p "$dst" || { echo "STATUS=FAIL"; echo "REASON=cannot-create:$dst"; exit 1; }
    if [ -f "$dst/$base" ] && [ "$dst/$base" -nt "$f" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    cp -p "$f" "$dst/$base" || { echo "STATUS=FAIL"; echo "REASON=copy-failed:$base"; exit 1; }
    copied=$((copied + 1))
  done
}

copy_dir agents
copy_dir crews

if [ "$found" -eq 0 ]; then
  # A repo with no crew is the normal case before crew-factory has ever run.
  # Say so rather than reporting a successful copy of nothing.
  echo "STATUS=NO_CREW"
  echo "COPIED=0"
  echo "SKIPPED_NEWER=0"
  exit 0
fi

echo "STATUS=OK"
echo "COPIED=$copied"
echo "SKIPPED_NEWER=$skipped"
exit 0

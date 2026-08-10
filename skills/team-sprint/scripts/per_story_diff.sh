#!/usr/bin/env bash
# per_story_diff.sh — emit the unified diff for a single sprint story.
#
# Usage:
#   per_story_diff.sh <story_id>
#
# Diff-base resolution (highest precedence first):
#   - TS_DIFF_BASE env short-circuit (Story GH3): diff from that sha without
#     reading state.json at all — no story_commits, no merge-base. Graph-mode
#     node executors MUST use this with the node's claim-time base_commit
#     (the integration HEAD the node branched from); story-commit/merge-base
#     resolution would fold previously integrated stories into the diff (D8).
#   - otherwise state.json is read via state.sh read, then lib.sh
#     resolve_diff_base:
#       - prior story SHA from state.json.story_commits[] (if <story_id> is
#         not the first in the sprint and a prior entry exists)
#       - otherwise: git merge-base <sprint_branch> <target_branch>
#
# HEAD expectation (Story GH4 / D6): the output is `git diff BASE...HEAD` —
# committed work only. Callers run this BEFORE the Phase 6 story commit, so
# phases 3/5 MUST have landed the story's in-flight work as provisional
# `wip(<story-id>)` commits first; otherwise the diff is empty. Working-tree
# diffs are not a substitute — they miss untracked files. Phase 6 squashes
# the wip commits into the single story commit.
#
# Required env:
#   TS_PLAN_PATH         path to the sprint plan (used to locate state.json;
#                        not required when TS_DIFF_BASE is set)
#
# Optional env:
#   TS_DIFF_BASE         explicit diff base sha/ref — highest precedence
#   TS_SPRINT_BRANCH     sprint branch (default: current HEAD branch)
#   TS_TARGET_BRANCH     target branch override (default: from state.json)
#
# Exit codes:
#   0 success
#   1 resolution error (missing arg, no plan path env, merge-base failure)
#   2 usage error

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_jq      || exit 1   # used at line 79; this script and state.sh are pure bash/jq/git

usage() {
  cat <<'USAGE' >&2
usage: per_story_diff.sh <story_id>
  env TS_PLAN_PATH must point at the sprint plan markdown so state.json can be located.
  env TS_DIFF_BASE (optional) short-circuits: diff from that sha, no state.json read.
USAGE
  exit 2
}

[[ $# -eq 1 ]] || usage
STORY_ID="${1:-}"
[[ -n "$STORY_ID" ]] || fail "per_story_diff.sh: empty story_id"

# TS_DIFF_BASE short-circuit (Story GH3 / D8): graph-mode executors pass the
# node's claim-time base_commit here — the only correct base for a node
# branch. Highest precedence; skips state.json entirely (no story_commits or
# merge-base consultation).
if [[ -n "${TS_DIFF_BASE:-}" ]]; then
  git diff "$TS_DIFF_BASE"...HEAD
  exit 0
fi

PLAN_PATH="${TS_PLAN_PATH:-}"
[[ -n "$PLAN_PATH" ]] || fail "per_story_diff.sh: TS_PLAN_PATH not set"

# state.sh read prints state.json on stdout, exits 2 if missing.
STATE_JSON="$("$SCRIPTS/state.sh" read "$PLAN_PATH")"

# Resolve the diff base via the shared lib.sh helper (deduped in Story LS4):
# prior story SHA from state.json.story_commits[], else merge-base(sprint,target).
SPRINT_BRANCH="${TS_SPRINT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
TARGET_BRANCH="${TS_TARGET_BRANCH:-$(printf '%s' "$STATE_JSON" | jq -r '.target_branch // ""')}"
BASE="$(resolve_diff_base "$STATE_JSON" "$STORY_ID" "$SPRINT_BRANCH" "$TARGET_BRANCH")"

git diff "$BASE"...HEAD

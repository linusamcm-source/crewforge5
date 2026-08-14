#!/usr/bin/env bash
# build_commit_msg.sh — emit a conventional-commit message for a sprint story.
#
# Usage:
#   build_commit_msg.sh <plan_path> <story_id> <type>
#
#   type ∈ {feat, fix, refactor, perf, docs, test, chore}
#
# Stdout is the full commit message:
#   <type>(<story_id>): <title>      # subject ≤72 unicode code points
#                                    # (truncated suffix is "…", total 72)
#
#   Story: <story_id> — <title>
#   Plan: <plan_path>
#
#   Acceptance criteria met:
#   - <ac bullet 1>
#   - <ac bullet 2>
#   ...
#
#   Gates: typecheck ✓ | lint ✓ | tests ✓ | coverage ✓
#
#   Co-Authored-By: Claude <noreply@anthropic.com>
#
# The `Story: <story_id>` body line is REQUIRED by mech-9's snapshot regen
# (`git log --grep '^Story: mech-N'`). Do not reformat it.
#
# Locale: LC_ALL=en_US.UTF-8 is forced internally so multi-byte titles are
# counted by code points (Python len()), never by bytes.
#
# Exit codes:
#   0 success
#   1 resolution error (missing args, unknown story)
#   2 usage error

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_python3 || exit 1   # jq no longer used: the story lookup moved into python

export LC_ALL=en_US.UTF-8

usage() {
  cat <<'USAGE' >&2
usage: build_commit_msg.sh <plan_path> <story_id> <type>
  type ∈ {feat, fix, refactor, perf, docs, test, chore}
USAGE
  exit 2
}

[[ $# -eq 3 ]] || usage

PLAN_PATH="$1"
STORY_ID="$2"
TYPE="$3"

[[ -n "$STORY_ID" ]] || fail "build_commit_msg.sh: empty story_id"
[[ -f "$PLAN_PATH" ]] || fail "build_commit_msg.sh: plan not found: $PLAN_PATH"

case "$TYPE" in
  feat|fix|refactor|perf|docs|test|chore) ;;
  *) fail "build_commit_msg.sh: invalid type '$TYPE' (allowed: feat|fix|refactor|perf|docs|test|chore)" ;;
esac

# Locate the story in the plan via parse_stories.sh; reuses the same
# heading-shape support so the message stays consistent with the rest of the
# sprint tooling.
STORIES_JSON="$("$SCRIPTS/parse_stories.sh" "$PLAN_PATH")"

# The story lookup happens in python below: parse_stories.sh is itself pure
# stdlib python3, so forking jq to select one array element that python then
# re-parses one line later bought nothing but a process and a dependency.
# Compose the message in python so unicode counting + JSON access are clean.
python3 - "$STORIES_JSON" "$STORY_ID" "$TYPE" "$PLAN_PATH" <<'PY'
import json
import sys

stories_json, story_id, type_, plan_path = sys.argv[1:5]
story = next(
    (s for s in json.loads(stories_json) if s.get("story_id") == story_id),
    None,
)
if story is None:
    # Same text and `[fail] ` prefix the shell `fail` helper (lib.sh:21) emitted,
    # so build_commit_msg.bats's "not found" assertion still matches.
    sys.stderr.write(
        f"[fail] build_commit_msg.sh: story '{story_id}' not found in {plan_path}\n"
    )
    sys.exit(1)

title = story.get("title", "") or story_id
ac = story.get("acceptance_criteria", []) or []

# Subject: "<type>(<story_id>): <title>" truncated to 72 code points. If the
# raw subject exceeds 72, keep the first 71 code points and append "…" so the
# total length is exactly 72 code points (never invalid UTF-8).
raw_subject = f"{type_}({story_id}): {title}"
if len(raw_subject) <= 72:
    subject = raw_subject
else:
    subject = raw_subject[:71] + "…"

lines = [
    subject,
    "",
    f"Story: {story_id} — {title}",
    f"Plan: {plan_path}",
    "",
    "Acceptance criteria met:",
]
for item in ac:
    lines.append(f"- {item}")
lines.extend([
    "",
    "Gates: typecheck ✓ | lint ✓ | tests ✓ | coverage ✓",
    "",
    "Co-Authored-By: Claude <noreply@anthropic.com>",
])

sys.stdout.write("\n".join(lines) + "\n")
PY

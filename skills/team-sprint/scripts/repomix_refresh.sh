#!/usr/bin/env bash
# repomix_refresh.sh — regenerate .repomix-output.xml when missing or stale.
# Story mech-7 deliverable.
#
# Usage:
#   repomix_refresh.sh [--max-age-minutes <n>] [--target-dir <path>]
#
# --max-age-minutes  default 60. Threshold compared against the mtime of
#                    <target>/.repomix-output.xml. If the pack is older,
#                    regenerate; otherwise no-op.
#
# --target-dir <path> default $PWD. May be absolute or relative-to-$PWD. The
#                     script `cd`s into <path> before invoking repomix and
#                     passes `-o .repomix-output.xml` explicitly so the
#                     output lands at <path>/.repomix-output.xml (overriding
#                     the repomix CLI default of `repomix-output.xml` without
#                     leading dot). The script returns to the original CWD on
#                     exit.
#
# Exit codes:
#   0 success (regenerated OR no-op fresh)
#   1 actual failure (missing repomix, repomix invocation failed, bad args)

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_repomix || exit 1

usage() {
  cat <<'USAGE' >&2
usage: repomix_refresh.sh [--max-age-minutes <n>] [--target-dir <path>]
USAGE
  exit 1
}

MAX_AGE_MINUTES=60
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-age-minutes)
      [[ $# -ge 2 ]] || usage
      MAX_AGE_MINUTES="$2"
      shift 2
      ;;
    --target-dir)
      [[ $# -ge 2 ]] || usage
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

# Validate max-age is a non-negative integer.
if ! [[ "$MAX_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
  fail "repomix_refresh.sh: --max-age-minutes must be a non-negative integer (got: $MAX_AGE_MINUTES)"
fi

# Resolve target dir. Relative paths resolve against the CALLER's CWD.
ORIG_CWD="$PWD"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$ORIG_CWD"
elif [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$ORIG_CWD/$TARGET_DIR"
fi

[[ -d "$TARGET_DIR" ]] || fail "repomix_refresh.sh: --target-dir not a directory: $TARGET_DIR"

# Canonicalise (resolves symlinks/.. so the pack path is stable).
TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"
PACK_FILE="$TARGET_DIR/.repomix-output.xml"

# Freshness check: file must exist AND be younger than MAX_AGE_MINUTES.
needs_refresh=1
if [[ -f "$PACK_FILE" ]]; then
  now_epoch="$(date +%s)"
  # mtime_epoch (lib.sh) handles the BSD/GNU stat split.
  file_mtime="$(mtime_epoch "$PACK_FILE")"
  age_seconds=$(( now_epoch - file_mtime ))
  max_age_seconds=$(( MAX_AGE_MINUTES * 60 ))
  if (( age_seconds <= max_age_seconds )); then
    needs_refresh=0
  fi
fi

if (( needs_refresh == 0 )); then
  info "repomix_refresh: $PACK_FILE is fresh (<= ${MAX_AGE_MINUTES}m); no-op"
  exit 0
fi

info "repomix_refresh: regenerating $PACK_FILE"

# cd into the target so repomix scans the right tree; ensure we return to the
# caller's CWD on every exit path. Explicit `-o .repomix-output.xml` overrides
# the CLI default to land at the dotfile path the rest of the skill expects.
trap 'cd "$ORIG_CWD"' EXIT

cd "$TARGET_DIR"
if ! repomix -o .repomix-output.xml >/dev/null 2>&1; then
  cd "$ORIG_CWD"
  fail "repomix_refresh.sh: repomix invocation failed in $TARGET_DIR"
fi

cd "$ORIG_CWD"
exit 0

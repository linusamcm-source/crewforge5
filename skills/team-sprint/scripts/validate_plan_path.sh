#!/usr/bin/env bash
# validate_plan_path.sh — Phase 0 plan-path uniqueness contract for the team-sprint skill.
#
# Validates that a plan filename carries a story/epic id slug, and classifies an
# existing per-sprint state directory as a legitimate resume vs. an accidental
# clobber. Also used by `team-sprint --abort` (via --slug-only) to derive the
# sprint directory from a plan path without re-running validation.
#
# Usage:
#   validate_plan_path.sh <plan_path>              # full validation
#   validate_plan_path.sh --slug-only <plan_path>  # derive slug + sprint dir only
#
# Run from the repo root — check 3 resolves `.team-sprint/` relative to $PWD.
#
# stdout — eval-safe KEY=VALUE lines (every value is [A-Za-z0-9._/-], no spaces):
#   SLUG=<kebab-slug>
#   SPRINT_DIR=.team-sprint/sprints/sprint-<slug>
#   STATUS=OK|RESUME|FAIL
# stderr — human-readable reason (emitted on RESUME and on every FAIL).
#
# Exit codes:
#   0  STATUS=OK | STATUS=RESUME  — proceed; caller branches on $STATUS
#   1  STATUS=FAIL                — naming-contract violation or clobber; STOP
#   2                             — usage error
set -euo pipefail

reason() { printf '%s\n' "$*" >&2; }

# Lowercase + collapse every non [a-z0-9-] character to a hyphen. `tr`/`sed`
# keep this bash-3.2 safe (the macOS default shell has no ${x,,}).
slug_of() {
  basename "$1" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g'
}

slug_only=false
if [[ "${1:-}" == "--slug-only" ]]; then
  slug_only=true
  shift
fi

plan_path="${1:-}"
if [[ -z "$plan_path" ]]; then
  reason "usage: validate_plan_path.sh [--slug-only] <plan_path>"
  echo "STATUS=FAIL"
  exit 2
fi

fname="$(basename "$plan_path" .md)"
slug="$(slug_of "$plan_path")"
sprint_dir=".team-sprint/sprints/sprint-${slug}"

echo "SLUG=${slug}"
echo "SPRINT_DIR=${sprint_dir}"

# --slug-only: caller (e.g. `team-sprint --abort`) just wants the derivation.
if [[ "$slug_only" == true ]]; then
  echo "STATUS=OK"
  exit 0
fi

# Check 1 — reject empty or generic filenames that carry no story id.
case "$fname" in
  ""|plan|story|stories|fix|fixes|untitled|readme|todo|tasks)
    reason "plan_path '${plan_path}' lacks a story id slug — rename to '<story-id>-<short-slug>.md'"
    echo "STATUS=FAIL"
    exit 1
    ;;
esac

# Check 2 — filename must contain a digit or a recognised id-token.
if ! printf '%s' "$fname" | grep -qE '([0-9]|BUG-|EPIC-|bug-|epic-|sprint-)'; then
  reason "plan_path '${plan_path}' does not include a story/epic id — rename to '<story-id>-<short-slug>.md'"
  echo "STATUS=FAIL"
  exit 1
fi

# Check 3 — collision check: distinguish resume from clobber.
if [[ -d "$sprint_dir" ]]; then
  state="${sprint_dir}/state.json"
  existing_plan="$(jq -r '.plan_path // ""' "$state" 2>/dev/null || true)"
  existing_done="$(jq -r '.done // false' "$state" 2>/dev/null || true)"
  if [[ "$existing_plan" == "$plan_path" && "$existing_done" != "true" ]]; then
    reason "resuming existing sprint at ${sprint_dir} (matches plan_path, not finalised)"
    echo "STATUS=RESUME"
    exit 0
  elif [[ "$existing_done" == "true" ]]; then
    reason "sprint dir '${sprint_dir}' already finalised (shipped) — pick a fresh story id slug for the new plan"
    echo "STATUS=FAIL"
    exit 1
  else
    reason "sprint dir '${sprint_dir}' exists for a different plan ('${existing_plan}') — rename current plan to a unique slug, or move the stale dir aside"
    echo "STATUS=FAIL"
    exit 1
  fi
fi

echo "STATUS=OK"
exit 0

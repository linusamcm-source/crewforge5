#!/usr/bin/env bash
# findings_gate.sh — prove a plan carries zero embedded FINDING markers.
#
# Phase 1's revise step is apply → fold → gate: apply_findings.sh annotates
# the plan with `<!-- FINDING <id> (<severity>): <recommendation> -->` marker
# lines, the lead folds each marker into revised prose (apply the
# recommendation, delete the marker), and this gate proves the fold finished.
# Without it the loop cannot converge — each round re-reviews a plan that is
# progressively more comment than content (sprint-recon-harness-1 ended with
# 64 markers embedded in a 58.4KB plan). A marker-laden plan must never be
# re-reviewed or promoted to plan-final.md.
#
# Usage:
#   findings_gate.sh <plan>
#
# Output: exactly one STATUS= line to stdout.
#   STATUS=OK COUNT=0      no `<!-- FINDING ` marker lines remain
#   STATUS=FAIL COUNT=<n>  n marker lines remain; each is listed on stderr as
#                          `findings_gate: line <N>: <marker text>`
#
# Exit codes:
#   0  STATUS=OK — the plan is fold-clean
#   1  STATUS=FAIL — markers remain
#   2  usage error, plan file missing, or plan unreadable (grep error) — the
#      gate fails CLOSED: a plan it could not read is never reported fold-clean

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
usage: findings_gate.sh <plan>
USAGE
  exit 2
}

main() {
  [[ $# -eq 1 ]] || usage
  local plan="$1"
  if [[ ! -f "$plan" ]]; then
    printf 'findings_gate.sh: plan not found: %s\n' "$plan" >&2
    exit 2
  fi

  # apply_findings.sh always starts a marker line with `<!-- FINDING ` at
  # column 0, so a fixed-string line grep is the whole detection. grep's exit
  # status must be captured explicitly: 1 means no match, but >1 means grep
  # never read the plan (permissions, bad path) — swallowing that with
  # `|| true` would fail the gate OPEN.
  local matches rc=0
  matches="$(grep -nF -- '<!-- FINDING ' "$plan")" || rc=$?
  if [[ "$rc" -gt 1 ]]; then
    printf 'findings_gate.sh: cannot read %s\n' "$plan" >&2
    exit 2
  fi

  if [[ -z "$matches" ]]; then
    printf 'STATUS=OK COUNT=0\n'
    return 0
  fi

  local count line
  count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  while IFS= read -r line; do
    printf 'findings_gate: line %s: %s\n' "${line%%:*}" "${line#*:}" >&2
  done <<<"$matches"
  printf 'STATUS=FAIL COUNT=%s\n' "$count"
  exit 1
}

main "$@"

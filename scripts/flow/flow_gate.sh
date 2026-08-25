#!/usr/bin/env bash
# flow_gate.sh — run a phase's declared gate, record the verdict, exit its code.
#
# Usage:
#   flow_gate.sh <flow> <phase>
# Runs the `gate` command declared for <phase> in skills/<flow>/phases.json,
# records phase.<phase>.status=PASS|FAIL plus phase.<phase>.stdout into
# state.json, prints STATUS=PASS or STATUS=FAIL, and exits the gate's own code.
# Gates run from the repo root, whatever directory the caller stood in, so a
# phases.json entry can name a repo-relative command.
#
# The gate's exit code is passed through rather than collapsed to 0/1, because
# a caller that wants to distinguish "gate failed" from "gate could not run"
# needs the number the gate actually chose.
#
# The gate's stdout is CAPTURED (this script's own stdout is the KEY=VALUE
# contract, and a gate's chatter on it would break every parser), recorded into
# state.json so a resumed flow can read why it stopped, and echoed to stderr so
# a human watching still sees it. The gate's stderr is never captured — it
# streams straight through.
#
# A phase declaring an empty gate records PASS without running anything: some
# phases are judgment, not a script, and that is a passable phase rather than a
# broken one. A phase id absent from the manifest is an error.
#
# Exit codes: the gate's own on a run gate; 0 when no gate is declared;
# 1 when the flow, manifest or phase cannot be resolved; 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_STATE="$HERE/flow_state.sh"

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

[ $# -eq 2 ] || usage
FLOW="$1"
PHASE="$2"
case "$FLOW$PHASE" in -*) usage ;; esac

command -v jq >/dev/null 2>&1 || { printf '[fail] jq missing — install: brew install jq\n' >&2; exit 1; }

MANIFEST="$("$FLOW_STATE" "$FLOW" manifest)" || exit 1

ROOT="$(git rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$ROOT" ]; then
  printf 'flow_gate.sh: not inside a git repository\n' >&2
  exit 1
fi
ROOT="$(cd "$ROOT/.." && pwd -P)"

# phases.json is either the bare array or {status_source, phases} — flow_next.sh
# documents both. Normalise before looking anything up, so a manifest that grew
# the object form does not silently stop resolving every phase in it.
# Checked, and empty is a failure: a malformed phases.json makes jq write
# nothing, FOUND then comes back empty rather than "0", and a `= "0"` guard
# would let an unknown phase through to be recorded PASS with no gate run. A
# gate that cannot read its own manifest must fail closed.
if ! NORM="$(jq 'if type == "array" then {phases: .} else . end' "$MANIFEST")" || [ -z "$NORM" ]; then
  printf 'flow_gate.sh: %s is not valid JSON\n' "$MANIFEST" >&2
  exit 1
fi

# Counting, not `.gate`: this distinguishes an absent phase from one whose gate
# is legitimately empty. `!= "1"` rather than `= "0"`, so an empty or duplicated
# answer is rejected too.
FOUND="$(printf '%s' "$NORM" | jq -r --arg id "$PHASE" '.phases | map(select(.id == $id)) | length')"
if [ "$FOUND" != "1" ]; then
  printf 'flow_gate.sh: %s does not name exactly one phase "%s" (found: %s)\n' \
    "$MANIFEST" "$PHASE" "${FOUND:-none}" >&2
  exit 1
fi

# A phase whose `when` excludes it is not part of this run, so gating it would
# record a verdict for work the flow never offered. flow_next.sh drops it from
# the manifest for the same reason; the two must agree or a `when`-excluded
# phase could be marked pass and confuse a later resume.
WHEN="$(printf '%s' "$NORM" | jq -r --arg id "$PHASE" '.phases | map(select(.id == $id)) | .[0].when // ""')"
if [ -n "$WHEN" ]; then
  ( cd "$ROOT" && bash -c "$WHEN" ) >/dev/null 2>&1
  WHEN_RC=$?
  case "$WHEN_RC" in
    0) ;;
    1) printf 'flow_gate.sh: phase %s is excluded from this run by its when clause\n' "$PHASE" >&2
       exit 1 ;;
    *) printf 'flow_gate.sh: the when clause for phase %s could not run: %s\n' "$PHASE" "$WHEN" >&2
       exit 1 ;;
  esac
fi

GATE="$(printf '%s' "$NORM" | jq -r --arg id "$PHASE" '.phases | map(select(.id == $id)) | .[0].gate // ""')"

record() { # $1 status  $2 stdout
  "$FLOW_STATE" "$FLOW" set "phase.$PHASE.status" "$1" "phase.$PHASE.stdout" "$2" || {
    printf 'flow_gate.sh: could not record the %s verdict for phase %s\n' "$1" "$PHASE" >&2
    exit 1
  }
}

if [ -z "$GATE" ]; then
  printf 'flow_gate.sh: phase %s declares no gate — recording PASS\n' "$PHASE" >&2
  record PASS ""
  printf 'STATUS=PASS\n'
  exit 0
fi

CAPTURE="$(mktemp "${TMPDIR:-/tmp}/flow_gate.XXXXXX")"
trap 'rm -f "$CAPTURE"' EXIT

( cd "$ROOT" && bash -c "$GATE" ) > "$CAPTURE"
RC=$?

GATE_OUT="$(cat "$CAPTURE")"
[ -n "$GATE_OUT" ] && printf '%s\n' "$GATE_OUT" >&2

if [ "$RC" -eq 0 ]; then
  record PASS "$GATE_OUT"
  printf 'STATUS=PASS\n'
else
  record FAIL "$GATE_OUT"
  printf 'STATUS=FAIL\n'
fi
exit "$RC"

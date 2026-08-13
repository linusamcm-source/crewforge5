#!/usr/bin/env bash
# flow_next.sh — print the next unblocked phase of a flow, or STATUS=DONE.
#
# Usage:
#   flow_next.sh <flow>
# stdout is KEY=VALUE — STATUS=NEXT / PHASE=<id> / DOC=<absolute phase doc>,
# or a lone STATUS=DONE when every phase in the manifest has passed. A pure
# function of state.json plus skills/<flow>/phases.json: it decides nothing
# and writes nothing, so asking twice always gives the same answer.
#
# A phase counts as finished when phase.<id>.status reads `pass` in any case —
# flow_gate.sh records the uppercase PASS, a human resuming by hand tends to
# type the lowercase, and both mean the same thing.
#
# Phases are offered in manifest order. `required` is carried for the phase
# docs and gates to consult; the driver does not skip on it, because a flow
# that wants to skip a phase marks it passed.
#
# Exit codes: 0 answered (NEXT or DONE), 1 no manifest for the flow, 2 usage.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_STATE="$HERE/flow_state.sh"

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

[ $# -eq 1 ] || usage
FLOW="$1"
case "$FLOW" in -*) usage ;; esac

command -v jq >/dev/null 2>&1 || { printf '[fail] jq missing — install: brew install jq\n' >&2; exit 1; }

MANIFEST="$("$FLOW_STATE" "$FLOW" manifest)" || exit 1
STATE="$("$FLOW_STATE" "$FLOW" path)"

ST='{}'
[ -f "$STATE" ] && ST="$(cat "$STATE")"

# One jq pass: drop every phase already passed, then answer with the first
# survivor. \t separates the two fields because a doc path may contain spaces.
ANSWER="$(jq -r --argjson st "$ST" '
  ($st.phase // {}) as $ph
  | map(select((($ph[.id].status // "") | ascii_downcase) != "pass"))
  | if length == 0 then "DONE" else "\(.[0].id)\t\(.[0].doc // "")" end
' "$MANIFEST")"

if [ "$ANSWER" = "DONE" ]; then
  printf 'STATUS=DONE\n'
  exit 0
fi

PHASE="${ANSWER%%	*}"
DOC="${ANSWER#*	}"
# Manifest docs are relative to the flow directory; an absolute one is honoured
# as written.
case "$DOC" in
  ""|/*) ;;
  *) DOC="$(dirname "$MANIFEST")/$DOC" ;;
esac

printf 'STATUS=NEXT\n'
printf 'PHASE=%s\n' "$PHASE"
printf 'DOC=%s\n' "$DOC"

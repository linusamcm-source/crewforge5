#!/usr/bin/env bash
# flow_next.sh — print the next unblocked phase of a flow, or STATUS=DONE.
#
# Usage:
#   flow_next.sh <flow>
# stdout is KEY=VALUE — STATUS=NEXT / PHASE=<id> / DOC=<absolute phase doc>,
# or a lone STATUS=DONE when every phase in the manifest has passed. A pure
# function of state.json plus skills/<flow>/phases.json plus whatever the
# manifest's own declared commands answer: it decides nothing and writes
# nothing, so asking twice always gives the same answer.
#
# A phase counts as finished when phase.<id>.status reads `pass` in any case —
# flow_gate.sh records the uppercase PASS, a human resuming by hand tends to
# type the lowercase, and both mean the same thing.
#
# Phases are offered in manifest order. `required` is carried for the phase
# docs and gates to consult; the driver does not skip on it, because a flow
# that wants to skip a phase marks it passed.
#
# MANIFEST SHAPE. phases.json is either the bare array it has always been, or
# an object `{status_source: <cmd>, phases: [...]}`. Both are normalised to the
# object here, so a flow that needs neither new field changes nothing.
#
# `when` (per phase) — a command deciding whether the phase is in this run at
# all. Non-zero exit drops it from the manifest entirely, for this call and for
# flow_gate.sh alike. It exists because `execute` walks a different phase list
# under `scheduling: graph` than under `sequential`, and one mode-aware manifest
# beats two manifests that drift.
#
# `status_source` (per manifest) — a command answering who owns phase progress.
# It prints `PHASE=<id>` for the phase in progress and optionally `DONE=1` when
# that phase is finished too; every phase BEFORE it counts passed, and that
# phase onward falls back to state.json. It exists because `execute` wraps
# team-sprint, which has tracked current_phase, current_story_id, story_commits
# and a whole graph node lifecycle for far longer than this driver has existed —
# so for the phases team-sprint owns, the honest answer is to ask it rather than
# to keep a second, coarser copy. A source that exits non-zero, prints no
# PHASE=, or names a phase not in the manifest has no opinion, and state.json
# decides alone.
#
# Both commands run from the repo root, like a gate, so a manifest entry can
# name a repo-relative command.
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

ROOT="$(git rev-parse --git-common-dir 2>/dev/null)" || ROOT=""
if [ -n "$ROOT" ]; then ROOT="$(cd "$ROOT/.." && pwd -P)"; else ROOT="$PWD"; fi

# Normalise both manifest shapes to the object form once, and keep it in a file
# so the later jq passes need no re-normalising.
NORM="$(mktemp "${TMPDIR:-/tmp}/flow_next.XXXXXX")"
trap 'rm -f "$NORM"' EXIT
jq 'if type == "array" then {phases: .} else . end' "$MANIFEST" > "$NORM"

# --- `when`: drop the phases this run does not walk ---------------------------
# Evaluated before anything else reads the list, so an excluded phase is absent
# from the ordering `status_source` is interpreted against as well.
KEEP=()
while IFS=$'\t' read -r pid pwhen; do
  [ -n "$pid" ] || continue
  if [ -n "$pwhen" ]; then
    ( cd "$ROOT" && bash -c "$pwhen" ) >/dev/null 2>&1 || continue
  fi
  KEEP+=( "$pid" )
done < <(jq -r '.phases[] | "\(.id)\t\(.when // "")"' "$NORM")

# An empty list must stay an empty JSON array, not [""] — `printf` on no args
# still emits one newline, which jq -R would read as one empty-string id.
if [ "${#KEEP[@]}" -eq 0 ]; then
  KEEP_JSON='[]'
else
  KEEP_JSON="$(printf '%s\n' "${KEEP[@]}" | jq -R . | jq -s .)"
fi

# --- `status_source`: ask the owner of these phases, if there is one ----------
SRC_PHASE=""
SRC_DONE=""
SRC_CMD="$(jq -r '.status_source // ""' "$NORM")"
if [ -n "$SRC_CMD" ]; then
  SRC_OUT="$( ( cd "$ROOT" && bash -c "$SRC_CMD" ) 2>/dev/null )" || SRC_OUT=""
  if [ -n "$SRC_OUT" ]; then
    SRC_PHASE="$(printf '%s\n' "$SRC_OUT" | sed -n 's/^PHASE=//p' | head -1)"
    SRC_DONE="$(printf '%s\n' "$SRC_OUT" | sed -n 's/^DONE=//p'  | head -1)"
  fi
fi

# One jq pass: keep the phases `when` allowed, mark each passed by state.json or
# by the status source, then answer with the first survivor. \t separates the
# two fields because a doc path may contain spaces.
ANSWER="$(jq -r \
  --argjson st "$ST" \
  --argjson keep "$KEEP_JSON" \
  --arg src "$SRC_PHASE" \
  --arg srcdone "$SRC_DONE" '
  ($st.phase // {}) as $ph
  | [ .phases[] | select(.id as $i | $keep | index($i)) ] as $live
  | ($live | map(.id) | index($src)) as $srcix
  | [ $live | to_entries[]
      | .key as $ix | .value as $p
      | select(
          ( (($ph[$p.id].status // "") | ascii_downcase) != "pass" )
          and ( $srcix == null
                or $ix > $srcix
                or ($ix == $srcix and ($srcdone | . != "1" and . != "true")) )
        )
      | $p ]
  | if length == 0 then "DONE" else "\(.[0].id)\t\(.[0].doc // "")" end
' "$NORM")"

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

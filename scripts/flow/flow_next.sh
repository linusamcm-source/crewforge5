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
# all. Exit 0 includes it, exit 1 drops it from the manifest entirely (for this
# call and for flow_gate.sh alike), and ANY OTHER exit is the probe failing to
# answer, which stops the driver rather than quietly shortening the flow. It exists because `execute` walks a different phase list
# under `scheduling: graph` than under `sequential`, and one mode-aware manifest
# beats two manifests that drift.
#
# A recorded FAIL outranks the status source. Phase docs advance their own state
# as the LAST step of the phase, so a source can already be pointing past a phase
# whose gate then fails; without this the failed phase would sit below the
# source's index and be treated as passed, and the driver would offer the next
# one. "A failed gate is re-offered, not advanced past" is the whole contract.
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

# The manifests' `gate`, `when` and `status_source` strings are expanded by
# `bash -c` below, against the real environment — and an unset CREWFORGE5_ROOT
# expands to nothing rather than failing, turning every declared gate into
# `bash "/skills/<flow>/scripts/<x>.sh"`: "No such file or directory", a phase
# that cannot run, and no hint that a variable was the cause. Shell state does
# not survive a tool call, so relying on the caller to have exported it makes
# all 38 manifest entries depend on remembering it in every single invocation.
#
# The driver knows where it lives. Deriving the plugin root from this script's
# own path costs nothing and makes a flow independent of how it was reached; an
# explicit CREWFORGE5_ROOT still wins, so a development checkout can override it.
CREWFORGE5_ROOT="${CREWFORGE5_ROOT:-$(cd "$HERE/../.." && pwd -P)}"
export CREWFORGE5_ROOT

ROOT="$(git rev-parse --git-common-dir 2>/dev/null)" || ROOT=""
if [ -n "$ROOT" ]; then ROOT="$(cd "$ROOT/.." && pwd -P)"; else ROOT="$PWD"; fi

# Normalise both manifest shapes to the object form once, and keep it in a file
# so the later jq passes need no re-normalising.
NORM="$(mktemp "${TMPDIR:-/tmp}/flow_next.XXXXXX")"
trap 'rm -f "$NORM"' EXIT
# Checked, because the failure is silent otherwise: a malformed phases.json makes
# jq write nothing, every later pass then reads an empty manifest, and an empty
# manifest answers STATUS=DONE — a broken flow would report itself finished.
if ! jq 'if type == "array" then {phases: .} else . end' "$MANIFEST" > "$NORM" || [ ! -s "$NORM" ]; then
  printf 'flow_next.sh: %s is not valid JSON\n' "$MANIFEST" >&2
  exit 1
fi

# --- `when`: drop the phases this run does not walk ---------------------------
# Evaluated before anything else reads the list, so an excluded phase is absent
# from the ordering `status_source` is interpreted against as well.
# Memoised by command text: `execute` gives five phases the same `when`, and
# without this the driver spawns the same probe five times per call to get the
# same answer. Scoped to this one invocation, so nothing is cached across calls
# and the answer stays as fresh as it ever was.
#
# Parallel arrays and a linear scan, NOT an associative array: macOS ships bash
# 3.2, which has none, and this driver runs wherever the plugin is installed.
# The list is one entry per DISTINCT `when` in a manifest, so the scan is over a
# handful of strings.
WHEN_CMDS=()
WHEN_VERDICTS=()

# Echoes in|out, or nothing when this command has not been probed yet. The
# explicit `return 0` matters: a bare fall-through returns the failed loop test,
# and under `set -e` that non-zero status kills the script at the assignment
# rather than reading as "not memoised yet".
_when_verdict() { # $1 command
  local i=0
  while [ "$i" -lt "${#WHEN_CMDS[@]}" ]; do
    if [ "${WHEN_CMDS[$i]}" = "$1" ]; then printf '%s\n' "${WHEN_VERDICTS[$i]}"; return 0; fi
    i=$((i + 1))
  done
  return 0
}

KEEP=()
while IFS=$'\t' read -r pid pwhen; do
  [ -n "$pid" ] || continue
  if [ -n "$pwhen" ]; then
    verdict="$(_when_verdict "$pwhen")"
    if [ -z "$verdict" ]; then
      # `|| when_rc=$?`, not a bare call then `$?`: this script runs under
      # `set -e`, which would kill it at the subshell the moment a `when`
      # legitimately answers 1 — the case statement would never be reached.
      when_rc=0
      ( cd "$ROOT" && bash -c "$pwhen" ) >/dev/null 2>&1 || when_rc=$?
      case "$when_rc" in
        0) verdict=in ;;
        1) verdict=out ;;
        # Above 1 the probe did not answer — it could not run. Excluding on that
        # is how `execute` walked from phase 2 to phase 7 with no implementation
        # phase offered when CREWFORGE5_ROOT was unset: every mode-gated phase
        # dropped out at once and the flow looked shorter rather than broken.
        *) printf 'flow_next.sh: the when clause for phase %s could not run: %s\n' "$pid" "$pwhen" >&2
           exit 1 ;;
      esac
      WHEN_CMDS+=( "$pwhen" )
      WHEN_VERDICTS+=( "$verdict" )
    fi
    [ "$verdict" = "in" ] || continue
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
      | (($ph[$p.id].status // "") | ascii_downcase) as $st
      | select(
          $st != "pass"
          and ( $st == "fail"
                or $srcix == null
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

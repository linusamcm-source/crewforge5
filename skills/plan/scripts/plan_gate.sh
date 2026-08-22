#!/usr/bin/env bash
# plan_gate.sh — shape gates for the `crewforge5:plan` artifacts.
#
# Usage:
#   plan_gate.sh <check>   run one gate: frames decisions audit triage
#   plan_gate.sh --list    print the checks this script answers to, one per line
# stdout is KEY=VALUE (STATUS=, CHECK=, …); detail and commentary go to stderr.
#
# These replace the `test -s` gates plan phases 2-5 shipped with. Non-emptiness
# proved a file was touched, not that the phase happened: a frames.md holding
# one sentence passed phase 2, a decisions.md that answered none of the framed
# decisions passed phase 3. Each gate here checks the SHAPE the phase doc
# promises — sections, cross-referenced IDs, dispositions — which is what the
# next phase actually consumes.
#
# NOTHING HERE EDITS ANYTHING. A gate that could repair what it measures would
# always pass. The ID pattern (table rows only, [A-Z]{1,4}[0-9]{1,3}) is
# check_coverage.sh's, quoted not re-invented, so phases 4, 5 and 8 agree on
# what counts as a finding.
#
# frames.md and decisions.md live BESIDE the flow's state.json — under the
# subject directory, asked from flow_state.sh — because they are this planning
# run's working notes: two concurrent plans must not share them, which is the
# same reason state is subject-keyed. TECH_DEBT_AUDIT.md and GOAL_IMPACT.md
# stay at their repo-level paths: master-plan and check_coverage.sh consume
# them there, and an audit of the repo is about the repo, not about one run.
#
# Exit codes: 0 pass, 1 fail, 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd -P)"
FLOW_STATE="$PLUGIN_ROOT/scripts/flow/flow_state.sh"

AUDIT_FILE="${PLAN_AUDIT_FILE:-TECH_DEBT_AUDIT.md}"
IMPACT_FILE="${PLAN_IMPACT_FILE:-docs/plans/GOAL_IMPACT.md}"

note()  { printf '%s\n' "$*" >&2; }
usage() { sed -n '5,8p' "$0" | sed 's/^# //' >&2; exit 2; }

emit() { # $1 STATUS  $2 CHECK  [KEY=VALUE …]
  local status="$1" check="$2" kv
  shift 2
  printf 'STATUS=%s\n' "$status"
  printf 'CHECK=%s\n' "$check"
  for kv in "$@"; do printf '%s\n' "$kv"; done
}

# The subject-keyed artifact dir: wherever this run's state.json lives.
art_dir() {
  local state
  state="$(bash "$FLOW_STATE" plan path)" || return 1
  dirname "$state"
}

# check_coverage.sh's extractor, verbatim: IDs count only inside table rows so
# prose mentions never read as findings.
_table_ids() { # $1 file
  grep -E '^\|' "$1" | grep -oE '\b[A-Z]{1,4}[0-9]{1,3}\b' | sort
}

# Decision ids from a frames/decisions file: D<n> on a `## ` heading.
#
# Two -e expressions, not one with `\b` or `\|`: both are GNU BRE extensions,
# and BSD sed reads `\b` as a literal `b` — on macOS no heading ever matched
# and every frames gate failed with "no decision section". The first
# expression takes a bare `## D3` heading, the second `## D1 — question`,
# with `[^0-9]` as the boundary so D1 never swallows D10.
_decision_ids() { # $1 file
  sed -n \
    -e 's/^## *\(D[0-9][0-9]*\)$/\1/p' \
    -e 's/^## *\(D[0-9][0-9]*\)[^0-9].*/\1/p' \
    "$1" | sort -u
}

# _section_body <file> <id> — the lines of one `## D<n>` section, heading
# excluded, ending at the next `## ` or EOF.
_section_body() {
  awk -v id="$2" '
    /^## / { on = ($2 == id) ? 1 : 0; next }
    on { print }
  ' "$1"
}

# Phase 2 — frames. Every framed decision must offer a real choice: two or more
# frames, or a single frame carrying its recorded skip-reason (`Skip:`) — the
# phase doc allows "the quick, standard answer" only when the reason is written
# down. A section with no frames at all is a question nobody answered.
check_frames() {
  local art frames ids id n_frames n_sections=0 bad=""
  art="$(art_dir)" || { emit FAIL frames "REASON=no-state"; return 1; }
  frames="$art/frames.md"
  if [ ! -s "$frames" ]; then
    note "frames: no frames at $frames — phase 2 has not written its sections"
    emit FAIL frames "REASON=no-frames" "EXPECTED=$frames"
    return 1
  fi
  ids="$(_decision_ids "$frames")"
  if [ -z "$ids" ]; then
    note "frames: $frames has no '## D<n>' decision section"
    emit FAIL frames "REASON=no-sections"
    return 1
  fi
  for id in $ids; do
    n_sections=$((n_sections + 1))
    n_frames="$(_section_body "$frames" "$id" | grep -c '^- Frame')"
    if [ "$n_frames" -eq 0 ]; then
      note "frames: $id has no '- Frame' bullet — the decision was named but never framed"
      bad="$bad $id"
    elif [ "$n_frames" -eq 1 ] && ! _section_body "$frames" "$id" | grep -q '^Skip:'; then
      note "frames: $id offers one frame and records no 'Skip:' reason — a single candidate is a skip, and a skip must say why"
      bad="$bad $id"
    fi
  done
  if [ -n "$bad" ]; then
    emit FAIL frames "SECTIONS=$n_sections" "REASON=unframed" "BAD=${bad# }"
    return 1
  fi
  emit OK frames "SECTIONS=$n_sections"
}

# Phase 3 — decisions. Every decision framed in phase 2 must carry a ratified
# answer: a matching `## D<n>` section with a `**Chosen:**` line. This is the
# cross-check the old `test -s` could not make — an unanswered decision goes
# into the plan as an assumption nobody agreed to.
check_decisions() {
  local art frames decisions ids id missing="" unchosen="" n=0
  art="$(art_dir)" || { emit FAIL decisions "REASON=no-state"; return 1; }
  frames="$art/frames.md"
  decisions="$art/decisions.md"
  if [ ! -s "$frames" ]; then
    note "decisions: no frames at $frames — phase 2's output is what this phase answers"
    emit FAIL decisions "REASON=no-frames"
    return 1
  fi
  if [ ! -s "$decisions" ]; then
    note "decisions: no decisions at $decisions"
    emit FAIL decisions "REASON=no-decisions" "EXPECTED=$decisions"
    return 1
  fi
  ids="$(_decision_ids "$frames")"
  for id in $ids; do
    n=$((n + 1))
    if ! grep -qE "^## *$id([^0-9]|$)" "$decisions"; then
      note "decisions: $id is framed but has no section in $decisions"
      missing="$missing $id"
    elif ! _section_body "$decisions" "$id" | grep -q '^\*\*Chosen:\*\*'; then
      note "decisions: $id has a section but no '**Chosen:**' line — discussed is not decided"
      unchosen="$unchosen $id"
    fi
  done
  if [ -n "$missing$unchosen" ]; then
    emit FAIL decisions "DECISIONS=$n" "MISSING=${missing# }" "UNCHOSEN=${unchosen# }"
    return 1
  fi
  emit OK decisions "DECISIONS=$n"
}

# Phase 4 — audit. Findings must carry stable IDs in table rows — that is the
# handle phases 5 and 8 match on, so a finding recorded only in prose escapes
# coverage silently. A clean repo is a real outcome: it says so with a literal
# `No findings` line, which is a claim, not an absence.
check_audit() {
  local n
  if [ ! -s "$AUDIT_FILE" ]; then
    note "audit: no audit at $AUDIT_FILE"
    emit FAIL audit "REASON=no-audit" "EXPECTED=$AUDIT_FILE"
    return 1
  fi
  n="$(_table_ids "$AUDIT_FILE" | sort -u | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    if grep -qiE '^ *No findings' "$AUDIT_FILE"; then
      emit OK audit "FINDINGS=0"
      return 0
    fi
    note "audit: $AUDIT_FILE has no ID-carrying table row and no 'No findings' claim"
    note "audit: an ID looks like F001/SEC1 in a markdown table row — prose findings escape phase 5 and phase 8"
    emit FAIL audit "REASON=no-finding-ids"
    return 1
  fi
  emit OK audit "FINDINGS=$n"
}

# Phase 5 — triage. Every ID in the impact map must exist in the audit (an
# invented ID would sail through phase 8, which only compares impact vs plan),
# appear exactly once (two rows for one ID means nobody chose), and carry a
# disposition in its row. Zero intersecting findings is legitimate and says so.
check_triage() {
  local ids dupes unknown="" id n bare
  if [ ! -s "$AUDIT_FILE" ]; then
    note "triage: no audit at $AUDIT_FILE — there is nothing to intersect with"
    emit FAIL triage "REASON=no-audit"
    return 1
  fi
  if [ ! -s "$IMPACT_FILE" ]; then
    note "triage: no impact map at $IMPACT_FILE"
    emit FAIL triage "REASON=no-impact" "EXPECTED=$IMPACT_FILE"
    return 1
  fi
  ids="$(_table_ids "$IMPACT_FILE")"
  n="$(printf '%s' "$ids" | sort -u | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    if grep -qiE '^ *No intersecting findings' "$IMPACT_FILE"; then
      emit OK triage "INTERSECTING=0"
      return 0
    fi
    note "triage: $IMPACT_FILE has no ID row and no 'No intersecting findings' claim"
    emit FAIL triage "REASON=no-rows"
    return 1
  fi
  dupes="$(printf '%s\n' "$ids" | uniq -d | tr '\n' ' ')"
  dupes="${dupes% }"
  if [ -n "$dupes" ]; then
    note "triage: duplicated in the disposition table — $dupes (one ID, two answers: nobody chose)"
    emit FAIL triage "REASON=duplicate-id" "DUPES=$dupes"
    return 1
  fi
  for id in $(printf '%s\n' "$ids" | uniq); do
    grep -E '^\|' "$AUDIT_FILE" | grep -qE "\b$id\b" || unknown="$unknown $id"
  done
  if [ -n "$unknown" ]; then
    note "triage: not in $AUDIT_FILE —$unknown (phase 8 compares impact vs plan, so an invented ID would never be caught again)"
    emit FAIL triage "REASON=unknown-id" "UNKNOWN=${unknown# }"
    return 1
  fi
  # A row's disposition is its LAST cell — positionally, not "last non-empty":
  # with an empty disposition the finding text is the last non-empty cell, and
  # a heuristic that walked backwards would read the finding as the decision.
  # A row that names an ID and decides nothing is the wish-list phase 8 warns
  # about, and phase 8 cannot catch it — it only compares ID sets.
  bare="$(grep -E '^\|' "$IMPACT_FILE" | awk -F'|' '
    { id=""
      for (i = 2; i <= NF; i++) {
        cell = $i
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell ~ /^[A-Z]{1,4}[0-9]{1,3}$/) { id = cell; break }
      }
      if (id == "") next
      # An ID row needs at least three cells — ID, finding, disposition. A
      # two-cell row cannot be carrying both, whichever cell holds text.
      cells = ($NF ~ /^[ \t]*$/) ? NF - 2 : NF - 1
      if (cells < 3) { print id; next }
      # The closing pipe makes the true last cell $(NF-1); a row without one
      # ends at $NF.
      disp = ($NF ~ /^[ \t]*$/) ? $(NF-1) : $NF
      gsub(/^[ \t]+|[ \t]+$/, "", disp)
      if (disp == "" || disp ~ /^-+$/ || disp == id) print id
    }' | tr '\n' ' ')"
  bare="${bare% }"
  if [ -n "$bare" ]; then
    note "triage: no disposition recorded for — $bare"
    emit FAIL triage "REASON=no-disposition" "BARE=$bare"
    return 1
  fi
  emit OK triage "INTERSECTING=$n"
}

[ $# -eq 1 ] || usage
case "$1" in
  --list)     printf '%s\n' frames decisions audit triage; exit 0 ;;
  -h|--help)  usage ;;
  frames)     check_frames ;;
  decisions)  check_decisions ;;
  audit)      check_audit ;;
  triage)     check_triage ;;
  *)          note "plan_gate.sh: unknown check \"$1\""; usage ;;
esac

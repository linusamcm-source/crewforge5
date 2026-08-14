#!/usr/bin/env bash
# init_gate.sh — the pass/fail gate behind each phase of `/crewforge5:init`.
#
# Usage:
#   init_gate.sh <check>   run one phase gate: preflight measure hygiene slim
#                          validate rectify distil report
#   init_gate.sh --list    print the checks this script answers to, one per line
# stdout is KEY=VALUE (STATUS=, CHECK=, …); detail and commentary go to stderr.
#
# ONE SCRIPT, NOT EIGHT. Six of the eight gates are per-target loops over
# scripts this bundle already ships (`retention_gate.sh` per proposal pair,
# `check.sh` per skill, the two validators per component, `ceiling.sh` per
# target), and every one resolves the same two locations. `--list` exists so a
# bats case can walk phases.json and prove each declared gate is answerable.
#
# NOTHING HERE EDITS ANYTHING. A gate that could repair what it measures would
# always pass. Repairs are the model's work, in the phase docs.
#
# Overridable so the tests can point at a fixture:
#   INIT_TARGET    config root under audit, holding skills/ and agents/ (repo root)
#   INIT_STATE     baseline.json, proposals/ and report.md (<repo>/.crewforge5/init)
#   INIT_DESC_CAP  description trim cap handed to token-slim's check.sh (300)
#
# Exit codes: 0 pass, 1 fail, 2 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# skills/init/scripts -> the plugin root, so every sub-skill script this gate
# reuses is found without an environment variable being set correctly first.
PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd -P)"

RETENTION="$PLUGIN_ROOT/scripts/retention_gate.sh"
SLIM_DIR="$PLUGIN_ROOT/skills/token-slim/scripts"
SKILL_V="$PLUGIN_ROOT/skills/skill-validator/scripts/validate_structure.sh"
GRADE="$PLUGIN_ROOT/skills/skill-validator/scripts/grade.sh"
AGENT_V="$PLUGIN_ROOT/skills/agent-validator/scripts/validate_agent.sh"
IMPROVE_DIR="$PLUGIN_ROOT/skills/self-improve/scripts"

note()  { printf '%s\n' "$*" >&2; }
usage() { sed -n '5,9p' "$0" | sed 's/^# //' >&2; exit 2; }

emit() { # $1 STATUS  $2 CHECK  [KEY=VALUE …]
  local status="$1" check="$2" kv
  shift 2
  printf 'STATUS=%s\n' "$status"
  printf 'CHECK=%s\n' "$check"
  for kv in "$@"; do printf '%s\n' "$kv"; done
}

# --- locations --------------------------------------------------------------
# --git-common-dir, not --show-toplevel: a call from a worktree still lands on
# the shared repo, so the flow keeps one .crewforge5 tree instead of one per
# worktree.
REPO_ROOT="$(git rev-parse --git-common-dir 2>/dev/null)"
if [ -n "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd -P)"
else
  REPO_ROOT="$PWD"
fi

TARGET="${INIT_TARGET:-$REPO_ROOT}"
STATE="${INIT_STATE:-$REPO_ROOT/.crewforge5/init}"
DESC_CAP="${INIT_DESC_CAP:-300}"
BASELINE="$STATE/baseline.json"

# Phase 0 — preflight. Later phases rewrite config files; an unrelated
# uncommitted edit makes the diff that proves what init changed unreadable.
check_preflight() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    note "preflight: not inside a git repository — init needs one to gate a clean tree"
    emit FAIL preflight "REASON=not-a-repo"
    return 1
  fi
  if [ ! -d "$TARGET" ]; then
    note "preflight: no config root at $TARGET — set INIT_TARGET"
    emit FAIL preflight "REASON=no-target"
    return 1
  fi
  local dirty
  dirty="$(git status --porcelain)"
  if [ -n "$dirty" ]; then
    note "preflight: working tree is dirty — commit or stash before init rewrites config"
    printf '%s\n' "$dirty" >&2
    emit FAIL preflight "REASON=dirty-tree"
    return 1
  fi
  emit OK preflight "TARGET=$TARGET" "STATE=$STATE"
}

# Phase 1 — measure. The baseline is the only record of what a description said
# before the trim, so every later claim of a saving depends on it.
check_measure() {
  if [ ! -s "$BASELINE" ]; then
    note "measure: $BASELINE is missing or empty — run token-slim's baseline.py first"
    emit FAIL measure "REASON=no-baseline"
    return 1
  fi
  local n
  n="$(jq -r 'if type == "object" then length else "x" end' "$BASELINE" 2>/dev/null)"
  case "$n" in
    ''|*[!0-9]*)
      note "measure: $BASELINE is not a baseline object"
      emit FAIL measure "REASON=not-a-baseline"
      return 1
      ;;
  esac
  if [ "$n" -lt 1 ]; then
    note "measure: $BASELINE records no skills"
    emit FAIL measure "REASON=empty-baseline"
    return 1
  fi
  emit OK measure "SKILLS=$n" "BASELINE=$BASELINE"
}

# Phase 2 — hygiene. Proposals land in scratch as <slug>.orig + <slug>.proposed
# pairs rather than being applied, so retention_gate.sh judges them before
# anything is overwritten. A proposal with no recorded original fails: with
# nothing to compare against, "everything survived" is an unearned verdict.
check_hygiene() {
  local dir="$STATE/proposals" rc=0 n=0 p orig
  if [ ! -d "$dir" ]; then
    note "hygiene: no proposals under $dir — phase 2 proposed no rewrite to gate"
    emit OK hygiene "PROPOSALS=0" "REASON=no-proposals"
    return 0
  fi
  for p in "$dir"/*.proposed; do
    [ -f "$p" ] || continue
    n=$((n + 1))
    orig="${p%.proposed}.orig"
    if [ ! -f "$orig" ]; then
      note "hygiene: $p has no recorded original at $orig"
      rc=1
      continue
    fi
    note "hygiene: $(basename "$orig") -> $(basename "$p")"
    bash "$RETENTION" "$orig" "$p" >&2 || rc=1
  done
  if [ "$rc" -ne 0 ]; then
    emit FAIL hygiene "PROPOSALS=$n" "REASON=retention-breach"
    return 1
  fi
  emit OK hygiene "PROPOSALS=$n"
}

# Phase 3 — slim. check.sh catches per-skill breaches (over cap, a trigger
# phrase or heading dropped, a broken references/ link); sweep.py catches the
# totals it cannot see. Both run: a trim can pass every skill and blow the sum.
check_slim() {
  local skills_dir="$TARGET/skills" rc=0 n=0 name
  if [ ! -s "$BASELINE" ]; then
    note "slim: no baseline at $BASELINE — phase 1 has not run"
    emit FAIL slim "REASON=no-baseline"
    return 1
  fi
  if [ ! -d "$skills_dir" ]; then
    note "slim: no skills directory at $skills_dir"
    emit FAIL slim "REASON=no-skills-dir"
    return 1
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    n=$((n + 1))
    bash "$SLIM_DIR/check.sh" "$name" "$skills_dir" "$BASELINE" "$DESC_CAP" >&2 || rc=1
  done < <(jq -r 'keys[]' "$BASELINE")
  python3 "$SLIM_DIR/sweep.py" --skills-dir "$skills_dir" --baseline "$BASELINE" >&2 || rc=1
  if [ "$rc" -ne 0 ]; then
    emit FAIL slim "SKILLS=$n" "DESC_CAP=$DESC_CAP" "REASON=slim-breach"
    return 1
  fi
  emit OK slim "SKILLS=$n" "DESC_CAP=$DESC_CAP"
}

# Phases 4 and 5 — validate, then rectify. Same walk, same two validators,
# different bar: phase 4 wants zero FAIL, phase 5 wants grade A per component
# (skill-validator's own scale), so the rectifier loop has a stopping condition
# that is not "looks better now".
_components() { # <kind>\t<label>\t<path>, agents first
  local f d
  if [ -d "$TARGET/agents" ]; then
    for f in "$TARGET"/agents/*.md; do
      [ -f "$f" ] || continue
      printf 'agent\t%s\t%s\n' "$(basename "$f" .md)" "$f"
    done
  fi
  if [ -d "$TARGET/skills" ]; then
    for d in "$TARGET"/skills/*/; do
      [ -f "$d/SKILL.md" ] || continue
      printf 'skill\t%s\t%s\n' "$(basename "$d")" "${d%/}"
    done
  fi
}

# _findings — turn one validator's JSON into grade.sh's ledger format. sed -E,
# not BRE alternation: `\|` is a GNU extension and this runs on BSD sed too.
_findings() { # $1 kind  $2 label  $3 path  $4 findings file
  local out
  case "$1" in
    agent) out="$(bash "$AGENT_V" "$3" 2>&1)" ;;
    skill) out="$(bash "$SKILL_V" "$3" 2>&1)" ;;
    *)     out="" ;;
  esac
  printf '%s\n' "$out" \
    | grep -E '"status":"(FAIL|WARN)"' \
    | sed -E "s/^.*\"status\":\"(FAIL|WARN)\",\"check\":\"([^\"]*)\",\"detail\":\"([^\"]*)\".*$/\1 [$2]: \2 — \3/" \
    >> "$4"
}

# _empty_target — an INIT_TARGET with nothing to walk is a mis-pointed root, not
# a clean bill of health. Both bars below are "zero bad components", which zero
# components satisfies for free, so the emptiness is checked before the bar.
_empty_target() { # $1 check name
  [ "$WALK_COMPONENTS" -eq 0 ] || return 1
  note "$1: no skills/ or agents/ under $TARGET — set INIT_TARGET to the config root"
  emit FAIL "$1" "COMPONENTS=0" "REASON=no-components"
}

# _walk — populates WALK_* and streams every finding to stderr.
_walk() {
  WALK_COMPONENTS=0
  WALK_FAILS=0
  WALK_WARNS=0
  WALK_BELOW_A=""
  local tmp kind label path findings f w g
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/init_gate.XXXXXX")" || return 1
  while IFS="$(printf '\t')" read -r kind label path; do
    [ -n "$kind" ] || continue
    WALK_COMPONENTS=$((WALK_COMPONENTS + 1))
    findings="$tmp/$kind.$label.findings"
    : > "$findings"
    _findings "$kind" "$label" "$path" "$findings"
    [ -s "$findings" ] && cat "$findings" >&2
    f="$(grep -c '^FAIL' "$findings")"
    w="$(grep -c '^WARN' "$findings")"
    WALK_FAILS=$((WALK_FAILS + f))
    WALK_WARNS=$((WALK_WARNS + w))
    g="$(bash "$GRADE" "$findings" | sed -n 's/^grade=//p')"
    [ "$g" = "A" ] || WALK_BELOW_A="$WALK_BELOW_A $label=$g"
  done < <(_components)
  rm -rf "$tmp"
}

check_validate() {
  _walk || { emit FAIL validate "REASON=walk-failed"; return 1; }
  _empty_target validate && return 1
  if [ "$WALK_FAILS" -gt 0 ]; then
    emit FAIL validate "COMPONENTS=$WALK_COMPONENTS" "FAILURES=$WALK_FAILS" "WARNINGS=$WALK_WARNS"
    return 1
  fi
  emit OK validate "COMPONENTS=$WALK_COMPONENTS" "FAILURES=0" "WARNINGS=$WALK_WARNS"
}

check_rectify() {
  _walk || { emit FAIL rectify "REASON=walk-failed"; return 1; }
  _empty_target rectify && return 1
  if [ -n "$WALK_BELOW_A" ]; then
    note "rectify: below grade A —$WALK_BELOW_A"
    emit FAIL rectify "COMPONENTS=$WALK_COMPONENTS" "FAILURES=$WALK_FAILS" \
                      "WARNINGS=$WALK_WARNS" "BELOW_A=${WALK_BELOW_A# }"
    return 1
  fi
  emit OK rectify "COMPONENTS=$WALK_COMPONENTS" "GRADE=A" "WARNINGS=$WALK_WARNS"
}

# Phase 6 — distil. An empty ledger passes, loudly: the failure mode of a
# self-improvement pass is inventing an edit because it was asked for one.
check_distil() {
  local n
  n="$(bash "$IMPROVE_DIR/ledger.sh" count 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 0 ]; then
    note "distil: nothing to distil — the ledger is empty, so phase 6 makes no edits"
    emit OK distil "LEDGER=0" "REASON=nothing-to-distil"
    return 0
  fi
  if bash "$IMPROVE_DIR/ceiling.sh" check >&2; then
    emit OK distil "LEDGER=$n"
    return 0
  fi
  emit FAIL distil "LEDGER=$n" "REASON=ceiling-breach"
  return 1
}

# Phase 7 — report. The delta is RE-MEASURED here, so a report claiming a saving
# the tree does not support fails. A gate that only checked the file existed
# would leave the one number anybody quotes the one number nobody verified.
check_report() {
  local report="$STATE/report.md" before after delta k
  if [ ! -s "$BASELINE" ]; then
    note "report: no baseline at $BASELINE — there is nothing to compare against"
    emit FAIL report "REASON=no-baseline"
    return 1
  fi
  if [ ! -s "$report" ]; then
    note "report: no report at $report"
    emit FAIL report "REASON=no-report"
    return 1
  fi
  before="$(jq -r '[.[].desc_chars] | add // 0' "$BASELINE")"
  after="$(python3 "$SLIM_DIR/baseline.py" --skills-dir "$TARGET/skills" --report \
           | jq -r '[.[].desc_chars] | add // 0')"
  case "$before$after" in
    ''|*[!0-9]*)
      note "report: could not re-measure description chars under $TARGET/skills"
      emit FAIL report "REASON=remeasure-failed"
      return 1
      ;;
  esac
  delta=$((before - after))
  for k in "DESC_CHARS_BEFORE=$before" "DESC_CHARS_AFTER=$after" "DESC_CHARS_DELTA=$delta"; do
    if ! grep -qF "$k" "$report"; then
      note "report: $report does not record the measured $k"
      emit FAIL report "REASON=delta-not-recorded" "MISSING=$k"
      return 1
    fi
  done
  emit OK report "DESC_CHARS_BEFORE=$before" "DESC_CHARS_AFTER=$after" "DESC_CHARS_DELTA=$delta"
}

# --- main -------------------------------------------------------------------
[ $# -eq 1 ] || usage

case "$1" in
  --list)
    printf '%s\n' preflight measure hygiene slim validate rectify distil report
    exit 0
    ;;
  -h|--help) usage ;;
esac

command -v jq >/dev/null 2>&1 || { note "[fail] jq missing — install: brew install jq"; exit 1; }

case "$1" in
  preflight) check_preflight ;;
  measure)   check_measure ;;
  hygiene)   check_hygiene ;;
  slim)      check_slim ;;
  validate)  check_validate ;;
  rectify)   check_rectify ;;
  distil)    check_distil ;;
  report)    check_report ;;
  *)
    note "init_gate.sh: unknown check \"$1\""
    usage
    ;;
esac

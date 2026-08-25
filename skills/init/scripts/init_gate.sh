#!/usr/bin/env bash
# init_gate.sh — the pass/fail gate behind each phase of `/crewforge5:init`.
#
# Usage:
#   init_gate.sh <check>   run one phase gate: deps preflight measure hygiene
#                          slim validate rectify distil report
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
# Where phase 4's spawned validators record what only a model can see, and where
# this gate caches what only a script can. INIT_CACHE=off disables the cache.
FINDINGS_DIR="${INIT_FINDINGS:-$STATE/findings}"
CACHE_DIR="$STATE/validator-cache"
CACHE_ON="${INIT_CACHE:-on}"

# --- dependencies -----------------------------------------------------------
# Phase 0 asks this before anything else: can the rest of the flow run at all?
# Required tools stop the flow; optional ones are named and carried, because
# this bundle degrades visibly rather than silently when one is absent.
#
# THIS CHECK MUST SURVIVE A MACHINE WITH NOTHING ON IT. Every other check here,
# and the flow driver above it, exits early when jq is missing — so a run that
# reached them would report "jq missing" and nothing else, which is the one
# moment the user most needs the full list. `deps` is exempt from that guard
# and is meant to be run directly, not through flow_gate.sh.
#
# It still installs nothing. Changing what is on someone's machine is not a
# gate's decision to make; it emits the commands and the caller decides.
DEPS_REQUIRED="bash git python3 jq"
DEPS_OPTIONAL="rtk just repomix shellcheck bats graphify codegraph"

_pkg_manager() {
  local m
  for m in brew apt-get dnf pacman; do
    if command -v "$m" >/dev/null 2>&1; then printf '%s\n' "$m"; return 0; fi
  done
  printf 'none\n'
}

# _install_cmd — how to install one tool under one manager, or nothing when
# this repo does not know. Silence beats a guess: an install line that does not
# work costs more than an admitted gap, and the user is about to paste it into
# a root shell.
_install_cmd() { # $1 tool  $2 manager
  case "$1" in
    repomix)   printf 'npm install -g repomix\n'; return 0 ;;
    graphify)  printf 'uv tool install graphifyy   # or: python3 -m pip install graphifyy\n'; return 0 ;;
    codegraph)
      # The project's own installer, quoted from its header. It vendors a Node
      # runtime under ~/.codegraph and symlinks into ~/.local/bin — no npm and
      # no sudo, which is why it leads. The npm package is the same thing for
      # anyone who would rather not pipe a remote script into a shell, and the
      # phase doc forbids running the piped form on the user's behalf.
      printf 'curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh\n'
      printf '# or, without piping a remote script to a shell: npm install -g @colbymchenry/codegraph\n'
      return 0
      ;;
  esac
  case "$2" in
    brew)
      case "$1" in
        python3) printf 'brew install python\n' ;;
        bats)    printf 'brew install bats-core\n' ;;
        *)       printf 'brew install %s\n' "$1" ;;
      esac
      ;;
    apt-get)
      case "$1" in
        git|python3|jq|shellcheck|bats) printf 'sudo apt-get install -y %s\n' "$1" ;;
      esac
      ;;
    dnf)
      case "$1" in
        shellcheck)          printf 'sudo dnf install -y ShellCheck\n' ;;
        git|python3|jq|bats) printf 'sudo dnf install -y %s\n' "$1" ;;
      esac
      ;;
    pacman)
      case "$1" in
        python3)            printf 'sudo pacman -S --needed python\n' ;;
        git|jq|shellcheck)  printf 'sudo pacman -S --needed %s\n' "$1" ;;
      esac
      ;;
  esac
}

# _deps_scan — populates DEPS_MISSING_REQ / DEPS_MISSING_OPT / DEPS_MANAGER and
# writes the copy-paste block to stderr. Separate from check_deps so preflight
# can consult it without emitting a second STATUS line onto stdout.
_deps_scan() {
  DEPS_MANAGER="$(_pkg_manager)"
  DEPS_MISSING_REQ=""
  DEPS_MISSING_OPT=""
  local t cmd unknown=""
  for t in $DEPS_REQUIRED; do
    command -v "$t" >/dev/null 2>&1 || DEPS_MISSING_REQ="$DEPS_MISSING_REQ $t"
  done
  for t in $DEPS_OPTIONAL; do
    command -v "$t" >/dev/null 2>&1 || DEPS_MISSING_OPT="$DEPS_MISSING_OPT $t"
  done
  DEPS_MISSING_REQ="${DEPS_MISSING_REQ# }"
  DEPS_MISSING_OPT="${DEPS_MISSING_OPT# }"

  [ -n "$DEPS_MISSING_REQ" ] && note "deps: required missing — $DEPS_MISSING_REQ"
  [ -n "$DEPS_MISSING_OPT" ] && note "deps: optional missing — $DEPS_MISSING_OPT (the flow runs, degraded)"
  if [ -z "$DEPS_MISSING_REQ" ] && [ -z "$DEPS_MISSING_OPT" ]; then
    note "deps: every required and optional tool is present"
    return 0
  fi
  note "deps: package manager — $DEPS_MANAGER"
  note "deps: ----- copy-paste into another terminal -----"
  for t in $DEPS_MISSING_REQ $DEPS_MISSING_OPT; do
    cmd="$(_install_cmd "$t" "$DEPS_MANAGER")"
    if [ -n "$cmd" ]; then note "$cmd"; else unknown="$unknown $t"; fi
  done
  [ -n "$unknown" ] && note "# no packaged install known here for:${unknown} — see each project's own docs"
  note "deps: ----- end -----"
  return 0
}

check_deps() {
  _deps_scan
  if [ -n "$DEPS_MISSING_REQ" ]; then
    emit FAIL deps "MANAGER=$DEPS_MANAGER" \
                   "REQUIRED_MISSING=${DEPS_MISSING_REQ// /,}" \
                   "OPTIONAL_MISSING=${DEPS_MISSING_OPT// /,}" \
                   "REASON=missing-required"
    return 1
  fi
  emit OK deps "MANAGER=$DEPS_MANAGER" "REQUIRED_MISSING=" \
               "OPTIONAL_MISSING=${DEPS_MISSING_OPT// /,}"
}

# Phase 0 — preflight. Dependencies first: a flow that cannot run its own
# scripts has nothing to say about a config root. Then the clean tree, because
# later phases rewrite config files and an unrelated uncommitted edit makes the
# diff that proves what init changed unreadable.
check_preflight() {
  _deps_scan
  if [ -n "$DEPS_MISSING_REQ" ]; then
    note "preflight: required tooling missing — $DEPS_MISSING_REQ"
    emit FAIL preflight "REASON=missing-deps" \
                        "REQUIRED_MISSING=${DEPS_MISSING_REQ// /,}"
    return 1
  fi
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

# --- the validator walk's cache ---------------------------------------------
# WHY A CACHE. The walk is the same work twice over: phase 4 gates on it, then
# phase 5 re-runs it after every repair — and phase 5 fans out one agent per
# FAILING component while the gate re-validates all of them. On a 38-component
# root that is ~6.5s per retry to learn that 37 components nobody touched are
# still fine.
#
# The key is CONTENT, not time. mtime says a file was written, not that it
# changed, and a rectifier that rewrites a component to what it already said
# would invalidate an entry that is still true. The validators' own bytes go
# into the key too, so editing a validator invalidates every entry rather than
# leaving the next run grading against the previous rules.
_hash_stdin() {
  # shasum is the macOS base install, sha256sum is GNU. Same order team-sprint's
  # state.sh uses for plan_of_record, for the same reason.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

# VALIDATOR_SIG — set once per run by _walk, not at file scope: `--list` and the
# dependency checks must answer on a machine where these scripts may be absent.
_validator_sig() {
  cat "$SKILL_V" "$AGENT_V" "$PLUGIN_ROOT/scripts/frontmatter_check.sh" 2>/dev/null | _hash_stdin
}

# _component_key — the cache key for one component, or nothing when caching is
# off. The tree is read ONCE, through -print0 into a temp file, and hashed as
# two things off that one read: the NUL-delimited path list (so a rename
# invalidates) and the concatenated contents (so an edit does). NUL delimiters
# make the list unambiguous whatever a filename holds, which is why there is no
# newline guard here and no `sort -z` — BSD sort has neither.
#
# The list is NOT sorted. find's order is stable for an unchanged tree, and a
# reordering can only ever cause a MISS, never a wrong hit: the contents are in
# the hash too, so two different trees cannot key the same.
_component_key() { # $1 kind  $2 path
  [ "$CACHE_ON" != "off" ] || return 0
  local kind="$1" path="$2" listing
  if [ "$kind" = "agent" ]; then
    { printf '%s\n%s\n' "${VALIDATOR_SIG:-none}" "$path"; cat "$path" 2>/dev/null; } | _hash_stdin
    return 0
  fi
  listing="$(mktemp "${TMPDIR:-/tmp}/init_gate_key.XXXXXX")" || return 0
  find "$path" -type f -print0 > "$listing" 2>/dev/null
  {
    printf '%s\n' "${VALIDATOR_SIG:-none}"
    cat "$listing"
    xargs -0 cat < "$listing" 2>/dev/null
  } | _hash_stdin
  rm -f "$listing"
}

# --- phase 4's behavioural half ---------------------------------------------
# The two validators grade behaviour as well as structure — agent simulation,
# instruction-compliance, efficiency — and only a model can run that half. Phase
# 4 spawns one per component to do it. Until this merge existed the gate re-derived
# the STRUCTURAL findings itself and ignored what the fleet reported, so 38 agent
# spawns of behavioural review could not fail the gate: the expensive half was
# ungated.
#
# The gate still re-derives the structural half rather than trusting the ledger
# for it. That is deliberate, and the same call phase 2 makes by demanding a
# `.orig` beside every `.proposed`: a bar the thing under test can write for
# itself is not a bar. What the ledger adds is the half no script can reach, and
# its ABSENCE fails — an unwritten ledger is a validator that did not run, and
# "no findings recorded" must not read the same as "no findings".
_behavioural_path() { printf '%s/%s.%s.md\n' "$FINDINGS_DIR" "$1" "$2"; }

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
#
# Each component's ledger is the STRUCTURAL findings this gate derives itself,
# plus the BEHAVIOURAL findings phase 4's spawned validator recorded. Both feed
# grade.sh, so a behavioural FAIL blocks exactly as a structural one does.
_walk() {
  WALK_COMPONENTS=0
  WALK_FAILS=0
  WALK_WARNS=0
  WALK_BELOW_A=""
  WALK_NO_LEDGER=""
  WALK_CACHED=0
  local tmp kind label path findings structural behavioural key cached f w g
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/init_gate.XXXXXX")" || return 1
  VALIDATOR_SIG="$(_validator_sig)"
  [ "$CACHE_ON" = "off" ] || mkdir -p "$CACHE_DIR" 2>/dev/null || true
  while IFS="$(printf '\t')" read -r kind label path; do
    [ -n "$kind" ] || continue
    WALK_COMPONENTS=$((WALK_COMPONENTS + 1))
    findings="$tmp/$kind.$label.findings"
    structural="$tmp/$kind.$label.structural"
    : > "$structural"

    # Structural half — cached on content, because phase 5 re-walks every
    # component after repairing one and the other 37 have not moved.
    cached=""
    key="$(_component_key "$kind" "$path")"
    [ -n "$key" ] && cached="$CACHE_DIR/$kind.$label.$key"
    if [ -n "$cached" ] && [ -f "$cached" ]; then
      cat "$cached" > "$structural"
      WALK_CACHED=$((WALK_CACHED + 1))
    else
      _findings "$kind" "$label" "$path" "$structural"
      if [ -n "$cached" ]; then
        # Drop this component's stale entries before writing the fresh one, so
        # the cache tracks the tree instead of growing a copy per edit.
        rm -f "$CACHE_DIR/$kind.$label."* 2>/dev/null || true
        cp "$structural" "$cached" 2>/dev/null || true
      fi
    fi

    cat "$structural" > "$findings"

    # Behavioural half — recorded by the phase-4 validator agent. Absent means
    # the validator did not run for this component, which is a finding of its
    # own rather than a clean bill of health.
    behavioural="$(_behavioural_path "$kind" "$label")"
    if [ -f "$behavioural" ]; then
      grep -E '^(FAIL|WARN|SKIPPED) ' "$behavioural" >> "$findings" || true
    else
      WALK_NO_LEDGER="$WALK_NO_LEDGER $label"
    fi

    [ -s "$findings" ] && cat "$findings" >&2
    f="$(grep -c '^FAIL' "$findings")"
    w="$(grep -c '^WARN' "$findings")"
    WALK_FAILS=$((WALK_FAILS + f))
    WALK_WARNS=$((WALK_WARNS + w))
    g="$(bash "$GRADE" "$findings" | sed -n 's/^grade=//p')"
    [ "$g" = "A" ] || WALK_BELOW_A="$WALK_BELOW_A $label=$g"
  done < <(_components)
  rm -rf "$tmp"
  WALK_NO_LEDGER="${WALK_NO_LEDGER# }"
}

check_validate() {
  _walk || { emit FAIL validate "REASON=walk-failed"; return 1; }
  _empty_target validate && return 1
  if [ -n "$WALK_NO_LEDGER" ]; then
    note "validate: no behavioural findings recorded for —$WALK_NO_LEDGER"
    note "validate: phase 4 spawns a validator per component; each must write $FINDINGS_DIR/<kind>.<label>.md"
    emit FAIL validate "COMPONENTS=$WALK_COMPONENTS" "REASON=no-behavioural-findings" \
                       "MISSING=${WALK_NO_LEDGER// /,}"
    return 1
  fi
  if [ "$WALK_FAILS" -gt 0 ]; then
    emit FAIL validate "COMPONENTS=$WALK_COMPONENTS" "FAILURES=$WALK_FAILS" "WARNINGS=$WALK_WARNS"
    return 1
  fi
  emit OK validate "COMPONENTS=$WALK_COMPONENTS" "FAILURES=0" "WARNINGS=$WALK_WARNS" "CACHED=$WALK_CACHED"
}

check_rectify() {
  _walk || { emit FAIL rectify "REASON=walk-failed"; return 1; }
  _empty_target rectify && return 1
  if [ -n "$WALK_NO_LEDGER" ]; then
    note "rectify: no behavioural findings recorded for —$WALK_NO_LEDGER"
    emit FAIL rectify "COMPONENTS=$WALK_COMPONENTS" "REASON=no-behavioural-findings" \
                      "MISSING=${WALK_NO_LEDGER// /,}"
    return 1
  fi
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
    printf '%s\n' deps preflight measure hygiene slim validate rectify distil report
    exit 0
    ;;
  -h|--help) usage ;;
esac

# `deps` and `preflight` must answer on a machine missing jq — that is the
# machine they exist for, and neither reads state through jq. Refusing here
# would report one missing tool and hide every other. The remaining checks all
# parse JSON, so for them a missing jq is still a stop.
case "$1" in
  deps|preflight) ;;
  *) command -v jq >/dev/null 2>&1 || { note "[fail] jq missing — install: brew install jq"; exit 1; } ;;
esac

case "$1" in
  deps)      check_deps ;;
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

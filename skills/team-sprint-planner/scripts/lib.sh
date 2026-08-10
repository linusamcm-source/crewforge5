#!/usr/bin/env bash
# shellcheck shell=bash
# lib.sh — shared helpers for the team-sprint-planner scripts. SOURCED, not
# executed. Trimmed from team-sprint's lib.sh to just what plan_readback.sh
# (its only remaining sourcer; tests/run-all.sh shellchecks it) needs — no
# repo/worktree/config helpers live here.

# Guard against double-source (set -u trips on re-sourcing if guard absent).
if [[ -n "${TEAM_SPRINT_PLANNER_LIB_LOADED:-}" ]]; then
  return 0
fi
TEAM_SPRINT_PLANNER_LIB_LOADED=1

# SCRIPTS resolves to the dir holding this file when sourced from any CWD.
# BASH_SOURCE[0] is the path of this file even when sourced.
if [[ -z "${SCRIPTS:-}" ]]; then
  SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
export SCRIPTS

log()  { printf '%s\n' "$*" >&2; }
info() { printf '[info] %s\n' "$*" >&2; }
warn() { printf '[warn] %s\n' "$*" >&2; }
fail() { printf '[fail] %s\n' "$*" >&2; exit 1; }

# Install hints — kept as functions so callers can re-use them.
_hint_jq()         { printf '%s\n' "jq missing — install: brew install jq"; }
_hint_python3()    { printf '%s\n' "python3 missing — install: brew install python3"; }
_hint_shellcheck() { printf '%s\n' "shellcheck missing — install: brew install shellcheck (>=0.9)"; }
_hint_bats()       { printf '%s\n' "bats missing — install: brew install bats-core (>=1.10)"; }

require_jq()         { command -v jq         >/dev/null 2>&1 || { _hint_jq         >&2; return 1; }; }
require_python3()    { command -v python3    >/dev/null 2>&1 || { _hint_python3    >&2; return 1; }; }
require_shellcheck() { command -v shellcheck >/dev/null 2>&1 || { _hint_shellcheck >&2; return 1; }; }
require_bats()       { command -v bats       >/dev/null 2>&1 || { _hint_bats       >&2; return 1; }; }

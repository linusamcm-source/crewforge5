#!/usr/bin/env bash
# run_gate.sh — run the typecheck + lint + test trio, tee each log, emit JSON.
#
# The deterministic sibling of coverage_check.sh. Where coverage_check.sh runs
# the coverage gate, run_gate.sh runs the typecheck/lint/test trio the lead
# previously invoked as three separate ad-hoc Bash calls (Phase 3 VERIFY /
# Phase 4 mechanical validation — SKILL.md "the lead runs test/typecheck/lint
# strings directly"). Each gate's full combined output is teed to
# $LOG_DIR/<gate>.log so a filtering proxy (`rtk read` / `rtk err`) can surface
# only the failing lines on demand WITHOUT the runner re-executing anything.
#
# Usage:
#   run_gate.sh [--project <dir>] [--log-dir <dir>] [--skip g1,g2,...]
#               [--typecheck <cmd>] [--lint <cmd>] [--test <cmd>]
#
# Per-gate command resolution (highest precedence first):
#   1. explicit --typecheck / --lint / --test flag
#   2. TS_COMMANDS_TYPECHECK / TS_COMMANDS_LINT / TS_COMMANDS_TEST env
#   3. detect_commands.sh <project> auto-detection
# A gate whose resolved command is empty is reported status:"skipped".
# --skip forces a gate to status:"skipped" regardless of its command.
#
# All gates that are enabled RUN (no short-circuit) so one invocation produces
# every gate's log in a single pass. Re-running overwrites the logs in place;
# the script never mutates the project or state.json.
#
# Output (stdout, JSON, sort_keys):
#   {"gates":{"typecheck":{"cmd","status","exit","log"},
#             "lint":{...},"test":{...}},
#    "log_dir":"...","passed":true|false,"ran":["typecheck","lint","test"]}
#   status ∈ passed | failed | skipped.
#
# Exit codes:
#   0  every gate that ran passed
#   1  one or more gates that ran failed
#   2  usage error
#   3  setup error (bad --project dir, detect_commands.sh failure)

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_python3 || exit 1

usage() {
  cat <<'USAGE' >&2
usage: run_gate.sh [--project <dir>] [--log-dir <dir>] [--skip g1,g2]
                   [--typecheck <cmd>] [--lint <cmd>] [--test <cmd>]
  Runs typecheck+lint+test, tees each to <log-dir>/<gate>.log, emits JSON.
  Commands resolve: flag > TS_COMMANDS_<GATE> env > detect_commands.sh.
USAGE
  exit 2
}

PROJECT="."
LOG_DIR=""
SKIP=""
CMD_TYPECHECK="${TS_COMMANDS_TYPECHECK:-}"
CMD_LINT="${TS_COMMANDS_LINT:-}"
CMD_TEST="${TS_COMMANDS_TEST:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)   PROJECT="${2:-}"; shift 2 ;;
    --log-dir)   LOG_DIR="${2:-}"; shift 2 ;;
    --skip)      SKIP="${2:-}"; shift 2 ;;
    --typecheck) CMD_TYPECHECK="${2:-}"; shift 2 ;;
    --lint)      CMD_LINT="${2:-}"; shift 2 ;;
    --test)      CMD_TEST="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    *)           warn "run_gate.sh: unknown arg: $1"; usage ;;
  esac
done

[[ -d "$PROJECT" ]] || { warn "run_gate.sh: not a directory: $PROJECT"; exit 3; }
PROJECT="$(cd "$PROJECT" && pwd -P)"
LOG_DIR="${LOG_DIR:-$PROJECT/.team-sprint/gate-logs}"
mkdir -p "$LOG_DIR"

# Fill any unresolved gate command from detect_commands.sh (one invocation).
if [[ -z "$CMD_TYPECHECK" || -z "$CMD_LINT" || -z "$CMD_TEST" ]]; then
  DETECT_JSON="$("$SCRIPTS/detect_commands.sh" "$PROJECT" 2>/dev/null || true)"
  if [[ -n "$DETECT_JSON" ]]; then
    [[ -z "$CMD_TYPECHECK" ]] && CMD_TYPECHECK="$(printf '%s' "$DETECT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("typecheck",""))' 2>/dev/null || true)"
    [[ -z "$CMD_LINT"      ]] && CMD_LINT="$(printf '%s' "$DETECT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("lint",""))' 2>/dev/null || true)"
    [[ -z "$CMD_TEST"      ]] && CMD_TEST="$(printf '%s' "$DETECT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("test",""))' 2>/dev/null || true)"
  fi
fi

is_skipped() { [[ ",$SKIP," == *",$1,"* ]]; }

# run_one <gate> <cmd> — run a gate in $PROJECT, tee to $LOG_DIR/<gate>.log.
# Appends a TAB-delimited "<gate>\t<status>\t<exit>\t<log>\t<cmd>" row to
# $RESULTS (commands hold spaces, never tabs). Never aborts the script.
RESULTS=""
run_one() {
  local gate="$1" cmd="$2" log rc status
  log="$LOG_DIR/$gate.log"
  if is_skipped "$gate" || [[ -z "$cmd" ]]; then
    RESULTS+="$gate"$'\t'"skipped"$'\t'"-1"$'\t'"$log"$'\t'"$cmd"$'\n'
    return 0
  fi
  info "gate:$gate → $cmd"
  rc=0
  ( cd "$PROJECT" && eval "$cmd" ) >"$log" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] && status="passed" || status="failed"
  RESULTS+="$gate"$'\t'"$status"$'\t'"$rc"$'\t'"$log"$'\t'"$cmd"$'\n'
}

run_one typecheck "$CMD_TYPECHECK"
run_one lint      "$CMD_LINT"
run_one test      "$CMD_TEST"

# Emit JSON + set exit code from the accumulated results. RESULTS is passed via
# env (not a pipe) because the heredoc already owns python's stdin.
RESULTS="$RESULTS" LOG_DIR="$LOG_DIR" python3 <<'PY'
import json, os, sys
log_dir = os.environ["LOG_DIR"]
gates, ran, passed = {}, [], True
for line in os.environ["RESULTS"].splitlines():
    if not line:
        continue
    gate, status, rc, log, cmd = line.split("\t", 4)
    gates[gate] = {"cmd": cmd, "status": status, "exit": int(rc), "log": log}
    if status != "skipped":
        ran.append(gate)
        if status != "passed":
            passed = False
out = {"gates": gates, "log_dir": log_dir, "passed": passed, "ran": ran}
sys.stdout.write(json.dumps(out, sort_keys=True) + "\n")
sys.exit(0 if passed else 1)
PY

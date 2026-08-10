#!/usr/bin/env bash
# graphify_ensure.sh — ensure the graphify knowledge-graph tool is installed for
# this project, verify it actually runs, and report graph freshness. The
# team-sprint and team-sprint-planner skills call this before they query the
# project's graphify-out/graph.json knowledge graph.
#
# graphify's full FIRST build is agent-driven — the /graphify skill dispatches
# semantic-extraction subagents, which a pure-bash script cannot do. So this
# script deliberately does NOT build the graph. It owns the deterministic half:
#   1. detect the right Python interpreter (uv tool / pipx / venv / system),
#   2. install the `graphifyy` package if `import graphify` fails,
#   3. persist graphify-out/.graphify_python for subsequent /graphify steps,
#   4. smoke-test that graphify actually runs (the "retest" the caller wants),
#   5. report whether graphify-out/graph.json exists and is fresh,
# so the lead knows whether it still needs to invoke /graphify to (re)build.
#
# Detection + install mirror the graphify skill's own "Step 1 — Ensure graphify
# is installed" block so behaviour is identical whether graphify is bootstrapped
# by /graphify directly or by this script.
#
# Usage:
#   graphify_ensure.sh --ensure        install if missing, persist interpreter,
#                                       then verify import + CLI run   (default)
#   graphify_ensure.sh --check         detect only, never install
#   graphify_ensure.sh --verify        smoke-test only: import + graphify runs
#                                       (+ a graph.json query when a graph exists)
#   graphify_ensure.sh --graph-status  report graph.json presence + freshness
#   [--max-age-minutes <n>]            staleness threshold for --graph-status
#                                       (default 240)
#   [--target-dir <path>]             project root to operate in (default $PWD)
#
# Output: every mode prints exactly one STATUS= line to stdout.
#   --ensure / --check / --verify : STATUS=OK | STATUS=MISSING | STATUS=FAIL
#   --graph-status                : STATUS=FRESH | STATUS=STALE | STATUS=MISSING
#
# Exit codes:
#   0  verdict produced (including MISSING/STALE — those are answers, not errors)
#   1  hard failure: install attempted and failed, or bad arguments

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'USAGE' >&2
usage: graphify_ensure.sh [--ensure|--check|--verify|--graph-status]
                          [--max-age-minutes <n>] [--target-dir <path>]
USAGE
  exit 1
}

MODE="--ensure"
TARGET_DIR=""
MAX_AGE_MINUTES=240

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ensure|--check|--verify|--graph-status) MODE="$1"; shift ;;
    --max-age-minutes)
      [[ $# -ge 2 ]] || usage
      MAX_AGE_MINUTES="$2"; shift 2 ;;
    --target-dir)
      [[ $# -ge 2 ]] || usage
      TARGET_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if ! [[ "$MAX_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
  fail "graphify_ensure.sh: --max-age-minutes must be a non-negative integer (got: $MAX_AGE_MINUTES)"
fi

# Resolve target dir the same way repomix_refresh.sh does: relative paths bind to
# the caller's CWD, then canonicalise so the graph paths are stable.
ORIG_CWD="$PWD"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$ORIG_CWD"
elif [[ "$TARGET_DIR" != /* ]]; then
  TARGET_DIR="$ORIG_CWD/$TARGET_DIR"
fi
[[ -d "$TARGET_DIR" ]] || fail "graphify_ensure.sh: --target-dir not a directory: $TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"

GRAPH_DIR="$TARGET_DIR/graphify-out"
PY_CACHE="$GRAPH_DIR/.graphify_python"
GRAPH_JSON="$GRAPH_DIR/graph.json"

# resolve_python — echo a python interpreter that can `import graphify`, else "".
# Order mirrors the graphify skill: cached interpreter → uv tool → graphify-bin
# shebang → system python3. Never installs; pure detection.
resolve_python() {
  local py cached bin sb
  # 1. Cached interpreter from a prior run.
  if [[ -f "$PY_CACHE" ]]; then
    cached="$(cat "$PY_CACHE" 2>/dev/null || true)"
    if [[ -n "$cached" && -x "$cached" ]] && "$cached" -c 'import graphify' 2>/dev/null; then
      printf '%s\n' "$cached"; return 0
    fi
  fi
  # 2. uv tool install — most reliable on modern Mac/Linux.
  if command -v uv >/dev/null 2>&1; then
    # `--from` is required: the package is graphifyy but its only executable is
    # `graphify`, so a bare `uv tool run graphifyy python` asks uv for an
    # executable named graphifyy and always returns empty — this branch never
    # fired, and on a minimal PATH --check reported MISSING on a healthy install.
    py="$(uv tool run --from graphifyy python -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
    if [[ -n "$py" ]] && "$py" -c 'import graphify' 2>/dev/null; then
      printf '%s\n' "$py"; return 0
    fi
  fi
  # 3. Shebang of the graphify launcher (pipx / direct pip installs).
  bin="$(command -v graphify 2>/dev/null || true)"
  if [[ -n "$bin" ]]; then
    # Anchor the `#!` strip: `tr -d '#!'` deletes those characters from ANYWHERE
    # in the path. Take only the interpreter word, and allow `@` — every
    # Homebrew versioned-Python shebang contains it
    # (/opt/homebrew/opt/python@3.13/…), so the old allowlist rejected the
    # common macOS install outright.
    sb="$(head -1 "$bin")"
    sb="${sb#\#!}"
    sb="${sb%% *}"
    case "$sb" in
      *[!a-zA-Z0-9/_.@+-]*) ;;  # reject anything with shell metachars
      *) if [[ -n "$sb" && -x "$sb" ]] && "$sb" -c 'import graphify' 2>/dev/null; then
           printf '%s\n' "$sb"; return 0
         fi ;;
    esac
  fi
  # 4. System python3.
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import graphify' 2>/dev/null; then
    printf '%s\n' "$(command -v python3)"; return 0
  fi
  printf '%s\n' ""
}

# install_graphify — install the graphifyy package; return non-zero on failure.
install_graphify() {
  if command -v uv >/dev/null 2>&1; then
    info "graphify_ensure: installing graphifyy via uv tool"
    uv tool install --upgrade graphifyy >/dev/null 2>&1 && return 0
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    info "graphify_ensure: installing graphifyy via pip"
    python3 -m pip install graphifyy >/dev/null 2>&1 && return 0
    python3 -m pip install graphifyy --break-system-packages >/dev/null 2>&1 && return 0
    return 1
  fi
  warn "graphify_ensure: no uv or python3 available to install graphifyy"
  return 1
}

# persist_interpreter — write the resolved interpreter to graphify-out so every
# subsequent /graphify step uses the same one.
persist_interpreter() {
  local py="$1"
  mkdir -p "$GRAPH_DIR"
  "$py" -c 'import sys; open(sys.argv[1],"w",encoding="utf-8").write(sys.executable)' "$PY_CACHE" 2>/dev/null || \
    printf '%s\n' "$py" > "$PY_CACHE"
}

# smoke_test — prove graphify actually runs. import is implied by a non-empty
# interpreter; additionally exercise the CLI/graph so a broken install surfaces.
# Returns 0 on success, non-zero otherwise. $1 = interpreter path.
smoke_test() {
  local py="$1" out
  # Module import must succeed.
  "$py" -c 'import graphify' 2>/dev/null || return 1
  # If a graph exists, the strongest retest is a real query against it. Prefer the
  # CLI; fall back to loading graph.json through the interpreter (query.md notes
  # the `graphify query` CLI may be unavailable, with a NetworkX fallback).
  if [[ -f "$GRAPH_JSON" ]]; then
    if command -v graphify >/dev/null 2>&1; then
      # Kept inside the subshell so the `cd` cannot leak into the caller. The
      # earlier `cd … && query || true` one-liner read as if-then-else and was
      # not (shellcheck SC2015): a failed `cd` fell through to `|| true` and was
      # indistinguishable from a query that ran and returned nothing. Both still
      # yield an empty `out`, which the caller treats the same — but the code no
      # longer claims otherwise, and shellcheck 0.11 stops failing the suite.
      out="$(cd "$TARGET_DIR" 2>/dev/null && graphify query 'overview of this codebase' 2>/dev/null)" || out=""
      [[ -n "$out" ]] && return 0
    fi
    # Path via argv, never interpolated into the source: a project path holding
    # an apostrophe or backslash otherwise produces a SyntaxError, and the bare
    # `return 1` below turns that into STATUS=FAIL — which phase-0 escalates to a
    # hard STOP under `graphify: on`. Same argv convention as schedule.sh:46.
    "$py" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); sys.exit(0 if d.get("nodes") else 1)' "$GRAPH_JSON" 2>/dev/null && return 0
    return 1
  fi
  # No graph yet: a clean import is the most we can assert. OK — the lead builds
  # the graph via /graphify next, then re-runs --verify.
  return 0
}

case "$MODE" in
  --check)
    py="$(resolve_python)"
    if [[ -n "$py" ]]; then
      persist_interpreter "$py"
      printf 'STATUS=OK\n'
    else
      printf 'STATUS=MISSING\n'
    fi
    ;;

  --ensure)
    py="$(resolve_python)"
    if [[ -z "$py" ]]; then
      install_graphify || fail "graphify_ensure.sh: graphifyy install failed"
      py="$(resolve_python)"
      [[ -n "$py" ]] || fail "graphify_ensure.sh: graphify still not importable after install"
    fi
    persist_interpreter "$py"
    if smoke_test "$py"; then
      printf 'STATUS=OK\n'
    else
      printf 'STATUS=FAIL\n'
    fi
    ;;

  --verify)
    py="$(resolve_python)"
    if [[ -z "$py" ]]; then
      printf 'STATUS=MISSING\n'
    elif smoke_test "$py"; then
      persist_interpreter "$py"
      printf 'STATUS=OK\n'
    else
      printf 'STATUS=FAIL\n'
    fi
    ;;

  --graph-status)
    if [[ ! -f "$GRAPH_JSON" ]]; then
      printf 'STATUS=MISSING\n'
    else
      now_epoch="$(date +%s)"
      # mtime_epoch (lib.sh) handles the BSD/GNU stat split.
      file_mtime="$(mtime_epoch "$GRAPH_JSON")"
      age_seconds=$(( now_epoch - file_mtime ))
      max_age_seconds=$(( MAX_AGE_MINUTES * 60 ))
      if (( age_seconds <= max_age_seconds )); then
        printf 'STATUS=FRESH\n'
      else
        printf 'STATUS=STALE\n'
      fi
    fi
    ;;
esac

exit 0

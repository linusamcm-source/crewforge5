#!/usr/bin/env bash
# coverage_check.sh — multi-language coverage gate for team-sprint Phase 3.
#
# Usage:
#   coverage_check.sh --mode whole|new --threshold <pct> \
#       [--diff-base <ref>] [--story-id <id>]
#
# Emits JSON on stdout. See Story mech-5 in the sprint plan for the contract.
#
# Skip path (script-internal, NEVER invokes the parser):
#   When `commands.coverage` (env or team-sprint.config.yaml) is literally the
#   string "true" OR `coverage_threshold` is 0, the script writes a single
#   stderr line and emits the disabled-gate JSON on stdout. The lead is
#   responsible for the state.json.gates append (script does not touch state).
#
# Format autodetect priority:
#   coverage/coverage-final.json    -> istanbul
#   coverage.out                    -> go
#   coverage.xml | coverage.json    -> python (cov.py / cobertura)
#   target/tarpaulin/cobertura.xml  -> rust (cobertura)
# Override via commands.coverage_report_path config.
#
# --mode new diff-base resolution (when --diff-base not passed):
#   - first story (no prior story_commits): merge-base(sprint_branch,target_branch)
#   - subsequent stories: SHA of prior story from state.json.story_commits[]
#   - --mode whole without --story-id: same merge-base fallback
#   Graph-mode node executors MUST pass --diff-base "$base_commit" (the node's
#   claim-time integration HEAD from graph.json, Story GH3): story-commit /
#   merge-base resolution is wrong for node branches — it would fold
#   previously integrated stories into this story's diff (D8).
#
# --mode new HEAD expectation (Story GH4 / D6): added lines come from
#   `git diff BASE...HEAD` — committed work only. Phases 3/5 land the story's
#   in-flight work as provisional `wip(<story-id>)` commits before invoking
#   this gate; otherwise the diff is empty (untracked files included) and the
#   gate passes vacuously on "no coverable lines". Phase 6 squashes the wip
#   commits into the single story commit.
#
# --mode new denominator (Story LS2, finding SCR6/SCR10; hardened P1-1/P1-3):
#   The pass ratio counts ONLY added *executable* lines in *coverable* files.
#   - Coverable = present in the coverage report OR a source file by extension.
#     A brand-new source file absent from the report (nyc/coverage.py omit
#     never-imported files) is coverable by extension and fails closed: every
#     added line counts as uncovered, so a wholly untested new module reports 0%
#     rather than passing vacuously (P1-1).
#   - Executable = the covered ∪ uncovered line set the report instruments for a
#     report-present file. Blank/comment/import/brace added lines are excluded
#     from BOTH numerator and denominator, so a comment block cannot inflate the
#     percentage (P1-3).
#   - Non-coverable files (markdown/YAML/config/etc.) never touch the ratio.
#     A diff of only non-coverable files -> pct:null + "no coverable lines" note,
#     PASS (no silent 100%, no divide-by-zero). A diff of coverable files that
#     add no executable lines -> pct:null + "no executable lines" note.
#
# --diff-base failure (P1-2): a non-zero `git diff` exit (bad base SHA,
#   unreachable ref, no merge-base) fails closed with exit 1 — an error-caused
#   empty diff is never confused with a legitimately empty diff.
#
# Exit codes:
#   0  normal (measured OR skipped path)
#   1  no coverage file detected AND not skipped (NO silent zero); OR git diff
#      failed in --mode new (P1-2)
#   2  usage error

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_jq      || exit 1
require_python3 || exit 1

usage() {
  cat <<'USAGE' >&2
usage: coverage_check.sh --mode whole|new --threshold <pct> \
                         [--diff-base <ref>] [--story-id <id>]
USAGE
  exit 2
}

# ---------------------------------------------------------------------------
# Arg parsing.
# ---------------------------------------------------------------------------
MODE=""
THRESHOLD=""
DIFF_BASE=""
STORY_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    # Each two-arg branch guards its own operand: a bare `shift 2` with one
    # positional left returns non-zero and `set -e` kills the script at exit 1
    # with no stderr, instead of the documented usage exit 2. Same convention as
    # preflight_subskills.sh:54, run_subskill_hooks.sh:52, graphify_ensure.sh:61.
    --mode)       [[ $# -ge 2 ]] || usage; MODE="$2";       shift 2 ;;
    --threshold)  [[ $# -ge 2 ]] || usage; THRESHOLD="$2";  shift 2 ;;
    --diff-base)  [[ $# -ge 2 ]] || usage; DIFF_BASE="$2";  shift 2 ;;
    --story-id)   [[ $# -ge 2 ]] || usage; STORY_ID="$2";   shift 2 ;;
    -h|--help)    usage ;;
    *)            usage ;;
  esac
done

[[ "$MODE" == "whole" || "$MODE" == "new" ]] || usage
# Numeric, not merely non-empty: a bad value otherwise surfaces as a raw Python
# ValueError traceback and exit 1, colliding with the documented exit-1 meaning
# ("no coverage file / git diff failed"). Empty fails the regex too.
[[ "$THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage

# ---------------------------------------------------------------------------
# Read config (commands.coverage, coverage_threshold, commands.coverage_report_path).
# Env vars override config file:
#   TEAM_SPRINT_CONFIG          path to config yaml (default: $PWD/team-sprint.config.yaml)
#   TS_COMMANDS_COVERAGE        overrides commands.coverage
#   TS_COVERAGE_THRESHOLD       overrides coverage_threshold
#   TS_COVERAGE_REPORT_PATH     overrides commands.coverage_report_path
#   TS_STATE_FILE               state.json path for new-mode diff-base resolution
#   TS_SPRINT_BRANCH            sprint branch (default: current HEAD branch)
#   TS_TARGET_BRANCH            target branch (default: from state.json)
# ---------------------------------------------------------------------------
CONFIG_FILE="${TEAM_SPRINT_CONFIG:-${PWD}/team-sprint.config.yaml}"

# commands.coverage and commands.coverage_report_path come from the shared
# lib.sh reader (deduped in Story LS4). coverage_threshold is a TOP-LEVEL scalar
# (not under commands:), so it is read with the focused scan below. Missing
# file/key -> empty string in every case.
{ IFS= read -r CFG_COMMANDS_COVERAGE
  IFS= read -r CFG_COVERAGE_REPORT_PATH
} < <(read_config_commands "$CONFIG_FILE" coverage coverage_report_path)

CFG_COVERAGE_THRESHOLD="$(read_config_scalar "$CONFIG_FILE" coverage_threshold)"

EFF_COMMANDS_COVERAGE="${TS_COMMANDS_COVERAGE-$CFG_COMMANDS_COVERAGE}"
EFF_COVERAGE_THRESHOLD="${TS_COVERAGE_THRESHOLD-$CFG_COVERAGE_THRESHOLD}"
EFF_REPORT_PATH="${TS_COVERAGE_REPORT_PATH-$CFG_COVERAGE_REPORT_PATH}"

# ---------------------------------------------------------------------------
# Skip-path check. NO parser invocation.
# Trigger when:
#   - effective commands.coverage == "true"  (literal string), OR
#   - effective coverage_threshold == 0      (numeric or "0")
# ---------------------------------------------------------------------------
is_skip=0
skip_reason=""

if [[ "$EFF_COMMANDS_COVERAGE" == "true" ]]; then
  is_skip=1
  skip_reason='commands.coverage="true"'
elif [[ -n "$EFF_COVERAGE_THRESHOLD" && "$EFF_COVERAGE_THRESHOLD" == "0" ]]; then
  is_skip=1
  skip_reason='coverage_threshold=0'
fi

if [[ "$is_skip" -eq 1 ]]; then
  printf 'coverage gate disabled by config (commands.coverage="true" or coverage_threshold=0)\n' >&2
  jq --sort-keys -n \
     --arg reason "$skip_reason" \
     --arg story  "$STORY_ID" \
     '{mode:"skipped", gate_status:"disabled", pass:null, reason:$reason, story_id:$story}'
  exit 0
fi

# ---------------------------------------------------------------------------
# Detect coverage report file.
# ---------------------------------------------------------------------------
FORMAT=""
REPORT=""

detect_report() {
  FORMAT=""
  REPORT=""
  if [[ -n "$EFF_REPORT_PATH" && -f "$EFF_REPORT_PATH" ]]; then
    REPORT="$EFF_REPORT_PATH"
    # Infer format from path/extension.
    case "$REPORT" in
      *coverage-final.json) FORMAT="istanbul" ;;
      *.out)                FORMAT="go" ;;
      *cobertura.xml)       FORMAT="rust" ;;
      *.xml)                FORMAT="python" ;;
      *.json)               FORMAT="python" ;;
      *)                    FORMAT="" ;;
    esac
  else
    if   [[ -f "coverage/coverage-final.json" ]]; then
      REPORT="coverage/coverage-final.json"; FORMAT="istanbul"
    elif [[ -f "coverage.out" ]]; then
      REPORT="coverage.out";                 FORMAT="go"
    elif [[ -f "coverage.xml" ]]; then
      REPORT="coverage.xml";                 FORMAT="python"
    elif [[ -f "coverage.json" ]]; then
      REPORT="coverage.json";                FORMAT="python"
    elif [[ -f "target/tarpaulin/cobertura.xml" ]]; then
      REPORT="target/tarpaulin/cobertura.xml"; FORMAT="rust"
    fi
  fi
}

detect_report

# No report on disk yet: run the effective coverage command (config or
# TS_COMMANDS_COVERAGE) once to produce it, then re-detect. Previously the
# script only detected pre-existing reports, so a lead that never ran the
# coverage command by hand hit "no coverage report detected" every time.
if [[ -z "$REPORT" && -n "$EFF_COMMANDS_COVERAGE" && "$EFF_COMMANDS_COVERAGE" != "true" ]]; then
  info "coverage_check: no report found; running coverage command: $EFF_COMMANDS_COVERAGE"
  if ! bash -c "$EFF_COMMANDS_COVERAGE" >&2; then
    warn "coverage_check: coverage command exited non-zero (failing tests fail the gate downstream if no report was produced)"
  fi
  detect_report
fi

if [[ -z "$REPORT" || -z "$FORMAT" ]]; then
  cat >&2 <<EOF
coverage_check.sh: no coverage report detected.
Detection chain (in priority order):
  1. commands.coverage_report_path (config or TS_COVERAGE_REPORT_PATH)  -> "${EFF_REPORT_PATH:-<unset>}"
  2. coverage/coverage-final.json   (istanbul)
  3. coverage.out                   (go)
  4. coverage.xml                   (python cobertura)
  5. coverage.json                  (python cov.py)
  6. target/tarpaulin/cobertura.xml (rust)
Set coverage_threshold:0 or commands.coverage:"true" to skip the gate.
EOF
  exit 1
fi

# ---------------------------------------------------------------------------
# --mode new: compute added-lines map via git diff.
# Diff-base resolution priority:
#   1. --diff-base CLI arg
#   2. prior story SHA from state.json.story_commits[] (if --story-id given)
#   3. merge-base(sprint_branch, target_branch)
# ---------------------------------------------------------------------------
ADDED_LINES_FILE=""
RESOLVED_BASE=""

if [[ "$MODE" == "new" ]]; then
  if [[ -n "$DIFF_BASE" ]]; then
    RESOLVED_BASE="$DIFF_BASE"
  else
    # Resolve via the shared lib.sh helper (deduped in Story LS4): prior story
    # SHA from state.json.story_commits[], else merge-base(sprint, target).
    state_file="${TS_STATE_FILE:-}"
    state_json="{}"
    if [[ -n "$state_file" && -f "$state_file" ]]; then
      state_json="$(cat "$state_file")"
    fi
    target_branch="$(printf '%s' "$state_json" | jq -r '.target_branch // ""')"
    sprint_branch="${TS_SPRINT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
    tgt="${TS_TARGET_BRANCH:-$target_branch}"
    RESOLVED_BASE="$(resolve_diff_base "$state_json" "$STORY_ID" "$sprint_branch" "$tgt")"
  fi

  ADDED_LINES_FILE="$(mktemp)"

  # Build {file: [added-line-numbers,...]} JSON from a unified diff. Capture
  # the diff to a tmp file so python can read it without colliding with the
  # heredoc-on-stdin.
  DIFF_TMP="$(mktemp)"
  DIFF_ERR="$(mktemp)"
  trap 'rm -f "$ADDED_LINES_FILE" "$DIFF_TMP" "$DIFF_ERR"' EXIT
  # Fail closed on a git error (bad/unreachable RESOLVED_BASE, bad story-commit
  # SHA, no merge-base). An error-caused empty diff must NOT masquerade as a
  # legitimately empty diff (the documented vacuous-pass-on-no-coverable-lines
  # case) and slip through as pct:null -> pass:true.
  git_diff_rc=0
  git diff "$RESOLVED_BASE"...HEAD --unified=0 -- > "$DIFF_TMP" 2>"$DIFF_ERR" || git_diff_rc=$?
  if [[ $git_diff_rc -ne 0 ]]; then
    printf 'coverage_check.sh: git diff failed (base=%s, rc=%d): %s\n' \
      "$RESOLVED_BASE" "$git_diff_rc" "$(tr '\n' ' ' < "$DIFF_ERR")" >&2
    exit 1
  fi
  python3 - "$DIFF_TMP" "$ADDED_LINES_FILE" <<'PY'
import json
import re
import sys

diff_path, out_path = sys.argv[1], sys.argv[2]
out = {}
current = None
with open(diff_path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if line.startswith("+++ b/"):
            current = line[6:].rstrip("\n")
            if current == "/dev/null":
                current = None
            else:
                out.setdefault(current, [])
            continue
        if line.startswith("+++ "):
            current = None
            continue
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
        if m and current is not None:
            start = int(m.group(1))
            count = int(m.group(2)) if m.group(2) is not None else 1
            if count == 0:
                continue
            out[current].extend(range(start, start + count))
            continue
with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(out))
PY
fi

# ---------------------------------------------------------------------------
# Invoke the parser. All format-specific logic lives in Python — bash text
# wrangling for cobertura XML / Istanbul JSON / go coverprofile is painful.
# ---------------------------------------------------------------------------
python3 - "$FORMAT" "$REPORT" "$MODE" "$THRESHOLD" "$ADDED_LINES_FILE" "$STORY_ID" <<'PY'
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

fmt, report, mode, threshold, added_file, story_id = sys.argv[1:7]
threshold_f = float(threshold)


def parse_istanbul(path):
    """Istanbul coverage-final.json -> (covered_lines, uncovered_lines) per file.

    Istanbul tracks statements (statementMap + s). Each statement maps to a
    start/end line range; if the hit count is zero, every line in that range
    is considered uncovered. Pct = covered statements / total statements.
    """
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    total_stmts = 0
    covered_stmts = 0
    uncovered_lines_by_file = {}
    covered_lines_by_file = {}

    for fname, file_cov in data.items():
        stmt_map = file_cov.get("statementMap", {})
        s = file_cov.get("s", {})
        uncovered = set()
        covered = set()
        for sid, loc in stmt_map.items():
            total_stmts += 1
            hits = s.get(sid, 0)
            start_line = loc.get("start", {}).get("line")
            end_line = loc.get("end", {}).get("line", start_line)
            if start_line is None:
                continue
            line_range = range(int(start_line), int(end_line) + 1)
            if hits and hits > 0:
                covered_stmts += 1
                covered.update(line_range)
            else:
                uncovered.update(line_range)
        # If a line is partially covered (covered in some stmts, uncovered in others)
        # treat covered as the winning signal.
        uncovered -= covered
        if uncovered:
            uncovered_lines_by_file[fname] = sorted(uncovered)
        covered_lines_by_file[fname] = sorted(covered)
    pct = (100.0 * covered_stmts / total_stmts) if total_stmts else 0.0
    return pct, uncovered_lines_by_file, set(data.keys()), covered_lines_by_file


def parse_go(path):
    """Go coverprofile:
        mode: <set|count|atomic>
        <file>:<startL>.<startC>,<endL>.<endC> <numStmt> <count>
    """
    total = 0
    covered = 0
    uncovered_lines_by_file = {}
    covered_lines_by_file = {}
    line_re = re.compile(
        r"^(?P<file>[^:]+):(?P<sl>\d+)\.\d+,(?P<el>\d+)\.\d+\s+(?P<n>\d+)\s+(?P<c>\d+)\s*$"
    )
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line or line.startswith("mode:"):
                continue
            m = line_re.match(line)
            if not m:
                continue
            fname = m.group("file")
            sl = int(m.group("sl"))
            el = int(m.group("el"))
            n = int(m.group("n"))
            c = int(m.group("c"))
            total += n
            line_range = range(sl, el + 1)
            if c > 0:
                covered += n
                covered_lines_by_file.setdefault(fname, set()).update(line_range)
            else:
                uncovered_lines_by_file.setdefault(fname, set()).update(line_range)
    # Subtract covered from uncovered (partial-block winner = covered).
    out = {}
    for fname, lines in uncovered_lines_by_file.items():
        cov = covered_lines_by_file.get(fname, set())
        diff = lines - cov
        if diff:
            out[fname] = sorted(diff)
    pct = (100.0 * covered / total) if total else 0.0
    coverage_files = set(covered_lines_by_file) | set(uncovered_lines_by_file)
    covered_out = {fn: sorted(ls) for fn, ls in covered_lines_by_file.items()}
    return pct, out, coverage_files, covered_out


def parse_python_cov_json(path):
    """coverage.py JSON: {"files": {<f>: {"executed_lines":[], "missing_lines":[]}}}"""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    total = 0
    covered = 0
    uncovered_lines_by_file = {}
    covered_lines_by_file = {}
    for fname, file_cov in data.get("files", {}).items():
        ex = file_cov.get("executed_lines", []) or []
        miss = file_cov.get("missing_lines", []) or []
        total += len(ex) + len(miss)
        covered += len(ex)
        if miss:
            uncovered_lines_by_file[fname] = sorted(int(x) for x in miss)
        covered_lines_by_file[fname] = sorted(int(x) for x in ex)
    pct = (100.0 * covered / total) if total else 0.0
    return pct, uncovered_lines_by_file, set(data.get("files", {}).keys()), covered_lines_by_file


def parse_cobertura(path):
    """Cobertura XML (used by python's coverage.xml and rust tarpaulin)."""
    tree = ET.parse(path)
    root = tree.getroot()
    total = 0
    covered = 0
    uncovered_lines_by_file = {}
    covered_lines_by_file = {}
    coverage_files = set()
    for cls in root.iter("class"):
        fname = cls.get("filename") or cls.get("name") or ""
        coverage_files.add(fname)
        miss = []
        hit = []
        for ln in cls.iter("line"):
            num = int(ln.get("number", "0"))
            hits = int(ln.get("hits", "0"))
            total += 1
            if hits > 0:
                covered += 1
                hit.append(num)
            else:
                miss.append(num)
        if miss:
            uncovered_lines_by_file.setdefault(fname, []).extend(miss)
        if hit:
            covered_lines_by_file.setdefault(fname, []).extend(hit)
    # Dedup + sort.
    for k, v in list(uncovered_lines_by_file.items()):
        uncovered_lines_by_file[k] = sorted(set(v))
    for k, v in list(covered_lines_by_file.items()):
        covered_lines_by_file[k] = sorted(set(v))
    pct = (100.0 * covered / total) if total else 0.0
    return pct, uncovered_lines_by_file, coverage_files, covered_lines_by_file


parsers = {
    "istanbul": parse_istanbul,
    "go":       parse_go,
    "python":   lambda p: (parse_cobertura(p) if p.endswith(".xml") else parse_python_cov_json(p)),
    "rust":     parse_cobertura,
}

if fmt not in parsers:
    sys.stderr.write(f"coverage_check.sh: unknown format {fmt}\n")
    sys.exit(1)

pct_whole, uncovered_whole, coverage_files, covered_whole = parsers[fmt](report)

note = None
if mode == "whole":
    pct = pct_whole
    uncovered = uncovered_whole
else:
    # --mode new: intersect uncovered with added lines.
    added = {}
    if added_file and os.path.isfile(added_file):
        with open(added_file, "r", encoding="utf-8") as f:
            try:
                added = json.load(f)
            except json.JSONDecodeError:
                added = {}

    # A brand-new source file may be wholly absent from the coverage report:
    # default nyc/istanbul and coverage.py-without-source= omit files that were
    # never imported by any test, so the report's file set is NOT a reliable
    # "coverable" oracle. We therefore classify by TWO signals:
    #   in_report(f)   — the report has per-line data for f (trustworthy).
    #   is_coverable(f)— f is coverable: in the report, OR a source file by
    #                    extension (report-absent new module — fail closed).
    # Anything else (markdown/YAML/config/etc.) is non-coverable and ignored.
    SOURCE_EXTS = {
        ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".go", ".rs",
        ".java", ".kt", ".kts", ".rb", ".swift", ".c", ".cc", ".cpp", ".cxx",
        ".h", ".hpp", ".hh", ".cs", ".php", ".scala", ".m", ".mm", ".sh",
        ".bash", ".ps1", ".psm1",
    }

    def resolve_key(diff_file, keys):
        """Map a repo-relative diff path onto its coverage-report key.

        Exact match first, then a BIDIRECTIONAL path-suffix match: Istanbul et al
        emit absolute keys while git diff emits repo-relative paths, but
        tarpaulin/cobertura can emit crate-relative keys that are SHORTER than the
        diff path — so both directions are needed.

        Bare-basename matching (the previous behaviour) was ambiguous and
        first-match-wins: with `src/a/index.ts` in the report and a wholly
        untested `src/b/index.ts` in the diff, the new file inherited the tested
        file's lines and scored pass:true / 100%. Basename collisions are the
        norm (index.ts, __init__.py, mod.rs, main.go), and since report keys are
        usually absolute this was the PRIMARY matching path, not a fallback.

        Zero candidates OR more than one (genuinely ambiguous) returns None, which
        falls into the existing fail-closed branch — an ambiguous file is treated
        as report-absent and every added line counts as uncovered.
        """
        if diff_file in keys:
            return diff_file
        cands = [k for k in keys
                 if k.endswith("/" + diff_file) or diff_file.endswith("/" + k)]
        return cands[0] if len(cands) == 1 else None

    def in_report(diff_file):
        return resolve_key(diff_file, coverage_files) is not None

    # Test files are the measuring instrument, not the measured surface: a
    # story's own new tests must not enter the new-code denominator (with
    # e.g. --cov=src they are absent from the report and would fail-closed
    # count as 0%-covered "new code", sinking the gate).
    def is_test_file(diff_file):
        parts = diff_file.replace("\\", "/").split("/")
        if any(p in ("tests", "test", "__tests__", "spec") for p in parts[:-1]):
            return True
        base = parts[-1]
        stem, _ = os.path.splitext(base)
        return (
            base.startswith("test_")
            or stem.endswith("_test")
            or ".spec." in base
            or ".test." in base
            or base == "conftest.py"
        )

    def is_coverable(diff_file):
        if is_test_file(diff_file):
            return False
        if in_report(diff_file):
            return True
        _, ext = os.path.splitext(diff_file)
        return ext.lower() in SOURCE_EXTS

    def report_lines(diff_file, table):
        key = resolve_key(diff_file, table)
        return set(table[key]) if key is not None else set()

    new_total = 0
    new_covered = 0
    uncovered = {}
    saw_coverable = False
    for diff_file, added_lines in added.items():
        if not is_coverable(diff_file):
            continue
        saw_coverable = True
        added_set = set(added_lines)
        if in_report(diff_file):
            # Executable lines = covered ∪ uncovered from the report. Only these
            # count — blank/comment/import/brace lines the report never
            # instrumented are excluded from BOTH numerator and denominator, so
            # a large comment block can't inflate the percentage.
            covered_set = report_lines(diff_file, covered_whole)
            uncov_set = report_lines(diff_file, uncovered_whole)
            executable = covered_set | uncov_set
            added_exec = added_set & executable
            added_cov = added_exec & covered_set
            new_total += len(added_exec)
            new_covered += len(added_cov)
            added_uncov = added_exec - added_cov
            if added_uncov:
                uncovered[diff_file] = sorted(added_uncov)
        else:
            # Report-absent source file: no per-line data, so fail closed —
            # every added line is treated as an uncovered executable line. A
            # whole untested new module therefore reports 0%, never a vacuous
            # pass.
            new_total += len(added_set)
            if added_set:
                uncovered[diff_file] = sorted(added_set)

    if new_total > 0:
        pct = 100.0 * new_covered / new_total
    elif saw_coverable:
        # Coverable source files were added but contributed no executable lines
        # (e.g. only comment/blank/import lines changed). Nothing to measure —
        # do NOT emit the misleading "only non-coverable files added" note.
        pct = None
        note = "no executable lines added in coverable files"
    else:
        # Diff added only non-coverable files (markdown/YAML/etc.): a defined,
        # documented result — pct:null + note — not a silent 100% or a
        # divide-by-zero. The gate passes: no coverable code was touched.
        pct = None
        note = "no coverable lines in diff (only non-coverable files added)"

result = {
    "mode":            mode,
    "gate_status":     "measured",
    "pct":             round(pct, 2) if pct is not None else None,
    "threshold":       threshold_f if threshold_f != int(threshold_f) else int(threshold_f),
    "pass":            True if pct is None else pct >= threshold_f,
    "uncovered":       [{"file": f, "lines": ls} for f, ls in sorted(uncovered.items())],
    "format_detected": fmt,
    "story_id":        story_id,
    "note":            note,
}

sys.stdout.write(json.dumps(result, sort_keys=True) + "\n")
PY

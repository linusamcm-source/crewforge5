#!/usr/bin/env bash
# shellcheck shell=bash
# lib.sh — shared helpers for the team-sprint skill. SOURCED, not executed.

# Guard against double-source (set -u trips on re-sourcing if guard absent).
if [[ -n "${TEAM_SPRINT_LIB_LOADED:-}" ]]; then
  return 0
fi
TEAM_SPRINT_LIB_LOADED=1

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

# Install hints — kept as functions so require_all can re-use them.
_hint_jq()         { printf '%s\n' "jq missing — install: brew install jq"; }
_hint_bats()       { printf '%s\n' "bats missing — install: brew install bats-core (>=1.10)"; }
_hint_shellcheck() { printf '%s\n' "shellcheck missing — install: brew install shellcheck (>=0.9)"; }
_hint_repomix()    { printf '%s\n' "repomix missing — install: npm i -g repomix OR bun add -g repomix (>=1.14)"; }
_hint_python3()    { printf '%s\n' "python3 missing — install: brew install python3"; }

require_jq()         { command -v jq         >/dev/null 2>&1 || { _hint_jq         >&2; return 1; }; }
require_bats()       { command -v bats       >/dev/null 2>&1 || { _hint_bats       >&2; return 1; }; }
require_shellcheck() { command -v shellcheck >/dev/null 2>&1 || { _hint_shellcheck >&2; return 1; }; }
require_repomix()    { command -v repomix    >/dev/null 2>&1 || { _hint_repomix    >&2; return 1; }; }
require_python3()    { command -v python3    >/dev/null 2>&1 || { _hint_python3    >&2; return 1; }; }

# require_all probes every tool in declaration order, accumulating install
# hints for ALL missing tools before exiting. Single missing → single hint;
# multi-missing → all hints joined by newlines.
require_all() {
  local missing=""
  local tool
  for tool in jq bats shellcheck repomix python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      local hint
      hint="$("_hint_${tool}")"
      if [[ -z "$missing" ]]; then
        missing="$hint"
      else
        missing="${missing}
${hint}"
      fi
    fi
  done
  if [[ -n "$missing" ]]; then
    printf '%s\n' "$missing" >&2
    return 1
  fi
  return 0
}

# repo_root — echo the main-repo root as an absolute, symlink-resolved path.
#
# Resolved from `git rev-parse --git-common-dir` (parent of the shared .git
# dir) so calls from a worktree CWD still return the MAIN repo root, not the
# worktree root. `--show-toplevel` would return the worktree root and create
# dual artifact locations, so it is deliberately NOT used here (CC-1 in
# plan-final; the dual-artifact bug recurred 2026-05-20/27, 06-09/10).
# --git-common-dir may be relative (e.g. ".git" in the main repo), so cd +
# pwd -P canonicalises it to an absolute path in both worktree and
# non-worktree cases.
#
# Outside a git repository `git rev-parse --git-common-dir` prints nothing and
# `cd "$common/.."` lands on `/`, which every caller then inherits as the repo
# root — art_dir, recon.sh's capability cache and its file-count guard alike.
# A guard that goes on to shell `find /` is the hazard, so an empty
# --git-common-dir fails loud instead of resolving to `/` (Story RH3).
repo_root() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] || fail "repo_root: not inside a git repository (git rev-parse --git-common-dir returned empty)"
  (cd "$common/.." && pwd -P)
}

# art_dir — resolve absolute artifact dir for a plan_path.
#   1. In-sprint-dir short-circuit: canonicalise plan_path's directory; if its
#      parent IS a .team-sprint/sprints dir and its basename is sprint-<slug>
#      directly (exact depth — not a deeper descendant, not another
#      .team-sprint subdir), that sprint dir (anchored at the MAIN repo root)
#      is used. The parent test is a suffix match on */.team-sprint/sprints,
#      not an exact repo_root comparison: a relative plan path resolved from a
#      worktree CWD canonicalises under the WORKTREE, and an exact-root test
#      would miss it and mint a slug from the basename. Revision artifacts
#      like <sprint-dir>/plan-vN.md must not mint a new slug from their
#      basename (obs 18980: `state.sh update <sprint-dir>/plan-v4.md` invented
#      sprint-plan-v4 and exited 2).
#   2. Otherwise derive SPRINT_DIR via validate_plan_path.sh --slug-only.
#   3. If state.json exists under repo_root + SPRINT_DIR AND has
#      .artifact_dir set (absolute), echo that.
#   4. Otherwise echo <main-repo-root>/SPRINT_DIR.
art_dir() {
  local plan_path="$1"
  local root
  root="$(repo_root)"
  local sprint_dir=""
  local plan_dir
  plan_dir="$(cd "$(dirname "$plan_path")" 2>/dev/null && pwd -P)" || plan_dir=""
  if [[ "$(dirname "$plan_dir")" == */.team-sprint/sprints \
        && "$(basename "$plan_dir")" == sprint-* ]]; then
    sprint_dir=".team-sprint/sprints/$(basename "$plan_dir")"
  else
    sprint_dir="$("$SCRIPTS/validate_plan_path.sh" --slug-only "$plan_path" \
                   | awk -F= '$1=="SPRINT_DIR"{print $2}')"
  fi
  if [[ -z "$sprint_dir" ]]; then
    fail "art_dir: could not derive SPRINT_DIR from $plan_path"
  fi
  local candidate="$root/$sprint_dir/state.json"
  if [[ -f "$candidate" ]]; then
    local existing
    existing="$(jq -r '.artifact_dir // ""' "$candidate" 2>/dev/null || true)"
    if [[ -n "$existing" && "$existing" = /* ]]; then
      printf '%s\n' "$existing"
      return 0
    fi
  fi
  printf '%s\n' "$root/$sprint_dir"
}

# resolve_diff_base <state_json> <story_id> <sprint_branch> <target_branch>
#   Echo the diff base for a story: the prior story's recorded SHA from
#   state.json.story_commits[], else merge-base(sprint_branch, target_branch).
#
#   story_commits[] is ordered; the "prior" SHA is the entry immediately before
#   <story_id>. If <story_id> is the first entry (index 0) or the list is empty
#   there is no prior, so the merge-base is used. If <story_id> is absent from a
#   non-empty list ("in flight") the last recorded entry is the prior. An empty
#   <story_id> skips the lookup and always falls to the merge-base.
#
#   Extracted from the identical inline resolvers in coverage_check.sh and
#   per_story_diff.sh (Story LS4). Fails if the merge-base is needed but the
#   target branch is empty or git merge-base fails.
resolve_diff_base() {
  local state_json="$1" story_id="$2" sprint_branch="$3" target_branch="$4"
  local prior_sha="" base
  if [[ -n "$story_id" ]]; then
    prior_sha="$(printf '%s' "$state_json" | jq -r --arg sid "$story_id" '
      (.story_commits // []) as $sc
      | ($sc | map(.story_id) | index($sid)) as $idx
      | if   $idx == null then
          if ($sc | length) > 0 then $sc[-1].sha else "" end
        elif $idx == 0    then ""
        else $sc[$idx - 1].sha
        end
    ')"
  fi
  if [[ -n "$prior_sha" && "$prior_sha" != "null" ]]; then
    printf '%s\n' "$prior_sha"
    return 0
  fi
  [[ -n "$target_branch" ]] || fail "resolve_diff_base: cannot resolve target_branch (set TS_TARGET_BRANCH or seed state.json)"
  base="$(git merge-base "$sprint_branch" "$target_branch" 2>/dev/null || true)"
  [[ -n "$base" ]] || fail "resolve_diff_base: git merge-base $sprint_branch $target_branch failed"
  printf '%s\n' "$base"
}

# read_config_command <config_file> <key>
#   Echo the commands.<key> value from a team-sprint config yaml, or empty
#   string when the file or key is absent.
#
#   Parses only the shape the skill uses — a top-level `commands:` block with
#   indented children — without a yaml dependency: blank and comment lines are
#   skipped, the `commands:` block is tracked via top-level-key resets, and a
#   value is unwrapped from surrounding quotes or stripped of a trailing `#`
#   comment. Extracted from the identical inline `commands:` parsers in
#   coverage_check.sh (read_config) and detect_commands.sh
#   (read_config_commands) (Story LS4). An empty or comment-only value does not
#   overwrite a prior non-empty match (last non-empty wins).
read_config_command() {
  # Delegates: the single-key form was a byte-for-byte duplicate of the batch
  # reader's state machine (quote unwrap, trailing-`#` strip, top-level-key
  # resets) and had ZERO production callers -- both real readers use the batch
  # form (coverage_check.sh:129, detect_commands.sh:71). Kept as a thin wrapper
  # so its bats coverage and any external caller keep working.
  #
  # NOT byte-equivalent in one unreached corner: on an UNREADABLE config
  # (chmod 000) the old single form raised PermissionError and exited 1, while
  # the batch form catches OSError and returns empty with rc 0. No caller or
  # test reaches that path, and returning empty is the more robust behaviour.
  read_config_commands "$1" "$2"
}

# read_config_scalar <config_file> <key>
#   Echo the value of a TOP-LEVEL scalar key (e.g. `coverage_threshold:`) from a
#   team-sprint config yaml, or empty string when the file or key is absent.
#   Mirrors read_config_command's quote-unwrap / trailing-`#`-comment strip, but
#   for an unindented top-level key rather than a child of `commands:`. Extracted
#   from the duplicated inline scalar parser in coverage_check.sh (Story P2-6).
#   An empty or comment-only value does not overwrite a prior match.
read_config_scalar() {
  local config_file="$1" key="$2"
  [[ -f "$config_file" ]] || { printf '\n'; return 0; }
  python3 - "$config_file" "$key" <<'PY'
import re
import sys

path, key = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()


def strip(v):
    v = v.strip()
    if v.startswith('"') or v.startswith("'"):
        q = v[0]
        end = v.find(q, 1)
        if end != -1:
            return v[1:end]
        return v[1:]
    return v.split("#", 1)[0].strip()


val = ""
key_re = re.compile(r"^" + re.escape(key) + r":\s*(.*)$")
for raw in text.splitlines():
    line = raw.rstrip()
    if not line or line.lstrip().startswith("#") or line.startswith((" ", "\t")):
        continue
    m = key_re.match(line)
    if m:
        v = strip(m.group(1))
        if v:
            val = v

sys.stdout.write(val + "\n")
PY
}

# read_config_commands <config_file> <key>...
#   Batch reader: echo the commands.<key> value for EACH key, one per line, in
#   argument order (an empty line for an absent key or missing file). Same parse
#   as read_config_command but in a SINGLE python invocation, so a caller reading
#   several keys (detect_commands.sh reads four) forks python once instead of N
#   times (Story P2-5, cold-path fork reduction). Always emits exactly one line
#   per key.
read_config_commands() {
  local config_file="$1"; shift
  python3 - "$config_file" "$@" <<'PY'
import re
import sys

path, keys = sys.argv[1], sys.argv[2:]
try:
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
except OSError:
    text = ""


def strip(v):
    v = v.strip()
    if v.startswith('"') or v.startswith("'"):
        q = v[0]
        end = v.find(q, 1)
        if end != -1:
            return v[1:end]
        return v[1:]
    return v.split("#", 1)[0].strip()


vals = {k: "" for k in keys}
key_res = {k: re.compile(r"^\s+" + re.escape(k) + r":\s*(.*)$") for k in keys}
in_commands = False
for raw in text.splitlines():
    line = raw.rstrip()
    if not line or line.lstrip().startswith("#"):
        continue
    if not line.startswith((" ", "\t")):
        in_commands = line.startswith("commands:")
        continue
    if not in_commands:
        continue
    for k in keys:
        m = key_res[k].match(line)
        if m:
            v = strip(m.group(1))
            if v:
                vals[k] = v
            break

sys.stdout.write("\n".join(vals[k] for k in keys) + "\n")
PY
}

# mtime_epoch <file> — echo the file's mtime as an integer Unix epoch.
#   GNU `stat -c %Y` (Linux) first, then BSD `stat -f %m` (macOS). The order
#   matters: GNU stat reads `-f` as "filesystem", prints a multi-line report on
#   stdout and exits non-zero, so a BSD-first probe feeds that report to the
#   caller. When it lands in `$(( ))`, bash parses the leading word as a
#   variable name and `set -u` kills the script with "File: unbound variable"
#   several frames away. BSD stat has no `-c` at all and fails cleanly, so
#   reversing the order is safe. The integer check rejects a non-numeric answer
#   here rather than deep inside an arithmetic expansion.
mtime_epoch() {
  local file="$1" out
  out="$(stat -c %Y "$file" 2>/dev/null)" || out=""
  if [[ ! "$out" =~ ^[0-9]+$ ]]; then
    out="$(stat -f %m "$file" 2>/dev/null)" || out=""
  fi
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$out"
}

# now_ms — echo the current Unix epoch in MILLISECONDS, as an integer.
#   The millisecond clock behind recon.sh's elapsed_ms (Story RH4). macOS
#   /bin/bash is 3.2.57 and has no EPOCHREALTIME, and `date +%s%3N` is GNU-only:
#   BSD date prints a literal `3N`, which would land in the call log as a
#   corrupt elapsed_ms. So this shells python3, the same dependency
#   read_config_scalar already takes.
now_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

# resolve_agent_type <config_file> <state_json> <config_key> <crew_key> <default>
#   Echo the subagent_type to spawn for a role, applying the ONE canonical
#   precedence:
#
#     explicit non-`auto` config <config_key>  >  state.json .crew.<crew_key>  >  <default>
#
#   This rule was previously restated in prose in SKILL.md, phase-3.md (twice)
#   and phase-4.md — four copies that could drift. Phases now call this instead
#   of re-deriving it. `auto` is the documented "no explicit override" sentinel
#   and must fall through, not resolve to the literal string "auto".
#
#   Missing config file, missing state file, absent keys, and `null` all fall
#   through to the next tier. Always echoes exactly one line.
resolve_agent_type() {
  local config_file="$1" state_json="$2" config_key="$3" crew_key="$4" default="$5"
  local v=""

  # Tier 1 — explicit config override.
  if [[ -f "$config_file" ]]; then
    v="$(read_config_scalar "$config_file" "$config_key")"
    v="${v%%[[:space:]]}"
    if [[ -n "$v" && "$v" != "auto" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  # Tier 2 — crew manifest resolved at Phase 0.
  if [[ -f "$state_json" ]] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r --arg k "$crew_key" '.crew[$k] // empty' "$state_json" 2>/dev/null)"
    if [[ -n "$v" && "$v" != "null" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  # Tier 3 — static default.
  printf '%s\n' "$default"
}

#!/usr/bin/env bash
# crew_check.sh — mechanised crew-manifest gates for crew-factory Phase 0 and
# team-sprint phase-0 step 10a.2. Owns the file/jq checks; fit and rebuild
# decisions stay with the calling agent.
#
# Usage:
#   crew_check.sh check <lang> [--project-dir <dir>] [--agents-dir <dir>] [--max-age-days <n>]
#   crew_check.sh verify <lang> [--project-dir <dir>]
#   crew_check.sh collision <lang> <role>... [--project-dir <dir>] [--agents-dir <dir>]
#
# Where agents live: generated agents are written to the PROJECT, at
# <project-dir>/.claude/agents (the --agents-dir default), because a crew is a
# property of the codebase it was built for — it costs description tokens in
# that repo and nowhere else, and it travels with the repo to the rest of the
# team. Reused agents are the exception: a role may map to a general-purpose
# agent from the user catalogue (boundary-reviewer, for one), so resolution
# falls back to ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents. Project first,
# matching how Claude Code itself resolves a subagent name.
#
# check — is the cached manifest usable?
#   STATUS=CACHED   manifest exists, schema-valid (see crews.schema.json),
#                   every crew.<role> resolves to <name>.md in the project or
#                   the user catalogue, and
#                   every generated agent still matches the required structure
#                   (frontmatter name/description/tools + '## Stack Knowledge'
#                   seed + '## Skills' where the manifest assigns skills).
#                   Reused agents are not structure-checked — the factory
#                   never wrote them.
#   STATUS=REBUILD  with REASON=manifest_missing|schema:<msg>|unresolved:<names>
#                   |malformed:<name>:<issue>,...  (malformed -> the factory
#                   rebuilds the named agents; conforming ones are reusable)
#   STALE=true|false|unknown  profile 'Verified YYYY-MM-DD' stamp older than
#                   --max-age-days (default 5). Informational only — never
#                   gates; the factory surfaces it as a --verify suggestion.
#   RULE_FILE=present|missing  is there a .claude/rules/<lang>.md carrying the
#                   stack's house conventions? Informational only, same as
#                   STALE — the factory writes a missing one in place, without
#                   regenerating a single agent.
#
# verify — do the manifest's verified commands still pass?
#   One 'CMD <name> PASS|FAIL' line per non-empty commands.* entry, then
#   STATUS=OK|FAIL. A FAIL is real rot: the factory escalates to a rebuild.
#
# collision — are the planned generated names safe to write?
#   For each role, <lang>-<role>.md existing in either directory without being
#   listed in the manifest's generated[] is an unrelated agent:
#   'COLLISION <name>' per hit, then STATUS=OK|COLLISION. The user catalogue
#   counts because a project agent SHADOWS a user one of the same name, so
#   writing over that name silently changes which agent an unrelated repo
#   would have got.
#
# Exit codes: 0 check ran (verdict is in STATUS) | 1 IO/tooling | 2 usage

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

usage() {
  sed -n '5,9p' "$0" | sed 's/^# //' >&2
  exit 2
}

MODE="" LANG_ARG="" PROJECT_DIR="$PWD" AGENTS_DIR="" MAX_AGE_DAYS=5
USER_AGENTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"
# Agents shipped by the plugin this script lives in. Without this tier, a crew
# manifest naming a registry agent — `boundary-reviewer`, which crew-factory is
# REQUIRED to reference and FORBIDDEN to generate — never resolves on a cold
# install, and every Phase 0 re-triggers a full rebuild (~470s per agent) for a
# file that was sitting in the bundle the whole time. It resolved here only
# because this machine happens to carry a personal copy in its user catalogue.
PLUGIN_AGENTS_DIR="$(cd "$SCRIPTS/../../.." 2>/dev/null && pwd)/agents"
ROLES=()

parse_args() {
  [[ $# -ge 2 ]] || usage
  MODE="$1"; LANG_ARG="$2"; shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir)  [[ $# -ge 2 ]] || usage; PROJECT_DIR="$2"; shift 2 ;;
      --agents-dir)   [[ $# -ge 2 ]] || usage; AGENTS_DIR="$2"; shift 2 ;;
      --max-age-days) [[ $# -ge 2 ]] || usage; MAX_AGE_DAYS="$2"; shift 2 ;;
      -*)             usage ;;
      *)              ROLES+=("$1"); shift ;;
    esac
  done
  case "$MODE" in check|verify|collision) ;; *) usage ;; esac
  [[ -d "$PROJECT_DIR" ]] || fail "crew_check.sh: not a directory: $PROJECT_DIR"
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
  # Defaulted after parsing, since it hangs off --project-dir.
  AGENTS_DIR="${AGENTS_DIR:-$PROJECT_DIR/.claude/agents}"
}

# Echo the path an agent name resolves to, project catalogue first, nothing if
# it resolves nowhere. Project-first mirrors Claude Code's own precedence, so a
# name checked here is the file that would actually be spawned.
agent_file() {
  local name="$1"
  if [[ -f "$AGENTS_DIR/$name.md" ]]; then
    printf '%s/%s.md' "$AGENTS_DIR" "$name"
  elif [[ -f "$USER_AGENTS_DIR/$name.md" ]]; then
    printf '%s/%s.md' "$USER_AGENTS_DIR" "$name"
  elif [[ -f "$PLUGIN_AGENTS_DIR/$name.md" ]]; then
    # Last, deliberately: a project or user agent of the same name still wins,
    # so this only ever adds resolutions that would otherwise have failed.
    printf '%s/%s.md' "$PLUGIN_AGENTS_DIR" "$name"
  fi
}

manifest_path() { printf '%s/.claude/crews/%s.json' "$PROJECT_DIR" "$LANG_ARG"; }
rule_path()     { printf '%s/.claude/rules/%s.md'    "$PROJECT_DIR" "$LANG_ARG"; }

# Pure-jq schema validation, same pattern as state.sh _validate_state.
# crews.schema.json is the human-readable statement of this shape.
validate_manifest() {
  local f="$1" err
  err="$(
    jq -e '
      def must(cond; msg): if cond then . else error(msg) end;

      must(type == "object"; "root must be object")
      | must(.language      | type == "string"; "language must be string")
      | must(.stack_profile | type == "string"; "stack_profile must be string")
      | must(.commands | type == "object" and (to_entries | all(.value | type == "string")); "commands must be an object of string values")
      | must(.crew | type == "object" and length > 0 and (to_entries | all(.value | type == "string" and (. | length) > 0)); "crew must be a non-empty object of non-empty string values")
      | must(.validation | type == "object"; "validation must be object")
      | must((.skills // {}) | type == "object" and (to_entries | all(.value | type == "array" and all(.[]; type == "string"))); "skills must be an object of string arrays")
      | must(.generated | type == "array" and all(.[]; type == "string"); "generated must be an array of strings")
      | must(.reused    | type == "array" and all(.[]; type == "string"); "reused must be an array of strings")
      | true
    ' "$f" 2>&1 >/dev/null
  )" || {
    printf '%s' "$err"
    return 1
  }
  return 0
}

# Echo the FIRST structural issue with a generated agent file, nothing if clean.
# Encodes the crew-factory generation contract: frontmatter (name matching the
# file, description, tools) + the Stack Knowledge seed ('## Stack Knowledge'
# matches both the developer base and the '(inherited)' role variant).
agent_structure_issue() {
  local name="$1" f
  f="$(agent_file "$name")"
  [[ -n "$f" ]] || return 0
  [[ "$(head -1 "$f")" == "---" ]] || { printf 'no_frontmatter'; return 0; }
  grep -qE "^name: *${name}[[:space:]]*$" "$f" || { printf 'name_mismatch'; return 0; }
  grep -q '^description:' "$f" || { printf 'no_description'; return 0; }
  grep -q '^tools:' "$f" || { printf 'no_tools'; return 0; }
  grep -q '^## Stack Knowledge' "$f" || { printf 'no_stack_knowledge'; return 0; }
  return 0
}

profile_staleness() {
  local manifest="$1" profile stamp
  profile="$(jq -r '.stack_profile // empty' "$manifest")"
  [[ -n "$profile" ]] || { printf 'unknown'; return 0; }
  [[ "$profile" = /* ]] || profile="$PROJECT_DIR/$profile"
  [[ -f "$profile" ]] || { printf 'unknown'; return 0; }
  stamp="$(grep -oE 'Verified [0-9]{4}-[0-9]{2}-[0-9]{2}' "$profile" | head -1 | cut -d' ' -f2 || true)"
  [[ -n "$stamp" ]] || { printf 'unknown'; return 0; }
  require_python3 >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  python3 - "$stamp" "$MAX_AGE_DAYS" <<'PY'
import datetime, sys
stamp = datetime.date.fromisoformat(sys.argv[1])
age = (datetime.date.today() - stamp).days
print("true" if age > int(sys.argv[2]) else "false")
PY
}

do_check() {
  local manifest missing="" role_name err stale
  manifest="$(manifest_path)"
  if [[ ! -f "$manifest" ]]; then
    printf 'STATUS=REBUILD\nREASON=manifest_missing\n'
    return 0
  fi
  if ! err="$(validate_manifest "$manifest")"; then
    printf 'STATUS=REBUILD\nREASON=schema:%s\n' "$err"
    return 0
  fi
  while IFS= read -r role_name; do
    [[ -n "$(agent_file "$role_name")" ]] || missing="${missing:+$missing,}$role_name"
  done < <(jq -r '.crew | to_entries[].value' "$manifest")
  if [[ -n "$missing" ]]; then
    printf 'STATUS=REBUILD\nREASON=unresolved:%s\n' "$missing"
    return 0
  fi

  # Generated agents must still match the generation contract; an agent the
  # factory wrote that no longer conforms gets rebuilt. Reused agents are
  # exempt — the factory never wrote them.
  local malformed="" issue agent_name agent_path
  while IFS= read -r agent_name; do
    [[ -n "$(agent_file "$agent_name")" ]] || continue
    issue="$(agent_structure_issue "$agent_name")"
    [[ -z "$issue" ]] || malformed="${malformed:+$malformed,}$agent_name:$issue"
  done < <(jq -r '.generated[]' "$manifest")

  # A generated agent for a role with assigned skills must carry '## Skills'.
  while IFS= read -r agent_name; do
    agent_path="$(agent_file "$agent_name")"
    [[ -n "$agent_path" ]] || continue
    grep -q '^## Skills' "$agent_path" \
      || malformed="${malformed:+$malformed,}$agent_name:no_skills_section"
  done < <(jq -r '
      .generated as $gen
      | .crew as $crew
      | (.skills // {}) | to_entries[]
      | select((.value | length) > 0)
      | $crew[.key] // empty
      | select(. as $n | $gen | index($n) != null)
    ' "$manifest")

  if [[ -n "$malformed" ]]; then
    printf 'STATUS=REBUILD\nREASON=malformed:%s\n' "$malformed"
    return 0
  fi

  stale="$(profile_staleness "$manifest")"
  # RULE_FILE follows the STALE precedent exactly: informational, never gating.
  # Every crew that predates rule generation lacks one, and returning REBUILD
  # for that would regenerate every existing crew at ~470s apiece to produce a
  # file the factory can write in place without touching a single agent.
  rule="missing"
  [[ -f "$(rule_path)" ]] && rule="present"
  printf 'STATUS=CACHED\nSTALE=%s\nRULE_FILE=%s\n' "$stale" "$rule"
}

do_verify() {
  local manifest name cmd rc all_ok=1
  manifest="$(manifest_path)"
  [[ -f "$manifest" ]] || fail "crew_check.sh verify: no manifest at $manifest"
  validate_manifest "$manifest" >/dev/null || fail "crew_check.sh verify: manifest fails schema"
  while IFS=$'\t' read -r name cmd; do
    [[ -n "$cmd" ]] || continue
    rc=0
    (cd "$PROJECT_DIR" && bash -c "$cmd") >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
      printf 'CMD %s PASS\n' "$name"
    else
      printf 'CMD %s FAIL\n' "$name"
      all_ok=0
    fi
  done < <(jq -r '.commands | to_entries[] | [.key, .value] | @tsv' "$manifest")
  if [[ $all_ok -eq 1 ]]; then printf 'STATUS=OK\n'; else printf 'STATUS=FAIL\n'; fi
}

do_collision() {
  [[ ${#ROLES[@]} -gt 0 ]] || usage
  local manifest role target hit=0
  manifest="$(manifest_path)"
  for role in "${ROLES[@]}"; do
    target="$LANG_ARG-$role"
    [[ -n "$(agent_file "$target")" ]] || continue
    if [[ -f "$manifest" ]] && jq -e --arg n "$target" '.generated | index($n) != null' "$manifest" >/dev/null 2>&1; then
      continue  # our own prior output — overwriting it is a refresh, not a collision
    fi
    printf 'COLLISION %s\n' "$target"
    hit=1
  done
  if [[ $hit -eq 0 ]]; then printf 'STATUS=OK\n'; else printf 'STATUS=COLLISION\n'; fi
}

main() {
  parse_args "$@"
  require_jq || exit 1
  case "$MODE" in
    check)     do_check ;;
    verify)    do_verify ;;
    collision) do_collision ;;
  esac
}

main "$@"

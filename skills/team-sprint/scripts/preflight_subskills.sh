#!/usr/bin/env bash
# shellcheck shell=bash
# preflight_subskills.sh — sub-skill presence probe for Phase 0.
#
# Two modes:
#   --probe-only <skill-name>   probe a single skill; exit 0 if present, 1 if absent.
#   --probe-all <plan_path>     probe every entry in $ART/state.json.subskill_hooks;
#                               honour per-entry `required` flag.
#
# Optional flags:
#   --probe-fn <path-to-script> override the default probe. The script is
#                               invoked as `<probe-fn> <skill-name>`; exit 0
#                               means present, non-zero means absent. Used by
#                               bats fixtures to inject canned verdicts.
#   --cache <path-to-json>      override the default lead-side cache file
#                               ($ART/preflight-cache.json) location.
#
# Default probe (no --probe-fn) delegates to the sub-skill resolver:
#   scripts/flow/subskill_resolve.sh --probe <skill-name>
# which searches the plugin tree, the project catalogue and the user catalogue
# in that order. Probing $HOME alone — as this did — declared every
# plugin-installed sub-skill missing, since plugin skills never live there.
#
# Lead-side cache (optional enrichment): when $ART/preflight-cache.json
# exists, a present/absent verdict for a given skill name wins over the
# filesystem default. Cache schema (pinned):
#   { "<skill-name>": { "present": bool, "probed_at": "<ISO-8601>", "source": "agent-tool" } }
#
# --probe-fn always wins over both cache and filesystem (test-injection).
#
# Exit codes:
#   0 all probed skills present (or --probe-all completed with no required-fail)
#   1 at least one `required: true` skill probe failed (or --probe-only miss)
#   2 usage error

set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_HERE/lib.sh"

usage() {
  cat <<'USAGE' >&2
usage: preflight_subskills.sh --probe-only <skill-name> [--probe-fn <path>] [--cache <path>]
       preflight_subskills.sh --probe-all <plan_path>  [--probe-fn <path>] [--cache <path>]
USAGE
  exit 2
}

MODE=""
ARG=""
PROBE_FN=""
CACHE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-only) [[ $# -ge 2 ]] || usage; MODE="probe-only"; ARG="$2"; shift 2 ;;
    --probe-all)  [[ $# -ge 2 ]] || usage; MODE="probe-all";  ARG="$2"; shift 2 ;;
    --probe-fn)   [[ $# -ge 2 ]] || usage; PROBE_FN="$2"; shift 2 ;;
    --cache)      [[ $# -ge 2 ]] || usage; CACHE_PATH="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            usage ;;
  esac
done

[[ -n "$MODE" && -n "$ARG" ]] || usage

# ---------------------------------------------------------------------------
# Probe helpers.
# ---------------------------------------------------------------------------

# Default filesystem probe — pure shell, no Agent tool involved.
_fs_probe() {
  local skill="$1"
  bash "$_HERE/../../../scripts/flow/subskill_resolve.sh" --probe "$skill"
}

# Cache lookup. Returns 0=present, 1=absent (with explicit "false"), 2=unknown.
_cache_lookup() {
  local skill="$1"
  local cache="$2"
  [[ -n "$cache" && -f "$cache" ]] || return 2
  require_jq || return 2
  local v
  v="$(jq -r --arg s "$skill" '
    if (.[$s] | type) == "object" and (.[$s].present | type) == "boolean"
    then (.[$s].present | tostring)
    else "unknown"
    end
  ' "$cache" 2>/dev/null || echo unknown)"
  case "$v" in
    true)  return 0 ;;
    false) return 1 ;;
    *)     return 2 ;;
  esac
}

# Composite probe: --probe-fn wins; else cache; else filesystem.
_probe_skill() {
  local skill="$1"
  if [[ -n "$PROBE_FN" ]]; then
    "$PROBE_FN" "$skill"
    return $?
  fi
  if _cache_lookup "$skill" "$CACHE_PATH"; then
    return 0
  else
    local rc=$?
    if [[ "$rc" -eq 1 ]]; then
      # Cache explicitly says absent — verdict wins.
      return 1
    fi
    # Cache silent → filesystem fallback.
  fi
  _fs_probe "$skill"
}

# ---------------------------------------------------------------------------
# Modes.
# ---------------------------------------------------------------------------

case "$MODE" in
  probe-only)
    SKILL="$ARG"
    if _probe_skill "$SKILL"; then
      exit 0
    else
      exit 1
    fi
    ;;

  probe-all)
    PLAN_PATH="$ARG"
    require_jq || exit 2
    ART="$(art_dir "$PLAN_PATH")"
    STATE="$ART/state.json"
    if [[ -z "$CACHE_PATH" ]]; then
      CACHE_PATH="$ART/preflight-cache.json"
    fi

    if [[ ! -f "$STATE" ]]; then
      warn "preflight_subskills.sh: state.json not found at $STATE; nothing to probe"
      exit 0
    fi

    HOOKS_JSON="$(jq -c '.subskill_hooks // []' "$STATE" 2>/dev/null || echo '[]')"
    COUNT="$(printf '%s' "$HOOKS_JSON" | jq 'length')"
    if [[ "$COUNT" -eq 0 ]]; then
      info "preflight_subskills.sh: no subskill_hooks declared; skipping probe"
      exit 0
    fi

    rc_global=0
    seen=""
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      skill="$(printf '%s' "$entry" | jq -r '.skill // ""')"
      required="$(printf '%s' "$entry" | jq -r '.required // false')"
      [[ -n "$skill" ]] || continue

      # De-dup: probe each skill name once across the array.
      case " $seen " in
        *" $skill "*) continue ;;
      esac
      seen="$seen $skill"

      if _probe_skill "$skill"; then
        info "subskill probe OK: $skill"
      else
        if [[ "$required" == "true" ]]; then
          warn "subskill probe FAILED (required): $skill"
          rc_global=1
        else
          warn "subskill probe FAILED (optional): $skill — hook will still attempt to run (command is authoritative)"
        fi
      fi
    done < <(printf '%s' "$HOOKS_JSON" | jq -c '.[]')

    exit "$rc_global"
    ;;

  *)
    usage
    ;;
esac

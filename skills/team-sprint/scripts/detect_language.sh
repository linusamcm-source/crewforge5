#!/usr/bin/env bash
# detect_language.sh — canonical crew language detection. team-sprint phase-0
# step 10a.1 and crew-factory Phase 0 both call this; neither keeps a prose
# copy of the marker table (the two prose copies drifted once already).
#
# Usage:
#   detect_language.sh [<project_dir>]
#
# Emits key=value lines on stdout:
#   STATUS=OK|AMBIGUOUS|UNKNOWN
#   LANG=<python|react-native|typescript|go|rust|powershell|bash>  (OK only)
#   CANDIDATES=<comma-separated langs>                             (AMBIGUOUS only)
#
# Marker table (exactly one hit -> OK):
#   pyproject.toml | setup.py               -> python
#   package.json with a react-native dep    -> react-native
#   package.json without                    -> typescript
#   go.mod                                  -> go
#   Cargo.toml                              -> rust
#   any *.psd1 / *.psm1 (depth <= 3)        -> powershell
#   no marker above, *.sh dominant (<= 3)   -> bash
#
# Markers from multiple families -> AMBIGUOUS with CANDIDATES; picking the
# primary by source volume is the caller's judgment, not this script's.
#
# Exit codes: 0 detection ran (including AMBIGUOUS/UNKNOWN) | 1 usage/IO

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

usage() {
  printf 'usage: detect_language.sh [<project_dir>]\n' >&2
  exit 2
}

main() {
  [[ $# -le 1 ]] || usage
  local dir="${1:-$PWD}"
  [[ -d "$dir" ]] || fail "detect_language.sh: not a directory: $dir"
  dir="$(cd "$dir" && pwd -P)"

  local candidates=()

  if [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" ]]; then
    candidates+=("python")
  fi

  if [[ -f "$dir/package.json" ]]; then
    require_jq || exit 1
    if jq -e '(.dependencies["react-native"] // .devDependencies["react-native"]) != null' \
        "$dir/package.json" >/dev/null 2>&1; then
      candidates+=("react-native")
    else
      candidates+=("typescript")
    fi
  fi

  [[ -f "$dir/go.mod" ]] && candidates+=("go")
  [[ -f "$dir/Cargo.toml" ]] && candidates+=("rust")

  local psd1_count
  psd1_count="$(find "$dir" -maxdepth 3 \( -name '*.psd1' -o -name '*.psm1' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$psd1_count" -gt 0 ]] && candidates+=("powershell")

  # bash is the fallback family: only considered when no manifest marker hit,
  # and only when *.sh outnumbers the other source families combined.
  if [[ ${#candidates[@]} -eq 0 ]]; then
    local sh_count other_count
    sh_count="$(find "$dir" -maxdepth 3 -name '*.sh' \
      -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    other_count="$(find "$dir" -maxdepth 3 \
      \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' \) \
      -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$sh_count" -gt 0 && "$sh_count" -ge "$other_count" ]]; then
      candidates+=("bash")
    fi
  fi

  case ${#candidates[@]} in
    0)
      printf 'STATUS=UNKNOWN\n'
      ;;
    1)
      printf 'STATUS=OK\n'
      printf 'LANG=%s\n' "${candidates[0]}"
      ;;
    *)
      local joined="" c
      for c in "${candidates[@]}"; do
        joined="${joined:+$joined,}$c"
      done
      printf 'STATUS=AMBIGUOUS\n'
      printf 'CANDIDATES=%s\n' "$joined"
      ;;
  esac
}

main "$@"

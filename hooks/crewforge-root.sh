#!/usr/bin/env bash
# crewforge-root.sh — SessionStart announcement of the plugin's install path.
#
# WHY THIS EXISTS. `${CLAUDE_PLUGIN_ROOT}` is expanded by the harness inside
# hook and command strings; it is NOT an environment variable the Bash tool
# inherits. Every skill in this plugin documents commands that live under the
# plugin tree, and a fresh installer has no way to know where that tree is —
# the install path carries a marketplace name and a version hash.
#
# So the one channel that does see the variable — a hook command — publishes it
# once per session, both as context the model can act on and as a file scripts
# can read. One short line; it is the price of being relocatable.
#
# Fails open and silent: an unknown root is a broken command later, never a
# blocked session now.
set -uo pipefail
exec 2>/dev/null

ROOT="${1:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT" ] || exit 0

STATE="${CLAUDE_PLUGIN_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/crewforge}"
mkdir -p "$STATE" && printf '%s\n' "$ROOT" > "$STATE/root" || true

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"SessionStart",
  "additionalContext":
    f"CrewForge root: {sys.argv[1]} — expand $CREWFORGE_ROOT to it in this plugin's commands."}}))
' "$ROOT"
exit 0

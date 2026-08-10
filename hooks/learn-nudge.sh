#!/usr/bin/env bash
# learn-nudge.sh — SessionStart reminder that the self-improvement ledger has
# work waiting.
#
# Distillation is deliberately manual: /self-improve rewrites skill and agent
# files, and that should not happen while attention is elsewhere. The cost of
# manual is forgetting the ledger exists, which is what this closes.
#
# SessionStart rather than Stop, because Stop fires on every assistant turn —
# a nag per turn, needing its own dedup state to stay bearable. This fires once,
# when there is capacity to act on it.
#
# Its output enters context, so it stays silent below the threshold and costs
# nothing in the normal case of a recently-distilled ledger. One line when it
# does speak.
set -uo pipefail

exec 2>/dev/null

# OFF BY DEFAULT, like every opinionated hook this plugin ships. CREWFORGE_HOOKS=1.
[ "${CREWFORGE_HOOKS:-0}" = "1" ] || exit 0

THRESHOLD="${LEARN_NUDGE_THRESHOLD:-5}"
# Same resolution as ledger.sh — state dir, not config dir, when nothing is set.
ROOT="${CLAUDE_CONFIG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/crewforge}"
DIR="$ROOT/ledger"

[ -d "$DIR" ] || exit 0
shopt -s nullglob
files=("$DIR"/*.jsonl)
[ ${#files[@]} -gt 0 ] || exit 0

total=$(cat "${files[@]}" 2>/dev/null | wc -l | tr -d ' ')
[ "${total:-0}" -ge "$THRESHOLD" ] || exit 0

# Name the targets, not the entries: which skills are asking for attention is
# the actionable part, and the notes themselves are what /self-improve reads.
targets=""
for f in "${files[@]}"; do
  n="$(basename "$f" .jsonl)"
  c="$(wc -l < "$f" | tr -d ' ')"
  targets="${targets:+$targets, }$n($c)"
done

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"SessionStart",
  "additionalContext":
    f"Self-improvement ledger: {sys.argv[1]} entries — {sys.argv[2]}. "
    "Run /self-improve to distil them, or mention it if the user asks about "
    "skill or agent quality. Do not distil unprompted."}}))
' "$total" "$targets"
exit 0

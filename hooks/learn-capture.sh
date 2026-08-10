#!/usr/bin/env bash
# learn-capture.sh — PostToolUse(Bash) capture for the self-improvement ledger.
#
# Records one line when a script that BELONGS to a skill or hook reports a
# failure. That is the only signal here, and it is deliberately narrow: a hook
# cannot judge, so it must not try. It notices that a skill's own tooling broke
# and writes down where; /self-improve decides whether that means anything.
#
# Best-effort by design, like the rtk hook (see RTK.md). It never blocks, never
# writes to stdout, and swallows every error — a capture channel that can stall
# a session is worse than no capture channel.
#
# Judgement-grade lessons arrive through the other door: `/learn <target> <note>`.
set -uo pipefail

exec 2>/dev/null

# OFF BY DEFAULT, like every opinionated hook this plugin ships. CREWFORGE_HOOKS=1.
[ "${CREWFORGE_HOOKS:-0}" = "1" ] || exit 0

ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
LEDGER="$ROOT/skills/self-improve/scripts/ledger.sh"
[ -x "$LEDGER" ] || exit 0

payload="$(cat)" || exit 0
[ -n "$payload" ] || exit 0

# Python via heredoc with the payload in the environment, never `python3 -c
# '...'`: a single quote anywhere in the script silently breaks that form, and
# this hook needs quoted regexes.
parsed="$(CAPTURE_PAYLOAD="$payload" python3 - <<'PY'
import json, os, re, sys

try:
    d = json.loads(os.environ["CAPTURE_PAYLOAD"])
except Exception:
    sys.exit(0)

cmd = d.get("tool_input", {}).get("command", "") or ""

# Never capture the ledger tooling itself. Reading the ledger prints entries,
# entries contain the failure text that triggers a capture, and the ledger then
# grows every time anyone inspects it - a feedback loop, not a signal.
if "self-improve/scripts/ledger.sh" in cmd:
    sys.exit(0)

# Only script paths this config owns. Anything else belongs to the project
# being worked on and is none of the ledger business.
m = re.search(r"(?:^|[\s/])skills/([A-Za-z0-9_.-]+)/scripts/([A-Za-z0-9_.-]+)", cmd)
if m:
    target, script = m.group(1), m.group(2)
else:
    m = re.search(r"(?:^|[\s/])hooks/([A-Za-z0-9_.-]+\.sh)", cmd)
    if not m:
        sys.exit(0)
    target, script = "hooks", m.group(1)

resp = d.get("tool_response")
if isinstance(resp, dict):
    # Read the streams, not the envelope. Dumping the whole dict makes the match
    # land on one long JSON line and stores noise instead of evidence.
    resp = "\n".join(str(resp.get(k, "")) for k in ("stdout", "stderr"))
elif not isinstance(resp, str):
    resp = str(resp) if resp is not None else ""

# The response shape is not contractual across tool versions, so match on what
# the scripts themselves emit rather than on a field that may not be there.
hit = re.search(r"^.*\b(FAIL|ERROR|Traceback|command not found|No such file)\b.*$",
                resp, re.M)
if not hit:
    sys.exit(0)

# Belt and braces on the same loop: a line that is already a ledger record is an
# echo of a past capture, whatever command produced it.
if re.search(r'"(ts|source)":\s*"', hit.group(0)):
    sys.exit(0)

# One line, whitespace-collapsed, bounded - the ledger stores evidence, not logs.
line = re.sub(r"\s+", " ", hit.group(0)).strip()[:280]
print(target)
print(f"{script}: {line}")
PY
)" || exit 0

target="$(printf '%s\n' "$parsed" | sed -n '1p')"
note="$(printf '%s\n' "$parsed" | sed -n '2p')"

[ -n "$target" ] || exit 0
[ -n "$note" ] || exit 0

bash "$LEDGER" add "$target" hook "$note" >/dev/null || true
exit 0

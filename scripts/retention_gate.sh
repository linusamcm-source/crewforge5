#!/usr/bin/env bash
# retention_gate.sh — assert a proposed CLAUDE.md slim kept everything that matters.
#
#   retention_gate.sh <original> <proposed>
#
# THE PROBLEM. `claude doctor` proposes CLAUDE.md trims, and a trim is judged by
# how much shorter it got. But the lines worth the most tokens are usually the
# ones worth keeping: an absolute directive nobody re-derives, the one exact
# command that works, a version number someone bled for. Shortening is easy to
# measure and losing a `never` is not, so the cheap metric wins by default.
#
# This is the counterweight, and it is PROPOSE-ONLY BY CONSTRUCTION: it takes two
# files and returns a verdict. It cannot edit anything, so no amount of
# misapplication turns it into a thing that rewrites your instructions.
#
# WHAT MUST SURVIVE — each is something a reader cannot reconstruct:
#   absolute directives   a line carrying never / always / must / do not
#   exact commands        anything in `backticks` that looks executable
#   paths                 file and directory references
#   versions              >=1.10, v2.3.1, 0.9
#   error strings         quoted text that a tool actually emits
#
# "Survives" means the text is still present SOMEWHERE in the proposal, not on
# the same line — reorganising is fine, losing is not.
#
# Exits 0 when everything survived, 1 with one line per loss, 2 on usage error.
set -uo pipefail

ORIGINAL="${1:-}"
PROPOSED="${2:-}"

if [ -z "$ORIGINAL" ] || [ -z "$PROPOSED" ]; then
  echo "usage: retention_gate.sh <original> <proposed>" >&2
  exit 2
fi
[ -f "$ORIGINAL" ] || { echo "FAIL: no such file: $ORIGINAL" >&2; exit 2; }
[ -f "$PROPOSED" ] || { echo "FAIL: no such file: $PROPOSED" >&2; exit 2; }

python3 - "$ORIGINAL" "$PROPOSED" <<'PY'
import re, sys
from pathlib import Path

original = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
proposed = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")

def norm(s):
    return re.sub(r"\s+", " ", s).strip()

hay = norm(proposed)
hay_lower = hay.lower()

losses = []

# 1. Absolute directives. The whole line is the unit: "never run find from /" is
#    not preserved by the word "never" surviving somewhere else, so the line's
#    distinctive content has to be there. Compared case-insensitively because a
#    rewrite may legitimately change "Never" to "never".
for line in original.splitlines():
    n = norm(line)
    if not n:
        continue
    if re.search(r"\b(never|always|must not|must|do not|don't)\b", n, re.I):
        stripped = norm(re.sub(r"^[-*+>\s]*(\d+\.)?\s*", "", n))
        stripped = norm(re.sub(r"[*_`#]", "", stripped))
        if len(stripped) < 12:
            continue
        if stripped.lower() not in re.sub(r"[*_`#]", "", hay_lower):
            losses.append(f"directive lost: {stripped[:100]}")

# 2. Backticked spans that look executable, or are paths, versions or error text.
#    A prose word in backticks (`true`, `auto`) is not worth gating on, so the
#    filter is deliberately narrow: it wants a command shape, a separator, or a
#    version.
CMD = re.compile(r"`([^`\n]{2,200})`")
def is_load_bearing(s):
    if re.search(r"[/\\]", s):                       return True   # a path
    if re.search(r"\bv?\d+\.\d+(\.\d+)?\b", s):      return True   # a version
    if re.search(r"\s--?[A-Za-z]", s):               return True   # a flag
    if re.search(r"^\s*\w+\s+\S", s) and " " in s:   return True   # cmd + arg
    return False

seen = set()
for m in CMD.finditer(original):
    span = norm(m.group(1))
    if span in seen or not is_load_bearing(span):
        continue
    seen.add(span)
    if span not in hay:
        losses.append(f"exact text lost: `{span[:100]}`")

# 3. Double-quoted strings long enough to be an error message rather than prose
#    emphasis. These are what someone greps a log for.
for m in re.finditer(r'"([^"\n]{12,200})"', original):
    span = norm(m.group(1))
    if span in seen:
        continue
    seen.add(span)
    if span not in hay:
        losses.append(f"quoted string lost: \"{span[:100]}\"")

orig_bytes, prop_bytes = len(original.encode()), len(proposed.encode())
saved = orig_bytes - prop_bytes
pct = (saved / orig_bytes * 100) if orig_bytes else 0.0
# `{saved:+d}` would print "+97" for a 97-byte SAVING, which reads as growth.
# Say which direction it went in words instead.
direction = "smaller" if saved > 0 else ("larger" if saved < 0 else "unchanged")
print(f"{orig_bytes} -> {prop_bytes} bytes ({abs(saved)} {direction}, {abs(pct):.1f}%)")

if losses:
    for l in losses:
        print(f"FAIL: {l}")
    print(f"FAIL: {len(losses)} retention breach(es) — the proposal is not safe to apply")
    sys.exit(1)

print("PASS: every directive, command, path, version and error string survived")
PY

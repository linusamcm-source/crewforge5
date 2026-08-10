#!/usr/bin/env bash
# budget_check.sh — the release gate for what this plugin costs before it is used.
#
#   budget_check.sh [--budget N] [--verbose]
#
# Every skill and agent description loads into every session, whether or not the
# skill is ever invoked. That is the plugin's rent. A skill carrying
# `disable-model-invocation: true` is hidden from the always-loaded catalogue and
# pays no rent, which is why hiding one is how a new skill gets paid for.
#
# This is `ceiling.sh`'s measurement applied once to the whole bundle instead of
# per target: sum the description characters, divide by 4 for tokens, fail over
# budget. The number moves in a reviewed diff or not at all — a bundle that
# grows by relaxing its own gate has no gate.
#
# Exits 0 within budget, 1 over it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUDGET=1200
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --budget) BUDGET="${2:?--budget needs a number}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    *) echo "usage: budget_check.sh [--budget N] [--verbose]" >&2; exit 2 ;;
  esac
done

python3 - "$ROOT" "$BUDGET" "$VERBOSE" <<'PY'
import re, sys
from pathlib import Path

root, budget, verbose = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == "1"

def frontmatter(path):
    text = path.read_text(errors="replace")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""

def field(fm, key):
    # Descriptions are single-line in this tree; a folded block would need a
    # YAML parser, and pulling one in for a gate that must run anywhere is a
    # worse trade than failing loudly on a shape we do not use.
    m = re.search(rf"^{key}:\s*(.*)$", fm, re.M)
    return m.group(1).strip() if m else ""

rows, total = [], 0
for skill in sorted((root / "skills").iterdir()):
    f = skill / "SKILL.md"
    if not f.is_file():
        continue
    fm = frontmatter(f)
    if field(fm, "disable-model-invocation").lower() == "true":
        rows.append(("skill", skill.name, 0, "hidden"))
        continue
    n = len(field(fm, "description"))
    total += n
    rows.append(("skill", skill.name, n, ""))

for agent in sorted((root / "agents").glob("*.md")):
    n = len(field(frontmatter(agent), "description"))
    total += n
    rows.append(("agent", agent.stem, n, ""))

tokens = round(total / 4)
if verbose:
    for kind, name, n, note in sorted(rows, key=lambda r: -r[2]):
        print(f"{n:5d}  {kind:5s}  {name}{'  (' + note + ')' if note else ''}")
    print()

hidden = sum(1 for r in rows if r[3] == "hidden")
print(f"always-loaded: {total} chars (~{tokens} tok) across "
      f"{sum(1 for r in rows if r[3] != 'hidden')} descriptions; {hidden} skills hidden")
print(f"budget: {budget} tok")

if tokens > budget:
    print(f"FAIL: over budget by {tokens - budget} tok. Hide a skill behind "
          f"`disable-model-invocation: true`, or trim a description. Do not move the number.")
    sys.exit(1)
print(f"PASS: {budget - tokens} tok of headroom")
PY

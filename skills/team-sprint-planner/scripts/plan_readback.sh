#!/usr/bin/env bash
# plan_readback.sh — mechanical final read-back for the planner's stage 8.
#
# Usage:
#   plan_readback.sh <plan_path>   # emit dot-point read-back (markdown) on stdout
#
# Read-back contract (deterministic, byte-identical across reruns):
#   - Line 1: provenance stamp verbatim, or "STAMP: MISSING (plan is not deployable)".
#   - One bullet per story: "- <id> — <title> (depends on: <ids|none>)".
#   - Single-story plans (no "## Story" headings) emit one bullet keyed by filename stem.
#   - Trailing line points at <plan-dir>/<plan-stem>-review/ if it exists.
#
# The Phase 8 system-context diagram is authored via the drawio skill (it needs
# recon judgment: touched components, inputs, outputs) — not generated here.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"

require_python3 || exit 1

usage() {
  cat <<'USAGE' >&2
usage: plan_readback.sh <plan_path>
USAGE
  exit 2
}

[[ $# -eq 1 ]] || usage
PLAN="$1"

[[ -f "$PLAN" ]] || fail "plan_readback.sh: plan not found: $PLAN"

python3 - "$PLAN" <<'PY'
import re, sys
from pathlib import Path

plan = Path(sys.argv[1])
text = plan.read_text(encoding="utf-8")
lines = text.splitlines()

stamp = next((l for l in lines if l.startswith("<!-- adversarial-review: ")), None)

story_re = re.compile(r"^## Story\s+(?P<id>\S+):\s*(?P<title>.+?)\s*$")
dep_re = re.compile(r"^### Depends On:\s*(?P<deps>.*?)\s*$")

stories = []  # [{id, title, deps}]
cur = None
for line in lines:
    m = story_re.match(line)
    if m:
        cur = {"id": m.group("id"), "title": m.group("title"), "deps": []}
        stories.append(cur)
        continue
    m = dep_re.match(line)
    if m and cur is not None:
        deps = m.group("deps")
        if deps.lower() != "none":
            cur["deps"] = [d for d in re.split(r"[,\s]+", deps) if d]

if not stories:
    # Single-story plan: whole file is one implicit story keyed by filename stem.
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), plan.stem)
    stories = [{"id": plan.stem, "title": title, "deps": []}]

out = []
out.append(stamp if stamp else "STAMP: MISSING (plan is not deployable)")
for s in stories:
    deps = ", ".join(s["deps"]) if s["deps"] else "none"
    out.append(f"- {s['id']} — {s['title']} (depends on: {deps})")
review_dir = plan.parent / f"{plan.stem}-review"
if review_dir.is_dir():
    out.append(f"Review artifacts: {review_dir}")
print("\n".join(out))
PY

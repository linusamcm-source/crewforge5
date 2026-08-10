#!/usr/bin/env bash
# ceiling.sh — the anti-verbosity gate for a self-improvement pass.
#
#   ceiling.sh check [target…]   assert every target is within budget (default: all)
#   ceiling.sh record [target…]  set the current sizes as the budget
#   ceiling.sh report            print budget vs actual, widest overrun first
#
# A target is a skill slug (skills/<slug>/SKILL.md) or an agent name
# (agents/<name>.md, or agents-parked/*/<name>.md). Budgets live beside the
# ledger, in the state directory resolved below — never inside the tree being
# measured, which an update replaces.
#
# Why a ceiling at all: a learning loop that may only ever append converges on
# a rulebook nobody reads and every session pays for. Holding the budget flat
# forces each new lesson to be paid for by tightening something else, so the
# file gets sharper rather than longer. `record` is how a budget legitimately
# moves — deliberately, in a reviewable diff, not as a side effect of a rewrite.
#
# Description bytes get the tighter budget of the two because they load in every
# session; body bytes load only on use.
#
# Exits 0 when every target passes, 1 with one FAIL line per breach.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Targets are resolved under ROOT. Default to the tree this script ships in —
# the plugin root — so the gate measures the bundle it belongs to and needs no
# user config directory to exist. CLAUDE_CONFIG_DIR still wins when set, which is how
# the tests point it at a fixture and how a config repo keeps using it in place.
ROOT="${CLAUDE_CONFIG_DIR:-$(cd "$HERE/../../.." && pwd)}"
# Recorded budgets are runtime state, not shipped content: they are one tree's
# byte sizes, and a plugin update replaces the install directory. They live with
# the ledger, beside it, wherever that is.
CEILINGS="${CLAUDE_CONFIG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/crewforge}/ceilings.json"
MODE="${1:-report}"
shift || true

[ -f "$CEILINGS" ] || { mkdir -p "$(dirname "$CEILINGS")"; echo '{}' > "$CEILINGS"; }

python3 - "$MODE" "$ROOT" "$CEILINGS" "$@" <<'PY'
import json, re, sys
from pathlib import Path

mode, root, ceilings_path, *targets = sys.argv[1:]
root = Path(root)
ceilings = json.loads(Path(ceilings_path).read_text())

# Descriptions load every session, so they get no slack at all: a reworded
# description must pay for itself, and `record` is the reviewable escape hatch.
# Bodies load only on use, so one lesson may land without a same-breath rewrite
# — but 5% of a small body is nothing, hence the absolute floor alongside it.
DESC_SLACK = 1.00
BODY_SLACK, BODY_FLOOR = 1.05, 400


def locate(name):
    p = root / "skills" / name / "SKILL.md"
    if p.is_file():
        return p
    p = root / "agents" / f"{name}.md"
    if p.is_file():
        return p
    hits = sorted((root / "agents-parked").glob(f"*/{name}.md"))
    return hits[0] if hits else None


def discover():
    out = [p.parent.name for p in sorted((root / "skills").glob("*/SKILL.md"))]
    out += [p.stem for p in sorted((root / "agents").glob("*.md"))]
    out += [p.stem for p in sorted((root / "agents-parked").glob("*/*.md"))
            if p.stem != "README"]
    return out


def measure(path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"\A---\n(.*?\n)---\n(.*)\Z", text, re.DOTALL)
    if not m:
        return None
    frontmatter, body = m.group(1), m.group(2)
    dm = re.search(r"^description:[ \t]*(.*(?:\n[ \t]+\S.*)*)", frontmatter, re.M)
    desc = re.sub(r"\s+", " ", dm.group(1) if dm else "").strip()
    if len(desc) >= 2 and desc[0] == desc[-1] and desc[0] in "\"'":
        desc = desc[1:-1].strip()
    return {
        "desc_chars": len(desc),
        "body_chars": len(body),
        # Quoted spans in a description are trigger phrases; losing one silently
        # breaks discovery, which no size check would ever catch.
        "trigger_phrases": re.findall(r'"([^"]+)"', desc),
        "_desc": desc,
        "_body": body,
    }


names = targets or discover()
failures, rows = [], []

for name in names:
    path = locate(name)
    if path is None:
        failures.append(f"FAIL [{name}]: no skill or agent by that name")
        continue
    cur = measure(path)
    if cur is None:
        failures.append(f"FAIL [{name}]: no valid frontmatter in {path}")
        continue

    if mode == "record":
        ceilings[name] = {k: cur[k] for k in ("desc_chars", "body_chars", "trigger_phrases")}
        continue

    budget = ceilings.get(name)
    if budget is None:
        if mode == "check":
            failures.append(f"FAIL [{name}]: no recorded budget — run `ceiling.sh record {name}`")
        continue

    desc_cap = int(budget["desc_chars"] * DESC_SLACK)
    body_cap = max(int(budget["body_chars"] * BODY_SLACK), budget["body_chars"] + BODY_FLOOR)
    rows.append((cur["desc_chars"] - desc_cap, name, cur, desc_cap, body_cap))

    if mode == "check":
        if cur["desc_chars"] > desc_cap:
            failures.append(
                f"FAIL [{name}]: description {cur['desc_chars']} > {desc_cap} chars. "
                f"Pay for the addition by cutting elsewhere in the description, or "
                f"`ceiling.sh record {name}` if the budget genuinely must move.")
        if cur["body_chars"] > body_cap:
            failures.append(
                f"FAIL [{name}]: body {cur['body_chars']} > {body_cap} chars. "
                f"Move detail into references/ and cite it, or tighten prose.")
        corpus = re.sub(r"\s+", " ", cur["_desc"] + " " + cur["_body"])
        for phrase in budget.get("trigger_phrases", []):
            if re.sub(r"\s+", " ", phrase) not in corpus:
                failures.append(f'FAIL [{name}]: trigger phrase lost: "{phrase}"')

if mode == "record":
    Path(ceilings_path).write_text(json.dumps(ceilings, indent=2, sort_keys=True) + "\n")
    print(f"recorded {len(names)} target(s) -> {ceilings_path}")
    sys.exit(0)

if mode == "report":
    print(f"{'target':32} {'desc':>12} {'body':>14}")
    for _, name, cur, dcap, bcap in sorted(rows, key=lambda r: -r[0]):
        print(f"{name:32} {cur['desc_chars']:>5}/{dcap:<6} {cur['body_chars']:>6}/{bcap:<7}")
    sys.exit(0)

for f in failures:
    print(f)
print(f"{'FAIL' if failures else 'PASS'}: {len(failures)} breach(es) across {len(names)} target(s)")
sys.exit(1 if failures else 0)
PY

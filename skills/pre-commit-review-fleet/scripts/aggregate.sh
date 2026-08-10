#!/usr/bin/env bash
# aggregate.sh <artifact-dir> [--out report.md] — Step 3 merge, mechanised.
# Reads every reviewer *.json in <artifact-dir>, merges findings, ranks by
# severity (CRITICAL > HIGH > MEDIUM > LOW > NIT), dedupes same-file:line
# findings across reviewers (contributing reviewers listed, first fix kept),
# and renders the ranked table plus a deterministic commit verdict:
#   verdict=block   CRITICAL present
#   verdict=waive   HIGH present (block unless explicitly waived)
#   verdict=pass    nothing above MEDIUM
# The verdict is computed here, never by the model. Always exits 0.
set -euo pipefail

DIR="${1:?usage: aggregate.sh <artifact-dir> [--out report.md]}"
OUT=""
[ "${2:-}" = "--out" ] && OUT="${3:?--out needs a path}"

exec python3 - "$DIR" "$OUT" <<'PY'
import json, pathlib, re, sys

d = pathlib.Path(sys.argv[1])
out_path = sys.argv[2]
RANK = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "NIT": 4}

merged = {}
reviewers_seen = []
for f in sorted(d.glob("*.json")):
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except ValueError:
        print(f"WARN: {f.name} is not valid JSON — skipped")
        continue
    reviewer = data.get("reviewer", f.stem)
    reviewers_seen.append(reviewer)
    for fd in data.get("findings", []):
        sev = str(fd.get("severity", "LOW")).upper()
        if sev not in RANK:
            sev = "LOW"
        loc = ""
        m = re.search(r"[\w./-]+\.[A-Za-z]{1,6}:\d+", str(fd.get("evidence", "")) + " " + str(fd.get("title", "")))
        if m:
            loc = m.group(0)
        key = loc or f"{reviewer}:{fd.get('title','')}"
        if key in merged:
            e = merged[key]
            e["reviewers"].append(reviewer)
            if RANK[sev] < RANK[e["severity"]]:
                e["severity"] = sev
        else:
            merged[key] = {**fd, "severity": sev, "reviewers": [reviewer], "loc": loc}

rows = sorted(merged.values(), key=lambda r: (RANK[r["severity"]], r.get("loc", "")))
counts = {s: 0 for s in RANK}
for r in rows:
    counts[r["severity"]] += 1

lines = []
lines.append(f"reviewers={','.join(reviewers_seen)}")
for s in RANK:
    lines.append(f"{s.lower()}={counts[s]}")
if counts["CRITICAL"]:
    lines.append("verdict=block")
elif counts["HIGH"]:
    lines.append("verdict=waive")
else:
    lines.append("verdict=pass")
lines.append("")
lines.append("| Sev | Finding | Where | Reviewers | Fix |")
lines.append("|---|---|---|---|---|")
for r in rows:
    fix = str(r.get("fix", "")).replace("|", "\\|").replace("\n", " ")[:120]
    title = str(r.get("title", "")).replace("|", "\\|")[:100]
    lines.append(f"| {r['severity']} | {title} | {r.get('loc','—')} | {'+'.join(dict.fromkeys(r['reviewers']))} | {fix} |")

report = "\n".join(lines)
print(report)
if out_path:
    pathlib.Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(out_path).write_text(report + "\n", encoding="utf-8")
    print(f"\nwritten={out_path}")
PY

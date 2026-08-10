#!/usr/bin/env bash
# efficiency.sh <skill-path> — mechanical Step 3 (efficiency) checks.
# Emits key=value metrics, then FAIL/WARN findings lines in the ledger format
# (`FAIL [efficiency]: ...`). Always exits 0 — grade.sh does the judging.
set -euo pipefail

DIR="${1:?usage: efficiency.sh <skill-path>}"
MD="$DIR/SKILL.md"
[ -f "$MD" ] || { echo "FAIL [efficiency]: no SKILL.md at $DIR"; exit 0; }

exec python3 - "$MD" "$DIR" <<'PY'
import pathlib, re, sys

md_path, dirpath = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
md = md_path.read_text(encoding="utf-8")

lines = md.count("\n") + 1
words = len(md.split())
est_tokens = round(words / 0.75)  # 1 token ~ 0.75 words
total_bytes = sum(f.stat().st_size for f in dirpath.rglob("*") if f.is_file())
directives = len(re.findall(r"\b(MUST|ALWAYS|NEVER|IMPORTANT)\b", md))
rationale = len(re.findall(r"\b[Bb]ecause\b|this matters|the reason is", md))

print(f"lines={lines}")
print(f"words={words}")
print(f"est_tokens={est_tokens}")
print(f"dir_bytes={total_bytes}")
print(f"caps_directives={directives}")
print(f"rationale_markers={rationale}")

findings = []
if lines > 1000:
    findings.append(f"FAIL [efficiency]: SKILL.md {lines} lines > 1000")
elif lines > 500:
    findings.append(f"WARN [efficiency]: SKILL.md {lines} lines > 500")
if directives > 10:
    findings.append(f"WARN [efficiency]: {directives} all-caps directives > 10 — explaining why beats shouting")

# progressive disclosure: big inline fenced blocks / tables belong in references/
fence = None
fence_start = 0
table_run = 0
for i, line in enumerate(md.split("\n"), 1):
    if line.lstrip().startswith("```"):
        if fence is None:
            fence, fence_start = i, i
        else:
            if i - fence_start - 1 > 50:
                findings.append(f"WARN [efficiency]: inline code block of {i - fence_start - 1} lines at line {fence_start} — move to references/")
            fence = None
        continue
    if fence is None and line.lstrip().startswith("|"):
        table_run += 1
        if table_run == 51:
            findings.append(f"WARN [efficiency]: inline table > 50 rows ending near line {i} — move to references/")
    else:
        table_run = 0

for f in findings:
    print(f)
if not findings:
    print("OK [efficiency]: all mechanical efficiency checks clean")
PY

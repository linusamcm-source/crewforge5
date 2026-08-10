#!/usr/bin/env bash
# check.sh <skill-name> <skills-dir> <baseline.json> [desc-cap]
# Asserts, for one skill, against the recorded baseline:
#   1. description ≤desc-cap (default 300) whitespace-normalized chars
#   2. every baseline quoted trigger phrase still present somewhere in the
#      skill's directory (SKILL.md or any other *.md, e.g. references/)
#   3. every baseline heading text present in SKILL.md or another *.md file
#   4. every references/*.md link in SKILL.md resolves to an existing file
# Exits 0 if all pass; non-zero with one line per failure otherwise.
set -u

SKILL="${1:?usage: check.sh <skill-name> <skills-dir> <baseline.json> [desc-cap]}"
SKILLS_DIR="${2:?usage: check.sh <skill-name> <skills-dir> <baseline.json> [desc-cap]}"
BASELINE="${3:?usage: check.sh <skill-name> <skills-dir> <baseline.json> [desc-cap]}"
DESC_CAP="${4:-300}"

DIR="$SKILLS_DIR/$SKILL"
MD="$DIR/SKILL.md"
[ -f "$MD" ] || { echo "FAIL: $MD not found"; exit 1; }
[ -f "$BASELINE" ] || { echo "FAIL: baseline $BASELINE not found"; exit 1; }

python3 - "$SKILL" "$DIR" "$BASELINE" "$DESC_CAP" <<'PY'
import json, re, sys
from pathlib import Path

skill, dirpath, baseline_path = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
desc_cap = int(sys.argv[4])
baseline = json.load(open(baseline_path))
entry = baseline.get(skill)

md = (dirpath / "SKILL.md").read_text(encoding="utf-8")
m = re.match(r"\A---\n(.*?\n)---\n(.*)\Z", md, re.DOTALL)
if not m:
    print(f"FAIL: {skill}/SKILL.md has no valid frontmatter"); sys.exit(1)
frontmatter, body = m.group(1), m.group(2)

dm = re.search(r"^description:[ \t]*(.*(?:\n[ \t]+\S.*)*)", frontmatter, re.MULTILINE)
desc = re.sub(r"\s+", " ", dm.group(1) if dm else "").strip()
if len(desc) >= 2 and desc[0] == desc[-1] and desc[0] in "\"'":
    desc = desc[1:-1]
desc = re.sub(r"\s+", " ", desc).strip()

failures = []

# 1. desc cap
if len(desc) > desc_cap:
    failures.append(f"desc {len(desc)} chars > {desc_cap}")

# corpus: SKILL.md + every other *.md in the skill dir (references/ etc.)
corpus = md
for f in sorted(dirpath.rglob("*.md")):
    if f.name != "SKILL.md":
        try:
            corpus += "\n" + f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            pass
norm_corpus = re.sub(r"\s+", " ", corpus)

if entry is None:
    print(f"FAIL: no baseline entry for {skill}"); sys.exit(1)

# 2. trigger-phrase retention (whitespace-insensitive)
for phrase in entry.get("trigger_phrases", []):
    if re.sub(r"\s+", " ", phrase) not in norm_corpus:
        failures.append(f"trigger phrase lost: \"{phrase}\"")

# 3. heading retention
for heading in entry.get("headings", []):
    if re.sub(r"\s+", " ", heading) not in norm_corpus:
        failures.append(f"heading lost: {heading}")

# 4. references/*.md links resolve
for link in re.findall(r"\(((?:\./)?references/[^)#\s]+\.md)\)", md):
    if not (dirpath / link.replace("./", "", 1)).is_file():
        failures.append(f"broken link: {link}")

for f in failures:
    print(f"FAIL [{skill}]: {f}")
sys.exit(1 if failures else 0)
PY

#!/usr/bin/env bash
# au-check.sh <file> — flag US spellings outside code fences and inline code.
# Wordlist: assets/au-words.tsv (us-regex<TAB>au-form). Prints line: word -> au form.
# Exit 1 if any finding (verification gate), 0 when clean. Flags are advisory —
# the model judges proper nouns and API names it deliberately left US-spelled.
set -euo pipefail

FILE="${1:?usage: au-check.sh <file>}"

exec python3 - "$FILE" "$(dirname "$0")/../assets/au-words.tsv" <<'PY'
import re, sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
pairs = []
for row in open(sys.argv[2], encoding="utf-8"):
    row = row.rstrip("\n")
    if not row or row.startswith("#"):
        continue
    us, au = row.split("\t")
    pairs.append((au, re.compile(rf"\b{us}\b", re.IGNORECASE)))

findings = 0
fence = False
for i, line in enumerate(lines, 1):
    if line.lstrip().startswith("```"):
        fence = not fence
        continue
    if fence:
        continue
    scrub = re.sub(r"`[^`]*`", "", line)
    for au, rx in pairs:
        for m in rx.finditer(scrub):
            print(f"{i}: {m.group(0)} -> {au}")
            findings += 1

print(f"findings={findings}")
sys.exit(1 if findings else 0)
PY

#!/usr/bin/env bash
# tells.sh [--max N] <file> — LLM-tell density score for a prose file.
# Patterns in assets/tell-patterns.tsv (category<TAB>regex). Code fences and inline
# code are stripped before scoring. Output: word count, per-category hits,
# density (tells per 100 words), em-dash rate, sentence-rhythm flags.
# --max N: exit 1 if density > N (used to vet sibling exemplars for contamination).
set -euo pipefail

MAX="-1"
if [ "${1:-}" = "--max" ]; then MAX="$2"; shift 2; fi
FILE="${1:?usage: tells.sh [--max N] <file>}"

exec python3 - "$FILE" "$(dirname "$0")/../assets/tell-patterns.tsv" "$MAX" <<'PY'
import re, statistics, sys

text = open(sys.argv[1], encoding="utf-8").read()
prose = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
prose = re.sub(r"`[^`\n]+`", " ", prose)

words = re.findall(r"[A-Za-z'’-]+", prose)
n = max(len(words), 1)

total = 0
by_cat = {}
hits = []
for line in open(sys.argv[2], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    cat, pat = line.split("\t", 1)
    found = re.findall(pat, prose, flags=re.IGNORECASE)
    if found:
        c = len(found)
        by_cat[cat] = by_cat.get(cat, 0) + c
        total += c
        sample = found[0] if isinstance(found[0], str) else found[0][0]
        hits.append(f"hit={cat}: {pat}  (x{c})")

density = round(total * 100 / n, 2)
print(f"words={n}")
print(f"tells={total}")
print(f"density={density}")
for cat in sorted(by_cat):
    print(f"{cat}={by_cat[cat]}")
for h in hits:
    print(h)

# rhythm stats are noise on short drafts (cross-dock territory) — need >=80 words
emdash = prose.count("—")
emdash_rate = round(emdash * 100 / n, 2)
print(f"emdash_per_100={emdash_rate}")
if emdash_rate > 1.0 and n >= 80:
    print("rhythm_flag=em-dash overuse")

sentences = [len(re.findall(r"[A-Za-z'’-]+", s)) for s in re.split(r"[.!?\n]+", prose)]
sentences = [s for s in sentences if s >= 3]
if len(sentences) >= 5 and n >= 80:
    cv = round(statistics.stdev(sentences) / statistics.mean(sentences), 2)
    print(f"sentence_cv={cv}")
    if cv < 0.35:
        print("rhythm_flag=uniform sentence length (natural writing varies more)")

maxd = float(sys.argv[3])
if maxd >= 0 and density > maxd:
    print(f"FAIL: density {density} > max {maxd}")
    sys.exit(1)
PY

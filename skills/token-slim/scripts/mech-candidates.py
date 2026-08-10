#!/usr/bin/env python3
"""mech-candidates.py — detect skills whose SKILL.md prose asks the model to do
mechanical work (count, verify, compare, threshold-check) that a script would do
deterministically. Detection only — the script-sandwich conversion itself is
per-skill judgment work; see ../references/script-sandwich.md.

Fenced code blocks are stripped before matching: instructions already inside a
```bash block are already mechanised.

Usage:
  mech-candidates.py --skills-dir DIR [--min-hits N]   (default N=3)
"""
import argparse
import re
from pathlib import Path

SMELLS = {
    "counting":   r"\b(count|tally|estimate|measure|sum up)\b",
    "check-each": r"\b(verify|check|confirm|ensure) (that|each|every|all)\b",
    "threshold":  r"(?:(?:>=?|<=?|more than|less than|fewer than|exceeds?|at least|at most|under|over) ?\d+|\b\d+ ?(?:lines|chars|characters|words|files|items|rows|warnings|failures|seconds)\b)",
    "searching":  r"\b(search for|grep|scan for|look for every)\b",
    "comparing":  r"\b(compare|diff) (the|each|against|with)\b",
    "invariant":  r"\b(must match|byte-identical|must exist|must resolve|must survive)\b",
}


def body_of(md: str) -> str:
    m = re.match(r"\A---\n.*?\n---\n(.*)\Z", md, re.DOTALL)
    return m.group(1) if m else md


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", required=True, type=Path)
    ap.add_argument("--min-hits", type=int, default=3)
    args = ap.parse_args()

    rows = []
    for skill_md in sorted(args.skills_dir.glob("*/SKILL.md")):
        body = body_of(skill_md.read_text(encoding="utf-8"))
        prose = re.sub(r"```.*?```", " ", body, flags=re.DOTALL)
        lines = prose.split("\n")
        hits, samples = {}, []
        for cat, pat in SMELLS.items():
            rx = re.compile(pat, re.IGNORECASE)
            for i, line in enumerate(lines, 1):
                for _ in rx.finditer(line):
                    hits[cat] = hits.get(cat, 0) + 1
                    if len(samples) < 3:
                        samples.append((i, cat, line.strip()[:90]))
        total = sum(hits.values())
        if total >= args.min_hits:
            has_scripts = (skill_md.parent / "scripts").is_dir()
            rows.append((total, skill_md.parent.name, hits, samples, has_scripts))

    rows.sort(reverse=True)
    if not rows:
        print("no candidates at this threshold")
        return
    for total, name, hits, samples, has_scripts in rows:
        cats = " ".join(f"{k}={v}" for k, v in sorted(hits.items()))
        flag = "scripts/ exists" if has_scripts else "no scripts/"
        print(f"{name}: hits={total} ({cats}) [{flag}]")
        for lineno, cat, text in samples:
            print(f"    L{lineno} [{cat}] {text}")


if __name__ == "__main__":
    main()

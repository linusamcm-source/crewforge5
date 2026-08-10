#!/usr/bin/env python3
"""baseline.py — record per-skill token-slim metrics for any skills directory.

For every <skills-dir>/*/SKILL.md:
  desc_chars      whitespace-normalized description char count
  body_chars      char count of everything after the closing frontmatter ---
  trigger_phrases every double-quoted phrase in the description
  headings        every ##/### heading text in the body

Usage:
  baseline.py --skills-dir DIR --out FILE   write the immutable baseline snapshot
  baseline.py --skills-dir DIR --report     print current measurements to stdout
"""
import argparse
import json
import re
import sys
from pathlib import Path


def parse_skill(path: Path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"\A---\n(.*?\n)---\n(.*)\Z", text, re.DOTALL)
    if not m:
        return None
    frontmatter, body = m.group(1), m.group(2)
    dm = re.search(
        r"^description:[ \t]*(.*(?:\n[ \t]+\S.*)*)", frontmatter, re.MULTILINE
    )
    desc = dm.group(1) if dm else ""
    desc = re.sub(r"\s+", " ", desc).strip()
    if len(desc) >= 2 and desc[0] == desc[-1] and desc[0] in "\"'":
        desc = desc[1:-1]
    normalized = re.sub(r"\s+", " ", desc).strip()
    return {
        "desc_chars": len(normalized),
        "body_chars": len(body),
        "trigger_phrases": re.findall(r'"([^"]+)"', desc),
        "headings": [
            h.strip()
            for h in re.findall(r"^#{2,3}\s+(.+)$", body, re.MULTILINE)
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", required=True, type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if not args.report and not args.out:
        ap.error("one of --out or --report is required")

    data = {}
    for skill_md in sorted(args.skills_dir.glob("*/SKILL.md")):
        entry = parse_skill(skill_md)
        if entry is not None:
            data[skill_md.parent.name] = entry

    if args.report:
        json.dump(data, sys.stdout, indent=2)
        print()
        return
    args.out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"{args.out} written: {len(data)} skills")


if __name__ == "__main__":
    main()

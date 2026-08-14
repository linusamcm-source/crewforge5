#!/usr/bin/env bash
# corpus-summary.sh [detect-json] — Step 2 post-detect logic, mechanised.
# Reads the detect JSON (default graphify-out/.graphify_detect.json), prints the
# clean corpus summary, and computes the size verdict the model must act on:
#   verdict=stop        no supported files (exit 1)
#   verdict=narrow      over threshold with subdirs — top-5 printed, ask the user
#   verdict=no-cluster  over threshold but flat root — suggest --no-cluster
#   verdict=proceed     under thresholds
set -euo pipefail

DETECT="${1:-graphify-out/.graphify_detect.json}"
[ -f "$DETECT" ] || { echo "error=no detect json at $DETECT — run Step 2's detect first" >&2; exit 1; }

exec python3 - "$DETECT" <<'PY'
import collections, json, sys
from pathlib import Path

d = json.load(open(sys.argv[1], encoding="utf-8"))
total_files = d.get("total_files", 0)
total_words = d.get("total_words", 0)
files = d.get("files", {})

print(f"Corpus: {total_files} files · ~{total_words:,} words")
for cat in ("code", "document", "paper", "image", "video"):
    fl = files.get(cat, [])
    if fl:
        exts = sorted({Path(f).suffix for f in fl if Path(f).suffix})[:6]
        print(f"  {cat}: {len(fl)} files ({' '.join(exts)})")

skipped = d.get("skipped_sensitive", []) or []
if skipped:
    print(f"skipped_sensitive={len(skipped)}")
    for s in skipped:
        print(f"  skipped: {s}")

if total_files == 0:
    print("verdict=stop")
    print("reason=No supported files found.")
    sys.exit(1)

if total_words > 2_000_000 or total_files > 500:
    root = d.get("scan_root", "")
    all_files = [f for fl in files.values() for f in fl
                 if not f.startswith(root.rstrip("/") + "/graphify-out/")]
    tops = collections.Counter()
    for f in all_files:
        rel = f[len(root):].lstrip("/") if root and f.startswith(root) else f
        tops["(root)" if "/" not in rel else rel.split("/", 1)[0]] += 1
    if set(tops) == {"(root)"}:
        print("verdict=no-cluster")
        print("reason=corpus over threshold but flat — no subfolders to narrow to; suggest --no-cluster")
    else:
        print("verdict=narrow")
        print(f"reason=corpus over threshold ({total_words:,} words / {total_files} files) — ask which subfolder")
        for name, n in tops.most_common(5):
            print(f"  subdir: {name} ({n} files)")
    sys.exit(0)

print("verdict=proceed")
PY

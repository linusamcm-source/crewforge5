#!/usr/bin/env bash
# verify-citations.sh <audit-file> — pre-delivery gate: every file:line citation
# in the audit must point at an existing live file with at least that many lines
# (pack/graph line numbers drift; the live tree is the evidence). Prints each
# failure, then verified=X/Y. Exit 1 if any citation fails.
set -euo pipefail

F="${1:?usage: verify-citations.sh <audit-file>}"
[ -f "$F" ] || { echo "error=no such file: $F" >&2; exit 1; }

exec python3 - "$F" <<'PY'
import pathlib, re, sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
# path.ext:123 — skip URLs and lone drive/port-like tokens
cites = set()
for m in re.finditer(r"(?<![\w:/])([\w][\w./-]*\.[A-Za-z]{1,6}):(\d{1,6})\b", text):
    start = m.start()
    # skip URL fragments: if the whitespace-delimited token containing this
    # match has a scheme, it's a URL, not a file citation
    preceding = re.search(r"\S*\Z", text[:start]).group(0)
    if "://" in preceding:
        continue
    cites.add((m.group(1), int(m.group(2))))

failed = 0
for path, line in sorted(cites):
    p = pathlib.Path(path)
    if not p.is_file():
        print(f"FAIL: {path}:{line} — file does not exist in live tree")
        failed += 1
        continue
    n = p.read_text(encoding="utf-8", errors="replace").count("\n") + 1
    if line > n:
        print(f"FAIL: {path}:{line} — file has only {n} lines")
        failed += 1

print(f"verified={len(cites) - failed}/{len(cites)}")
sys.exit(1 if failed else 0)
PY

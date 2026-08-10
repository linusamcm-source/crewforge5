#!/usr/bin/env bash
# prior-findings.sh [audit-file] — Phase 0 repeat-run check, mechanised.
# Extracts finding rows (ID | Category | File:Line | Severity) from an existing
# TECH_DEBT_AUDIT.md findings table so the new audit can tag RESOLVED / NEW.
# Prints prior_findings=N then one ID<TAB>severity<TAB>file:line row per finding.
set -euo pipefail

F="${1:-TECH_DEBT_AUDIT.md}"
if [ ! -f "$F" ]; then
  echo "prior_findings=0"
  echo "note=no prior audit at $F — first run, no RESOLVED/NEW tagging needed"
  exit 0
fi

exec python3 - "$F" <<'PY'
import re, sys

rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4:
        continue
    # a findings row starts with an ID like TD-12, A3, SEC-04 — not a header/divider
    if re.fullmatch(r"[A-Z]{1,6}-?\d{1,4}", cells[0]):
        sev = next((c for c in cells if c.lower() in
                    ("critical", "high", "medium", "low")), "?")
        loc = next((c for c in cells if re.search(r"[\w/.-]+:\d+", c)), "?")
        rows.append((cells[0], sev, loc))

print(f"prior_findings={len(rows)}")
for rid, sev, loc in rows:
    print(f"{rid}\t{sev}\t{loc}")
PY

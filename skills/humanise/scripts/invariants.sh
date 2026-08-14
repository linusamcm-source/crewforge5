#!/usr/bin/env bash
# invariants.sh — protected-token lockfile for rewrites that must not alter technical facts.
#   invariants.sh extract <draft>            print protected tokens, one per line
#   invariants.sh verify <lockfile> <output> exit 1 listing any token missing from output
# Protected classes: inline `code` spans, semver, --flags, UPPER_SNAKE names, URLs, file paths.
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  extract)
    FILE="${2:?usage: invariants.sh extract <draft>}"
    exec python3 - "$FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
tokens = set()
tokens |= set(re.findall(r"`[^`\n]+`", text))
tokens |= set(re.findall(r"\bv?\d+\.\d+\.\d+[\w.-]*", text))
tokens |= set(re.findall(r"(?<![\w-])--[A-Za-z][\w-]+", text))
tokens |= set(re.findall(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b", text))
tokens |= {t.rstrip(".,;)") for t in re.findall(r"https?://\S+", text)}
tokens |= set(re.findall(r"(?<![\w`])[\w.~-]*/[\w.-]+\.[a-z]{1,5}\b", text))
for t in sorted(tokens):
    print(t)
PY
    ;;
  verify)
    LOCK="${2:?usage: invariants.sh verify <lockfile> <output>}"
    OUT="${3:?usage: invariants.sh verify <lockfile> <output>}"
    exec python3 - "$LOCK" "$OUT" <<'PY'
import sys
lock = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
out = open(sys.argv[2], encoding="utf-8").read()
missing = [t for t in lock if t not in out]
for t in missing:
    print(f"MISSING: {t}")
print(f"{len(lock) - len(missing)}/{len(lock)} invariants intact")
sys.exit(1 if missing else 0)
PY
    ;;
  *)
    echo "usage: invariants.sh extract <draft> | verify <lockfile> <output>" >&2
    exit 2
    ;;
esac

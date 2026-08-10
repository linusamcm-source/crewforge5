#!/usr/bin/env bash
# exists.sh <kind> <name> — the Step 3 pre-implementation safety check, mechanised.
# Answers "does this already exist in the pack?" before any code is written.
#   kind: file    — a file whose path contains <name>
#         symbol  — a function/class/type/const definition named <name>
#         test    — a test covering <name>
#         import  — an import of the exact string <name>
# Prints found=yes|no hits=N and sample matches. Always exits 0 — the caller
# reads the answer (found=yes on a planned CREATE means extend, never overwrite).
set -euo pipefail

KIND="${1:?usage: exists.sh file|symbol|test|import <name>}"
NAME="${2:?usage: exists.sh file|symbol|test|import <name>}"
PACK="${REPOMIX_PACK:-.repomix-output.xml}"
[ -f "$PACK" ] || { echo "error=no pack at $PACK — run pack.sh first" >&2; exit 1; }

# grep is line-based, so plain . never crosses a line — [^\n] in ERE would
# wrongly exclude the literal character n.
case "$KIND" in
  file)   PAT="<file path=\"[^\"]*$NAME";;
  symbol) PAT="(func|function|class|def|type|interface|const|var|let|fn|struct|trait|impl).{0,40}\b$NAME\b";;
  test)   PAT="Test$NAME|describe\\(['\"].{0,30}$NAME|it\\(['\"].{0,60}$NAME|test_${NAME}|def test_[a-z_]*$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')";;
  import) PAT="import .{0,80}$NAME|require\\(.{0,40}$NAME|from .{0,60}$NAME import|from ['\"].{0,60}$NAME";;
  *) echo "error=unknown kind: $KIND (file|symbol|test|import)" >&2; exit 2;;
esac

# grep -nE, not rtk: rtk grep is BRE-only and rejects these alternation
# patterns; output here is small and -m bounded, so token filtering isn't needed.
out="$(grep -nE -B 2 -m 25 -- "$PAT" "$PACK" 2>/dev/null || true)"

hits=0
[ -n "$out" ] && hits="$(printf '%s\n' "$out" | grep -cE '.' || true)"
if [ -n "$out" ]; then
  echo "found=yes"
  echo "hits=$hits"
  printf '%s\n' "$out" | head -30
else
  echo "found=no"
  echo "hits=0"
fi

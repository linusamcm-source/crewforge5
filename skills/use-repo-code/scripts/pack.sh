#!/usr/bin/env bash
# pack.sh [max-age-seconds] — ensure a fresh repomix pack (Step 1, mechanised).
# Regenerates when missing or older than max-age (default 7200s). Respects
# $REPOMIX_PACK. Prints pack= age_s= regenerated= provider=.
set -euo pipefail

MAX_AGE="${1:-7200}"
PACK="${REPOMIX_PACK:-.repomix-output.xml}"
IGNORE="**/node_modules/**,**/dist/**,**/build/**,**/.next/**,**/.expo/**,**/coverage/**,**/cdk.out/**,**/*.lock,**/package-lock.json,**/bun.lockb,**/yarn.lock,**/graphify-out/**,**/.repomix-output.xml,**/.venv/**,**/__pycache__/**"

# GNU first, deliberately: GNU reads `-f` as `--file-system` and succeeds with
# unrelated output, so a BSD-first `||` fallback never fires on Linux. BSD stat
# has no `-c` and fails cleanly, so this order works on both. See lib.sh
# mtime_epoch for the full account.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

age=-1
[ -f "$PACK" ] && age=$(( $(date +%s) - $(mtime "$PACK") ))

if [ "$age" -ge 0 ] && [ "$age" -le "$MAX_AGE" ]; then
  echo "pack=$PACK"; echo "age_s=$age"; echo "regenerated=no"
  exit 0
fi

provider=""
for cmd in "repomix" "npx --yes repomix@latest" "bunx repomix@latest"; do
  if command -v "${cmd%% *}" >/dev/null 2>&1; then provider="$cmd"; break; fi
done
[ -n "$provider" ] || { echo "regenerated=no"; echo "error=no repomix/npx/bunx on PATH"; exit 1; }

$provider \
  --compress --style xml --remove-comments --remove-empty-lines \
  --truncate-base64 --top-files-len 20 \
  -o "$PACK" \
  --ignore "$IGNORE" \
  2>&1 | tail -5

echo "pack=$PACK"; echo "age_s=0"; echo "regenerated=yes"; echo "provider=${provider%% *}"

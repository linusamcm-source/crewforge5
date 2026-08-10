#!/usr/bin/env bash
# verify_gnu_portability.sh — run the bats suite against GNU-semantics `stat`
# on a BSD host, so Linux-only failures surface before CI does.
#
#   verify_gnu_portability.sh [bats-file …]     (default: the whole suite)
#
# WHY THIS EXISTS. `stat` is the single richest source of works-on-my-Mac bugs in
# this toolchain, and the failure mode is silent rather than loud:
#
#   stat -f %m "$f" 2>/dev/null || stat -c %Y "$f"
#
# reads as "BSD, else GNU" and is neither. GNU takes `-f` as `--file-system` and
# `%m` as the MOUNT POINT — it EXITS 0 with unrelated output, so the `||` never
# runs. The mount point then reaches `$(( ))`, bash parses its leading word as a
# variable name, and `set -u` kills the script frames away with something like
# "File: unbound variable". That single inversion cost 80 failing tests on
# ubuntu-latest and exactly zero on macOS.
#
# A shim reproduces it in seconds. The correct order is GNU-first — BSD has no
# `-c` at all and fails cleanly, so it degrades properly in both directions.
#
# This is a DEVELOPMENT aid, not a substitute for the Linux CI job: it models
# `stat` only. Anything else that differs between the platforms — merged-usr
# `/bin`, GNU vs BSD `sed -i`, flag ordering — still needs a real runner.
#
# Exits 0 when the suite passes under GNU semantics, 1 otherwise, 2 if the
# environment is wrong (this only makes sense on a BSD/macOS host).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v bats >/dev/null 2>&1 || { echo "SKIP: bats is not installed"; exit 2; }
if stat -c %Y "$ROOT" >/dev/null 2>&1; then
  echo "SKIP: this host already has GNU stat — run the suite directly, the shim would be a no-op"
  exit 2
fi

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT

cat > "$SHIM/stat" <<'SHIMEOF'
#!/usr/bin/env bash
# GNU coreutils `stat`, modelled on a BSD host.
#   -c FMT FILE  GNU format string  -> mapped onto the BSD equivalent
#   -f           GNU --file-system  -> SUCCEEDS with filesystem info, not mtime
#   (no flags)   GNU default output -> begins "  File: …"
# The -f branch is the whole point: it must exit 0, because code that assumes
# it fails on Linux is exactly what this shim exists to catch.
args=(); fmt=""; mode="default"
while [ $# -gt 0 ]; do
  case "$1" in
    -c) mode="c"; fmt="$2"; shift 2 ;;
    -f) mode="f"; shift ;;
    --) shift; break ;;
    -*) shift ;;
    *)  args+=("$1"); shift ;;
  esac
done
f="${args[0]:-}"
case "$mode" in
  c) case "$fmt" in
       %Y) exec /usr/bin/stat -f %m "$f" ;;
       %s) exec /usr/bin/stat -f %z "$f" ;;
       *)  exec /usr/bin/stat -f "$fmt" "$f" ;;
     esac ;;
  f) printf '  File: "%s"\n' "$f"; exit 0 ;;
  *) printf '  File: %s\n' "$f"; exit 0 ;;
esac
SHIMEOF
chmod +x "$SHIM/stat"

# Prove the shim actually models GNU before trusting a green result from it.
if PATH="$SHIM:$PATH" stat -f %m "$ROOT" 2>/dev/null | grep -qE '^[0-9]+$'; then
  echo "FAIL: the shim returned an epoch for \`stat -f %m\` — it is not modelling GNU, so a pass here would mean nothing"
  exit 2
fi

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=("$ROOT"/skills/team-sprint/scripts/tests/*.bats)
fi

echo "running ${#targets[@]} bats file(s) under GNU-semantics stat…"
out="$(PATH="$SHIM:$PATH" bats "${targets[@]}" 2>&1)"
rc=$?

passed="$(printf '%s\n' "$out" | grep -cE '^ok ')"
failed="$(printf '%s\n' "$out" | grep -cE '^not ok')"
echo "  $passed passed, $failed failed"

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "$out" | grep -E '^not ok' | head -20
  echo
  echo "FAIL: these pass on BSD and would fail on Linux. Check every \`stat\`"
  echo "      call on the path — GNU-first ordering, and validate the result."
  exit 1
fi

[ "$rc" -eq 0 ] || { echo "FAIL: bats exited $rc"; exit 1; }
echo "PASS: the suite holds under GNU stat semantics"

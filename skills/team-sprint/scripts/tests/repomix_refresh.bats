#!/usr/bin/env bats
# repomix_refresh.bats — fixtures for scripts/repomix_refresh.sh (Story mech-7).
#
# We never invoke the real repomix binary — every test PATH-shadows a fake
# `repomix` so we exercise the script's freshness/argument logic without
# depending on a slow CLI.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  RR_SH="$SCRIPTS/repomix_refresh.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP

  # BIN holds the PATH-shadow stubs.
  BIN="$TMP/bin"
  mkdir -p "$BIN"
  ORIG_PATH="$PATH"
  export ORIG_PATH
}

teardown() {
  PATH="$ORIG_PATH"
  rm -rf "$TMP"
}

# Install a fake `repomix` on PATH that writes the file passed via -o to CWD.
install_fake_repomix() {
  cat > "$BIN/repomix" <<'EOF'
#!/usr/bin/env bash
out=".repomix-output.xml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
printf '<fake-pack/>\n' > "$out"
EOF
  chmod +x "$BIN/repomix"
}

# ---------------------------------------------------------------------------
# require_repomix fails (exit 1) when repomix is not on PATH.
# ---------------------------------------------------------------------------
@test "missing repomix on PATH -> exit 1 with install hint" {
  # PATH-shadow: empty BIN dir first, no system PATH. /usr/bin only for stat,
  # date, etc — we need basic coreutils but NOT repomix.
  PATH="$BIN:/usr/bin:/bin" run "$RR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repomix missing"* ]]
  [[ "$output" == *"npm i -g repomix"* ]]
}

# ---------------------------------------------------------------------------
# Stale pack inside target -> regenerated.
# ---------------------------------------------------------------------------
@test "stale pack: regenerated when older than --max-age-minutes" {
  install_fake_repomix
  PROJECT="$TMP/proj"
  mkdir -p "$PROJECT"
  # Seed a stale pack (mtime two hours ago).
  printf 'OLD\n' > "$PROJECT/.repomix-output.xml"
  touch -t "$(date -u -v-2H +%Y%m%d%H%M 2>/dev/null || date -u -d '2 hours ago' +%Y%m%d%H%M)" \
    "$PROJECT/.repomix-output.xml"

  PATH="$BIN:/usr/bin:/bin" run "$RR_SH" --target-dir "$PROJECT" --max-age-minutes 60
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.repomix-output.xml" ]
  # Fake repomix writes "<fake-pack/>" — confirms regeneration happened.
  grep -q "fake-pack" "$PROJECT/.repomix-output.xml"
}

# ---------------------------------------------------------------------------
# Fresh pack -> no-op; mtime preserved exactly.
# ---------------------------------------------------------------------------
@test "fresh pack: no-op (mtime unchanged)" {
  install_fake_repomix
  PROJECT="$TMP/proj"
  mkdir -p "$PROJECT"
  printf 'KEEPME\n' > "$PROJECT/.repomix-output.xml"

  # Capture mtime before. `stat -f %m` (BSD) or `stat -c %Y` (GNU).
  if mtime_before="$(stat -f %m "$PROJECT/.repomix-output.xml" 2>/dev/null)"; then :
  else mtime_before="$(stat -c %Y "$PROJECT/.repomix-output.xml")"; fi

  PATH="$BIN:/usr/bin:/bin" run "$RR_SH" --target-dir "$PROJECT" --max-age-minutes 60
  [ "$status" -eq 0 ]

  if mtime_after="$(stat -f %m "$PROJECT/.repomix-output.xml" 2>/dev/null)"; then :
  else mtime_after="$(stat -c %Y "$PROJECT/.repomix-output.xml")"; fi

  [ "$mtime_before" = "$mtime_after" ]
  # File contents preserved -> proves we did NOT call the fake repomix.
  grep -q "KEEPME" "$PROJECT/.repomix-output.xml"
}

# ---------------------------------------------------------------------------
# --target-dir to a tmpdir with no pack: creates <tmpdir>/.repomix-output.xml.
# ---------------------------------------------------------------------------
@test "--target-dir absolute path: produces <tmpdir>/.repomix-output.xml" {
  install_fake_repomix
  PROJECT="$TMP/proj-abs"
  mkdir -p "$PROJECT"
  [ ! -f "$PROJECT/.repomix-output.xml" ]

  PATH="$BIN:/usr/bin:/bin" run "$RR_SH" --target-dir "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.repomix-output.xml" ]
  grep -q "fake-pack" "$PROJECT/.repomix-output.xml"
}

# ---------------------------------------------------------------------------
# --target-dir to a tmpdir that already holds a fresh pack: no-op.
# ---------------------------------------------------------------------------
@test "--target-dir with fresh pack: no-op" {
  install_fake_repomix
  PROJECT="$TMP/proj-fresh"
  mkdir -p "$PROJECT"
  printf 'PRE-EXISTING\n' > "$PROJECT/.repomix-output.xml"

  PATH="$BIN:/usr/bin:/bin" run "$RR_SH" --target-dir "$PROJECT" --max-age-minutes 60
  [ "$status" -eq 0 ]
  # Contents preserved -> no regeneration.
  grep -q "PRE-EXISTING" "$PROJECT/.repomix-output.xml"
}

# ---------------------------------------------------------------------------
# Relative --target-dir resolves against the caller's CWD (not against the
# script's location).
# ---------------------------------------------------------------------------
@test "relative --target-dir resolves against caller CWD" {
  install_fake_repomix
  PARENT="$TMP/parent"
  mkdir -p "$PARENT/sub"
  [ ! -f "$PARENT/sub/.repomix-output.xml" ]

  # Invoke from PARENT with relative "sub". Pack must land at PARENT/sub/...
  cd "$PARENT"
  PATH="$BIN:/usr/bin:/bin" run "$RR_SH" --target-dir "sub"
  [ "$status" -eq 0 ]
  [ -f "$PARENT/sub/.repomix-output.xml" ]
  grep -q "fake-pack" "$PARENT/sub/.repomix-output.xml"
}

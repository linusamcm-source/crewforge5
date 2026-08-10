#!/usr/bin/env bats
# recon.bats — RED-phase contract for scripts/recon.sh (Story RH1).
#
# recon.sh is the capability router: it collapses ~167 provider tools to 10
# intents, resolves an ordered provider chain per intent, and prints ONE
# STATUS= line per invocation. Nothing here touches a real provider — every
# provider is a PATH-shadowed stub under $BIN whose stdout / exit code is
# driven by files under $TMP/stub, so the suite is hermetic and offline.
#
# The sandbox PATH is deliberately "$BIN:/usr/bin:/bin" — that is the ONLY way
# to make codegraph/graphify/rtk genuinely ABSENT on a machine where all three
# live in /opt/homebrew/bin (PATH-shadowing cannot hide a later entry). jq /
# python3 / git are symlinked into $BIN so lib.sh still works. /bin/bash there
# is 3.2.57, so the sandbox enforces the bash-3.2 house rule for free.
#
# Fixture provider outputs live under scripts/fixtures/recon/ and were captured
# from the live tools on 2026-07-28: CodeGraph 1.5.0 `status` (ANSI included —
# it colours even when piped, and it exits 0 whether or not the project is
# initialised), graphify `explain`, and rtk 0.44.0 `grep` including its
# "  +<n> more in <file>" trailer.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RECON="$SCRIPTS/recon.sh"
  PROVIDERS="$SCRIPTS/recon_providers.sh"
  FIX="$SCRIPTS/fixtures/recon"
  PLAN="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/docs/plans/recon-harness-1.md"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  BIN="$TMP/bin"
  STUB="$TMP/stub"
  REPO="$TMP/repo"
  mkdir -p "$BIN" "$STUB" "$REPO"

  _link_tool jq
  _link_tool python3
  _link_tool git

  # A tracked, bash-only fixture repo. `recon_min_files: 0` keeps the DEGRADED
  # and provider-resolution cases passing once RH3 inserts the small-repo guard
  # ahead of provider resolution (RH1 AC).
  ( cd "$REPO" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$REPO" && git init -q . >/dev/null 2>&1 )
  printf 'recon_min_files: 0\n' > "$REPO/team-sprint.config.yaml"
  printf '#!/usr/bin/env bash\nonly_fn() { printf hi; }\n' > "$REPO/only.sh"
  ( cd "$REPO" \
      && git add only.sh team-sprint.config.yaml >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# --- sandbox helpers --------------------------------------------------------

_link_tool() {
  local p
  p="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "$p" ]; then
    ln -sf "$p" "$BIN/$1"
  fi
}

# _recon <args...> — run recon.sh in the fixture repo on the sandbox PATH,
# capturing STDOUT ONLY. The STATUS grammar is a stdout contract; lib.sh's
# info/warn go to stderr and must never contaminate a line-count assertion.
_recon() {
  ( cd "$REPO" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>/dev/null )
}

# _recon_all — same, but merges stderr (usage block, warnings).
_recon_all() {
  ( cd "$REPO" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>&1 )
}

# _recon_in <dir> <args...> — run recon.sh from an ARBITRARY directory: a repo
# subdirectory (artifacts must still resolve from the repo root) or a second
# fixture repo with a different language mix.
_recon_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>/dev/null )
}

# _install_stub <name> — PATH-shadow a provider binary. Behaviour is driven by
# $STUB/<name>.out (stdout), $STUB/<name>.exit (exit code) and, for codegraph,
# $STUB/codegraph.status (the `status` subcommand's stdout). Every invocation
# appends to $STUB/<name>.log so a test can assert a provider was — or was NOT
# — executed.
_install_stub() {
  cat > "$BIN/$1" <<'STUB'
#!/bin/bash
name="$(basename "$0")"
d="$(dirname "$0")/../stub"
printf '%s %s\n' "$name" "$*" >> "$d/$name.log"
if [ "$name" = codegraph ] && [ "$1" = status ]; then
  if [ -f "$d/codegraph.status" ]; then cat "$d/codegraph.status"; fi
  exit 0
fi
case "$1" in
  --version|-V|version) cat "$d/$name.version" 2>/dev/null || printf '9.9.9\n'; exit 0 ;;
esac
if [ -f "$d/$name.out" ]; then cat "$d/$name.out"; fi
exit "$(cat "$d/$name.exit" 2>/dev/null || printf 0)"
STUB
  chmod +x "$BIN/$1"
  : > "$STUB/$1.out"
  printf '0\n' > "$STUB/$1.exit"
}

_stub_out()  { cp "$2" "$STUB/$1.out"; }
_stub_exit() { printf '%s\n' "$2" > "$STUB/$1.exit"; }
_not_ran()   { [ ! -s "$STUB/$1.log" ]; }
_runs() {
  if [ -f "$STUB/$1.log" ]; then
    wc -l < "$STUB/$1.log" | tr -d ' '
  else
    printf 0
  fi
}

# _caps_provider <name> <available> <indexed> <languages-json> — emit ONE
# provider object for the capability cache, with the (binary path, mtime, size)
# triple read off the real stub, so a router that revalidates the triple sees a
# consistent, unchanged cache.
_caps_provider() {
  local name="$1" avail="$2" indexed="$3" langs="$4"
  local binname="$name" bin="" mt=0 sz=0
  if [ "$name" = repomix ]; then
    binname=rtk
  fi
  if [ "$avail" = true ] && [ -x "$BIN/$binname" ]; then
    bin="$BIN/$binname"
    mt="$(stat -f %m "$bin" 2>/dev/null || stat -c %Y "$bin")"
    sz="$(stat -f %z "$bin" 2>/dev/null || stat -c %s "$bin")"
  fi
  jq -n --arg n "$name" --argjson a "$avail" --argjson i "$indexed" \
        --argjson l "$langs" --arg b "$bin" --argjson m "$mt" --argjson s "$sz" \
        '{($n): {available:$a, indexed:$i, languages:$l, version:"stub",
                 binary:$b, binary_mtime:$m, binary_size:$s,
                 resolved_at:(now|floor)}}'
}

# _write_caps <provider-object>... — merge into .recon/capabilities.json.
_write_caps() {
  mkdir -p "$REPO/.recon"
  printf '%s\n' "$@" | jq -s '{providers: add, resolved_at:(now|floor)}' \
    > "$REPO/.recon/capabilities.json"
}

# _write_caps_aged <age-seconds> <provider-object>... — same, but the cache's
# top-level resolved_at is backdated, so a router that revalidates the cache on
# the intent path (not merely under --probe) can be told apart from one that
# trusts any existing file forever.
_write_caps_aged() {
  local age="$1"
  shift
  mkdir -p "$REPO/.recon"
  printf '%s\n' "$@" | jq -s --argjson age "$age" \
    '{providers: add, resolved_at: ((now|floor) - $age)}' \
    > "$REPO/.recon/capabilities.json"
}

# _write_caps_in <dir> <provider-object>... — _write_caps for a second repo.
_write_caps_in() {
  local d="$1"
  shift
  mkdir -p "$d/.recon"
  printf '%s\n' "$@" | jq -s '{providers: add, resolved_at:(now|floor)}' \
    > "$d/.recon/capabilities.json"
}

_status_lines() { printf '%s\n' "$output" | grep -c '^STATUS=' || true; }
_out_lines()    { printf '%s\n' "$output" | grep -c . || true; }

# ---------------------------------------------------------------------------
# 1. Usage / modes
# ---------------------------------------------------------------------------

@test "--help exits 1 and names all 10 intents and every mode" {
  run _recon_all --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  local i
  for i in text callers callees impact tests path dynamic coupling docs spans; do
    if [[ "$output" != *"$i"* ]]; then
      echo "usage block omits intent: $i"
      false
    fi
  done
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"--probe"* ]]
  [[ "$output" == *"--no-delegate"* ]]
  [[ "$output" == *"<intent>"* ]]
}

# ---------------------------------------------------------------------------
# 2. Evaluation order — disabled, intent match, small-repo guard, providers
# ---------------------------------------------------------------------------

@test "evaluation order: unknown intent plus absent providers yields NO_INTENT_MATCH, never DEGRADED" {
  # Two conditions trip at once. Intent match is step 2, provider resolution is
  # step 4, so the intent verdict must win.
  run _recon frobnicate x
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=NO_INTENT_MATCH"* ]]
  [[ "$output" != *"STATUS=DEGRADED"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "an unrecognised intent is an answer, not an error: NO_INTENT_MATCH and exit 0" {
  run _recon frobnicate x
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=NO_INTENT_MATCH"* ]]
  [ "$(_out_lines)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 3. DEGRADED — no provider installed at all
# ---------------------------------------------------------------------------

@test "no providers installed: callers prints exactly one STATUS=DEGRADED REASON=not-installed and exits 0" {
  run _recon callers only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DEGRADED REASON=not-installed"* ]]
  [ "$(_status_lines)" -eq 1 ]
  [ "$(_out_lines)" -eq 1 ]
}

@test "the DEGRADED fixture repo sets recon_min_files 0 so it survives RH3 guard insertion" {
  grep -q '^recon_min_files: 0$' "$REPO/team-sprint.config.yaml"
  run _recon callers only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DEGRADED"* ]]
  [[ "$output" != *"STATUS=SKIP"* ]]
}

@test "with recon unset or auto an absent provider set never hard-fails" {
  # The `recon: on` HARD gate is RH5's; RH1 must never exit non-zero here.
  run _recon impact only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DEGRADED"* ]]
}

# ---------------------------------------------------------------------------
# 4. --probe
# ---------------------------------------------------------------------------

@test "--probe with no providers prints exactly one STATUS=DEGRADED REASON=not-installed and exits 0" {
  run _recon_all --probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DEGRADED REASON=not-installed"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "--probe with every bash-probeable provider resolved prints exactly one STATUS=OK" {
  _install_stub codegraph
  _install_stub graphify
  _install_stub rtk
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"

  run _recon --probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=OK"* ]]
  [ "$(_status_lines)" -eq 1 ]
  [ "$(_out_lines)" -eq 1 ]
}

@test "--probe writes .recon/capabilities.json with every documented per-provider key" {
  _install_stub codegraph
  _install_stub graphify
  _install_stub rtk
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"

  run _recon --probe
  [ "$status" -eq 0 ]
  [ -f "$REPO/.recon/capabilities.json" ]

  local caps="$REPO/.recon/capabilities.json" p
  for p in repomix graphify codegraph tokensave; do
    run jq -e --arg p "$p" '
      .providers[$p]
      | (.available|type) == "boolean"
        and (.indexed|type) == "boolean"
        and (.languages|type) == "array"
        and (.version|type) == "string"
        and (.binary|type) == "string"
        and (.binary_mtime|type) == "number"
        and (.binary_size|type) == "number"
        and (.resolved_at|type) == "number"
    ' "$caps"
    if [ "$status" -ne 0 ]; then
      echo "capabilities.json missing documented keys for provider: $p"
      false
    fi
  done
}

@test "--probe records languages from codegraph Files by Language and graph.json metadata.language" {
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"

  run _recon --probe
  [ "$status" -eq 0 ]
  local caps="$REPO/.recon/capabilities.json"
  run jq -e '.providers.codegraph.languages | index("typescript")' "$caps"
  [ "$status" -eq 0 ]
  run jq -e '.providers.codegraph.languages | index("python")' "$caps"
  [ "$status" -eq 0 ]
  run jq -e '.providers.graphify.languages | index("bash")' "$caps"
  [ "$status" -eq 0 ]
  run jq -e '.providers.graphify.languages | index("markdown")' "$caps"
  [ "$status" -eq 0 ]
}

@test "--probe reads codegraph initialisation from stdout, never from its exit code" {
  # `codegraph status` exits 0 whether or not the project is initialised.
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.codegraph.available == true and .providers.codegraph.indexed == false' \
    "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]
}

@test "--probe records an EMPTY language catalogue when codegraph prints no Files by Language block" {
  # `codegraph status` on an un-initialised project prints no language block, so
  # _codegraph_facts emits its INDEXED= line and nothing else. Splitting that
  # one-line payload on a newline it does not contain writes the marker itself
  # into the cache as if it were a language name — a fabricated catalogue entry
  # in the very artifact the language filter reads.
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.codegraph.languages == []' "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]
}

@test "a second --probe inside the TTL re-resolves indexed, so an index built meanwhile is visible at once" {
  # --probe exists to RE-RESOLVE (recon.sh usage line: "resolve providers,
  # refresh .recon/capabilities.json"). Short-circuiting a cached entry on the
  # (binary, mtime, size) triple alone answered from the cache for the whole
  # recon_probe_max_age_minutes TTL (default 1440), so an index built after the
  # first probe stayed invisible for a day — the exact "newly indexed provider is
  # invisible and the silence is reported as a confident not-installed" failure
  # recon.sh's header forbids. It also breaks phase-0.md step 9a → 9b, which
  # builds the graph and then probes it inside one Phase 0.
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"

  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.graphify.indexed == false
             and .providers.codegraph.indexed == false' \
    "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]

  # Build both indexes. No binary moved: only the artefacts they read changed,
  # which is precisely what the triple cannot see.
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"

  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.graphify.indexed == true
             and (.providers.graphify.languages | index("bash")) != null
             and .providers.codegraph.indexed == true' \
    "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]
}

@test "a changed binary mtime re-probes that provider alone" {
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"

  run _recon --probe
  [ "$status" -eq 0 ]
  local base_cg base_gr
  base_cg="$(_runs codegraph)"
  base_gr="$(_runs graphify)"

  touch -t 203001010000 "$BIN/codegraph"
  run _recon --probe
  [ "$status" -eq 0 ]
  [ "$(_runs codegraph)" -gt "$base_cg" ]
  [ "$(_runs graphify)" -eq "$base_gr" ]
}

@test "--probe reads codegraph initialisation from the markers the live tool actually prints" {
  # CodeGraph 1.5.0 prints NO line ending in "Initialized" for an indexed
  # project: it prints an `Index Statistics:` block and `Index is up to date`.
  # Matching on a marker the tool never emits leaves codegraph permanently
  # no-index in production while a fabricated fixture keeps the suite green.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.codegraph.available == true
             and .providers.codegraph.indexed == true' \
    "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]
}

@test "the initialized codegraph fixture is a real capture, not a hand-written one" {
  [ -f "$FIX/codegraph-status-initialized.txt" ]
  run bash -c "grep -c 'Not initialized' '$FIX/codegraph-status-initialized.txt' || true"
  [ "$output" = "0" ]
  grep -q 'Index Statistics:' "$FIX/codegraph-status-initialized.txt"
  grep -q 'Index is up to date' "$FIX/codegraph-status-initialized.txt"
  grep -q 'Files by Language:' "$FIX/codegraph-status-initialized.txt"
}

@test "a capability cache older than the TTL is re-probed on the INTENT path, not trusted forever" {
  # RECON_PROBE_MAX_AGE_MINUTES must gate the intent path too. Otherwise an
  # installed, indexed provider that was absent when the cache was written stays
  # permanently invisible and the router reports a confident not-installed —
  # the false negative this router exists to prevent.
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  # 30 days old, and it records every provider as absent.
  _write_caps_aged $((30 * 86400)) \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon --no-delegate callers only_fn
  [ "$status" -eq 0 ]
  # assert_line / refute_line, not `[[ ]]`: bash 3.2's errexit does not fire on
  # a failing `[[ ]]`, so a non-final `[[ ]]` never fails a bats test.
  assert_line "PROVIDER=graphify"
  assert_line "STATUS=OK"
  refute_line "STATUS=DEGRADED"
}

@test "a capability cache inside the TTL is trusted on the intent path and never re-probed" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps_aged 60 \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  local before after
  before="$(jq -r '.resolved_at' "$REPO/.recon/capabilities.json")"

  run _recon --no-delegate spans lib.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  after="$(jq -r '.resolved_at' "$REPO/.recon/capabilities.json")"
  [ "$before" = "$after" ]
}

# ---------------------------------------------------------------------------
# 5. Present-but-un-indexed vs absent — REASON=no-index vs REASON=not-installed
# ---------------------------------------------------------------------------

@test "codegraph present but not initialized: tests emits STATUS=DELEGATE PROVIDER=tokensave" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon tests only.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DELEGATE"* ]]
  [[ "$output" == *"PROVIDER=tokensave"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "codegraph present but not initialized: dynamic emits STATUS=DELEGATE PROVIDER=tokensave" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon dynamic "who handles the retry callback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DELEGATE"* ]]
  [[ "$output" == *"PROVIDER=tokensave"* ]]
}

@test "un-indexed codegraph under --no-delegate: tests emits UNAVAILABLE REASON=no-index, never EMPTY" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon --no-delegate tests only.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=no-index"* ]]
  [[ "$output" != *"STATUS=EMPTY"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "tests: a real codegraph affected answer is COUNT=1 through the router, never a terminal EMPTY" {
  # EMPTY is TERMINAL in recon_resolve, so a normaliser that read the
  # `affected -j` payload as zero rows did not merely mis-report codegraph — it
  # ended the walk, and the tokensave link behind it never fired. The router
  # level is where that costs the answer, so it is asserted here as well as in
  # the adapter suite.
  local js="$TMP/affected" i
  mkdir -p "$js/src/auth"
  ( cd "$js" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$js" && git init -q . >/dev/null 2>&1 )
  printf 'recon_min_files: 0\n' > "$js/team-sprint.config.yaml"
  for i in 1 2 3; do
    printf 'function m%s(){}\n' "$i" > "$js/src/auth/m$i.js"
  done
  ( cd "$js" && git add . >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true

  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-affected.json"
  _write_caps_in "$js" \
    "$(_caps_provider codegraph true true '["javascript"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$js" tests src/auth/session.js
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=codegraph"
  assert_line "test/auth/session.test.js:1	session.test.js	test"
  assert_line "STATUS=OK COUNT=1"
  refute_line "STATUS=EMPTY"
  refute_line "STATUS=DELEGATE"
  [ "$(_status_lines)" -eq 1 ]
}

@test "un-indexed codegraph under --no-delegate: dynamic emits UNAVAILABLE REASON=no-index" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  run _recon --no-delegate dynamic "who handles the retry callback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=no-index"* ]]
  [[ "$output" != *"STATUS=EMPTY"* ]]
}

@test "dynamic with the codegraph binary absent entirely emits STATUS=DELEGATE PROVIDER=tokensave" {
  run _recon dynamic "who handles the retry callback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DELEGATE"* ]]
  [[ "$output" == *"PROVIDER=tokensave"* ]]
}

@test "dynamic with codegraph absent under --no-delegate: UNAVAILABLE REASON=not-installed, graphify untouched" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  run _recon --no-delegate dynamic "who handles the retry callback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=not-installed"* ]]
  [[ "$output" != *"REASON=no-index"* ]]
  # graphify is not on the `dynamic` chain and must not be invoked at all.
  _not_ran graphify
}

# ---------------------------------------------------------------------------
# 6. Language filtering
# ---------------------------------------------------------------------------

@test "callers is answered by graphify when graphify indexed bash and codegraph did not" {
  _install_stub codegraph
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph true true '["typescript"]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon callers only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROVIDER=graphify"* ]]
  [[ "$output" == *"STATUS=OK"* ]]
  # A language-filtered link is skipped exactly as an absent binary is.
  _not_ran codegraph
}

@test "no chain provider indexed the primary language: UNAVAILABLE REASON=language-unsupported, never EMPTY" {
  _install_stub codegraph
  _install_stub graphify
  _write_caps \
    "$(_caps_provider codegraph true true '["typescript"]')" \
    "$(_caps_provider graphify  true true '["python"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon path only_fn other_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=language-unsupported"* ]]
  [[ "$output" != *"STATUS=EMPTY"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "a repo whose tracked files carry an unmapped extension is language-unsupported, never EMPTY" {
  # The language guard must not fail OPEN when no primary language can be
  # derived: an un-checkable catalogue is "I cannot tell", and letting the
  # provider answer anyway turns a wrong-language index into a confident
  # STATUS=EMPTY COUNT=0. `.ex` is outside _recon_lang_for_path's table, as is
  # every Elixir/Lua/Dart/Scala/Haskell repo and every docs-only repo.
  local ex="$TMP/exrepo"
  mkdir -p "$ex"
  ( cd "$ex" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$ex" && git init -q . >/dev/null 2>&1 )
  # Same reason the shared fixture repo carries it: the language filter is what
  # is under test here, so RH3's small-repo guard — which sits AHEAD of provider
  # resolution — must not answer first for this one-file repo.
  printf 'recon_min_files: 0\n' > "$ex/team-sprint.config.yaml"
  printf 'defmodule A do\nend\n' > "$ex/a.ex"
  ( cd "$ex" \
      && git add a.ex >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true

  _install_stub graphify
  : > "$STUB/graphify.out"
  _write_caps_in "$ex" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["typescript"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$ex" --no-delegate callers only_fn
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"
  refute_line "STATUS=EMPTY"
  [ "$(_status_lines)" -eq 1 ]
}

@test "a path argument names the language the gate checks, not the repo's majority language" {
  # _lang_ok graded the provider's catalogue against the repo's PRIMARY language,
  # which is a majority vote over `git ls-files`. In a polyglot repo that let a
  # provider answer about a language it never indexed: codegraph indexed the
  # javascript majority, the question was about a .sh file, and the answer came
  # back STATUS=EMPTY COUNT=0 — a confident false negative. When the ARGUMENT
  # names a language, that is the language the catalogue has to cover.
  local poly="$TMP/poly" i
  mkdir -p "$poly"
  ( cd "$poly" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$poly" && git init -q . >/dev/null 2>&1 )
  printf 'recon_min_files: 0\n' > "$poly/team-sprint.config.yaml"
  for i in 1 2 3; do
    printf 'function m%s(){}\n' "$i" > "$poly/m$i.js"
  done
  printf '#!/usr/bin/env bash\nhelper() { :; }\n' > "$poly/helper.sh"
  ( cd "$poly" && git add . >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true

  _install_stub codegraph
  _install_stub graphify
  _stub_out codegraph "$FIX/codegraph-callers.json"
  # BOTH links of the callers chain indexed the majority language and nothing
  # else, so the terminal reason is the language one — recon_resolve reports the
  # LAST link's reason, and a chain ending in an absent binary would report
  # not-installed however the earlier link was filtered.
  _write_caps_in "$poly" \
    "$(_caps_provider codegraph true true '["javascript"]')" \
    "$(_caps_provider graphify  true true '["javascript"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  # The .sh argument sits outside both catalogues: say so, never EMPTY.
  run _recon_in "$poly" --no-delegate callers helper.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"
  refute_line "STATUS=EMPTY"
  # Skipped exactly as an absent binary is — neither provider is even asked.
  _not_ran codegraph
  _not_ran graphify

  # …and a .js argument in the SAME repo still resolves through codegraph.
  run _recon_in "$poly" --no-delegate callers m1.js
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK COUNT=2"
}

# ---------------------------------------------------------------------------
# 7. --no-delegate / RECON_NO_MCP skip the MCP-only link
# ---------------------------------------------------------------------------

@test "coupling A B --no-delegate with tokensave present answers PROVIDER=graphify, not STATUS=DELEGATE" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave true false '[]')"

  run _recon coupling only_fn other_fn --no-delegate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROVIDER=graphify"* ]]
  [[ "$output" != *"STATUS=DELEGATE"* ]]
}

@test "RECON_NO_MCP=1 is equivalent to --no-delegate on the coupling chain" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave true false '[]')"

  export RECON_NO_MCP=1
  run _recon coupling only_fn other_fn
  unset RECON_NO_MCP
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROVIDER=graphify"* ]]
  [[ "$output" != *"STATUS=DELEGATE"* ]]
}

# ---------------------------------------------------------------------------
# 8. Output grammar
# ---------------------------------------------------------------------------

@test "every emitted result line matches the RH1 result grammar" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon spans lib.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=OK"* ]]

  local bad="" line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      PROVIDER=*|STATUS=*|TRUNCATED=*) continue ;;
    esac
    if ! printf '%s' "$line" | grep -qE '^[^	]+:[0-9]+	[^	]*	[^	]*$'; then
      bad="$bad | $line"
    fi
  done <<< "$output"
  if [ -n "$bad" ]; then
    echo "non-conforming result lines:$bad"
    false
  fi
}

@test "an OK answer carries the PROVIDER INTENT FRESHNESS QUERY header and a COUNT, STATUS last" {
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon spans lib.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROVIDER=graphify"* ]]
  [[ "$output" == *"INTENT=spans"* ]]
  [[ "$output" == *"FRESHNESS="* ]]
  [[ "$output" == *"QUERY="* ]]
  [[ "$output" == *"COUNT="* ]]
  printf '%s\n' "$output" | tail -1 | grep -q '^STATUS=OK'
}

@test "a non-answer status is a single STATUS line with no header, no COUNT and no FRESHNESS" {
  run _recon callers only_fn
  [ "$status" -eq 0 ]
  [ "$(_out_lines)" -eq 1 ]
  [[ "$output" != *"FRESHNESS="* ]]
  [[ "$output" != *"COUNT="* ]]
  [[ "$output" != *"INTENT="* ]]
}

@test "no emitted line carries source-code bodies from codegraph explore" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-explore.txt"
  _write_caps \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon dynamic "token parsing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/auth/session.ts:40"* ]]
  [[ "$output" != *"SECRET_SAUCE"* ]]
  [[ "$output" != *"CANARY_BODY_TEXT"* ]]
  [[ "$output" != *'```'* ]]
}

# ---------------------------------------------------------------------------
# 9. Chain semantics — advance, terminal, exactly one STATUS line
# ---------------------------------------------------------------------------

@test "a failing first link advances the chain and only the answering link reports" {
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_exit codegraph 1
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon --no-delegate callees only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROVIDER=graphify"* ]]
  [[ "$output" == *"STATUS=OK"* ]]
  [[ "$output" != *"REASON=provider-error"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "a zero-exit provider with no result lines is terminal: STATUS=EMPTY COUNT=0, chain does not advance" {
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  : > "$STUB/codegraph.out"
  _stub_out graphify "$FIX/graphify-explain.txt"
  _write_caps \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon --no-delegate impact only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=EMPTY"* ]]
  [[ "$output" == *"COUNT=0"* ]]
  _not_ran graphify
}

@test "a non-zero provider exit on the last link yields UNAVAILABLE REASON=provider-error" {
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_exit codegraph 1
  _stub_exit graphify 1
  _write_caps \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon --no-delegate callers only_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=provider-error"* ]]
}

@test "exactly one STATUS line on a three-link chain whose first two links fail" {
  # `callers` is codegraph -> tokensave -> graphify: codegraph fails, the
  # MCP-only link is skipped by --no-delegate, graphify fails.
  _install_stub codegraph
  _install_stub graphify
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_exit codegraph 1
  _stub_exit graphify 1
  _write_caps \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave true false '[]')"

  run _recon --no-delegate callers only_fn
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 10. Delegation
# ---------------------------------------------------------------------------

@test "STATUS=DELEGATE carries PROVIDER INTENT and JSON-parsable ARGS, and no TOOL without a roster" {
  run _recon coupling only_fn other_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DELEGATE"* ]]
  [[ "$output" == *"PROVIDER=tokensave"* ]]
  [[ "$output" == *"INTENT=coupling"* ]]
  # bash cannot enumerate an MCP roster, so a hardcoded TOOL= is forbidden.
  [[ "$output" != *"TOOL="* ]]

  local line args
  line="$(printf '%s\n' "$output" | grep '^STATUS=DELEGATE')"
  args="${line#*ARGS=}"
  [ "$args" != "$line" ]
  printf '%s' "$args" | jq -e . >/dev/null
}

@test "no MCP tool name is hardcoded anywhere in the router or the adapters" {
  [ -f "$RECON" ]
  [ -f "$PROVIDERS" ]
  run bash -c "grep -c 'tokensave_' '$RECON' '$PROVIDERS' | grep -v ':0\$' || true"
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# 11. Truncation / line cap
# ---------------------------------------------------------------------------

@test "output beyond RECON_MAX_LINES is truncated with a TRUNCATED marker and a pre-truncation COUNT" {
  _install_stub graphify
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  {
    printf 'Node: lib.sh\n'
    printf 'Connections (60):\n'
    i=1
    while [ "$i" -le 60 ]; do
      printf '  --> fn_%s() [defines] [EXTRACTED] skills/team-sprint/scripts/lib.sh:L%s\n' "$i" "$i"
      i=$((i + 1))
    done
  } > "$STUB/graphify.out"

  run _recon spans lib.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRUNCATED=50/60"* ]]
  [[ "$output" == *"COUNT=60"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '	' || true)" -eq 50 ]
}

@test "RECON_MAX_LINES overrides the default cap of 50" {
  _install_stub graphify
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  {
    printf 'Node: lib.sh\n'
    printf 'Connections (10):\n'
    i=1
    while [ "$i" -le 10 ]; do
      printf '  --> fn_%s() [defines] [EXTRACTED] skills/team-sprint/scripts/lib.sh:L%s\n' "$i" "$i"
      i=$((i + 1))
    done
  } > "$STUB/graphify.out"

  export RECON_MAX_LINES=3
  run _recon spans lib.sh
  unset RECON_MAX_LINES
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRUNCATED=3/10"* ]]
  [[ "$output" == *"COUNT=10"* ]]
}

# ---------------------------------------------------------------------------
# 12. text intent (repomix / rtk) and docs through the router
# ---------------------------------------------------------------------------

@test "text maps pack offsets to source-relative coordinates through the router" {
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon text marker
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha/one.sh:3"* ]]
  [[ "$output" == *"beta/two.md:4"* ]]
  [[ "$output" == *"STATUS=OK"* ]]
}

@test "text is answered from the pack even when the QUERY looks like a file of a language nothing indexed" {
  # CLAUDE.md routes "text/occurrence, location unknown" through `recon.sh text`,
  # and `text` is a full-text grep over the pack: repomix parses no language at
  # all and its catalogue is derived from the pack's own <file path=…> tags. The
  # language gate reads a source extension off any ARGUMENT, so once it consulted
  # the query's language `text session.ts` in a repo with no TypeScript was
  # refused REASON=language-unsupported while the pack held real hits — a false
  # refusal on the one chain that could have answered.
  local js="$TMP/jsonly" i
  mkdir -p "$js"
  ( cd "$js" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$js" && git init -q . >/dev/null 2>&1 )
  printf 'recon_min_files: 0\n' > "$js/team-sprint.config.yaml"
  for i in 1 2 3; do
    printf 'function m%s(){}\n' "$i" > "$js/m$i.js"
  done
  ( cd "$js" && git add . >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true

  _install_stub rtk
  _install_stub graphify
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$js/.repomix-output.xml"
  _write_caps_in "$js" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["javascript"]')" \
    "$(_caps_provider repomix   true true '["javascript"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$js" --no-delegate text session.ts
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "STATUS=OK COUNT=2"
  refute_line "STATUS=UNAVAILABLE REASON=language-unsupported"

  # --explain reads the same gate and must describe the same route.
  run _recon_in "$js" --no-delegate --explain text session.ts
  [ "$status" -eq 0 ]
  refute_line "PROVIDER=repomix REASON=capability-mismatch"
  [[ "$output" == *"PROVIDER=repomix COMMAND=rtk grep"* ]]

  # The exemption is `text`'s alone: a STRUCTURAL intent asking about the same
  # argument still refuses rather than letting a provider that never parsed the
  # language answer a confident EMPTY.
  : > "$STUB/graphify.out"
  run _recon_in "$js" --no-delegate callers session.ts
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"
  refute_line "STATUS=EMPTY"
}

@test "text never attributes a hit to a <file path= mention that sits inside prose" {
  # A pack's prose (docs about grepping the pack) contains the literal string
  # `<file path="…">` mid-line. An unanchored tag index treats it as a real tag
  # and every downstream hit is credited to a FABRICATED path at a wrong line —
  # the exact opposite of the trustworthy file:line citation the router sells.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-phantom.txt"
  cp "$FIX/pack-phantom-tag.xml" "$REPO/.repomix-output.xml"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon text marker
  [ "$status" -eq 0 ]
  assert_line "alpha/one.sh:3"
  refute_line "decoy/x.ts"
}

@test "--probe reads languages from real pack tags only, never from a prose mention" {
  _install_stub rtk
  cp "$FIX/pack-phantom-tag.xml" "$REPO/.repomix-output.xml"
  run _recon --probe
  [ "$status" -eq 0 ]
  run jq -e '.providers.repomix.languages == ["bash"]' \
    "$REPO/.recon/capabilities.json"
  [ "$status" -eq 0 ]
}

@test "the router answers a subdirectory exactly as it answers the repo root" {
  # The router resolves artifacts from the repo root; the adapters must too.
  # Resolving them from CWD turns an OK answer into UNAVAILABLE the moment the
  # caller runs from anywhere but the root — and blames a provider that never
  # errored.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  mkdir -p "$REPO/sub"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon text marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "alpha/one.sh:3"

  run _recon_in "$REPO/sub" text marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "alpha/one.sh:3"
  assert_line "STATUS=OK"
  refute_line "STATUS=UNAVAILABLE"
}

@test "the router answers a subdirectory exactly as it answers the repo root for graphify too" {
  # The repomix sibling above only proves the PACK PATH is root-resolved. The
  # graphify CLI resolves graphify-out/graph.json relative to its own $PWD, so
  # the adapter must also RUN it from the root. This stub refuses exactly as the
  # real CLI does when the graph is not under its CWD.
  printf '#!/bin/bash\nexit 0\n' > "$BIN/fakepy"
  chmod +x "$BIN/fakepy"
  cat > "$BIN/graphify" <<'STUB'
#!/bin/bash
d="$(dirname "$0")/../stub"
printf 'graphify %s\n' "$*" >> "$d/graphify.log"
if [ ! -f graphify-out/graph.json ]; then
  printf 'error: graph file not found: %s/graphify-out/graph.json\n' "$PWD" >&2
  exit 1
fi
cat "$d/graphify.out"
STUB
  chmod +x "$BIN/graphify"
  mkdir -p "$REPO/graphify-out" "$REPO/sub"
  cp "$FIX/graphify-query.txt" "$STUB/graphify.out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon docs "what does lib.sh do"
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  assert_line "STATUS=OK"

  run _recon_in "$REPO/sub" docs "what does lib.sh do"
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  assert_line "skills/team-sprint/scripts/lib.sh:21"
  assert_line "STATUS=OK"
  refute_line "STATUS=UNAVAILABLE"

  run _recon_in "$REPO/sub" spans lib.sh
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  refute_line "STATUS=UNAVAILABLE"
}

@test "a truncated rtk result set answers OK: the summary header never kills the adapter" {
  # Every real truncated `rtk grep` run opens with `<n> matches in <m> files:`.
  # That line starts with a digit and carries a colon, so a loose result-line
  # test admits it, and evaluating its non-numeric prefix arithmetically under
  # recon.sh's `set -u` aborts the adapter — the router then reports UNAVAILABLE
  # REASON=provider-error for the whole `text` intent against the live pack.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits.txt"
  cp "$FIX/pack-truncated.xml" "$REPO/.repomix-output.xml"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_all text marker
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK COUNT=40"
  refute_line "matches in"
  refute_line "unbound variable"
  refute_line "REASON=provider-error"
  assert_line "alpha/one.sh:2"
  assert_line "beta/two.md:6"
}

@test "text with no rtk match at all is STATUS=EMPTY COUNT=0, never provider-error" {
  # `rtk grep` exits 1 when nothing matched. On the single-link `text` chain
  # that is the commonest negative query there is, and it must read as the
  # zero-result ANSWER rather than as a broken provider.
  _install_stub rtk
  _stub_exit rtk 1
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon text zzzz_no_such_string_zzzz
  [ "$status" -eq 0 ]
  assert_line "STATUS=EMPTY COUNT=0"
  refute_line "REASON=provider-error"
  [ "$(_status_lines)" -eq 1 ]
}

@test "text is a single-link chain: an absent pack is UNAVAILABLE REASON=no-index, never EMPTY" {
  _install_stub rtk
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon text marker
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=no-index"* ]]
  [[ "$output" != *"STATUS=EMPTY"* ]]
}

@test "docs with graphify present but no usable interpreter falls through to a not-installed repomix" {
  # graphify_ensure.sh --check finds no interpreter that can `import graphify`
  # in the sandbox, so the graphify link yields the failure sentinel and the
  # chain advances to repomix, which is absent -> the terminal link's reason.
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon docs "what does lib.sh do"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=UNAVAILABLE REASON=not-installed"* ]]
  [ "$(_status_lines)" -eq 1 ]
}

@test "docs is answered from real graphify query output, never a confident EMPTY" {
  # `docs` maps to `graphify query`, whose output is `NODE <name> [src=… loc=L…]`
  # — a different shape from `explain`'s connection lines. A normaliser that
  # only knows connection lines silently drops every row and the router reports
  # STATUS=EMPTY COUNT=0 against a provider that returned 62 nodes.
  printf '#!/bin/bash\nexit 0\n' > "$BIN/fakepy"
  chmod +x "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-query.txt"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _write_caps \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon docs "what does lib.sh do"
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  assert_line "STATUS=OK"
  refute_line "STATUS=EMPTY"
  assert_line "skills/team-sprint/scripts/lib.sh:21"
}

# ---------------------------------------------------------------------------
# 13. Header-comment contract (graphify_ensure.sh:1-38 style)
# ---------------------------------------------------------------------------

@test "the header comment documents every mode, the evaluation order and the exit codes" {
  [ -f "$RECON" ]
  local hdr token
  # The window is the header BLOCK — everything up to `set -euo pipefail` — not a
  # line count. A fixed `1,90p` says "documented in the first 90 lines", which is
  # not the contract and turns any honest addition to the header into a red test
  # for the token that got pushed over the line.
  hdr="$(sed -n '1,/^set -euo pipefail/p' "$RECON")"
  for token in '--help' '--probe' '--no-delegate' 'Usage:' 'Output:' 'Exit codes:' 'evaluation order'; do
    case "$hdr" in
      *"$token"*) : ;;
      *) echo "header comment omits: $token"; false ;;
    esac
  done
}

@test "recon.sh sources lib.sh instead of reimplementing fail/warn/info/log" {
  [ -f "$RECON" ]
  run grep -c 'source .*lib\.sh' "$RECON"
  [ "$status" -eq 0 ]
  [ "$output" != "0" ]
  run bash -c "grep -cE '^(fail|warn|info|log)\(\)' '$RECON' || true"
  [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# 14. CONTRACT COVERAGE loops (substitute for the disabled line-coverage gate)
# ---------------------------------------------------------------------------

@test "contract coverage: all 10 intents are named in a test AND in the router dispatch" {
  [ -f "$RECON" ]
  local missing_test="" missing_router="" i
  for i in text callers callees impact tests path dynamic coupling docs spans; do
    if [ -z "$(grep -lE "_recon( --[a-z-]+)* ${i} " "$BATS_TEST_FILENAME" || true)" ]; then
      missing_test="$missing_test $i"
    fi
    if [ -z "$(grep -l "$i" "$RECON" || true)" ]; then
      missing_router="$missing_router $i"
    fi
  done
  if [ -n "$missing_test" ]; then echo "intents with no test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "intents absent from recon.sh:$missing_router"; false; fi
}

@test "contract coverage: every STATUS value RH1 produces is asserted as emitted and named by the router" {
  # The list is READ from the plan's Output grammar block, never restated here,
  # so a new status cannot be added in one place and go untested in the other.
  [ -f "$PLAN" ]
  [ -f "$RECON" ]
  local line vals s missing_test="" missing_router=""
  line="$(grep -m1 '^STATUS=<' "$PLAN" || true)"
  if [ -z "$line" ]; then echo "no STATUS= grammar line in $PLAN"; false; fi
  vals="${line#STATUS=<}"
  vals="${vals%%>*}"
  for s in $(printf '%s' "$vals" | tr '|' ' '); do
    # RH1 builds neither SKIP branch: REASON=disabled is RH5's, small-repo RH3's.
    if [ "$s" = "SKIP" ]; then
      continue
    fi
    if [ -z "$(grep -l "STATUS=$s" "$BATS_TEST_FILENAME" || true)" ]; then
      missing_test="$missing_test $s"
    fi
    if [ -z "$(grep -l "$s" "$RECON" || true)" ]; then
      missing_router="$missing_router $s"
    fi
  done
  if [ -n "$missing_test" ]; then echo "STATUS values with no test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "STATUS values absent from recon.sh:$missing_router"; false; fi
}

@test "contract coverage: every REASON value RH1 produces is asserted with its status" {
  [ -f "$RECON" ]
  local r missing_test="" missing_router=""
  for r in not-installed no-index language-unsupported provider-error; do
    if [ -z "$(grep -l "REASON=$r" "$BATS_TEST_FILENAME" || true)" ]; then
      missing_test="$missing_test $r"
    fi
    if [ -z "$(grep -l "$r" "$RECON" || true)" ]; then
      missing_router="$missing_router $r"
    fi
  done
  if [ -n "$missing_test" ]; then echo "REASON values with no test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "REASON values absent from recon.sh:$missing_router"; false; fi
}

@test "contract coverage: the router header documents the full plan grammar status set" {
  [ -f "$PLAN" ]
  [ -f "$RECON" ]
  local line vals s hdr missing=""
  line="$(grep -m1 '^STATUS=<' "$PLAN" || true)"
  vals="${line#STATUS=<}"
  vals="${vals%%>*}"
  hdr="$(sed -n '1,90p' "$RECON")"
  for s in $(printf '%s' "$vals" | tr '|' ' '); do
    case "$hdr" in
      *"$s"*) : ;;
      *) missing="$missing $s" ;;
    esac
  done
  if [ -n "$missing" ]; then echo "header omits documented statuses:$missing"; false; fi
}

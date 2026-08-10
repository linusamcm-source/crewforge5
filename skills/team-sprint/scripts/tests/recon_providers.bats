#!/usr/bin/env bats
# recon_providers.bats — RED-phase contract for scripts/recon_providers.sh
# (Story RH1): one adapter function per provider, each translating an intent +
# argument into that provider's native invocation and normalising its output
# into the RH1 line grammar.
#
# recon_providers.sh is a SOURCED library, so these tests source it and call
# the adapter functions directly. The provider binaries themselves are always
# PATH-shadowed stubs under $BIN driven by files under $TMP/stub.
#
# The whole scripts dir is COPIED into $TMP/scripts for every test, so a test
# can swap graphify_ensure.sh for a counting stub and prove the graphify
# adapter shells it exactly once — and only when the .graphify_python cache is
# invalid. lib.sh resolves $SCRIPTS from its own BASH_SOURCE, so the sandbox
# copy binds the adapters to the sandbox graphify_ensure.sh with no new flag.
#
# Adapter contract pinned by this suite:
#   recon_adapter_<provider> <intent> <arg>...
#     stdout : zero or more `<path>:<line>\t<symbol>\t<relation>` result lines,
#              then exactly one trailing `TOTAL=<n>` line carrying the
#              PRE-truncation hit total (the router turns it into `COUNT=` and
#              never re-emits it). The tokensave adapter is the documented
#              exception: it emits its `STATUS=DELEGATE ...` line and no TOTAL.
#     return : 0 when the provider answered, $RECON_ADAPTER_ERROR (the
#              documented failure sentinel) when it did not — absent binary,
#              missing index, non-zero provider exit, or an MCP-only link under
#              RECON_NO_MCP=1. The router maps the sentinel to the next link.
#
# Fixtures under scripts/fixtures/recon/ were captured from the live tools on
# 2026-07-28 (CodeGraph 1.5.0, graphify 0.9.27, rtk 0.44.0).
#
# CONVENTION used by the contract-coverage loop at the bottom: every
# absent-provider test carries the literal phrase "<provider> absent" in its
# test name.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SDIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$SDIR/fixtures/recon"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  BIN="$TMP/bin"
  STUB="$TMP/stub"
  REPO="$TMP/repo"
  SBOX="$TMP/scripts"
  mkdir -p "$BIN" "$STUB" "$REPO" "$SBOX"

  ORIG_PATH="$PATH"
  export ORIG_PATH

  _link_tool jq
  _link_tool python3
  _link_tool git

  # Sandbox copy of the scripts dir. Copy whatever exists; RED-phase runs have
  # no recon_providers.sh yet and must fail on the missing source, not here.
  cp "$SDIR"/*.sh "$SBOX"/ 2>/dev/null || true

  export ENSURE_LOG="$TMP/ensure.log"

  ( cd "$REPO" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$REPO" && git init -q . >/dev/null 2>&1 )
  printf '#!/usr/bin/env bash\nonly_fn() { printf hi; }\n' > "$REPO/only.sh"
}

teardown() {
  cd /
  PATH="$ORIG_PATH"
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

_sandbox_path() { PATH="$BIN:/usr/bin:/bin"; }

# _load — source the sandbox recon_providers.sh into the current test shell.
# Guards are cleared first so a test can re-source after swapping a sibling.
_load() {
  unset SCRIPTS TEAM_SPRINT_LIB_LOADED RECON_PROVIDERS_LOADED
  # shellcheck source=/dev/null
  . "$SBOX/recon_providers.sh"
}

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
_stub_log()  { cat "$STUB/$1.log" 2>/dev/null || true; }

# _fake_python — an interpreter that satisfies graphify_ensure.sh:96-101, i.e.
# it is -x and `-c 'import graphify'` exits 0.
_fake_python() {
  printf '#!/bin/bash\nexit 0\n' > "$BIN/fakepy"
  chmod +x "$BIN/fakepy"
}

# _stub_ensure — replace the sandbox graphify_ensure.sh with a counting stub.
# $1, when given, is the interpreter path --check should persist to the cache.
_stub_ensure() {
  local py="${1:-}"
  cat > "$SBOX/graphify_ensure.sh" <<STUB
#!/usr/bin/env bash
printf 'check %s\n' "\$*" >> "\$ENSURE_LOG"
if [ -n "${py}" ]; then
  mkdir -p graphify-out
  printf '%s\n' "${py}" > graphify-out/.graphify_python
  printf 'STATUS=OK\n'
else
  printf 'STATUS=MISSING\n'
fi
exit 0
STUB
  chmod +x "$SBOX/graphify_ensure.sh"
}

_ensure_runs() {
  if [ -f "$ENSURE_LOG" ]; then
    wc -l < "$ENSURE_LOG" | tr -d ' '
  else
    printf 0
  fi
}

# _assert_grammar — every stdout line except the trailing TOTAL= marker must
# match the RH1 result grammar.
_assert_grammar() {
  local bad="" line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      TOTAL=*) continue ;;
    esac
    if ! printf '%s' "$line" | grep -qE '^[^	]+:[0-9]+	[^	]*	[^	]*$'; then
      bad="$bad | $line"
    fi
  done <<< "$output"
  if [ -n "$bad" ]; then
    echo "non-conforming adapter lines:$bad"
    false
  fi
}

_total() { printf '%s\n' "$output" | grep '^TOTAL=' | tail -1 | cut -d= -f2; }

# ---------------------------------------------------------------------------
# 1. Sourced-library house conventions
# ---------------------------------------------------------------------------

@test "recon_providers.sh is a sourced lib: shellcheck directive, load guard, no set -euo pipefail" {
  [ -f "$SDIR/recon_providers.sh" ]
  run grep -c '^# shellcheck shell=bash' "$SDIR/recon_providers.sh"
  [ "$output" != "0" ]
  run bash -c "grep -cE '^set -euo pipefail' '$SDIR/recon_providers.sh' || true"
  [ "$output" = "0" ]
  run bash -c "grep -c 'RECON_PROVIDERS_LOADED' '$SDIR/recon_providers.sh' || true"
  [ "$output" != "0" ]
}

@test "sourcing recon_providers.sh twice is a no-op and defines the failure sentinel" {
  _sandbox_path
  _load
  # Re-source WITHOUT clearing the guard: the load guard must make this inert
  # rather than tripping `set -u` the way a re-run initialiser would.
  # shellcheck source=/dev/null
  . "$SBOX/recon_providers.sh"
  [ -n "${RECON_ADAPTER_ERROR:-}" ]
  [ "$RECON_ADAPTER_ERROR" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 2. repomix adapter (rtk grep over the pack)
# ---------------------------------------------------------------------------

@test "the repomix adapter command contains rtk grep and never a bare grep or rg" {
  [ -f "$SDIR/recon_providers.sh" ]
  # Source-level: the generated invocation is explicitly rtk-prefixed.
  run grep -cE 'rtk[[:space:]]+grep' "$SDIR/recon_providers.sh"
  [ "$output" != "0" ]
  # Captured-argv level: run the adapter against a stub rtk and read back the
  # exact command string it generated, without ever running a real grep.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  local cmd
  cmd="$(_stub_log rtk)"
  [[ "$cmd" == "rtk grep "* ]]
  [[ "$cmd" == *".repomix-output.xml"* ]]
  [[ "$cmd" != *" rg "* ]]
}

@test "the text adapter converts pack offsets into source-relative coordinates across a tag boundary" {
  # pack-two-files.xml: <file path="alpha/one.sh"> at pack line 7 with a hit at
  # pack line 10 -> alpha/one.sh:3; <file path="beta/two.md"> at pack line 15
  # with a hit at pack line 19 -> beta/two.md:4. Mirrors the live pack, where
  # the agents/boundary-reviewer.md tag sits at 472 and that file's line 2 at
  # pack line 474.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha/one.sh:3"* ]]
  [[ "$output" == *"beta/two.md:4"* ]]
  [[ "$output" != *"alpha/one.sh:4"* ]]
  _assert_grammar
}

@test "text COUNT is emitted hits plus the rtk +<n> more trailer total" {
  # rtk-grep-hits.txt is a REAL truncated `rtk grep` capture against
  # pack-truncated.xml: a `40 matches in 1 files:` header, 25 result lines
  # spanning the tag boundary, then the `+15 more in` trailer.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits.txt"
  cp "$FIX/pack-truncated.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  # 25 emitted hits + "+15 more in ..." = 40
  [ "$(_total)" -eq 40 ]
  # The trailer itself is never emitted as a result line.
  [[ "$output" != *"more in"* ]]
}

@test "rtk's <n> matches in <m> files: summary header is never emitted as a result line" {
  # The header's own first field is `40 matches in 1 files` — a NON-numeric
  # prefix ahead of the `:`. A result-line test that only checks "starts with a
  # digit" arithmetic-evaluates it under set -u and kills the adapter, so every
  # real truncated rtk result set reports UNAVAILABLE REASON=provider-error.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits.txt"
  cp "$FIX/pack-truncated.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  refute_line "matches in"
  # The header is skipped, not mis-credited: the first and last emitted hits are
  # the real ones, mapped across the tag boundary.
  assert_line "alpha/one.sh:2"
  assert_line "beta/two.md:6"
  _assert_grammar
}

@test "rtk exiting 1 with no output is zero hits, not a provider error" {
  # `rtk grep` follows grep(1): exit 1 means "no match". Mapping it to the
  # failure sentinel makes the commonest negative query on the single-link
  # `text` chain report UNAVAILABLE REASON=provider-error, blaming a provider
  # that worked perfectly.
  _install_stub rtk
  _stub_exit rtk 1
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text zzzz_no_such_string_zzzz
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 0 ]
}

@test "rtk exiting above 1 is a real failure and returns the sentinel" {
  _install_stub rtk
  _stub_exit rtk 2
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
}

@test "rtk exiting 1 while still printing hits is a real failure and returns the sentinel" {
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  _stub_exit rtk 1
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
}

@test "text COUNT with no rtk trailer is the emitted hit count" {
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 2 ]
}

@test "the text adapter ignores a <file path= mention buried in prose, tag index is anchored" {
  # pack-phantom-tag.xml: the ONLY real tag is <file path="alpha/one.sh"> at
  # pack line 7; pack line 9 is prose that quotes `<file path="decoy/x.ts">`
  # mid-line. An unanchored tag index credits the hit at pack line 10 to
  # decoy/x.ts:1 — a path that does not exist, at a line that is not its line.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-phantom.txt"
  cp "$FIX/pack-phantom-tag.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  # assert_line / refute_line, not `[[ ]]`: bash 3.2's errexit does not fire on
  # a failing `[[ ]]`, so a non-final `[[ ]]` never fails a bats test.
  assert_line "alpha/one.sh:3"
  refute_line "decoy"
  _assert_grammar
}

@test "hits the tag index cannot attribute return the sentinel, never a confident TOTAL=0" {
  # pack-no-anchored-tags.xml carries the SAME two files at the same offsets as
  # pack-two-files.xml, but in a pack style whose file markers are markdown
  # headings — so the anchored `^<file path="…">$` index finds nothing and
  # every real hit is dropped as unattributable.
  #
  # Zero attributed rows over non-empty hits is "I cannot read this output",
  # not "nothing found". Reporting TOTAL=0 makes the single-link `text` chain
  # print STATUS=EMPTY COUNT=0 — stamped FRESHNESS=fresh — over hits rtk really
  # returned, which is the worst failure this router has. recon_adapter_graphify
  # already carries this exact rule for output its normaliser cannot read.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-no-anchored-tags.xml" "$REPO/.repomix-output.xml"
  # The hits are REAL …
  [ "$(grep -c . "$FIX/rtk-grep-hits-no-trailer.txt")" -eq 2 ]
  # … and the pack carries no anchored tag for the indexer to attribute them to.
  run bash -c "grep -c '^<file path=\"[^\"]*\">\$' '$FIX/pack-no-anchored-tags.xml' || true"
  [ "$output" = "0" ]

  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  refute_line "TOTAL=0"

  # CONTROL — the same hits over a pack the indexer CAN read stay an answer, so
  # this is a rule about unreadable packs and not a blanket failure.
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  run recon_adapter_repomix text marker
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 2 ]
}

@test "genuinely empty rtk output over an unreadable pack is still TOTAL=0, not the sentinel" {
  # The mirror of the case above: no hits at all is an ANSWER (STATUS=EMPTY
  # COUNT=0) whatever the pack's style, so the new rule must key on
  # "hits arrived and none could be attributed", never on "the pack has no tags".
  _install_stub rtk
  _stub_exit rtk 1
  cp "$FIX/pack-no-anchored-tags.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text zzzz_no_such_string_zzzz
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 0 ]
}

@test "the repomix adapter resolves the pack from RECON_ROOT, not from the caller's CWD" {
  # The router probes the pack at its resolved repo root; an adapter that
  # resolves it from CWD reports UNAVAILABLE REASON=provider-error from any
  # subdirectory for a query that answers OK from the root.
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  mkdir -p "$REPO/sub"
  _sandbox_path
  _load
  cd "$REPO/sub"
  export RECON_ROOT="$REPO"
  run recon_adapter_repomix text marker
  unset RECON_ROOT
  [ "$status" -eq 0 ]
  assert_line "alpha/one.sh:3"
  assert_line "beta/two.md:4"
}

@test "repomix absent: no rtk on PATH returns the failure sentinel and never aborts the shell" {
  cp "$FIX/pack-two-files.xml" "$REPO/.repomix-output.xml"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  # The caller shell survived the adapter call.
  printf 'still alive\n' | grep -q alive
}

@test "repomix with the pack absent returns the failure sentinel" {
  _install_stub rtk
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_repomix text marker
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
}

# ---------------------------------------------------------------------------
# 3. graphify adapter — .graphify_python cache reuse
# ---------------------------------------------------------------------------

@test "a VALID .graphify_python cache skips interpreter detection entirely" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq 0 ]
  [ "$(_ensure_runs)" -eq 0 ]
}

@test "a STALE .graphify_python cache pointing at a deleted path re-runs detection" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out"
  cp "$FIX/graphify-python-stale" "$REPO/graphify-out/.graphify_python"
  [ ! -x "$(cat "$REPO/graphify-out/.graphify_python")" ]
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq 0 ]
  [ "$(_ensure_runs)" -eq 1 ]
}

@test "with no cache the adapter shells graphify_ensure.sh --check exactly once and re-reads the cache" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq 0 ]
  [ "$(_ensure_runs)" -eq 1 ]
  grep -q -- '--check' "$ENSURE_LOG"
  [ -f "$REPO/graphify-out/.graphify_python" ]
}

@test "graphify absent: no interpreter after --check returns the sentinel and never crashes" {
  _stub_ensure ""
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  [ "$(_ensure_runs)" -eq 1 ]
  printf 'still alive\n' | grep -q alive
}

@test "the graphify adapter normalises explain output into the RH1 grammar" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"skills/team-sprint/scripts/state.sh:8"* ]]
  [[ "$output" == *"skills/team-sprint/scripts/lib.sh:21"* ]]
  [ "$(_total)" -eq 6 ]
}

@test "the graphify adapter normalises query output for the docs intent" {
  # `graphify query` emits `NODE <name> [src=<path> loc=L<n> …]`, never the
  # connection lines `explain` emits. Dropping every row here is how a live,
  # 62-node answer became STATUS=EMPTY COUNT=0.
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-query.txt"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify docs "what does lib.sh do"
  [ "$status" -eq 0 ]
  _assert_grammar
  assert_line "skills/team-sprint/scripts/lib.sh:21"
  assert_line "fail()"
  assert_line "agents/go-architect.md:48"
  # Node names carrying spaces survive as one symbol field.
  assert_line "Stack Knowledge (inherited)"
  # The traversal header and the TRUNCATED advisory are never result lines.
  refute_line "Traversal:"
  refute_line "token budget"
  [ "$(_total)" -eq 8 ]
}

@test "graphify stdout the normaliser cannot parse is the failure sentinel, never a silent zero" {
  # A provider that answered but in a shape we cannot read is "I do not know",
  # so the chain must advance. Reporting it as zero results would let the
  # router emit a confident EMPTY over a real answer.
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  printf 'Some future graphify output format nobody taught us to read.\n' \
    > "$STUB/graphify.out"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  refute_line "TOTAL=0"
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
}

@test "a genuinely empty graphify answer stays an answer: no result lines and TOTAL=0" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  : > "$STUB/graphify.out"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 0 ]
}

@test "the graphify adapter reads its interpreter cache from RECON_ROOT, not from the caller's CWD" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$REPO/graphify-out" "$REPO/sub"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO/sub"
  export RECON_ROOT="$REPO"
  run recon_adapter_graphify spans lib.sh
  unset RECON_ROOT
  [ "$status" -eq 0 ]
  # The root's VALID cache was found from the subdirectory, so detection did
  # not re-run.
  [ "$(_ensure_runs)" -eq 0 ]
}

@test "the graphify adapter runs the CLI from RECON_ROOT, not from the caller's CWD" {
  # graphify resolves graphify-out/graph.json relative to $PWD, so pinning only
  # the artifact PATHS to RECON_ROOT is not enough: the CLI itself must be
  # invoked from the root. Otherwise the same query answers OK from the root and
  # UNAVAILABLE REASON=provider-error from any subdirectory.
  _fake_python
  _stub_ensure "$BIN/fakepy"
  # A graphify that behaves like the real one: it refuses unless the graph sits
  # under its own CWD.
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
  cp "$FIX/graphify-explain.txt" "$STUB/graphify.out"
  cp "$FIX/graphify-graph.json" "$REPO/graphify-out/graph.json"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO/sub"
  export RECON_ROOT="$REPO"
  run recon_adapter_graphify spans lib.sh
  unset RECON_ROOT
  [ "$status" -eq 0 ]
  assert_line "skills/team-sprint/scripts/lib.sh:21"
}

@test "a non-zero graphify exit returns the failure sentinel and emits no result lines" {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_exit graphify 1
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_graphify spans lib.sh
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# 3b. graphify adapter — edge DIRECTION and RELATION are the answer
#
# `explain` prints one connection per edge, prefixed with the direction marker:
# `<--` is INBOUND (something points at the node) and `-->` is OUTBOUND. Answering
# `callees` with the inbound set is a confident, WRONG answer, which is worse than
# no answer at all, so the marker is parsed AND used rather than parsed and
# dropped. A file-`defines` edge is likewise not a call: counting it made a symbol
# with no known callers report COUNT=1 pointing at its own definition.
#
# Both fixtures were captured from the live graphify 0.9.27 over this repo on
# 2026-07-28: `explain require_jq` (1 inbound defines, 3 inbound calls, 1 outbound
# call) and `explain repo_root` (a single inbound defines and nothing else).
# ---------------------------------------------------------------------------

# _graphify_fixture <fixture> — a graphify stub answering with <fixture>, a valid
# interpreter cache, and the sandbox PATH loaded. Every 3b test needs the same
# five lines.
_graphify_fixture() {
  _fake_python
  _stub_ensure "$BIN/fakepy"
  _install_stub graphify
  _stub_out graphify "$1"
  mkdir -p "$REPO/graphify-out"
  printf '%s\n' "$BIN/fakepy" > "$REPO/graphify-out/.graphify_python"
  _sandbox_path
  _load
  cd "$REPO"
}

@test "callers answers with the INBOUND edges only, and never counts a defines edge" {
  _graphify_fixture "$FIX/graphify-explain-require-jq.txt"
  run recon_adapter_graphify callers require_jq
  [ "$status" -eq 0 ]
  _assert_grammar
  # The three `<-- … [calls]` rows, and only those.
  assert_line "skills/team-sprint/scripts/preflight_subskills.sh:132"
  assert_line "skills/team-sprint/scripts/preflight_subskills.sh:81"
  assert_line "skills/team-sprint/scripts/run_subskill_hooks.sh:80"
  # `_hint_jq()` is what require_jq CALLS, not what calls it.
  refute_line "_hint_jq"
  # A file defining a symbol is not a caller of it.
  refute_line "defines"
  [ "$(_total)" -eq 3 ]
}

@test "callees answers with the OUTBOUND edges only, never callers' answer verbatim" {
  _graphify_fixture "$FIX/graphify-explain-require-jq.txt"
  run recon_adapter_graphify callers require_jq
  [ "$status" -eq 0 ]
  local callers_out="$output"
  run recon_adapter_graphify callees require_jq
  [ "$status" -eq 0 ]
  _assert_grammar
  # Byte-identical bodies for "what calls X" and "what does X call" is the
  # cardinal sin: one of the two is confidently wrong.
  [ "$output" != "$callers_out" ]
  assert_line "_hint_jq"
  refute_line "preflight_subskills.sh"
  refute_line "run_subskill_hooks.sh"
  refute_line "defines"
  [ "$(_total)" -eq 1 ]
}

@test "impact answers with BOTH directions, still without the defines edge" {
  _graphify_fixture "$FIX/graphify-explain-require-jq.txt"
  run recon_adapter_graphify impact require_jq
  [ "$status" -eq 0 ]
  _assert_grammar
  assert_line "_hint_jq"
  assert_line "_cache_lookup"
  assert_line "skills/team-sprint/scripts/run_subskill_hooks.sh:80"
  refute_line "defines"
  [ "$(_total)" -eq 4 ]
}

@test "a symbol whose ONLY edge is its own defines is not a confident callers answer" {
  # graphify's bash call graph is incomplete — this repo has functions with real
  # call sites and zero inbound call edges — so answering STATUS=OK COUNT=1 over
  # the definition edge is a false positive that reads as a complete answer.
  # The sentinel advances the chain instead; silence must never read as safe.
  _graphify_fixture "$FIX/graphify-explain-defines-only.txt"
  run recon_adapter_graphify callers repo_root
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  [ -z "$output" ]
}

@test "the direction filter is intent-scoped: spans over the same fixture still sees every edge" {
  # `spans` asks which files a feature touches, so a defines edge IS an answer.
  # A filter applied globally would turn this into the sentinel too.
  _graphify_fixture "$FIX/graphify-explain-defines-only.txt"
  run recon_adapter_graphify spans repo_root
  [ "$status" -eq 0 ]
  _assert_grammar
  assert_line "defines"
  [ "$(_total)" -eq 1 ]
}

@test "contract coverage: every call-graph intent is exercised and both direction markers are fixtured" {
  local i missing="" m
  for i in callers callees impact; do
    grep -l "recon_adapter_graphify $i " "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
      || missing="$missing $i"
  done
  if [ -n "$missing" ]; then echo "call-graph intents never exercised here:$missing"; false; fi
  # The mixed fixture must really carry both markers, or the direction
  # assertions above are measuring a one-sided fixture.
  for m in '<--' '-->'; do
    grep -q -- "$m" "$FIX/graphify-explain-require-jq.txt" \
      || { echo "fixture carries no $m row"; false; }
  done
  # And the adapter must USE the marker, not merely capture it: over ONE mixed
  # fixture the three intents must each answer a different row count. A textual
  # grep for the capture group would pass against the code that discards it.
  _graphify_fixture "$FIX/graphify-explain-require-jq.txt"
  local seen=""
  for i in callers callees impact; do
    run recon_adapter_graphify "$i" require_jq
    [ "$status" -eq 0 ]
    seen="$seen $(_total)"
  done
  [ "$seen" = " 3 1 4" ] \
    || { echo "callers/callees/impact row counts are$seen, expected 3 1 4"; false; }
}

# ---------------------------------------------------------------------------
# 4. codegraph adapter — JSON normalisation and body stripping
# ---------------------------------------------------------------------------

@test "the codegraph adapter normalises callers --json output into the RH1 grammar" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers parseToken
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"src/auth/session.ts:58"* ]]
  [[ "$output" == *"authenticate"* ]]
  [[ "$output" == *"src/auth/refresh.ts:17"* ]]
  [ "$(_total)" -eq 2 ]
}

@test "the codegraph adapter passes -j on every subcommand that offers it, and never on the ones that do not" {
  # Without -j the real CLI answers in decorated text, the JSON branch is dead
  # and the symbol column comes back empty. The stub cats its fixture whatever
  # argv it gets, so only a captured-argv assertion can see this — the same way
  # the repomix test asserts `rtk grep `.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers.json"
  _sandbox_path
  _load
  cd "$REPO"
  local intent
  for intent in callers callees impact tests; do
    : > "$STUB/codegraph.log"
    run recon_adapter_codegraph "$intent" parseToken
    [ "$status" -eq 0 ]
    if ! printf '%s' "$(_stub_log codegraph)" | grep -q -- ' -j'; then
      echo "codegraph $intent invocation carries no -j: $(_stub_log codegraph)"
      false
    fi
  done
  # `codegraph explore` and `codegraph node` have no --json option; passing one
  # would make the real CLI reject the invocation outright.
  : > "$STUB/codegraph.log"
  _stub_out codegraph "$FIX/codegraph-explore.txt"
  run recon_adapter_codegraph dynamic "token parsing"
  [ "$status" -eq 0 ]
  if printf '%s' "$(_stub_log codegraph)" | grep -q -- ' -j'; then
    echo "codegraph explore invocation must not carry -j: $(_stub_log codegraph)"
    false
  fi
}

@test "the codegraph explore fixture yields declaring file:line and none of its body text" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-explore.txt"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph dynamic "token parsing"
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"src/auth/session.ts:40"* ]]
  [[ "$output" == *"src/auth/refresh.ts:17"* ]]
  [[ "$output" != *"SECRET_SAUCE"* ]]
  [[ "$output" != *"CANARY_BODY_TEXT"* ]]
  [[ "$output" != *"decodeBase64Payload(raw)"* ]]
  [[ "$output" != *'```'* ]]
}

@test "the codegraph node fixture yields declaring file:line and none of its body text" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-node.txt"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph dynamic parseToken
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"src/auth/session.ts:40"* ]]
  [[ "$output" != *"SECRET_SAUCE"* ]]
  [[ "$output" != *"decodeBase64Payload(raw)"* ]]
  [[ "$output" != *'```'* ]]
}

@test "codegraph's explicit not-found answer takes the failure sentinel, never zero rows" {
  # CodeGraph 1.5.0 exits 0 for BOTH of these and distinguishes them only in its
  # stdout (captured live 2026-07-28 from a JS repo carrying a real index):
  #   codegraph callers m1   -j  -> {"symbol":"m1","callers":[]}      the symbol is
  #                                 indexed and nothing calls it — an ANSWER
  #   codegraph callers nope -j  -> ℹ Symbol "nope" not found         I have no such
  #                                 symbol — "I do not know"
  # The second is what codegraph says about EVERY symbol of a language it has no
  # grammar for (it ships none for shell), so normalising it to zero rows dresses
  # "I never parsed that language" up as "there are no callers". Silence reads as
  # safe-to-change, which is the worst failure this router can have.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-not-found.txt"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers helper
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  case "$output" in
    *TOTAL=*) echo "the not-found answer was emitted as a row count: $output"; false ;;
  esac
}

@test "a codegraph symbol with an empty callers array stays an answer: TOTAL=0" {
  # The other half of the same contract: genuinely empty provider output is an
  # ANSWER (the router prints STATUS=EMPTY COUNT=0) and must NOT take the
  # sentinel, or every uncalled symbol would walk the whole chain reporting
  # UNAVAILABLE. Fixture captured from the same live index as the one above.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers-empty.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers m1
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 0 ]
}

@test "the codegraph affected --json shape is normalised into rows, never TOTAL=0" {
  # `tests` maps to `affected -j` (_recon_codegraph_argv), whose payload carries
  # NEITHER filePath NOR startLine — it names its answer in a flat
  # `affectedTests` array of paths. A normaliser that only knows the
  # filePath+startLine shape read that real answer as zero rows, and EMPTY is
  # terminal in recon_resolve, so the tokensave link behind it never fired: a
  # confident STATUS=EMPTY COUNT=0 over a provider that answered. Fixture
  # captured live from CodeGraph 1.5.0 on 2026-07-28.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-affected.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph tests src/auth/session.js
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"test/auth/session.test.js:1"* ]]
  [ "$(_total)" -eq 1 ]
}

@test "a codegraph affected answer naming no tests stays an answer: TOTAL=0" {
  # The recognised-empty half of the same contract, captured from the same live
  # index: `affectedTests: []` IS an answer and must not take the sentinel, or
  # every untested file would walk the whole chain reporting UNAVAILABLE.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-affected-empty.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph tests nope.js
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 0 ]
}

@test "the codegraph impact --json shape is normalised into rows" {
  # `impact`/`path` map to `impact -j`, whose answer sits under `affected` as
  # filePath+startLine objects. Captured live alongside the `affected -j` one so
  # both JSON subcommands the argv map issues have a fixture.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-impact.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph impact parseToken
  [ "$status" -eq 0 ]
  _assert_grammar
  [[ "$output" == *"src/auth/session.js:1"* ]]
  [[ "$output" == *"test/auth/session.test.js:1"* ]]
  [ "$(_total)" -eq 3 ]
}

@test "codegraph JSON in a shape this normaliser cannot read takes the sentinel, never zero rows" {
  # The JSON branch's own "output we cannot read" case, and the rule that makes
  # the two tests above safe: only a RECOGNISED result key may answer zero. A
  # payload carrying none of them is "I do not know" — a new subcommand, a
  # schema bump, another tool's JSON — and takes the sentinel so the chain
  # advances, exactly as the markdown branch and recon_adapter_graphify do.
  # Hand-written, not captured: the point is a shape the adapter has never seen.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-unknown-shape.json"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers parseToken
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  case "$output" in
    *TOTAL=*) echo "an unreadable JSON shape was emitted as a row count: $output"; false ;;
  esac
}

@test "contract coverage: every codegraph JSON subcommand the argv map issues has a fixture the adapter reads" {
  # Proved by looping the argv map's own subcommands against the fixture dir,
  # not by eye: a subcommand added to _recon_codegraph_argv with no captured
  # payload is exactly how `affected -j` reached production unread.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _sandbox_path
  _load
  cd "$REPO"
  local intent sub missing="" unread=""
  for intent in callers callees impact tests; do
    sub="$(_recon_codegraph_argv "$intent")"
    sub="${sub%% *}"
    if [ ! -f "$FIX/codegraph-$sub.json" ]; then
      missing="$missing $sub"
      continue
    fi
    # And the fixture must be one the adapter actually READS: a payload it
    # cannot normalise answers no rows for every query on that intent.
    _stub_out codegraph "$FIX/codegraph-$sub.json"
    run recon_adapter_codegraph "$intent" parseToken
    if [ "$status" -ne 0 ] || [ "$(_total)" -lt 1 ]; then
      unread="$unread $sub"
    fi
  done
  if [ -n "$missing" ]; then echo "codegraph subcommands with no JSON fixture:$missing"; false; fi
  if [ -n "$unread" ]; then echo "codegraph fixtures the adapter reads no rows from:$unread"; false; fi
}

@test "ANSI-decorated codegraph JSON still reaches the JSON branch" {
  # codegraph colours its output even when piped — every status fixture in this
  # directory carries the escapes. A leading-character test run against the raw
  # bytes sees \033[ and not `{`, so real JSON would fall through to the markdown
  # normaliser and lose every row it carries.
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  printf '\033[34m' > "$STUB/codegraph.out"
  cat "$FIX/codegraph-callers.json" >> "$STUB/codegraph.out"
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers parseToken
  [ "$status" -eq 0 ]
  [ "$(_total)" -eq 2 ]
  _assert_grammar
}

@test "a non-zero codegraph exit returns the failure sentinel and never aborts the shell" {
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_exit codegraph 1
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers parseToken
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  printf 'still alive\n' | grep -q alive
}

@test "codegraph absent: no binary on PATH returns the failure sentinel" {
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_codegraph callers parseToken
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
}

# ---------------------------------------------------------------------------
# 5. tokensave adapter — MCP-only, never executed, never named
# ---------------------------------------------------------------------------

@test "the tokensave adapter emits STATUS=DELEGATE with INTENT and JSON-parsable ARGS" {
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_tokensave coupling only_fn other_fn
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=DELEGATE"* ]]
  [[ "$output" == *"PROVIDER=tokensave"* ]]
  [[ "$output" == *"INTENT=coupling"* ]]
  local args="${output#*ARGS=}"
  [ "$args" != "$output" ]
  printf '%s' "$args" | jq -e . >/dev/null
  printf '%s' "$args" | jq -e '. | type == "object"' >/dev/null
}

@test "the tokensave adapter emits no TOOL= when no live MCP roster supplied one" {
  _sandbox_path
  _load
  cd "$REPO"
  run recon_adapter_tokensave dynamic "who handles the retry callback"
  [ "$status" -eq 0 ]
  [[ "$output" != *"TOOL="* ]]
  run bash -c "grep -c 'tokensave_' '$SDIR/recon_providers.sh' || true"
  [ "$output" = "0" ]
}

@test "tokensave absent: RECON_NO_MCP=1 skips the MCP-only link via the failure sentinel" {
  _sandbox_path
  _load
  cd "$REPO"
  export RECON_NO_MCP=1
  run recon_adapter_tokensave coupling only_fn other_fn
  unset RECON_NO_MCP
  [ "$status" -eq "$RECON_ADAPTER_ERROR" ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# 6. CONTRACT COVERAGE — every provider has a present AND an absent test
# ---------------------------------------------------------------------------

@test "contract coverage: every provider has a present-fixture test, an absent test, and its fixtures" {
  local p missing_present="" missing_absent="" stale n
  for p in repomix graphify codegraph tokensave; do
    if [ -z "$(grep -l "recon_adapter_${p} " "$BATS_TEST_FILENAME" || true)" ]; then
      missing_present="$missing_present $p"
    fi
    if [ -z "$(grep -l "^@test \".*${p} absent" "$BATS_TEST_FILENAME" || true)" ]; then
      missing_absent="$missing_absent $p"
    fi
  done
  if [ -n "$missing_present" ]; then echo "providers with no present test:$missing_present"; false; fi
  if [ -n "$missing_absent" ]; then echo "providers with no absent test:$missing_absent"; false; fi

  # The two fixtures the DoD calls out by name: the stale .graphify_python
  # cache must point at a path that no longer exists, and the fixture pack must
  # carry at least two <file path=…> tags so offset mapping is exercised across
  # a tag boundary.
  [ -f "$FIX/graphify-python-stale" ]
  stale="$(cat "$FIX/graphify-python-stale")"
  [ -n "$stale" ]
  [ ! -e "$stale" ]
  [ -f "$FIX/pack-two-files.xml" ]
  n="$(grep -c '<file path=' "$FIX/pack-two-files.xml" || true)"
  [ "$n" -ge 2 ]
}

@test "contract coverage: all four providers are implemented as adapters in recon_providers.sh" {
  [ -f "$SDIR/recon_providers.sh" ]
  local p missing=""
  for p in repomix graphify codegraph tokensave; do
    if [ -z "$(grep -l "recon_adapter_${p}()" "$SDIR/recon_providers.sh" || true)" ]; then
      missing="$missing $p"
    fi
  done
  if [ -n "$missing" ]; then echo "adapters missing from recon_providers.sh:$missing"; false; fi
}

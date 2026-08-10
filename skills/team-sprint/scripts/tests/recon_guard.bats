#!/usr/bin/env bats
# recon_guard.bats — RED-phase contract for Story RH3: the small-repo guard,
# the not-a-repo guard and the per-provider FRESHNESS contract in recon.sh.
#
# Every test builds its OWN repo, because the thing under test is the TRACKED
# FILE COUNT: a shared fixture repo cannot carry 19 files and 20 files at once.
# `_mkrepo <dir> <n> <ext>` asserts the fixture really tracks exactly <n> files,
# so a `FILES=<n>` assertion measures the guard and never the fixture.
#
# The sandbox PATH is "$BIN:/usr/bin:/bin", exactly as recon.bats does it — the
# only way to make codegraph/graphify/rtk genuinely ABSENT on a machine where
# all three live in /opt/homebrew/bin. jq / python3 / git are symlinked into
# $BIN so lib.sh still works, and /bin/bash there is 3.2.57, so the sandbox
# enforces the bash-3.2 house rule for free.
#
# Two seams make the "never shells an unscoped find" ACs assertable without
# reading the implementation: $BIN/find logs every invocation and then execs the
# real find, and $BIN/git can be swapped for a stub that fails `ls-files` alone
# (exit 128) while passing every other subcommand through to the real git.
#
# Several ACs restate behaviour RH1 already satisfies (a `text` query works, an
# unknown intent answers NO_INTENT_MATCH, `tests` delegates). Those tests carry
# a CONTROL assertion in the SAME repo — the structural query that must SKIP —
# because without it the test cannot tell "the guard exempts this" from "there
# is no guard at all", which is precisely what RH3 adds.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RECON="$SCRIPTS/recon.sh"
  FIX="$SCRIPTS/fixtures/recon"
  PLAN="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/docs/plans/recon-harness-1.md"
  # The worktree's OWN graphify index — a genuine 3453-node graph, not the
  # 804-byte fixture. AC "graphify freshness is asserted against a real
  # graphify-out/graph.json and not by forced-mtime fixture alone".
  REAL_GRAPH="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)/graphify-out/graph.json"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  BIN="$TMP/bin"
  STUB="$TMP/stub"
  mkdir -p "$BIN" "$STUB"
  : > "$STUB/find.log"

  REAL_GIT="$(command -v git 2>/dev/null || printf '/usr/bin/git')"
  _link_tool jq
  _link_tool python3
  _link_tool git
  _install_find_probe
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

# _install_find_probe — a PATH-shadowing `find` that records every invocation
# and then runs the real one. The not-a-repo AC asserts the generated command
# string is EMPTY; the git-failure AC asserts it is rooted at the validated
# repo path and never at `/` or $HOME (CLAUDE.md: never run find from / or ~).
_install_find_probe() {
  cat > "$BIN/find" <<STUB
#!/bin/bash
printf 'find [cwd=%s] %s\n' "\$PWD" "\$*" >> "$STUB/find.log"
exec /usr/bin/find "\$@"
STUB
  chmod +x "$BIN/find"
}

# _find_never_rooted_at_slash_or_home — no logged find has `/` or \$HOME as its
# search root, whether passed as an argument or inherited as the CWD by a
# `cd "\$root" && find .` form (CLAUDE.md: never run find from / or ~).
_find_never_rooted_at_slash_or_home() {
  if grep -E " /( |$)|cwd=/\]| $HOME( |$)|cwd=$HOME\]" "$STUB/find.log" >/dev/null 2>&1; then
    echo "find rooted at / or \$HOME:"
    cat "$STUB/find.log"
    false
  fi
}

# _stub_git_ls_files_fail — git that exits 128 for `ls-files` and passes every
# other subcommand through to the real binary, so the repo stays a real repo
# while the guard's file count fails. Failing ALL of git would trip the
# not-a-repo branch instead and never reach the count.
_stub_git_ls_files_fail() {
  rm -f "$BIN/git"
  cat > "$BIN/git" <<STUB
#!/bin/bash
for a in "\$@"; do
  if [ "\$a" = ls-files ]; then exit 128; fi
done
exec $REAL_GIT "\$@"
STUB
  chmod +x "$BIN/git"
}

# _mkrepo <dir> <n> <ext> — a git repo tracking EXACTLY <n> files of <ext>.
# The trailing assertion is deliberate: an off-by-one fixture would turn a
# FILES=<n> assertion into a measurement of this helper.
_mkrepo() {
  local d="$1" n="$2" ext="$3" i=1 tracked
  mkdir -p "$d"
  ( cd "$d" && git init -q -b main . >/dev/null 2>&1 ) \
    || ( cd "$d" && git init -q . >/dev/null 2>&1 )
  while [ "$i" -le "$n" ]; do
    printf '#!/usr/bin/env bash\nfn_%s() { printf hi; }\n' "$i" > "$d/f$i.$ext"
    i=$((i + 1))
  done
  ( cd "$d" && git add -- ./*."$ext" >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 ) || true
  tracked="$( cd "$d" && git ls-files | wc -l | tr -d ' ' )"
  if [ "$tracked" -ne "$n" ]; then
    echo "fixture error: $d tracks $tracked files, expected $n"
    false
  fi
}

# _config <dir> <line>... — write team-sprint.config.yaml. It is left UNTRACKED
# on purpose (as the live one is, matched by .gitignore's /* whitelist rule), so
# writing a config never perturbs the tracked-file count the guard measures.
_config() {
  local d="$1"
  shift
  printf '%s\n' "$@" > "$d/team-sprint.config.yaml"
}

# _age_file <file> <minutes> — set the mtime <minutes> in the past to the
# SECOND. touch -t's [[CC]YY]MMDDhhmm[.SS] form is honoured by BSD and GNU
# alike; truncating to the minute instead would leave the computed age
# straddling <n> and <n>+1 and make `stale:300m` flaky.
_age_file() {
  local f="$1" mins="$2" ts
  ts="$(python3 -c 'import sys, time; print(time.strftime("%Y%m%d%H%M.%S", time.localtime(time.time() - int(sys.argv[1]) * 60)))' "$mins")"
  touch -t "$ts" "$f"
}

# _install_stub <name> — PATH-shadow a provider binary, driven by
# $STUB/<name>.out / .exit and, for codegraph, $STUB/codegraph.status. Every
# invocation appends to $STUB/<name>.log so a test can assert a provider was —
# or was NOT — executed. Same shape as recon.bats:95.
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

_stub_out() { cp "$2" "$STUB/$1.out"; }
_not_ran()  { [ ! -s "$STUB/$1.log" ]; }
_runs() {
  if [ -f "$STUB/$1.log" ]; then
    wc -l < "$STUB/$1.log" | tr -d ' '
  else
    printf 0
  fi
}

# _caps_provider / _write_caps_in — the capability cache the router reads,
# carrying the real stub's (binary, mtime, size) triple so a router that
# revalidates the triple sees an unchanged cache (recon.bats:131).
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

_write_caps_in() {
  local d="$1"
  shift
  mkdir -p "$d/.recon"
  printf '%s\n' "$@" | jq -s '{providers: add, resolved_at:(now|floor)}' \
    > "$d/.recon/capabilities.json"
}

# _bin_without_python3 — echo a PATH directory holding everything the router
# needs EXCEPT python3. /usr/bin/python3 exists on stock macOS, so the sandbox
# PATH "$BIN:/usr/bin:/bin" cannot make the interpreter genuinely absent;
# curating one directory can, and the trailing assertion proves it did.
_bin_without_python3() {
  local d="$TMP/nopy" f n
  mkdir -p "$d"
  for f in /bin/*; do
    ln -sf "$f" "$d/$(basename "$f")"
  done
  for n in git jq sed awk grep tr wc sort uniq head tail cut basename dirname \
           mktemp stat env touch xargs; do
    f="$(PATH=/usr/bin:/bin command -v "$n" 2>/dev/null || true)"
    if [ -n "$f" ]; then ln -sf "$f" "$d/$n"; fi
  done
  # The sandbox's own stubs and probes win — except python3, which must not be
  # reachable from this PATH by any name.
  for f in "$BIN"/*; do
    n="$(basename "$f")"
    if [ "$n" != python3 ]; then ln -sf "$f" "$d/$n"; fi
  done
  if [ -n "$(PATH="$d" command -v python3 2>/dev/null || true)" ]; then
    echo "fixture error: python3 still resolvable from $d"
    false
  fi
  printf '%s\n' "$d"
}

# _recon_in <dir> <args...> — run recon.sh from <dir> on the sandbox PATH,
# STDOUT ONLY: the STATUS grammar is a stdout contract and lib.sh's info/warn
# go to stderr, where they must never contaminate a line-count assertion.
_recon_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>/dev/null )
}

# _recon_all_on_path <bindir> <dir> <args...> — same as _recon_all_in but on a
# caller-supplied PATH, so a test can shadow a tool out of it entirely.
_recon_all_on_path() {
  local p="$1" d="$2"
  shift 2
  ( cd "$d" && PATH="$p" bash "$RECON" "$@" 2>&1 )
}

# _recon_all_in — same, but merges stderr (so an abort message is visible).
_recon_all_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>&1 )
}

_status_lines() { printf '%s\n' "$output" | grep -c '^STATUS=' || true; }
_out_lines()    { printf '%s\n' "$output" | grep -c . || true; }
_freshness()    { printf '%s\n' "$output" | grep -o 'FRESHNESS=[^ ]*' | head -1 || true; }

# ---------------------------------------------------------------------------
# 1. Small-repo guard — the 19/20 boundary, both directions
# ---------------------------------------------------------------------------

@test "AC1: 19 tracked files skips with STATUS=SKIP REASON=small-repo FILES=19 and invokes no provider" {
  local d="$TMP/r19"
  _mkrepo "$d" 19 sh
  # Both structural providers are installed and would answer; the guard sits
  # AHEAD of provider resolution, so neither may be executed at all — not even
  # by the capability probe.
  _install_stub codegraph
  _install_stub graphify

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=19"
  [ "$(_status_lines)" -eq 1 ]
  [ "$(_out_lines)" -eq 1 ]
  # The SKIP line is well-formed under the Output grammar: no header line, so
  # no FRESHNESS= and no COUNT= (plan, Output grammar block).
  refute_line "FRESHNESS="
  refute_line "COUNT="
  _not_ran codegraph
  _not_ran graphify
}

@test "AC2: 20 tracked files proceeds to provider resolution" {
  local d="$TMP/r20"
  _mkrepo "$d" 20 sh

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  refute_line "STATUS=SKIP"
  refute_line "REASON=small-repo"
  # No provider is installed, so resolution itself is what answers.
  assert_line "STATUS=DEGRADED REASON=not-installed"
  [ "$(_status_lines)" -eq 1 ]

  # The SAME call, one tracked file fewer, must flip: "proceeds at 20" is only
  # meaningful against the transition, otherwise it is satisfied by a router
  # with no guard at all.
  ( cd "$d" && git rm -q -- f20.sh >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm drop >/dev/null 2>&1 ) \
    || { echo "fixture error: could not drop a tracked file"; false; }
  [ "$( cd "$d" && git ls-files | wc -l | tr -d ' ' )" -eq 19 ]
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=19"
}

@test "AC3: text is exempt from the guard while a structural intent in the SAME repo skips" {
  local d="$TMP/rtext"
  _mkrepo "$d" 5 sh
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  # Tier 1 stays cheap at any repo size: text answers.
  run _recon_in "$d" text marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "STATUS=OK"
  refute_line "REASON=small-repo"
  [ "$(_runs rtk)" -gt 0 ]

  # CONTROL — the guard must genuinely be live in this 5-file repo, otherwise
  # "text is exempt" is indistinguishable from "no guard exists".
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"
}

@test "AC4: recon_min_files 0 disables the guard entirely" {
  local d="$TMP/rzero"
  _mkrepo "$d" 5 sh

  # CONTROL — with no config the hardcoded default of 20 skips this repo.
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"

  _config "$d" 'recon_min_files: 0'
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  refute_line "STATUS=SKIP"
  refute_line "REASON=small-repo"
  assert_line "STATUS=DEGRADED REASON=not-installed"
}

@test "AC5: evaluation order — an unknown intent in a 5-file repo is NO_INTENT_MATCH, never small-repo" {
  local d="$TMP/rorder"
  _mkrepo "$d" 5 sh

  # CONTROL — the small-repo condition is genuinely live here (step 3).
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"

  # Both conditions trip at once; intent match is step 2 and must win.
  run _recon_in "$d" frobnicate x
  [ "$status" -eq 0 ]
  assert_line "STATUS=NO_INTENT_MATCH"
  refute_line "STATUS=SKIP"
  refute_line "REASON=small-repo"
  [ "$(_status_lines)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 2. not-a-repo — root resolution precedes any find
# ---------------------------------------------------------------------------

@test "AC7: outside a git repo, callers emits one STATUS=SKIP REASON=not-a-repo FILES=0 and shells no find" {
  local d="$TMP/plain"
  mkdir -p "$d"
  # Not a repo, and deliberately no git init: repo_root() would resolve `/` here.
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" git rev-parse --is-inside-work-tree >/dev/null 2>&1 ) \
    && { echo "fixture error: $d is inside a git repo"; false; }

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=not-a-repo FILES=0"
  [ "$(_status_lines)" -eq 1 ]
  [ "$(_out_lines)" -eq 1 ]
  refute_line "FRESHNESS="
  # The generated find command string is EMPTY — no find ran at all …
  [ ! -s "$STUB/find.log" ]
  # … and in particular none rooted at / or $HOME.
  _find_never_rooted_at_slash_or_home
}

@test "AC8: a git ls-files failure (exit 128) never aborts the script under set -euo pipefail" {
  local d="$TMP/rgitfail"
  _mkrepo "$d" 25 sh
  _stub_git_ls_files_fail

  run _recon_all_in "$d" callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  refute_line "unbound variable"
  refute_line "No such file or directory"
  # A real repo above the threshold: the guard must not report not-a-repo.
  refute_line "REASON=not-a-repo"
  # The verdict was reached THROUGH the count, not by aborting before it: the
  # AC's literal capture form is `n="$(git ls-files 2>/dev/null | wc -l)" || n=0`,
  # so a dead `git ls-files` counts ZERO files and the guard SKIPS. FILES=0 is
  # what pins that; "did not abort" alone is also true of a router that never
  # counts anything, and was satisfied by a fallback that counted the wrong set.
  assert_line "STATUS=SKIP REASON=small-repo FILES=0"
}

@test "AC8: the count is TRACKED files — a git failure never inverts the verdict" {
  # The two counts STRADDLE the threshold on purpose: 5 tracked (skip) against
  # 35 in the working tree (proceed). A fallback that counted the working tree
  # would let a `git` failure turn a repo the guard must skip into a full
  # provider resolution — a failure inverting the verdict instead of failing
  # conservative.
  local d="$TMP/rstraddle" i=1
  _mkrepo "$d" 5 sh
  while [ "$i" -le 30 ]; do
    printf '#!/usr/bin/env bash\nuntracked_%s() { :; }\n' "$i" > "$d/u$i.sh"
    i=$((i + 1))
  done
  local all
  all=( "$d"/*.sh )
  [ "${#all[@]}" -eq 35 ]
  [ "$( cd "$d" && git ls-files | wc -l | tr -d ' ' )" -eq 5 ]

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"

  _stub_git_ls_files_fail
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=0"
  refute_line "STATUS=DEGRADED"
  refute_line "STATUS=UNAVAILABLE"
}

@test "AC9: the file count shells no find at all, so it is never rooted at / or \$HOME" {
  local d="$TMP/rfind"
  _mkrepo "$d" 25 sh
  _stub_git_ls_files_fail

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  # `git ls-files` is dead and a verdict still came out, so the count ran and
  # took its `|| n=0` fallback rather than shelling a working-tree find: the
  # generated find command string is EMPTY …
  [ ! -s "$STUB/find.log" ]
  # … which is the strongest form of "never rooted at / or $HOME", and the same
  # posture AC7 pins outside a repo (CLAUDE.md: never run find from / or ~).
  _find_never_rooted_at_slash_or_home
}

# ---------------------------------------------------------------------------
# 3. Config resolution — hardcoded defaults and the worktree rule
# ---------------------------------------------------------------------------

@test "AC11: with no config file the defaults are recon_min_files 20, graphify 240 and repomix 240" {
  # (a) recon_min_files -> 20: 19 skips, 20 proceeds, with no config anywhere.
  local a="$TMP/cfg19"
  _mkrepo "$a" 19 sh
  [ ! -f "$a/team-sprint.config.yaml" ]
  run _recon_in "$a" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=19"

  local b="$TMP/cfg20"
  _mkrepo "$b" 20 sh
  run _recon_in "$b" callers foo
  [ "$status" -eq 0 ]
  refute_line "REASON=small-repo"

  # (b) graphify_max_age_minutes -> 240: a 300-minute-old graph is stale.
  local g="$TMP/cfggr"
  _mkrepo "$g" 25 sh
  [ ! -f "$g/team-sprint.config.yaml" ]
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$g/graphify-out"
  cp "$FIX/graphify-graph.json" "$g/graphify-out/graph.json"
  _age_file "$g/graphify-out/graph.json" 300
  _write_caps_in "$g" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_in "$g" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  assert_line "FRESHNESS=stale:300m"

  # (c) repomix_max_age_minutes -> 240: a 300-minute-old pack is stale.
  local p="$TMP/cfgpk"
  _mkrepo "$p" 25 sh
  [ ! -f "$p/team-sprint.config.yaml" ]
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$p/.repomix-output.xml"
  _age_file "$p/.repomix-output.xml" 300
  _write_caps_in "$p" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_in "$p" text marker
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  assert_line "FRESHNESS=stale:300m"
}

@test "AC12: from a worktree CWD with no config of its own, recon_min_files comes from the main tree" {
  local main="$TMP/wtmain" wt="$TMP/wtchild"
  _mkrepo "$main" 5 sh
  ( cd "$main" && git -c user.email=t@t -c user.name=t \
      worktree add -q -b side "$wt" >/dev/null 2>&1 ) \
    || { echo "fixture error: git worktree add failed"; false; }
  [ -d "$wt" ]
  # phase-2.md copies no config into a node worktree, so the worktree CWD is
  # config-free by construction — assert the fixture really is.
  [ ! -f "$wt/team-sprint.config.yaml" ]

  _config "$main" 'recon_min_files: 0'
  run _recon_in "$wt" callers foo
  [ "$status" -eq 0 ]
  refute_line "STATUS=SKIP"
  refute_line "REASON=small-repo"

  # CONTROL — flipping ONLY the main-tree config changes the verdict from the
  # worktree CWD, which is what proves the main-tree config was read (a
  # $PWD-relative lookup would find nothing and silently use the default).
  _config "$main" 'recon_min_files: 100'
  run _recon_in "$wt" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo"
}

# ---------------------------------------------------------------------------
# 4. FRESHNESS — computed per provider against that provider's own max-age key
# ---------------------------------------------------------------------------

@test "AC13: a 300-minute-old graph against graphify_max_age_minutes 240 is FRESHNESS=stale:300m STATUS=OK" {
  local d="$TMP/fr300"
  _mkrepo "$d" 25 sh
  _config "$d" 'graphify_max_age_minutes: 240'
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$d/graphify-out"
  cp "$FIX/graphify-graph.json" "$d/graphify-out/graph.json"
  _age_file "$d/graphify-out/graph.json" 300
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  assert_line "FRESHNESS=stale:300m"
  # Downgraded, not an error: a stale answer with an honest label is usable.
  assert_line "STATUS=OK"
  refute_line "STATUS=UNAVAILABLE"
}

@test "AC13b: a graph written just now against the default 240 minutes is FRESHNESS=fresh" {
  # The `fresh` half of the FRESHNESS vocabulary, asserted DIRECTLY. AC14's
  # real-index case and AC16's control accept `fresh` only inside a disjunction
  # or refute it, so both stay green with `fresh` made unreachable — which is
  # how a whole documented value slipped through the coverage gate.
  local d="$TMP/frfresh"
  _mkrepo "$d" 25 sh
  # No config: the hardcoded 240-minute default. Age 0 clears it by 240
  # minutes, so this cannot straddle the boundary and cannot flake.
  [ ! -f "$d/team-sprint.config.yaml" ]
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$d/graphify-out"
  cp "$FIX/graphify-graph.json" "$d/graphify-out/graph.json"
  touch "$d/graphify-out/graph.json"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify"
  assert_line "FRESHNESS=fresh"
  assert_line "STATUS=OK"
  refute_line "FRESHNESS=stale:"
  refute_line "FRESHNESS=none"
}

@test "AC14: against the repo's REAL graphify index, spans reports fresh or stale, never FRESHNESS=none" {
  # Not a forced-mtime fixture: this is the worktree's own graph.json, copied
  # with -p so its genuine mtime survives.
  #
  # Skipped rather than failed when there is no index. graphify earns its keep
  # on call-graph reachability in source trees; $CLAUDE_CONFIG_DIR is 407 files of mostly
  # markdown and shell, which the ladder answers at Tier 0/1, so no index is
  # built here deliberately. The assertion below is still the real one wherever
  # an index does exist — this precondition is about the environment, not the
  # router.
  [ -f "$REAL_GRAPH" ] || skip "no graphify index in this repo (graphify indexes source trees, not this config repo)"
  [ "$(jq '.nodes | length' "$REAL_GRAPH")" -gt 1000 ]

  local d="$TMP/frreal"
  _mkrepo "$d" 25 sh
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$d/graphify-out"
  cp -p "$REAL_GRAPH" "$d/graphify-out/graph.json"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  refute_line "FRESHNESS=none"
  local fr
  fr="$(_freshness)"
  case "$fr" in
    FRESHNESS=fresh|FRESHNESS=stale:[0-9]*m) : ;;
    *) echo "real index reported: '$fr' (want fresh or stale:<n>m)"; false ;;
  esac
}

@test "AC15: with graphify-out absent, spans emits exactly one STATUS line, exits 0 and no FRESHNESS at all" {
  local d="$TMP/frnone"
  _mkrepo "$d" 25 sh
  [ ! -d "$d/graphify-out" ]

  run _recon_all_in "$d" spans foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  # The absent-index branch is taken BEFORE any mtime_epoch call — the helper
  # aborts under set -e on a missing file, so a `stat` error here means the
  # guard leaned on the helper instead of testing first.
  refute_line "stat:"
  refute_line "No such file or directory"
  # This is the FRESHNESS=none coverage case: the value is never emitted,
  # because a status with no header line carries no FRESHNESS= at all.
  refute_line "FRESHNESS=none"
  refute_line "FRESHNESS="

  # Below the guard threshold the same query is a well-formed SKIP line, which
  # likewise carries no FRESHNESS= and no COUNT= (plan, Output grammar block).
  local s="$TMP/frnonesmall"
  _mkrepo "$s" 5 sh
  run _recon_in "$s" spans foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"
  refute_line "FRESHNESS="
  refute_line "COUNT="
}

@test "AC16: a stale repomix pack is FRESHNESS=stale:300m and graphify_max_age_minutes cannot move it" {
  local d="$TMP/frpack"
  _mkrepo "$d" 25 sh
  _config "$d" 'repomix_max_age_minutes: 240'
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  _age_file "$d/.repomix-output.xml" 300
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" text marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "STATUS=OK"
  assert_line "FRESHNESS=stale:300m"

  # Each provider is graded against its OWN key: moving graphify's threshold
  # must not relabel a repomix-served answer.
  _config "$d" 'repomix_max_age_minutes: 240' 'graphify_max_age_minutes: 100000'
  run _recon_in "$d" text marker
  [ "$status" -eq 0 ]
  assert_line "FRESHNESS=stale:300m"
  refute_line "FRESHNESS=fresh"
}

@test "AC17: a CodeGraph answer is FRESHNESS=live only when the daemon-liveness probe succeeds" {
  local d="$TMP/frlive"
  _mkrepo "$d" 25 sh
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers.json"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" callers parseToken
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=codegraph"
  assert_line "STATUS=OK"
  assert_line "FRESHNESS=live"
}

@test "AC18: codegraph printing Not initialized on stdout (exit 0) is never labelled live" {
  local d="$TMP/frnotlive"
  _mkrepo "$d" 25 sh
  _install_stub codegraph
  # `codegraph status` exits 0 whether or not the project is initialised, so the
  # branch must read STDOUT. Reading the exit code claims `live` on a repo with
  # no daemon at all.
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers.json"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" callers parseToken
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=codegraph"
  assert_line "STATUS=OK"
  refute_line "FRESHNESS=live"
  local fr
  fr="$(_freshness)"
  case "$fr" in
    FRESHNESS=fresh|FRESHNESS=stale:[0-9]*m) : ;;
    *) echo "uninitialised codegraph reported: '$fr' (want the mtime_epoch fallback)"; false ;;
  esac
}

@test "AC17: with python3 absent the liveness probe degrades — one STATUS line, exit 0, never live" {
  # `codegraph status` is parsed by a python3 heredoc. Unguarded, an absent
  # interpreter exits the router 127 with ZERO STATUS lines, which breaks both
  # the documented exit-code contract (0 verdict / 1 bad args) and the
  # "STATUS= is mandatory and always last" grammar.
  local d="$TMP/nopy3" nobin
  _mkrepo "$d" 25 sh
  _install_stub codegraph
  # A genuinely initialised, daemon-backed project: the ONLY reason the probe
  # cannot confirm it is the missing interpreter.
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _stub_out codegraph "$FIX/codegraph-callers.json"
  nobin="$(_bin_without_python3)"

  # (a) --probe: this path parses `codegraph status` and writes the cache.
  run _recon_all_on_path "$nobin" "$d" --probe
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  refute_line "python3: command not found"
  [ -f "$d/.recon/capabilities.json" ]
  # An unparseable status block is an UNKNOWN catalogue, recorded as not
  # indexed — never as a confident language list.
  [ "$(jq -r '.providers.codegraph.indexed' "$d/.recon/capabilities.json")" = "false" ]

  # (b) the bare intent form, with the cache pre-seeded so the codegraph link
  # answers and _freshness has to grade it.
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true true '["bash"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_all_on_path "$nobin" "$d" callers parseToken
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  assert_line "STATUS=OK"
  refute_line "python3: command not found"
  # AC17 is literal: `live` only when the daemon-liveness probe SUCCEEDS. With
  # no interpreter it did not run at all, so the answer falls back to the
  # mtime computation exactly as AC18's uninitialised case does. Claiming
  # `live` here would be a verdict the router never verified.
  refute_line "FRESHNESS=live"
  local fr
  fr="$(_freshness)"
  case "$fr" in
    FRESHNESS=fresh|FRESHNESS=stale:[0-9]*m) : ;;
    *) echo "python3-absent codegraph reported: '$fr' (want the mtime fallback)"; false ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. Language filter vs the guard — a false EMPTY is the worst answer
# ---------------------------------------------------------------------------

@test "AC6a: in an all-.bats repo, tests never emits EMPTY on either side of the guard boundary" {
  # CodeGraph ships no shell grammar, so an EMPTY here would read as "asked and
  # found nothing" and would silently retire SKILL.md Phase 3/4's
  # convention-based test scoping.
  local d="$TMP/bats20"
  _mkrepo "$d" 20 bats
  _install_stub codegraph
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true true '["typescript"]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  # At the threshold the chain resolves: the codegraph link is dropped by the
  # language filter and tokensave — exempt from that filter — is terminal.
  run _recon_in "$d" tests f1.bats
  [ "$status" -eq 0 ]
  assert_line "STATUS=DELEGATE"
  assert_line "PROVIDER=tokensave"
  refute_line "STATUS=EMPTY"
  _not_ran codegraph

  # Below the threshold the guard answers first — still never EMPTY.
  local s="$TMP/bats19"
  _mkrepo "$s" 19 bats
  run _recon_in "$s" tests f1.bats
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=19"
  refute_line "STATUS=EMPTY"
}

@test "AC6b: REASON=language-unsupported only on a fully bash-probeable chain, and the guard still wins first" {
  local d="$TMP/langunsup"
  _mkrepo "$d" 25 sh
  _install_stub codegraph
  _install_stub graphify
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true true '["typescript"]')" \
    "$(_caps_provider graphify  true true '["python"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  # `callers` chains codegraph -> graphify: both bash-probeable, neither
  # indexed this repo's language.
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"
  refute_line "STATUS=EMPTY"
  [ "$(_status_lines)" -eq 1 ]

  # CONTROL — the same chain below the threshold reports the GUARD's reason,
  # never the language filter's: step 3 precedes step 4.
  local s="$TMP/langunsupsmall"
  _mkrepo "$s" 5 sh
  _write_caps_in "$s" \
    "$(_caps_provider codegraph true true '["typescript"]')" \
    "$(_caps_provider graphify  true true '["python"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_in "$s" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"
  refute_line "REASON=language-unsupported"
}

# ---------------------------------------------------------------------------
# 6. Documentation contracts (DoD)
# ---------------------------------------------------------------------------

@test "DoD: the header comment documents the threshold, its inline rationale and this plan, not union.md" {
  [ -f "$RECON" ]
  local hdr token
  hdr="$(sed -n '1,120p' "$RECON")"
  for token in 'recon_min_files' '20' 'small-repo' 'not-a-repo' 'FRESHNESS' \
               'read everything' 'overhead' 'recon-harness-1'; do
    case "$hdr" in
      *"$token"*) : ;;
      *) echo "header comment omits: $token"; false ;;
    esac
  done
  # union.md is untracked and .gitignore-matched, so it is absent from the
  # worktree where this DoD is checked and must not be the citation.
  run bash -c "grep -c 'union.md' '$RECON' || true"
  [ "$output" = "0" ]
}

@test "DoD: the plan's REASON vocabulary and FILES rule gain not-a-repo in BOTH places" {
  [ -f "$PLAN" ]
  # (1) The Output grammar block's closed REASON= vocabulary.
  run bash -c "grep 'Closed vocabulary' '$PLAN' | grep -c 'not-a-repo' || true"
  [ "$output" != "0" ]
  # (2) The FILES= rule widens beyond small-repo.
  run bash -c "grep 'FILES=<n>' '$PLAN' | grep -c 'not-a-repo' || true"
  [ "$output" != "0" ]
  # (3) The coverage-gate section's REASON= list, so the two cannot drift.
  run bash -c "grep 'Every .REASON=. value' '$PLAN' | grep -c 'not-a-repo' || true"
  [ "$output" != "0" ]
}

# ---------------------------------------------------------------------------
# 7. CONTRACT COVERAGE loops (substitute for the disabled line-coverage gate)
# ---------------------------------------------------------------------------

# _recon_body — recon.sh with its header comment block stripped. The loops
# below grep THIS, not the whole file: the header already lists every
# FRESHNESS= and REASON= value as documentation, so grepping the file would let
# a value be documented and never computed — exactly the drift the gate exists
# to catch.
_recon_body() { sed -n '/^set -euo pipefail/,$p' "$RECON"; }

@test "contract coverage: every FRESHNESS value is asserted in a test and computed by the router" {
  [ -f "$RECON" ]
  local v pat body missing_test="" missing_router=""
  body="$(_recon_body)"
  for v in live fresh stale: none; do
    # The test half demands the ASSERTING form, not a bare mention: a bare
    # `FRESHNESS=$v` grep is satisfied by a `refute_line` and by a disjunctive
    # `case` arm, neither of which can fail when the value stops being emitted.
    # `none` is the documented exception — the absent-index case prints no
    # header line at all, so a refutation is the only assertable form (DoD:
    # "asserted as such").
    if [ "$v" = none ]; then
      pat="refute_line \"FRESHNESS=none"
    else
      pat="assert_line \"FRESHNESS=$v"
    fi
    if [ -z "$(grep -lF "$pat" "$BATS_TEST_FILENAME" || true)" ]; then
      missing_test="$missing_test $v"
    fi
    # The router half matches the EMITTING printf, never a bare substring:
    # `fresh` also occurs in _cached_entry_fresh, _freshness_by_age, _freshness
    # and _caps_fresh, so `case $body in *fresh*` is satisfied by four function
    # names with the value itself deleted.
    case "$body" in
      *"printf '$v"*) : ;;
      *) missing_router="$missing_router $v" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "FRESHNESS values with no asserting test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "FRESHNESS values never emitted in recon.sh:$missing_router"; false; fi
}

@test "contract coverage: every REASON value RH3 emits is asserted with its status and emitted by the router" {
  [ -f "$RECON" ]
  local r body missing_test="" missing_router=""
  body="$(_recon_body)"
  for r in small-repo not-a-repo language-unsupported; do
    if [ -z "$(grep -l "REASON=$r" "$BATS_TEST_FILENAME" || true)" ]; then
      missing_test="$missing_test $r"
    fi
    case "$body" in
      *"$r"*) : ;;
      *) missing_router="$missing_router $r" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "REASON values with no test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "REASON values never emitted by recon.sh:$missing_router"; false; fi
}

@test "contract coverage: the guard boundary is fixtured on BOTH sides (19 skips, 20 proceeds)" {
  local n missing=""
  for n in 19 20; do
    if [ -z "$(grep -lF "_mkrepo \"\$d\" $n sh" "$BATS_TEST_FILENAME" || true)" ] \
       && [ -z "$(grep -lF "_mkrepo \"\$a\" $n sh" "$BATS_TEST_FILENAME" || true)" ] \
       && [ -z "$(grep -lF "_mkrepo \"\$b\" $n sh" "$BATS_TEST_FILENAME" || true)" ]; then
      missing="$missing $n"
    fi
  done
  if [ -n "$missing" ]; then echo "guard boundary sides with no fixture:$missing"; false; fi
  # …the router carries a branch that can tell the two sides apart…
  local body token
  body="$(_recon_body)"
  for token in 'recon_min_files' 'FILES='; do
    case "$body" in
      *"$token"*) : ;;
      *) echo "recon.sh has no guard branch mentioning: $token"; false ;;
    esac
  done
  # …and both verdicts are asserted, not merely fixtured.
  run bash -c "grep -c 'STATUS=SKIP REASON=small-repo FILES=19' '$BATS_TEST_FILENAME' || true"
  [ "$output" != "0" ]
  run bash -c "grep -c 'refute_line \"REASON=small-repo\"' '$BATS_TEST_FILENAME' || true"
  [ "$output" != "0" ]
}

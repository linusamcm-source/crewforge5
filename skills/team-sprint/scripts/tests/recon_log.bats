#!/usr/bin/env bats
# recon_log.bats — RED-phase contract for Story RH4: the call log at
# <main-repo-root>/.recon/calls.jsonl, the `now_ms()` producer behind
# `elapsed_ms`, the conditional `.gitignore` append and the `--explain` mode.
#
# The log is the evidence base for retiring a provider that never wins a chain,
# so the assertions here are about the RECORD, not the answer: one line per
# invocation, fixed arity, and a fixed-arity object that still parses when the
# query carries a quote, a backslash and a tab. A log line that silently drops a
# field, or a whole line that fails `jq -e .`, reads downstream as "that
# provider was never asked" — the same false negative the router's UNAVAILABLE
# branch exists to prevent.
#
# The sandbox PATH is "$BIN:/usr/bin:/bin", exactly as recon.bats:73 and
# recon_guard.bats do it — the only way to make codegraph/graphify/rtk genuinely
# ABSENT on a machine where all three live in /opt/homebrew/bin. jq / python3 /
# git are symlinked into $BIN so lib.sh still works, and /bin/bash there is
# 3.2.57, so the sandbox enforces the bash-3.2 house rule for free.
#
# Every test builds its OWN repo: the log is resolved through repo_root(), so a
# shared fixture repo cannot carry a worktree case, a read-only `.recon/` case
# and a `/*`-whitelist `.gitignore` case at once.
#
# TWO STATUS CLASSES. The plan fixes the log at eight keys
# {intent, provider, query, count, status, freshness, elapsed_ms, ts}. On the
# answer statuses (OK, EMPTY) all eight carry values. On the five non-answer
# statuses (SKIP, DEGRADED, UNAVAILABLE, NO_INTENT_MATCH, DELEGATE) `provider`,
# `count` and `freshness` are explicit JSON null — present-and-null, never
# absent. `query` is asserted PRESENT but not asserted non-null on the
# non-answer statuses: AC6 and the plan's prose name exactly `provider`,
# `count` and `freshness` as the nulls, while the DoD's "only intent status ts
# elapsed_ms carry values" enumeration omits `query` from both groups. Arity is
# what both readings agree on, so arity is what `_log_nonanswer_field` asserts
# for that one key.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RECON="$SCRIPTS/recon.sh"
  PROVIDERS="$SCRIPTS/recon_providers.sh"
  LIB_SH="$SCRIPTS/lib.sh"
  FIX="$SCRIPTS/fixtures/recon"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  BIN="$TMP/bin"
  STUB="$TMP/stub"
  mkdir -p "$BIN" "$STUB"

  _link_tool jq
  _link_tool python3
  _link_tool git
}

teardown() {
  cd /
  # The read-only-.recon case leaves a mode-500 directory behind; without this
  # `rm -rf` cannot unlink its children and the sandbox leaks into /tmp.
  chmod -R u+rwx "$TMP" 2>/dev/null || true
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

# _install_stub <name> — PATH-shadow a provider binary, driven by
# $STUB/<name>.out / .exit / .sleep and, for codegraph, $STUB/codegraph.status.
# Every invocation appends to $STUB/<name>.log so a test can assert a provider
# was — or was NOT — executed. Same shape as recon.bats:95, plus the `.sleep`
# seam AC4 needs to prove `elapsed_ms` measures real elapsed time.
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
if [ -f "$d/$name.sleep" ]; then sleep "$(cat "$d/$name.sleep")"; fi
if [ -f "$d/$name.out" ]; then cat "$d/$name.out"; fi
exit "$(cat "$d/$name.exit" 2>/dev/null || printf 0)"
STUB
  chmod +x "$BIN/$1"
  : > "$STUB/$1.out"
  printf '0\n' > "$STUB/$1.exit"
}

_stub_out()   { cp "$2" "$STUB/$1.out"; }
_stub_sleep() { printf '%s\n' "$2" > "$STUB/$1.sleep"; }
_not_ran()    { [ ! -s "$STUB/$1.log" ]; }

# _mkrepo <dir> <n> <ext> — a git repo tracking EXACTLY <n> files of <ext>. The
# trailing assertion is deliberate: an off-by-one fixture would turn a
# `FILES=<n>` assertion into a measurement of this helper (recon_guard.bats:111).
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

# _config <dir> <line>... — write team-sprint.config.yaml, left UNTRACKED as the
# live one is, so writing a config never perturbs the tracked-file count.
_config() {
  local d="$1"
  shift
  printf '%s\n' "$@" > "$d/team-sprint.config.yaml"
}

# _caps_provider <name> <available> <indexed> <languages-json> — ONE provider
# object for the capability cache, with the (binary path, mtime, size) triple
# read off the real stub so a router that revalidates the triple sees an
# unchanged cache (recon.bats:131).
_caps_provider() {
  local name="$1" avail="$2" indexed="$3" langs="$4"
  local binname="$name" bin="" mt=0 sz=0
  if [ "$name" = repomix ]; then
    binname=rtk
  fi
  if [ "$avail" = true ] && [ -x "$BIN/$binname" ]; then
    bin="$BIN/$binname"
    # GNU first: GNU reads `-f` as --file-system and EXITS 0 with unrelated
    # output, so the BSD-first form never falls through on Linux and feeds
    # a mount point into arithmetic. BSD has no `-c` and fails cleanly.
    mt="$(stat -c %Y "$bin" 2>/dev/null || stat -f %m "$bin")"
    sz="$(stat -c %s "$bin" 2>/dev/null || stat -f %z "$bin")"
  fi
  jq -n --arg n "$name" --argjson a "$avail" --argjson i "$indexed" \
        --argjson l "$langs" --arg b "$bin" --argjson m "$mt" --argjson s "$sz" \
        '{($n): {available:$a, indexed:$i, languages:$l, version:"stub",
                 binary:$b, binary_mtime:$m, binary_size:$s,
                 resolved_at:(now|floor)}}'
}

# _write_caps_in <dir> <provider-object>... — merge into .recon/capabilities.json.
_write_caps_in() {
  local d="$1"
  shift
  mkdir -p "$d/.recon"
  printf '%s\n' "$@" | jq -s '{providers: add, resolved_at:(now|floor)}' \
    > "$d/.recon/capabilities.json"
}

# _caps_none_in <dir> — every provider absent and un-indexed: the ABSENT case
# the contract-coverage gate demands be fixtured alongside the present ones.
_caps_none_in() {
  _write_caps_in "$1" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
}

# _recon_in <dir> <args...> — run recon.sh from <dir> on the sandbox PATH,
# STDOUT ONLY: the STATUS grammar is a stdout contract and lib.sh's info/warn go
# to stderr, where they must never contaminate a line-count assertion.
_recon_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>/dev/null )
}

# _recon_all_in <dir> <args...> — same, with stderr merged (the WARN cases).
_recon_all_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>&1 )
}

_status_lines() { printf '%s\n' "$output" | grep -c '^STATUS=' || true; }

# _no_header_line — no line of $output matches the ANSWER header grammar
# `PROVIDER=… INTENT=… FRESHNESS=… QUERY=…` (recon.sh:526). A mode status
# carries none, exactly as --probe carries none. Refuting a bare `FRESHNESS=`
# instead would also forbid a chain report that names each link's index
# freshness, which the AC does not forbid — and the terminal
# `STATUS=OK PROVIDER=… INTENT=…` line is required to carry those two keys.
_no_header_line() {
  if printf '%s\n' "$output" | grep -Eq '^PROVIDER=.*INTENT=.*FRESHNESS=.*QUERY='; then
    echo "--explain emitted an answer header line:"
    printf '%s\n' "$output"
    return 1
  fi
}

# _assert_closed_terminal_reason — the REASON= on $output's TERMINAL STATUS=
# line is a member of the closed vocabulary recon.sh:76-78 fixes. --explain's
# per-link reasons are a WIDER, mode-local vocabulary (`capability-mismatch`,
# `no-delegate`); the status line is not free to borrow from it, or a caller
# that parses STATUS= sees a REASON no contract lists and the two modes name
# one condition two ways. Looped against the list, never eyeballed.
_assert_closed_terminal_reason() {
  local line reason r ok=0
  line="$(printf '%s\n' "$output" | grep '^STATUS=' | tail -n 1 || true)"
  if [ -z "$line" ]; then
    echo "no terminal STATUS= line in output: $output"
    return 1
  fi
  case "$line" in
    *REASON=*) : ;;
    *) return 0 ;;
  esac
  reason="${line#*REASON=}"
  reason="${reason%% *}"
  for r in disabled small-repo not-a-repo not-installed no-index \
           language-unsupported provider-error; do
    if [ "$reason" = "$r" ]; then
      ok=1
    fi
  done
  if [ "$ok" -ne 1 ]; then
    echo "terminal line carries REASON=$reason, outside the closed vocabulary: $line"
    return 1
  fi
}

# _answer_repo <dir> — a 25-file bash repo where `spans f1.sh` is ANSWERED by a
# stubbed graphify (STATUS=OK PROVIDER=graphify FRESHNESS=fresh), the shape
# recon_guard.bats:580 uses. Gives the answer status class a producer.
_answer_repo() {
  local d="$1"
  _mkrepo "$d" 25 sh
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
}

# _empty_repo <dir> — a 25-file bash repo where `text <pattern>` is answered
# STATUS=EMPTY COUNT=0 by a stubbed rtk that matches nothing. EMPTY is an answer
# status, so its log line carries all eight fields.
_empty_repo() {
  local d="$1"
  _mkrepo "$d" 25 sh
  _install_stub rtk
  : > "$STUB/rtk.out"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"
}

# --- call-log helpers -------------------------------------------------------

_log_path()  { printf '%s\n' "$1/.recon/calls.jsonl"; }

_log_count() {
  if [ -f "$1/.recon/calls.jsonl" ]; then
    wc -l < "$1/.recon/calls.jsonl" | tr -d ' '
  else
    printf 0
  fi
}

_log_last() { tail -n 1 "$1/.recon/calls.jsonl"; }

# _log_parses <dir> — every line of the log parses under `jq -e .` (AC1).
_log_parses() {
  local d="$1" line n=0
  if [ ! -f "$d/.recon/calls.jsonl" ]; then
    echo "no call log at $d/.recon/calls.jsonl"
    return 1
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
      echo "log line $n does not parse under jq -e .: $line"
      return 1
    fi
  done < "$d/.recon/calls.jsonl"
  if [ "$n" -eq 0 ]; then
    echo "call log at $d is empty"
    return 1
  fi
}

# _log_get <dir> <field> — the last log line's <field>, `null` for JSON null.
_log_get() {
  printf '%s' "$(_log_last "$1")" | jq -r --arg k "$2" '.[$k] // "null"'
}

# _assert_logged_status <dir> <STATUS> — the last log line's .status. Named with
# the status as a LITERAL argument so the contract-coverage loop can prove every
# one of the closed seven values is asserted, by grep, not by eye.
_assert_logged_status() {
  local d="$1" want="$2" got
  got="$(printf '%s' "$(_log_last "$d")" | jq -r '.status // "<absent>"')"
  if [ "$got" != "$want" ]; then
    echo "logged status is '$got', expected '$want' — line: $(_log_last "$d")"
    return 1
  fi
}

# _log_answer_field <dir> <field> — on OK / EMPTY every one of the eight keys is
# present AND carries a value.
_log_answer_field() {
  local d="$1" f="$2" line
  line="$(_log_last "$d")"
  if ! printf '%s' "$line" | jq -e --arg k "$f" 'has($k)' >/dev/null 2>&1; then
    echo "answer-class log line is missing key '$f': $line"
    return 1
  fi
  if ! printf '%s' "$line" | jq -e --arg k "$f" '.[$k] != null' >/dev/null 2>&1; then
    echo "answer-class log line has null '$f' (must carry a value): $line"
    return 1
  fi
}

# _log_nonanswer_field <dir> <field> — on SKIP / DEGRADED / UNAVAILABLE /
# NO_INTENT_MATCH / DELEGATE the object keeps its fixed arity: `provider`,
# `count` and `freshness` are present-and-NULL (never absent — an absent key is
# indistinguishable from a writer that forgot the field), the rest carry values.
# `query` is asserted for arity only; see the header note on the two readings.
_log_nonanswer_field() {
  local d="$1" f="$2" line
  line="$(_log_last "$d")"
  if ! printf '%s' "$line" | jq -e --arg k "$f" 'has($k)' >/dev/null 2>&1; then
    echo "non-answer-class log line is missing key '$f' (must be present-and-null, not absent): $line"
    return 1
  fi
  case "$f" in
    provider|count|freshness)
      if ! printf '%s' "$line" | jq -e --arg k "$f" '.[$k] == null' >/dev/null 2>&1; then
        echo "non-answer-class log line has non-null '$f': $line"
        return 1
      fi ;;
    query)
      : ;;
    *)
      if ! printf '%s' "$line" | jq -e --arg k "$f" '.[$k] != null' >/dev/null 2>&1; then
        echo "non-answer-class log line has null '$f' (must carry a value): $line"
        return 1
      fi ;;
  esac
}

# ---------------------------------------------------------------------------
# 1. The call log — one line per invocation, at the MAIN repo root
# ---------------------------------------------------------------------------

@test "AC1: every invocation appends exactly one line to <main-repo-root>/.recon/calls.jsonl, each parsing under jq -e ." {
  local d="$TMP/one"
  _answer_repo "$d"
  [ ! -f "$(_log_path "$d")" ]

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  [ "$(_log_count "$d")" -eq 1 ]

  # A second, DIFFERENT invocation appends exactly one more — the count tracks
  # invocations, not answers, so an unanswerable query is recorded too.
  run _recon_in "$d" frobnicate x
  [ "$status" -eq 0 ]
  [ "$(_log_count "$d")" -eq 2 ]

  run _recon_in "$d" spans f2.sh
  [ "$status" -eq 0 ]
  [ "$(_log_count "$d")" -eq 3 ]

  _log_parses "$d"
}

@test "AC2: from a worktree CWD the line lands in the MAIN tree's log and the worktree holds no .recon/" {
  local main="$TMP/wtmain" wt="$TMP/wtchild"
  _answer_repo "$main"
  ( cd "$main" && git -c user.email=t@t -c user.name=t \
      worktree add -q -b side "$wt" >/dev/null 2>&1 ) \
    || { echo "fixture error: git worktree add failed"; false; }
  [ -d "$wt" ]

  # Seed one line from the main tree, then invoke from the WORKTREE CWD: the
  # main log must GROW BY ONE. repo_root() is git-common-dir based precisely so
  # every node worktree appends to the single log the main tree holds.
  run _recon_in "$main" spans f1.sh
  [ "$status" -eq 0 ]
  local before
  before="$(_log_count "$main")"
  [ "$before" -eq 1 ]

  run _recon_in "$wt" spans f1.sh
  [ "$status" -eq 0 ]
  [ "$(_log_count "$main")" -eq $((before + 1)) ]
  # A $PWD-relative resolution would create a second, invisible log here.
  [ ! -e "$wt/.recon" ]
  _log_parses "$main"
}

@test "AC3: a query carrying a double quote, a backslash and a tab round-trips byte-identically under jq -r .query" {
  local d="$TMP/hostile"
  _answer_repo "$d"
  # Built with printf so the tab is a REAL tab, not the two characters \t: a
  # hand-built log line would be unparseable on the quote alone, and the tab is
  # what a naive `printf '%s'` writer turns into an invalid raw control char.
  local q
  q="$(printf 'sa"y\\hi\tthere')"

  run _recon_in "$d" spans "$q"
  [ "$status" -eq 0 ]
  [ "$(_log_count "$d")" -eq 1 ]
  _log_parses "$d"

  local got
  got="$(printf '%s' "$(_log_last "$d")" | jq -r '.query')"
  if [ "$got" != "$q" ]; then
    echo "query did not round-trip"
    printf 'sent: %s\n' "$q" | od -c | head -3
    printf 'got : %s\n' "$got" | od -c | head -3
    false
  fi
}

@test "AC4: elapsed_ms is a non-negative integer and is strictly greater than 0 for a provider that sleeps" {
  local d="$TMP/elapsed"
  _answer_repo "$d"

  # (a) A plain invocation: a non-negative INTEGER, never a float and never a
  # `date +%s%3N`-style literal `3N` from a BSD date that does not know %3N.
  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  local ms
  ms="$(_log_get "$d" elapsed_ms)"
  if ! [[ "$ms" =~ ^[0-9]+$ ]]; then
    echo "elapsed_ms is not a non-negative integer: '$ms'"
    false
  fi
  # It must also be a JSON NUMBER, not a quoted string — `--argjson`, per the
  # plan's jq-emission convention.
  printf '%s' "$(_log_last "$d")" | jq -e '.elapsed_ms | type == "number"' >/dev/null

  # (b) A provider stubbed to sleep 1s: strictly greater than 0, and large
  # enough to prove the field measures real elapsed time rather than being a
  # hardcoded 0 (which would satisfy "non-negative integer" forever).
  local e="$TMP/elapsed-slow"
  _answer_repo "$e"
  _stub_sleep graphify 1
  run _recon_in "$e" spans f1.sh
  [ "$status" -eq 0 ]
  local slow
  slow="$(_log_get "$e" elapsed_ms)"
  [[ "$slow" =~ ^[0-9]+$ ]]
  [ "$slow" -gt 0 ]
  [ "$slow" -ge 900 ]
}

@test "AC6: a small-repo SKIP logs provider, count and freshness as present-and-null JSON null" {
  local d="$TMP/skiplog"
  _mkrepo "$d" 5 sh
  # No config: the hardcoded recon_min_files default of 20, so 5 files SKIP.
  [ ! -f "$d/team-sprint.config.yaml" ]

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"
  [ "$(_log_count "$d")" -eq 1 ]
  _log_parses "$d"
  _assert_logged_status "$d" SKIP

  # Present-and-null, not absent — the fixed-arity choice the Output grammar
  # block commits the log to. `has()` is the whole point: `.provider == null` is
  # ALSO true for a key that was never written.
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" freshness
  printf '%s' "$(_log_last "$d")" | jq -e 'has("provider") and has("count") and has("freshness")' >/dev/null
}

@test "AC7: with recon_log off nothing is appended and the normal STATUS= line still prints" {
  local d="$TMP/logoff"
  _answer_repo "$d"
  _config "$d" 'recon_log: off'

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  [ "$(_status_lines)" -eq 1 ]
  # Nothing appended: neither the file nor the directory entry is created for
  # it. `.recon/capabilities.json` still lives there, so assert on the log path.
  [ ! -e "$(_log_path "$d")" ]

  # CONTROL — the same repo with recon_log ON does log, which is what proves the
  # key was READ rather than the log never having worked in this fixture.
  _config "$d" 'recon_log: on'
  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  [ "$(_log_count "$d")" -eq 1 ]
}

@test "AC11: a read-only .recon/ degrades to STATUS=OK with a stderr WARN — logging never fails a query" {
  local d="$TMP/ro"
  _answer_repo "$d"
  [ ! -e "$(_log_path "$d")" ]
  chmod 500 "$d/.recon"

  run _recon_all_in "$d" spans f1.sh
  chmod 700 "$d/.recon"
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  [ "$(_status_lines)" -eq 1 ]
  # The query still answered: the log is an observer, never a gate.
  refute_line "STATUS=UNAVAILABLE"
  refute_line "STATUS=DEGRADED"
  # …and the failure was REPORTED, not swallowed: a log that silently stops
  # recording is the one failure mode that corrupts the evidence base without
  # ever showing up in an answer. Asserted last so the plain-bash fallback
  # runner, which does not abort a test body on the first failed assertion,
  # still reports this case red.
  assert_line "[warn]"
}

@test "AC11b: a read-only .recon/ with a COLD capability cache still prints exactly one STATUS= line and exits 0" {
  local d="$TMP/ro-cold"
  _mkrepo "$d" 25 sh
  # No capabilities.json at all, so the capability PROBE runs and cannot persist
  # — the write AC11's fixture never reaches, because it pre-writes a
  # freshly-resolved cache and _caps_fresh short-circuits the probe entirely.
  mkdir -p "$d/.recon"
  [ ! -e "$d/.recon/capabilities.json" ]
  chmod 500 "$d/.recon"

  run _recon_all_in "$d" callers foo
  chmod 700 "$d/.recon"
  # A probe that cannot write its cache is a DEGRADED route, never a crash: the
  # exit-code contract reserves 1 for bad arguments, and "STATUS= is mandatory
  # and always last" admits no invocation that prints none at all.
  [ "$status" -eq 0 ]
  refute_line "[fail]"
  assert_line "[warn]"
  [ "$(_status_lines)" -eq 1 ]
}

@test "AC11c: --probe and --explain on an unwritable .recon/ each still print exactly one STATUS= line and exit 0" {
  local d="$TMP/ro-modes"
  _mkrepo "$d" 25 sh
  mkdir -p "$d/.recon"
  chmod 500 "$d/.recon"

  run _recon_all_in "$d" --probe
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  assert_line "STATUS=DEGRADED REASON=not-installed"

  run _recon_all_in "$d" --explain callers foo
  chmod 700 "$d/.recon"
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  refute_line "[fail]"
  assert_line "STATUS=UNAVAILABLE REASON=not-installed"
}

# ---------------------------------------------------------------------------
# 2. The conditional .gitignore append
# ---------------------------------------------------------------------------

@test "AC12: .recon/ is appended to a conventional .gitignore that does not already match it" {
  local d="$TMP/gi-conv"
  _answer_repo "$d"
  cp "$FIX/gitignore-conventional" "$d/.gitignore"
  # Fixture precondition: check-ignore does NOT already match, so the append is
  # the effective act and not a redundant one.
  ( cd "$d" && ! git check-ignore -q .recon/ ) \
    || { echo "fixture error: conventional .gitignore already matches .recon/"; false; }
  local orig_lines
  orig_lines="$(wc -l < "$d/.gitignore" | tr -d ' ')"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]

  grep -q '^\.recon/' "$d/.gitignore" \
    || { echo "no .recon/ line in .gitignore:"; cat "$d/.gitignore"; false; }
  # Append, never rewrite: the original content survives unchanged as a prefix.
  head -n "$orig_lines" "$d/.gitignore" | cmp -s - "$FIX/gitignore-conventional" \
    || { echo "the original .gitignore content was modified, not appended to"; false; }
  # The EFFECT, asserted last so the plain-bash fallback runner still reports
  # this case red: a `.recon/` line that git does not honour is decoration.
  ( cd "$d" && git check-ignore -q .recon/ ) \
    || { echo ".recon/ is still not ignored after the append:"; cat "$d/.gitignore"; false; }
}

@test "AC12b: against a /*-whitelist .gitignore that already matches, the file is left byte-identical" {
  local d="$TMP/gi-wl"
  _answer_repo "$d"
  cp "$FIX/gitignore-whitelist" "$d/.gitignore"
  # Fixture precondition: `/*` already matches .recon/, so an appended line
  # would be redundant, not effective (as in $CLAUDE_CONFIG_DIR, .gitignore:8:/*).
  ( cd "$d" && git check-ignore -q .recon/ ) \
    || { echo "fixture error: whitelist .gitignore does not already match .recon/"; false; }

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]

  cmp -s "$d/.gitignore" "$FIX/gitignore-whitelist" \
    || { echo ".gitignore was modified though check-ignore already matched:"; diff "$FIX/gitignore-whitelist" "$d/.gitignore" || true; false; }

  # CONTROL — "the file was left alone" is also true of a router that never
  # touches .gitignore at all, so this case cannot pass vacuously: the append
  # must EXIST and be gated on the check-ignore predicate.
  local body
  body="$(_router_body)"
  case "$body" in
    *".gitignore"*) : ;;
    *) echo "the router never writes .gitignore — the byte-identical case is vacuous"; false ;;
  esac
  case "$body" in
    *"check-ignore"*) : ;;
    *) echo "the router never consults git check-ignore — the append is unconditional"; false ;;
  esac
}

@test "AC12c: a .gitignore whose last line has no trailing newline is appended to without corrupting that rule, and only once" {
  local d="$TMP/gi-nonl"
  _answer_repo "$d"
  cp "$FIX/gitignore-no-trailing-newline" "$d/.gitignore"
  ( cd "$d" && ! git check-ignore -q .recon/ ) \
    || { echo "fixture error: the newline-less .gitignore already matches .recon/"; false; }
  # The rule a bare `printf … >>` destroys by concatenating onto it.
  ( cd "$d" && git check-ignore -q node_modules ) \
    || { echo "fixture error: node_modules is not ignored before the append"; false; }
  local orig_bytes
  orig_bytes="$(wc -c < "$FIX/gitignore-no-trailing-newline" | tr -d ' ')"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]

  # Append, never rewrite: the original bytes survive as a prefix.
  head -c "$orig_bytes" "$d/.gitignore" | cmp -s - "$FIX/gitignore-no-trailing-newline" \
    || { echo "the newline-less .gitignore was rewritten, not appended to:"; cat "$d/.gitignore"; false; }
  # The last pre-existing rule still stands.
  ( cd "$d" && git check-ignore -q node_modules ) \
    || { echo "the append destroyed the last pre-existing rule:"; cat "$d/.gitignore"; false; }

  # Exactly once, ever: an append that never takes effect re-appends on every
  # subsequent invocation, growing a tracked file without ever ignoring .recon/.
  run _recon_in "$d" spans f2.sh
  [ "$status" -eq 0 ]
  local n
  n="$(grep -c '^\.recon/$' "$d/.gitignore" || true)"
  [ "$(printf '%s' "$n" | tr -d ' ')" -eq 1 ] \
    || { echo ".recon/ appears $n times in .gitignore:"; cat "$d/.gitignore"; false; }

  # The EFFECT, asserted last so the plain-bash fallback runner still reports
  # this case red: a `.recon/` line that git does not honour is decoration.
  ( cd "$d" && git check-ignore -q .recon/ ) \
    || { echo ".recon/ is still not ignored after the append:"; cat "$d/.gitignore"; false; }
}

# ---------------------------------------------------------------------------
# 3. --explain — the plan, never the query
# ---------------------------------------------------------------------------

@test "AC8: --explain callers foo prints the chain and the resolved command, logs nothing, runs no provider, prints one STATUS= line, exits 0" {
  local d="$TMP/explain"
  _answer_repo "$d"
  : > "$STUB/graphify.log"

  run _recon_in "$d" --explain callers foo
  [ "$status" -eq 0 ]
  # No provider executed…
  _not_ran graphify
  # …and nothing logged: --explain answers nothing, so it is not a call.
  [ ! -e "$(_log_path "$d")" ]
  # Exactly one STATUS= line, exactly as every other mode (graphify_ensure.sh:32).
  [ "$(_status_lines)" -eq 1 ]
  # The chain: both links of `callers` are named, in order.
  assert_line "codegraph"
  assert_line "graphify"
  # The resolved command — `callers` maps to graphify's `explain` subcommand
  # (recon_providers.sh:300-304), so this is the command that WOULD run. Last,
  # so the plain-bash fallback runner still reports this case red: the usage
  # block that today's `-*) usage` branch prints already names both providers.
  assert_line "graphify explain foo"
}

@test "AC9: --explain ends in STATUS=OK PROVIDER=<would-be> INTENT=<intent> when a link resolves, and carries no header line" {
  local d="$TMP/explain-ok"
  _answer_repo "$d"

  run _recon_in "$d" --explain callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  # A mode status carries no result header and no COUNT=, exactly as --probe.
  _no_header_line
  refute_line "COUNT="
  # The terminal line, asserted last so the plain-bash fallback runner still
  # reports this case red.
  assert_line "STATUS=OK PROVIDER=graphify INTENT=callers"
}

@test "AC9b: --explain ends in STATUS=UNAVAILABLE REASON=not-installed when no link resolves, and carries no header line" {
  local d="$TMP/explain-none"
  _mkrepo "$d" 25 sh
  # The ABSENT case, fixtured explicitly: no provider on the chain exists.
  _caps_none_in "$d"

  run _recon_in "$d" --explain callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  _no_header_line
  refute_line "COUNT="
  [ ! -e "$(_log_path "$d")" ]
  # Terminal line last, for the plain-bash fallback runner.
  assert_line "STATUS=UNAVAILABLE REASON=not-installed"
}

@test "AC10: --explain names every unavailable provider with a reason: not-installed, no-index, capability-mismatch, no-delegate" {
  # (a) not-installed — the binary is absent.
  local a="$TMP/ex-absent"
  _mkrepo "$a" 25 sh
  _caps_none_in "$a"
  run _recon_in "$a" --explain callers foo
  [ "$status" -eq 0 ]
  assert_line "not-installed"

  # (b) no-index — codegraph is installed but its project is not initialised.
  local b="$TMP/ex-noindex"
  _mkrepo "$b" 25 sh
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  _write_caps_in "$b" \
    "$(_caps_provider codegraph true false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_in "$b" --explain callers foo
  [ "$status" -eq 0 ]
  assert_line "no-index"

  # (c) capability-mismatch — graphify is installed and indexed, but indexed a
  # language this repo does not use. THE false-negative case: silence from a
  # provider that cannot parse the language must never read as "no callers".
  local c="$TMP/ex-lang"
  _mkrepo "$c" 25 sh
  _install_stub graphify
  mkdir -p "$c/graphify-out"
  cp "$FIX/graphify-graph.json" "$c/graphify-out/graph.json"
  _write_caps_in "$c" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["python"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  run _recon_in "$c" --explain callers foo
  [ "$status" -eq 0 ]
  assert_line "capability-mismatch"

  # (d) no-delegate — the MCP-only link under --no-delegate.
  local e="$TMP/ex-nodelegate"
  _mkrepo "$e" 25 sh
  _caps_none_in "$e"
  run _recon_in "$e" --explain --no-delegate tests foo
  [ "$status" -eq 0 ]
  assert_line "no-delegate"
}

@test "AC9c: --explain's terminal STATUS= line stays inside the closed REASON vocabulary and names the condition as intent mode does" {
  # (a) capability-mismatch — the per-link reason is --explain's own vocabulary;
  # the terminal line must use the router's, and must name the SAME condition
  # intent mode names for the identical fixture: language-unsupported.
  local c="$TMP/ex9c-lang"
  _mkrepo "$c" 25 sh
  _install_stub graphify
  mkdir -p "$c/graphify-out"
  cp "$FIX/graphify-graph.json" "$c/graphify-out/graph.json"
  _write_caps_in "$c" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["python"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$c" --explain callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  _assert_closed_terminal_reason
  # The per-link line keeps the mode-local name; only the STATUS line is mapped.
  assert_line "PROVIDER=graphify REASON=capability-mismatch"
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"

  # The same repo through the intent path: one condition, one name.
  run _recon_in "$c" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=language-unsupported"

  # (b) no-delegate — mapped to the not-installed the chain itself reports for
  # an MCP-only link skipped under --no-delegate.
  local e="$TMP/ex9c-nodelegate"
  _mkrepo "$e" 25 sh
  _caps_none_in "$e"

  run _recon_in "$e" --explain --no-delegate tests foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  _assert_closed_terminal_reason
  assert_line "PROVIDER=tokensave REASON=no-delegate"
  assert_line "STATUS=UNAVAILABLE REASON=not-installed"
}

@test "AC8b: --explain in a sub-threshold repo reports the small-repo SKIP, not a route the router would never take" {
  local d="$TMP/ex-small"
  _mkrepo "$d" 5 sh
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$d/graphify-out"
  cp "$FIX/graphify-graph.json" "$d/graphify-out/graph.json"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"
  : > "$STUB/graphify.log"

  # --explain first, so the log assertion is about --explain and not about the
  # intent-mode control below (a SKIP is itself logged).
  run _recon_in "$d" --explain callers foo
  [ "$status" -eq 0 ]
  [ "$(_status_lines)" -eq 1 ]
  _not_ran graphify
  [ ! -e "$(_log_path "$d")" ]
  # The guard is step 3 of the single evaluation order, AHEAD of chain
  # resolution, so a PROVIDER= line here advertises a path the router never
  # walks — the one thing a mode whose whole job is describing the route cannot
  # do.
  refute_line "STATUS=OK PROVIDER=graphify INTENT=callers"
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"

  # CONTROL — what the router actually does with the identical query.
  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=small-repo FILES=5"
}

@test "DoD: the recon.sh header-comment mode list names --explain" {
  # graphify_ensure.sh:32 is the convention this mirrors: every mode is listed
  # in the header block and every mode prints exactly one STATUS= line.
  local header
  header="$(sed -n '1,/^set -euo pipefail/p' "$RECON")"
  case "$header" in
    *"--explain"*) : ;;
    *) echo "recon.sh header comment does not list the --explain mode"; false ;;
  esac
}

@test "DoD: the recon.sh header comment documents the log schema split by status class" {
  local header token
  header="$(sed -n '1,/^set -euo pipefail/p' "$RECON")"
  # All eight keys, plus the two-class rule, documented where the grammar lives.
  for token in intent provider query count status freshness elapsed_ms ts \
               calls.jsonl null; do
    case "$header" in
      *"$token"*) : ;;
      *) echo "recon.sh header comment omits log-schema token: $token"; false ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# 4. Both status classes, field by field
# ---------------------------------------------------------------------------

@test "answer class (STATUS=OK): all eight log fields carry values" {
  local d="$TMP/cls-ok"
  _answer_repo "$d"

  run _recon_in "$d" spans f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
  _assert_logged_status "$d" OK
  _log_answer_field "$d" intent
  _log_answer_field "$d" provider
  _log_answer_field "$d" query
  _log_answer_field "$d" count
  _log_answer_field "$d" status
  _log_answer_field "$d" freshness
  _log_answer_field "$d" elapsed_ms
  _log_answer_field "$d" ts
  # The values are the ANSWER's, not placeholders.
  [ "$(_log_get "$d" intent)" = spans ]
  [ "$(_log_get "$d" provider)" = graphify ]
  [ "$(_log_get "$d" query)" = f1.sh ]
  [ "$(_log_get "$d" freshness)" = fresh ]
  printf '%s' "$(_log_last "$d")" | jq -e '.count | type == "number"' >/dev/null
}

@test "answer class (STATUS=EMPTY): all eight log fields carry values, count is 0" {
  local d="$TMP/cls-empty"
  _empty_repo "$d"

  run _recon_in "$d" text zzz-no-such-token
  [ "$status" -eq 0 ]
  assert_line "STATUS=EMPTY COUNT=0"
  _assert_logged_status "$d" EMPTY
  _log_answer_field "$d" intent
  _log_answer_field "$d" provider
  _log_answer_field "$d" query
  _log_answer_field "$d" status
  _log_answer_field "$d" freshness
  _log_answer_field "$d" elapsed_ms
  _log_answer_field "$d" ts
  # `count` is 0 here, which is a VALUE, not a null: EMPTY is an answer.
  _log_answer_field "$d" count
  printf '%s' "$(_log_last "$d")" | jq -e '.count == 0' >/dev/null \
    || { echo "EMPTY logged count is not 0: $(_log_last "$d")"; false; }
}

@test "non-answer class (STATUS=DEGRADED): fixed arity, provider/count/freshness null" {
  local d="$TMP/cls-degraded"
  _mkrepo "$d" 25 sh
  _caps_none_in "$d"

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=DEGRADED REASON=not-installed"
  _assert_logged_status "$d" DEGRADED
  _log_parses "$d"
  _log_nonanswer_field "$d" intent
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" query
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" status
  _log_nonanswer_field "$d" freshness
  _log_nonanswer_field "$d" elapsed_ms
  _log_nonanswer_field "$d" ts
}

@test "non-answer class (STATUS=UNAVAILABLE): fixed arity, provider/count/freshness null" {
  local d="$TMP/cls-unavail"
  _mkrepo "$d" 25 sh
  _install_stub codegraph
  cp "$FIX/codegraph-status-not-initialized.txt" "$STUB/codegraph.status"
  # Installed but un-indexed: the chain cannot answer for a reason other than
  # "the whole instrument set is missing", so UNAVAILABLE, not DEGRADED.
  _write_caps_in "$d" \
    "$(_caps_provider codegraph true false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE"
  _assert_logged_status "$d" UNAVAILABLE
  _log_nonanswer_field "$d" intent
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" query
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" status
  _log_nonanswer_field "$d" freshness
  _log_nonanswer_field "$d" elapsed_ms
  _log_nonanswer_field "$d" ts
}

@test "non-answer class (STATUS=NO_INTENT_MATCH): fixed arity, provider/count/freshness null" {
  local d="$TMP/cls-noint"
  _answer_repo "$d"

  run _recon_in "$d" frobnicate x
  [ "$status" -eq 0 ]
  assert_line "STATUS=NO_INTENT_MATCH"
  _assert_logged_status "$d" NO_INTENT_MATCH
  _log_nonanswer_field "$d" intent
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" query
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" status
  _log_nonanswer_field "$d" freshness
  _log_nonanswer_field "$d" elapsed_ms
  _log_nonanswer_field "$d" ts
  # The intent is recorded even when it matched nothing — the log is how a
  # never-matching intent name becomes visible.
  [ "$(_log_get "$d" intent)" = frobnicate ]
}

@test "non-answer class (STATUS=DELEGATE): fixed arity, provider/count/freshness null" {
  local d="$TMP/cls-delegate"
  _mkrepo "$d" 25 sh
  # `tests` chains codegraph -> tokensave; codegraph absent, tokensave is
  # MCP-only and exempt from the language filter, so the verdict is DELEGATE.
  _caps_none_in "$d"

  run _recon_in "$d" tests f1.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=DELEGATE PROVIDER=tokensave"
  _assert_logged_status "$d" DELEGATE
  _log_nonanswer_field "$d" intent
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" query
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" status
  _log_nonanswer_field "$d" freshness
  _log_nonanswer_field "$d" elapsed_ms
  _log_nonanswer_field "$d" ts
}

@test "non-answer class (STATUS=SKIP): fixed arity on every field" {
  local d="$TMP/cls-skip"
  _mkrepo "$d" 5 sh

  run _recon_in "$d" callers foo
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP"
  _assert_logged_status "$d" SKIP
  _log_nonanswer_field "$d" intent
  _log_nonanswer_field "$d" provider
  _log_nonanswer_field "$d" query
  _log_nonanswer_field "$d" count
  _log_nonanswer_field "$d" status
  _log_nonanswer_field "$d" freshness
  _log_nonanswer_field "$d" elapsed_ms
  _log_nonanswer_field "$d" ts
}

@test "the logged object has EXACTLY the eight documented keys, in both classes" {
  # Fixed arity means fixed BOTH ways: a ninth key is as much a schema break as
  # a missing one, and the coverage loop below can only police the eight it
  # knows about.
  local keys='["count","elapsed_ms","freshness","intent","provider","query","status","ts"]'

  local a="$TMP/arity-ok"
  _answer_repo "$a"
  run _recon_in "$a" spans f1.sh
  [ "$status" -eq 0 ]
  printf '%s' "$(_log_last "$a")" | jq -e --argjson k "$keys" '(keys | sort) == $k' >/dev/null \
    || { echo "answer-class keys: $(printf '%s' "$(_log_last "$a")" | jq -c 'keys|sort')"; false; }

  local b="$TMP/arity-skip"
  _mkrepo "$b" 5 sh
  run _recon_in "$b" callers foo
  [ "$status" -eq 0 ]
  printf '%s' "$(_log_last "$b")" | jq -e --argjson k "$keys" '(keys | sort) == $k' >/dev/null \
    || { echo "non-answer-class keys: $(printf '%s' "$(_log_last "$b")" | jq -c 'keys|sort')"; false; }
}

# ---------------------------------------------------------------------------
# 5. CONTRACT COVERAGE loops (the substitute for the disabled coverage gate)
# ---------------------------------------------------------------------------

# _router_body — recon.sh + recon_providers.sh with recon.sh's header comment
# block stripped. The loops grep THIS, not the whole file: the header lists the
# statuses and the log schema as documentation, so grepping the file would let a
# value be documented and never emitted — exactly the drift the gate catches.
# recon_providers.sh is included because STATUS=DELEGATE is emitted there
# (recon_providers.sh:421), and the log must record it like any other.
_router_body() {
  sed -n '/^set -euo pipefail/,$p' "$RECON"
  cat "$PROVIDERS"
}

@test "contract coverage: every one of the eight log fields is asserted in BOTH status classes" {
  local f missing_answer="" missing_nonanswer="" missing_router=""
  local body
  body="$(_router_body)"
  for f in intent provider query count status freshness elapsed_ms ts; do
    # The ASSERTING form, not a bare mention: `_log_answer_field <dir> <field>`
    # can only pass when the field really carries a value on OK/EMPTY, whereas a
    # bare `grep -F "$f"` is satisfied by this very comment.
    if ! grep -Eq "_log_answer_field [^ ]+ $f\$" "$BATS_TEST_FILENAME"; then
      missing_answer="$missing_answer $f"
    fi
    if ! grep -Eq "_log_nonanswer_field [^ ]+ $f\$" "$BATS_TEST_FILENAME"; then
      missing_nonanswer="$missing_nonanswer $f"
    fi
    # The router half matches the key in its OBJECT-CONSTRUCTION form
    # (`intent:` / `"intent":`) at a WORD BOUNDARY, never a bare substring:
    # `ts` and `count` occur inside `results`, `_tracked_count` and a dozen
    # other identifiers, so `case $body in *ts*` — and even *"ts:"* — is
    # satisfied with the field itself deleted.
    if ! printf '%s\n' "$body" | grep -Eq "(^|[^A-Za-z0-9_\"])\"?${f}\"?:"; then
      missing_router="$missing_router $f"
    fi
  done
  if [ -n "$missing_answer" ]; then echo "log fields with no answer-class assertion:$missing_answer"; false; fi
  if [ -n "$missing_nonanswer" ]; then echo "log fields with no non-answer-class assertion:$missing_nonanswer"; false; fi
  if [ -n "$missing_router" ]; then echo "log fields never named in the router body:$missing_router"; false; fi
}

@test "contract coverage: every one of the seven closed STATUS values is asserted as LOGGED and emitted by the router" {
  local v missing_test="" missing_router=""
  local body
  body="$(_router_body)"
  for v in OK EMPTY UNAVAILABLE SKIP DEGRADED NO_INTENT_MATCH DELEGATE; do
    # `_assert_logged_status <dir> <STATUS>` reads the value back OUT of the log
    # line, so a status the router prints but never records fails here.
    if ! grep -Eq "_assert_logged_status [^ ]+ $v\$" "$BATS_TEST_FILENAME"; then
      missing_test="$missing_test $v"
    fi
    case "$body" in
      *"STATUS=$v"*) : ;;
      *) missing_router="$missing_router $v" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "STATUS values never asserted as logged:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "STATUS values never emitted by the router:$missing_router"; false; fi
  # No status can be "asserted as LOGGED" while the router has no log writer at
  # all, so the writer's existence is part of THIS gate rather than a separate
  # one that could pass while every status went unrecorded. Last, so the
  # plain-bash fallback runner reports it too.
  case "$body" in
    *"calls.jsonl"*) : ;;
    *) echo "the router writes no calls.jsonl — no STATUS value can be logged"; false ;;
  esac
}

@test "contract coverage: every --explain skip reason has a test and is emitted by the router" {
  local r missing_test="" missing_router=""
  local body
  body="$(_router_body)"
  for r in not-installed no-index capability-mismatch no-delegate; do
    if ! grep -q "assert_line \"$r\"" "$BATS_TEST_FILENAME"; then
      missing_test="$missing_test $r"
    fi
    case "$body" in
      *"$r"*) : ;;
      *) missing_router="$missing_router $r" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "--explain skip reasons with no test:$missing_test"; false; fi
  if [ -n "$missing_router" ]; then echo "--explain skip reasons never emitted by the router:$missing_router"; false; fi
}

@test "contract coverage: every .gitignore fixture exists and has a test, and the two predicate fixtures disagree on check-ignore" {
  local fx
  for fx in gitignore-conventional gitignore-whitelist gitignore-no-trailing-newline; do
    [ -f "$FIX/$fx" ] || { echo "missing fixture: $FIX/$fx"; false; }
    grep -q "$fx" "$BATS_TEST_FILENAME" || { echo "fixture with no test: $fx"; false; }
  done
  # The newline-less fixture only tests the hazard while it genuinely ends
  # without a newline — one stray editor save and its case goes vacuous.
  [ -n "$(tail -c 1 "$FIX/gitignore-no-trailing-newline")" ] \
    || { echo "gitignore-no-trailing-newline ends in a newline — its case is vacuous"; false; }
  # They must genuinely differ on the predicate the append is conditional on —
  # two fixtures that both match (or both miss) would test one branch twice.
  local d="$TMP/gifix"
  _mkrepo "$d" 3 sh
  cp "$FIX/gitignore-conventional" "$d/.gitignore"
  ( cd "$d" && ! git check-ignore -q .recon/ ) \
    || { echo "gitignore-conventional already matches .recon/ — it must not"; false; }
  cp "$FIX/gitignore-whitelist" "$d/.gitignore"
  ( cd "$d" && git check-ignore -q .recon/ ) \
    || { echo "gitignore-whitelist does not match .recon/ — it must"; false; }
  # Two fixtures only test two branches if the router actually BRANCHES on the
  # predicate: the append is conditional on `git check-ignore -q .recon/`, so an
  # unconditional appender must fail here rather than pass the whitelist case by
  # luck of never having been run against it.
  local body
  body="$(_router_body)"
  case "$body" in
    *"check-ignore"*) : ;;
    *) echo "the router never consults git check-ignore — the append cannot be conditional"; false ;;
  esac
}

@test "contract coverage: the hostile-input query and the worktree resolution each have a test" {
  # The two cases whose absence would leave the log's two structural hazards
  # untested: an unparseable line, and a second log nobody reads.
  grep -q 'jq -r .\.query.' "$BATS_TEST_FILENAME" \
    || { echo "no test round-trips .query via jq -r"; false; }
  grep -q 'git .*worktree add' "$BATS_TEST_FILENAME" \
    || { echo "no test invokes recon.sh from a worktree CWD"; false; }
  # The router must resolve the log through repo_root(), never against $PWD: a
  # CWD-relative path is exactly how a worktree grows its own orphan log.
  local body
  body="$(_router_body)"
  case "$body" in
    *"repo_root"*) : ;;
    *) echo "recon.sh never calls repo_root — the log cannot be main-tree resolved"; false ;;
  esac
  case "$body" in
    *"calls.jsonl"*) : ;;
    *) echo "the router never names calls.jsonl"; false ;;
  esac
}

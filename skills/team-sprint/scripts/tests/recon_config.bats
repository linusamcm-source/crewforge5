#!/usr/bin/env bats
# recon_config.bats — RED-phase contract for Story RH5: the `recon` config block
# and total degradation.
#
# RH5 adds six top-level scalar keys — `recon`, `recon_min_files`,
# `recon_providers`, `recon_log`, `recon_max_lines`,
# `recon_probe_max_age_minutes` — and the evaluation order's step 1
# (`recon: off` -> STATUS=SKIP REASON=disabled, recon.sh:24). Every one of them
# is read with lib.sh's `read_config_scalar`, which parses a TOP-LEVEL SCALAR and
# nothing else: a nested map or a YAML flow sequence comes back as the literal
# source text, so the shape of the key is part of the contract and is asserted
# here against the example config, not eyeballed.
#
# Every key also carries a HARDCODED default inside recon.sh, because
# `read_config_scalar` returns the empty string for an absent FILE and for an
# absent KEY alike — the two are indistinguishable (plan, RH5 prose). Both cases
# are fixtured: a repo with no `team-sprint.config.yaml` at all, and a repo whose
# config carries the whole block minus the one key under test.
#
# The sandbox PATH is "$BIN:/usr/bin:/bin", exactly as recon.bats:73,
# recon_guard.bats and recon_log.bats do it — the only way to make
# codegraph/graphify/rtk genuinely ABSENT on a machine where all three live in
# /opt/homebrew/bin. jq / python3 / git are symlinked into $BIN so lib.sh still
# works, and /bin/bash there is 3.2.57, so the sandbox enforces the bash-3.2
# house rule for free.
#
# Every test builds its OWN repo: the config is resolved through repo_root() and
# each case needs a different config file, so one shared fixture repo cannot
# carry the `off`, `auto` and `on` branches at once.
#
# THE THREE-VALUE ENUM IS THE POINT. `off` is a SKIP that touches no provider,
# `auto` degrades and reports, `on` is a Phase 0 gate that fails LOUD. An
# unexercised enum branch is an untested branch, so the contract-coverage loops
# at the bottom prove each value is exercised by grep against this file, never by
# eye — the substitute for the disabled line-coverage gate.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RECON="$SCRIPTS/recon.sh"
  PROVIDERS="$SCRIPTS/recon_providers.sh"
  LIB_SH="$SCRIPTS/lib.sh"
  SCHEMA="$SCRIPTS/state.schema.json"
  EXAMPLE="$(cd "$SCRIPTS/.." && pwd)/team-sprint.config.yaml.example"
  GUARD_BATS="$BATS_TEST_DIRNAME/recon_guard.bats"
  # The live sprint config is untracked and .gitignore-matched, so its DoD is
  # asserted by READING the file — it appears in no `git diff`.
  LIVE_CONFIG="${TEAM_SPRINT_LIVE_CONFIG:-$HOME/.claude/team-sprint.config.yaml}"
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
# $STUB/<name>.out / .exit and, for codegraph, $STUB/codegraph.status. Every
# invocation appends to $STUB/<name>.log so a test can assert a provider was —
# or was NOT — executed. Same shape as recon.bats:95 and recon_log.bats:86.
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
_ran()      { [ -s "$STUB/$1.log" ]; }

# _stub_lines <name> <n> — <n> graphify `explain` connection lines on stdout, so
# the result-line cap has a producer whose row count the test controls exactly.
_stub_lines() {
  local name="$1" n="$2" i=1
  {
    printf 'Node: lib.sh\n'
    printf 'Connections (%s):\n' "$n"
    while [ "$i" -le "$n" ]; do
      printf '  --> fn_%s() [defines] [EXTRACTED] skills/team-sprint/scripts/lib.sh:L%s\n' "$i" "$i"
      i=$((i + 1))
    done
  } > "$STUB/$name.out"
}

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
    return 1
  fi
}

# _config <dir> <line>... — write team-sprint.config.yaml, left UNTRACKED as the
# live one is, so writing a config never perturbs the tracked-file count.
_config() {
  local d="$1"
  shift
  printf '%s\n' "$@" > "$d/team-sprint.config.yaml"
}

# _config_omitting <dir> <key> — the whole RH5 block at its documented defaults
# with exactly ONE key removed. This is the second half of AC9: an absent KEY
# must fall back to the same hardcoded default an absent FILE does, because
# read_config_scalar returns the empty string for both.
_config_omitting() {
  local d="$1" omit="$2" k
  : > "$d/team-sprint.config.yaml"
  for k in "recon: auto" \
           "recon_min_files: 20" \
           "recon_providers: codegraph graphify repomix tokensave" \
           "recon_log: on" \
           "recon_max_lines: 50" \
           "recon_probe_max_age_minutes: 1440"; do
    case "$k" in
      "$omit:"*) continue ;;
    esac
    printf '%s\n' "$k" >> "$d/team-sprint.config.yaml"
  done
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
    mt="$(stat -f %m "$bin" 2>/dev/null || stat -c %Y "$bin")"
    sz="$(stat -f %z "$bin" 2>/dev/null || stat -c %s "$bin")"
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

# _write_caps_aged_in <dir> <age-seconds> <provider-object>... — same, with the
# cache's top-level resolved_at backdated, so a router that revalidates against
# the CONFIGURED TTL can be told apart from one that revalidates against a
# constant (recon.bats:145).
_write_caps_aged_in() {
  local d="$1" age="$2"
  shift 2
  mkdir -p "$d/.recon"
  printf '%s\n' "$@" | jq -s --argjson age "$age" \
    '{providers: add, resolved_at: ((now|floor) - $age)}' \
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

# _caps_graphify_only_in <dir> <indexed> — graphify present (indexed or not),
# everything else absent.
_caps_graphify_only_in() {
  _write_caps_in "$1" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true "$2" '["bash"]')" \
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

# _recon_all_in <dir> <args...> — same, with stderr merged: the config-error and
# WARN cases, whose message is part of the contract.
_recon_all_in() {
  local d="$1"
  shift
  ( cd "$d" && PATH="$BIN:/usr/bin:/bin" bash "$RECON" "$@" 2>&1 )
}

_status_lines() { printf '%s\n' "$output" | grep -c '^STATUS=' || true; }
_out_lines()    { printf '%s\n' "$output" | grep -c . || true; }

# _log_lines <dir> — the number of lines in that repo's call log, 0 when absent.
_log_lines() {
  if [ -f "$1/.recon/calls.jsonl" ]; then
    wc -l < "$1/.recon/calls.jsonl" | tr -d ' '
  else
    printf 0
  fi
}

# _router_body — recon.sh + recon_providers.sh with recon.sh's header comment
# block stripped. The coverage loops grep THIS, not the whole file: the header
# documents the keys and the statuses as prose, so grepping the file would let a
# key be documented and never read — exactly the drift the gate catches.
_router_body() {
  sed -n '/^set -euo pipefail/,$p' "$RECON"
  cat "$PROVIDERS"
}

# _recon_keys — the six keys RH5 owns, one per line. One list, consumed by AC8,
# AC9, AC10 and the coverage loops alike, so a key can never be added to one
# gate and quietly missed by another.
_recon_keys() {
  printf '%s\n' recon recon_min_files recon_providers recon_log \
                recon_max_lines recon_probe_max_age_minutes
}

# _assert_enabled_pair <dir> <intent> <arg> — the degradation verdict just
# asserted in <dir> was produced by an ENABLED router, proved by flipping the
# same repo's config to `recon: off` and getting step 1's SKIP instead.
#
# Without this pair a chain-degradation assertion is satisfied by a router that
# reads no config at all: "the chain advanced" and "the config was honoured" are
# two claims, and only the second is RH5's. The config is restored afterwards so
# the caller can keep asserting on the same fixture.
_assert_enabled_pair() {
  local d="$1" intent="$2" arg="$3" out rc=0 saved=""
  if [ -f "$d/team-sprint.config.yaml" ]; then
    saved="$(cat "$d/team-sprint.config.yaml")"
  fi
  _config "$d" "recon: off"
  out="$(_recon_in "$d" "$intent" "$arg")" || rc=$?
  if [ -n "$saved" ]; then
    printf '%s\n' "$saved" > "$d/team-sprint.config.yaml"
  else
    rm -f "$d/team-sprint.config.yaml"
  fi
  [ "$rc" -eq 0 ] || { echo "recon: off exited $rc, expected 0: $out"; return 1; }
  case "$out" in
    *"STATUS=SKIP REASON=disabled"*) : ;;
    *) echo "the same fixture under recon: off answered '$out', not step 1's SKIP — the router reads no config"; return 1 ;;
  esac
}

# _assert_key_is_read <base> <key> <mode> — the flip side of a default: a
# HARDCODED default is only a default while the key is genuinely read, so an
# explicit NON-default value must move the behaviour. A constant that happens to
# equal the documented default satisfies every default assertion above and reads
# nothing at all — which is precisely the RH5 gap.
_assert_key_is_read() {
  local base="$1" key="$2" mode="$3"
  local d="$base/$key-$mode-read" out rc=0
  case "$key" in
    recon_min_files) _mkrepo "$d" 19 sh ;;
    *)               _mkrepo "$d" 25 sh ;;
  esac

  case "$key" in
    recon)
      _config "$d" "recon: off"
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      case "$out" in
        *"STATUS=SKIP REASON=disabled"*) : ;;
        *) echo "$key/$mode: an explicit 'off' did not move the verdict: $out"; return 1 ;;
      esac
      ;;
    recon_min_files)
      _config "$d" "recon_min_files: 0"
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      case "$out" in
        *"REASON=small-repo"*) echo "$key/$mode: an explicit 0 did not disable the guard: $out"; return 1 ;;
      esac
      ;;
    recon_providers)
      _config "$d" "recon_providers: tokensave"
      _caps_none_in "$d"
      out="$(_recon_in "$d" --explain callers fn_1)" || rc=$?
      case "$out" in
        *"PROVIDER=codegraph"*|*"PROVIDER=graphify"*)
          echo "$key/$mode: a one-name allow-list still walked the whole chain: $out"; return 1 ;;
      esac
      ;;
    recon_log)
      _config "$d" "recon_log: off"
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      if [ "$(_log_lines "$d")" -ne 0 ]; then
        echo "$key/$mode: an explicit 'off' still logged $(_log_lines "$d") line(s)"
        return 1
      fi
      ;;
    recon_max_lines)
      _config "$d" "recon_max_lines: 5"
      _install_stub graphify
      _stub_lines graphify 60
      _write_caps_in "$d" \
        "$(_caps_provider codegraph false false '[]')" \
        "$(_caps_provider graphify  true true '["bash"]')" \
        "$(_caps_provider repomix   false false '[]')" \
        "$(_caps_provider tokensave false false '[]')"
      out="$(_recon_in "$d" spans lib.sh)" || rc=$?
      case "$out" in
        *"TRUNCATED=5/60"*) : ;;
        *) echo "$key/$mode: an explicit cap of 5 was ignored: $out"; return 1 ;;
      esac
      ;;
    recon_probe_max_age_minutes)
      _config "$d" "recon_probe_max_age_minutes: 5"
      _install_stub codegraph
      cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
      _write_caps_aged_in "$d" 600 \
        "$(_caps_provider codegraph false false '[]')" \
        "$(_caps_provider graphify  false false '[]')" \
        "$(_caps_provider repomix   false false '[]')" \
        "$(_caps_provider tokensave false false '[]')"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      if ! _ran codegraph; then
        echo "$key/$mode: a 10-minute-old cache survived an explicit 5-minute TTL"
        return 1
      fi
      ;;
    *)
      echo "no read assertion for key $key"
      return 1
      ;;
  esac
  [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
}

# _assert_key_default <base> <key> <mode> — assert the HARDCODED default of one
# key holds in a repo built for it. <mode> is `noconfig` (no
# team-sprint.config.yaml at all) or `partial` (the whole block minus <key>);
# read_config_scalar returns the empty string for both, so both must land on the
# same default.
_assert_key_default() {
  local base="$1" key="$2" mode="$3"
  local d="$base/$key-$mode" out rc=0
  case "$key" in
    recon_min_files) _mkrepo "$d" 19 sh ;;
    *)               _mkrepo "$d" 25 sh ;;
  esac
  [ "$mode" = noconfig ] || _config_omitting "$d" "$key"

  case "$key" in
    recon)
      # default `auto`: zero providers is a REPORTED degradation, never a hard
      # fail (that is `on`) and never a SKIP (that is `off`).
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0 (default auto never hard-fails): $out"; return 1; }
      case "$out" in
        *"STATUS=DEGRADED"*) : ;;
        *) echo "$key/$mode: expected STATUS=DEGRADED, got: $out"; return 1 ;;
      esac
      case "$out" in
        *"REASON=disabled"*) echo "$key/$mode: default resolved to off, not auto: $out"; return 1 ;;
      esac
      ;;
    recon_min_files)
      # default 20: a 19-file repo is below the floor.
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
      case "$out" in
        *"STATUS=SKIP REASON=small-repo FILES=19"*) : ;;
        *) echo "$key/$mode: expected the default-20 guard to skip a 19-file repo, got: $out"; return 1 ;;
      esac
      ;;
    recon_providers)
      # default chain `codegraph graphify repomix tokensave`: every one of the
      # four is still walkable, so the empty/absent value is NOT zero providers.
      _caps_none_in "$d"
      out="$(_recon_in "$d" --explain callers fn_1)$(_recon_in "$d" --explain text fn_1)$(_recon_in "$d" --explain tests fn_1)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
      local p
      for p in codegraph graphify repomix tokensave; do
        case "$out" in
          *"PROVIDER=$p"*) : ;;
          *) echo "$key/$mode: default chain never walks $p: $out"; return 1 ;;
        esac
      done
      ;;
    recon_log)
      # default `on`: the invocation is recorded.
      _caps_none_in "$d"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
      if [ "$(_log_lines "$d")" -ne 1 ]; then
        echo "$key/$mode: default is on, expected exactly 1 log line, got $(_log_lines "$d")"
        return 1
      fi
      ;;
    recon_max_lines)
      # default 50: 60 rows truncate at 50 and COUNT stays pre-truncation.
      _install_stub graphify
      _stub_lines graphify 60
      _write_caps_in "$d" \
        "$(_caps_provider codegraph false false '[]')" \
        "$(_caps_provider graphify  true true '["bash"]')" \
        "$(_caps_provider repomix   false false '[]')" \
        "$(_caps_provider tokensave false false '[]')"
      out="$(_recon_in "$d" spans lib.sh)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
      case "$out" in
        *"TRUNCATED=50/60"*) : ;;
        *) echo "$key/$mode: expected the default cap of 50, got: $out"; return 1 ;;
      esac
      ;;
    recon_probe_max_age_minutes)
      # default 1440 minutes: a cache 100 minutes old is inside the TTL, so no
      # provider is re-probed.
      _install_stub codegraph
      _write_caps_aged_in "$d" 6000 \
        "$(_caps_provider codegraph false false '[]')" \
        "$(_caps_provider graphify  false false '[]')" \
        "$(_caps_provider repomix   false false '[]')" \
        "$(_caps_provider tokensave false false '[]')"
      out="$(_recon_in "$d" callers fn_1)" || rc=$?
      [ "$rc" -eq 0 ] || { echo "$key/$mode: exit $rc, expected 0: $out"; return 1; }
      if ! _not_ran codegraph; then
        echo "$key/$mode: a 100-minute-old cache was re-probed under the default 1440-minute TTL"
        return 1
      fi
      ;;
    *)
      echo "no default assertion for key $key"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 1. `recon: off` — evaluation-order step 1
# ---------------------------------------------------------------------------

@test "AC1: recon: off answers STATUS=SKIP REASON=disabled and exits 0 for every one of the 10 intents" {
  local d="$TMP/off-all"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: off"
  # Providers are present AND indexed: `off` must win over a chain that could
  # otherwise answer, or the branch is indistinguishable from "nothing installed".
  _install_stub graphify
  _stub_out graphify "$FIX/graphify-explain.txt"
  mkdir -p "$d/graphify-out"
  cp "$FIX/graphify-graph.json" "$d/graphify-out/graph.json"
  _caps_graphify_only_in "$d" true

  local i
  for i in text callers callees impact tests path dynamic coupling docs spans; do
    run _recon_in "$d" "$i" fn_1
    [ "$status" -eq 0 ]
    assert_line "STATUS=SKIP REASON=disabled" || return 1
    [ "$(_status_lines)" -eq 1 ]
    [ "$(_out_lines)" -eq 1 ]
  done
  _not_ran graphify
}

@test "AC1: recon: off precedes the intent match — an unknown intent is SKIP disabled, never NO_INTENT_MATCH" {
  # Evaluation order, recon.sh:22-27: step 1 is `disabled`, step 2 is the intent
  # match. Two live conditions can never race, so the order is asserted, not the
  # conjunction.
  local d="$TMP/off-order"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: off"
  _caps_none_in "$d"

  run _recon_in "$d" no_such_intent fn_1
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=disabled" || return 1
  refute_line "NO_INTENT_MATCH" || return 1
  [ "$(_status_lines)" -eq 1 ]
}

@test "AC1: recon: off answers --probe with STATUS=SKIP REASON=disabled and writes no capability cache" {
  # recon.sh:82-84 fixes --probe's three outcomes; the disabled one is RH5's.
  # Phase 0 calls exactly this, so an `off` sprint must not shell a probe.
  local d="$TMP/off-probe"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: off"
  _install_stub codegraph

  run _recon_in "$d" --probe
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=disabled" || return 1
  [ "$(_status_lines)" -eq 1 ]
  _not_ran codegraph
  [ ! -f "$d/.recon/capabilities.json" ]
}

@test "AC2: recon: on with zero providers available exits non-zero — the Phase 0 gate fails loud" {
  local d="$TMP/on-zero"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: on"
  _caps_none_in "$d"

  run _recon_all_in "$d" --probe
  [ "$status" -ne 0 ] || return 1

  # The control lives in the same test on purpose: the gate must fire on
  # ABSENCE, not on the enum value. Asserted apart, an implementation that
  # exits non-zero for every `recon: on` sprint would pass the half above.
  local p="$TMP/on-present"
  _mkrepo "$p" 25 sh
  _config "$p" "recon: on"
  _install_stub codegraph
  _install_stub graphify
  _install_stub rtk
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  cp "$FIX/pack-two-files.xml" "$p/.repomix-output.xml"
  mkdir -p "$p/graphify-out"
  cp "$FIX/graphify-graph.json" "$p/graphify-out/graph.json"

  run _recon_in "$p" --probe
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK"
}

@test "AC3: recon: auto with zero providers is STATUS=DEGRADED and exit 0, where recon: on on the same repo exits non-zero" {
  # The contrast IS the acceptance criterion: `auto` never hard-fails, and the
  # only thing that separates it from `on` is the exit code. Asserting the two
  # halves apart would let an implementation that ignores the key entirely pass
  # the `auto` half.
  local d="$TMP/auto-zero"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: auto"
  _caps_none_in "$d"

  run _recon_in "$d" callers fn_1
  [ "$status" -eq 0 ]
  assert_line "STATUS=DEGRADED"
  [ "$(_status_lines)" -eq 1 ]

  run _recon_in "$d" --probe
  [ "$status" -eq 0 ]
  assert_line "STATUS=DEGRADED REASON=not-installed"

  _config "$d" "recon: on"
  run _recon_all_in "$d" --probe
  [ "$status" -ne 0 ] || return 1
}

# ---------------------------------------------------------------------------
# 2. Total degradation on the two-link `docs` chain
# ---------------------------------------------------------------------------

@test "AC4: docs over an INSTALLED but unindexed graphify advances to repomix and answers PROVIDER=repomix" {
  local d="$TMP/docs-unindexed"
  _mkrepo "$d" 25 sh
  _install_stub graphify
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  # No graphify-out/graph.json anywhere: the graphify link has a binary and no
  # index. A false negative here — reporting graphify's silence as an answer —
  # is the worst failure this router can have.
  [ ! -e "$d/graphify-out/graph.json" ]
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" docs marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "STATUS=OK"
  refute_line "STATUS=UNAVAILABLE"
  [ "$(_status_lines)" -eq 1 ]

  # …and the skipped link is named `no-index`, never silently dropped.
  run _recon_in "$d" --explain docs marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=graphify REASON=no-index"

  _assert_enabled_pair "$d" docs marker || return 1
}

@test "AC4: docs with the graphify BINARY absent still answers PROVIDER=repomix" {
  local d="$TMP/docs-nographify"
  _mkrepo "$d" 25 sh
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  [ ! -x "$BIN/graphify" ]
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" docs marker
  [ "$status" -eq 0 ]
  assert_line "PROVIDER=repomix"
  assert_line "STATUS=OK"
  [ "$(_status_lines)" -eq 1 ]

  _assert_enabled_pair "$d" docs marker || return 1
}

@test "AC5: docs is terminal UNAVAILABLE REASON=no-index when the repomix pack is missing — the last link's OWN reason" {
  local d="$TMP/docs-nopack"
  _mkrepo "$d" 25 sh
  _install_stub graphify
  _install_stub rtk
  # rtk is installed; the pack — repomix's index — is not.
  [ ! -e "$d/.repomix-output.xml" ]
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true false '[]')" \
    "$(_caps_provider repomix   true false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" docs marker
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=no-index"
  refute_line "STATUS=EMPTY"
  [ "$(_status_lines)" -eq 1 ]

  _assert_enabled_pair "$d" docs marker || return 1
}

@test "AC5: docs is terminal UNAVAILABLE REASON=not-installed when rtk is absent" {
  local d="$TMP/docs-nortk"
  _mkrepo "$d" 25 sh
  _install_stub graphify
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  [ ! -x "$BIN/rtk" ]
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" docs marker
  [ "$status" -eq 0 ]
  assert_line "STATUS=UNAVAILABLE REASON=not-installed"
  refute_line "STATUS=EMPTY"
  [ "$(_status_lines)" -eq 1 ]

  _assert_enabled_pair "$d" docs marker || return 1
}

# ---------------------------------------------------------------------------
# 3. recon_providers — the single source of truth for provider opt-out
# ---------------------------------------------------------------------------

@test "AC6: gitnexus anywhere in recon_providers exits non-zero with a message naming PolyForm-Noncommercial" {
  local d="$TMP/gitnexus"
  _mkrepo "$d" 25 sh
  _caps_none_in "$d"

  local list
  # First, middle and last position — the AC says "in any position", and a
  # first-word-only check is exactly the bug that phrasing anticipates.
  for list in "gitnexus" \
              "codegraph gitnexus graphify" \
              "codegraph graphify repomix tokensave gitnexus"; do
    _config "$d" "recon_providers: $list"
    run _recon_all_in "$d" callers fn_1
    [ "$status" -ne 0 ] || return 1
    assert_line "PolyForm-Noncommercial"
  done
}

@test "AC7: recon_providers with an EMPTY value resolves to the default chain, exactly as an absent key does" {
  # read_config_scalar cannot tell an empty value from an absent key — both
  # return the empty string — so the two must be indistinguishable downstream.
  # Zero providers is spelled `recon: off`, never `recon_providers:`.
  local dempty="$TMP/prov-empty" dabsent="$TMP/prov-absent"
  _mkrepo "$dempty" 25 sh
  _mkrepo "$dabsent" 25 sh
  _config "$dempty" "recon_providers:"
  _config "$dabsent" "recon: auto"
  _caps_none_in "$dempty"
  _caps_none_in "$dabsent"

  local i
  for i in callers text tests path; do
    run _recon_in "$dempty" --explain "$i" fn_1
    [ "$status" -eq 0 ]
    local got="$output"
    run _recon_in "$dabsent" --explain "$i" fn_1
    [ "$status" -eq 0 ]
    if [ "$got" != "$output" ]; then
      echo "empty and absent recon_providers disagree on $i:"
      echo "empty : $got"
      echo "absent: $output"
      return 1
    fi
  done

  # …and the default chain is all four names, not zero providers.
  run _recon_in "$dempty" --explain callers fn_1
  assert_line "PROVIDER=codegraph"
  assert_line "PROVIDER=graphify"
  run _recon_in "$dempty" --explain text fn_1
  assert_line "PROVIDER=repomix"
  run _recon_in "$dempty" --explain tests fn_1
  assert_line "PROVIDER=tokensave"

  # "the DEFAULT chain" is only distinguishable from "whatever chain the router
  # hardcodes" when a NON-default list produces a different walk. Without this
  # half, a router that never reads the key passes the whole test.
  _config "$dempty" "recon_providers: tokensave"
  run _recon_in "$dempty" --explain callers fn_1
  [ "$status" -eq 0 ]
  refute_line "PROVIDER=codegraph"
  refute_line "PROVIDER=graphify"
}

@test "AC7: a valid recon_providers list is honoured — a provider absent from it is never walked, even when installed and indexed" {
  # Dropping a name from the list is the ONLY way to opt a provider out (there
  # is deliberately no per-provider `<provider>_enabled` key), so an available,
  # indexed, language-matching provider that is not on the list must be skipped
  # exactly as an absent one is.
  local d="$TMP/prov-list"
  _mkrepo "$d" 25 sh
  _config "$d" "recon_providers: codegraph graphify tokensave"
  _install_stub rtk
  _stub_out rtk "$FIX/rtk-grep-hits-no-trailer.txt"
  cp "$FIX/pack-two-files.xml" "$d/.repomix-output.xml"
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   true true '["bash","markdown"]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" docs marker
  [ "$status" -eq 0 ]
  refute_line "PROVIDER=repomix"
  refute_line "STATUS=OK"
  [ "$(_status_lines)" -eq 1 ]
  _not_ran rtk
}

# ---------------------------------------------------------------------------
# 4. The config surface: shape, comment block and hardcoded defaults
# ---------------------------------------------------------------------------

@test "AC8: every recon key has a type:/default: comment block in team-sprint.config.yaml.example" {
  # The column format is the one graphify: uses at
  # team-sprint.config.yaml.example:152-178 — `# <key><pad>type: <t>   default: <d>`.
  local k missing_comment="" missing_key=""
  for k in $(_recon_keys); do
    if ! grep -Eq "^# ${k}[[:space:]]+type: .+default: .+" "$EXAMPLE"; then
      missing_comment="$missing_comment $k"
    fi
    if ! grep -Eq "^${k}:" "$EXAMPLE"; then
      missing_key="$missing_key $k"
    fi
  done
  if [ -n "$missing_comment" ]; then
    echo "keys with no 'type: … default: …' comment block in $EXAMPLE:$missing_comment"
    return 1
  fi
  if [ -n "$missing_key" ]; then
    echo "keys absent from $EXAMPLE:$missing_key"
    return 1
  fi
  # The enum keys must also name their alternatives, as graphify: does.
  grep -q "^# Alternatives: off | auto | on" "$EXAMPLE" \
    || { echo "the recon enum does not document its alternatives in the graphify: format"; return 1; }
}

@test "AC10: every recon key is a TOP-LEVEL SCALAR that read_config_scalar parses out of the example unmodified" {
  # A nested map or a YAML flow sequence would need parser work RH5 does not
  # scope: read_config_scalar returns the literal source text for a sequence,
  # brackets and comma included. Reading each key back OUT of the example with
  # the real helper is the only assertion that catches it.
  local k v empty=""
  # shellcheck source=/dev/null
  source "$LIB_SH"
  for k in $(_recon_keys); do
    v="$(read_config_scalar "$EXAMPLE" "$k")"
    if [ -z "$v" ]; then
      empty="$empty $k"
      continue
    fi
    case "$v" in
      *'['*|*']'*|*','*|*'{'*|*'}'*)
        echo "$k is not a plain scalar — read_config_scalar returned: $v"
        false ;;
    esac
  done
  if [ -n "$empty" ]; then
    echo "keys read_config_scalar cannot read out of $EXAMPLE (nested, sequenced or absent):$empty"
    return 1
  fi
  # The documented default of the list key is the space-separated default chain.
  v="$(read_config_scalar "$EXAMPLE" recon_providers)"
  [ "$v" = "codegraph graphify repomix tokensave" ] \
    || { echo "recon_providers in the example is '$v', expected the default chain"; return 1; }
}

@test "AC9: every recon key's hardcoded default holds in a repo with NO team-sprint.config.yaml at all" {
  local base="$TMP/def-noconfig" k
  mkdir -p "$base"
  for k in $(_recon_keys); do
    _assert_key_default "$base" "$k" noconfig || return 1
    # A default is only a DEFAULT while the key is read; see _assert_key_is_read.
    _assert_key_is_read "$base" "$k" noconfig || return 1
  done
}

@test "AC9: every recon key's hardcoded default holds in a repo whose config omits just that key" {
  local base="$TMP/def-partial" k
  mkdir -p "$base"
  for k in $(_recon_keys); do
    _assert_key_default "$base" "$k" partial || return 1
    _assert_key_is_read "$base" "$k" partial || return 1
    # The fixture must genuinely omit the key under test and keep the others,
    # or the case is vacuous. `if`, never `grep && { … }`: under errexit the
    # `&&` form returns 1 in exactly the PASSING case and fails the test.
    if grep -Eq "^${k}:" "$base/$k-partial/team-sprint.config.yaml"; then
      echo "fixture error: $k is still present in its own omit-config"
      return 1
    fi
    if [ "$k" != recon_log ] \
       && ! grep -q "^recon_log:" "$base/$k-partial/team-sprint.config.yaml"; then
      echo "fixture error: the omit-config for $k dropped more than one key"
      return 1
    fi
  done
}

# ---------------------------------------------------------------------------
# 5. The numeric keys, read from the CONFIG and not from the environment alone
# ---------------------------------------------------------------------------

@test "recon_max_lines below the cap emits every row, no TRUNCATED marker and a matching COUNT" {
  local d="$TMP/maxlines-under"
  _mkrepo "$d" 25 sh
  _config "$d" "recon_max_lines: 100"
  _install_stub graphify
  _stub_lines graphify 60
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" spans lib.sh
  [ "$status" -eq 0 ]
  assert_line "STATUS=OK COUNT=60"
  refute_line "TRUNCATED="
  [ "$(printf '%s\n' "$output" | grep -c '	' || true)" -eq 60 ]
}

@test "recon_max_lines over the cap emits ONE TRUNCATED=<emitted>/<total> line and a pre-truncation COUNT" {
  local d="$TMP/maxlines-over"
  _mkrepo "$d" 25 sh
  _config "$d" "recon_max_lines: 3"
  _install_stub graphify
  _stub_lines graphify 10
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" spans lib.sh
  [ "$status" -eq 0 ]
  assert_line "TRUNCATED=3/10"
  assert_line "STATUS=OK COUNT=10"
  [ "$(printf '%s\n' "$output" | grep -c '^TRUNCATED=' || true)" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '	' || true)" -eq 3 ]
}

@test "recon_max_lines: a non-numeric RECON_MAX_LINES override falls back to the cap and still emits STATUS=" {
  # The env override documented at recon.sh:122-123 was passed straight into
  # `[[ -lt ]]`, so a typo aborted the router under `set -u`: exit 1, ZERO
  # STATUS= lines and a leaked recon-out temp file. That breaks two contracts
  # this file writes itself — `STATUS= is mandatory and always last`
  # (recon.sh:73) and the exit table (recon.sh:89-101), which reserves 1 for bad
  # arguments and a REFUSED config, so a caller branching on rc=1 mistakes a
  # typo for the gitnexus refusal. The config path already guards the identical
  # value ('' | *[!0-9]* -> default); the env path must guard it identically.
  local d="$TMP/maxlines-env-nonnumeric"
  _mkrepo "$d" 25 sh
  _config "$d" "recon_max_lines: 3"
  _install_stub graphify
  _stub_lines graphify 10
  _write_caps_in "$d" \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  true true '["bash"]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  local sandbox_tmp="$TMP/maxlines-env-tmpdir" leaked
  mkdir -p "$sandbox_tmp"
  export TMPDIR="$sandbox_tmp"
  export RECON_MAX_LINES=abc
  run _recon_in "$d" spans lib.sh
  unset RECON_MAX_LINES
  [ "$status" -eq 0 ]
  assert_line "TRUNCATED=3/10"
  assert_line "STATUS=OK COUNT=10"
  [ "$(_status_lines)" -eq 1 ]

  # A NEGATIVE override never crashes — it silently emitted zero rows and a
  # `TRUNCATED=-5/10` marker, a wrong answer rather than a loud one. The same
  # one guard catches both, so both are asserted against it.
  export RECON_MAX_LINES=-5
  run _recon_in "$d" spans lib.sh
  unset RECON_MAX_LINES
  [ "$status" -eq 0 ]
  assert_line "TRUNCATED=3/10"
  assert_line "STATUS=OK COUNT=10"

  # The aborted run left its recon-out temp behind; a run that reaches its
  # STATUS= line removes it.
  leaked="$(find "$sandbox_tmp" -maxdepth 1 -name 'recon-out.*' | wc -l | tr -d ' ')"
  unset TMPDIR
  [ "$leaked" -eq 0 ]
}

@test "recon_probe_max_age_minutes: a cache INSIDE the configured TTL execs no provider" {
  local d="$TMP/ttl-fresh"
  _mkrepo "$d" 25 sh
  # 3 days, against a cache 2 days old: inside the CONFIGURED window and outside
  # the 1440-minute hardcoded one, so only a config-driven TTL passes.
  _config "$d" "recon_probe_max_age_minutes: 4320"
  _install_stub codegraph
  _write_caps_aged_in "$d" 172800 \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" callers fn_1
  [ "$status" -eq 0 ]
  _not_ran codegraph
}

@test "recon_probe_max_age_minutes: a cache OLDER than the configured TTL is re-probed" {
  local d="$TMP/ttl-expired"
  _mkrepo "$d" 25 sh
  # 5 minutes, against a cache 10 minutes old: expired under the CONFIGURED
  # window and still fresh under the 1440-minute hardcoded one. A cache trusted
  # past its TTL keeps a newly installed provider invisible and reports that
  # silence as a confident not-installed (recon.sh:61-65).
  _config "$d" "recon_probe_max_age_minutes: 5"
  _install_stub codegraph
  cp "$FIX/codegraph-status-initialized.txt" "$STUB/codegraph.status"
  _write_caps_aged_in "$d" 600 \
    "$(_caps_provider codegraph false false '[]')" \
    "$(_caps_provider graphify  false false '[]')" \
    "$(_caps_provider repomix   false false '[]')" \
    "$(_caps_provider tokensave false false '[]')"

  run _recon_in "$d" callers fn_1
  [ "$status" -eq 0 ]
  _ran codegraph
}

@test "recon_log: on — a disabled-router SKIP is still recorded as exactly one line with status SKIP" {
  # RH4's AC1: EVERY intent invocation appends exactly one line, and the only
  # exempt modes are --probe and --explain. A SKIP that logged nothing would
  # make "how often was recon disabled" unanswerable from the evidence base.
  local d="$TMP/log-on-disabled"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: off" "recon_log: on"
  _caps_none_in "$d"

  run _recon_in "$d" callers fn_1
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=disabled" || return 1
  [ "$(_log_lines "$d")" -eq 1 ]
  run jq -er '.status' "$d/.recon/calls.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "SKIP" ]
}

@test "recon_log: off — nothing is appended and the disabled SKIP still prints" {
  local d="$TMP/log-off-disabled"
  _mkrepo "$d" 25 sh
  _config "$d" "recon: off" "recon_log: off"
  _caps_none_in "$d"

  run _recon_in "$d" callers fn_1
  [ "$status" -eq 0 ]
  assert_line "STATUS=SKIP REASON=disabled" || return 1
  [ "$(_log_lines "$d")" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. Definition of Done — the two artifacts outside recon.sh
# ---------------------------------------------------------------------------

@test "DoD: state.schema.json declares recon_degraded as a boolean" {
  # additionalProperties is true, so an unknown key passes validation silently:
  # unless the schema NAMES it, the flag is unenforced.
  run jq -e '.properties.recon_degraded.type == "boolean"' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "DoD: the live team-sprint.config.yaml carries the recon block" {
  # Untracked and .gitignore-matched, so this is asserted by READING the file —
  # it appears in no `git diff`. Without it every key resolves to its hardcoded
  # default for the whole sprint.
  # Machine-local state: a fresh install has no live config at all, and this
  # DoD is about a config that exists, not about forcing one into being. Skip
  # rather than fail, or CI is green only on the machine the file was born on.
  [ -f "$LIVE_CONFIG" ] || skip "no live config at $LIVE_CONFIG — generated on first run, not shipped"
  local k missing=""
  for k in $(_recon_keys); do
    grep -Eq "^${k}:" "$LIVE_CONFIG" || missing="$missing $k"
  done
  if [ -n "$missing" ]; then
    echo "keys absent from the live config $LIVE_CONFIG:$missing"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 7. CONTRACT COVERAGE loops (the substitute for the disabled coverage gate)
# ---------------------------------------------------------------------------

@test "contract coverage: all three recon enum values are exercised here and branched on by the router" {
  local v missing_test="" missing_router="" body
  body="$(_router_body)"
  for v in off auto on; do
    # The CONFIG-WRITING form (`_config <dir> "recon: <v>"`) — a bare mention of
    # the word would be satisfied by this very comment.
    grep -l "\"recon: $v\"" "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
      || missing_test="$missing_test $v"
    case "$body" in
      *"$v"*) : ;;
      *) missing_router="$missing_router $v" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "recon enum values never exercised by a test:$missing_test"; return 1; fi
  if [ -n "$missing_router" ]; then echo "recon enum values the router never names:$missing_router"; return 1; fi
  # …and the router must actually READ the key, not merely contain the words.
  case "$body" in
    *"read_config_scalar"*|*"_config_value"*) : ;;
    *) echo "the router reads no config at all"; return 1 ;;
  esac
  case "$body" in
    *"REASON=disabled"*) : ;;
    *) echo "the router never emits REASON=disabled — the off branch does not exist"; return 1 ;;
  esac
}

@test "contract coverage: both recon_log values are exercised here and branched on by the router" {
  local v missing="" body
  body="$(_router_body)"
  for v in off on; do
    grep -l "\"recon_log: $v\"" "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
      || missing="$missing $v"
  done
  if [ -n "$missing" ]; then echo "recon_log values never exercised by a test:$missing"; return 1; fi
  case "$body" in
    *"recon_log"*) : ;;
    *) echo "the router never reads recon_log"; return 1 ;;
  esac
  # RH5 owns the key's DOCUMENTATION as well as its branch: an undocumented
  # enum is one nobody can set on purpose.
  grep -Eq "^# recon_log[[:space:]]+type: .+default: .+" "$EXAMPLE" \
    || { echo "recon_log has no type:/default: comment block in $EXAMPLE"; return 1; }
}

@test "contract coverage: all three recon_providers cases — a valid list, an empty value and gitnexus — are exercised" {
  local c missing="" body
  body="$(_router_body)"
  # The three literal config lines, each written by a test above.
  for c in "recon_providers: codegraph graphify tokensave" \
           "recon_providers:\"" \
           "recon_providers: \$list"; do
    grep -l "$c" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing="$missing [$c]"
  done
  if [ -n "$missing" ]; then echo "recon_providers cases never exercised:$missing"; return 1; fi
  grep -l 'gitnexus' "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
    || { echo "the gitnexus rejection has no test"; return 1; }
  case "$body" in
    *"recon_providers"*) : ;;
    *) echo "the router never reads recon_providers"; return 1 ;;
  esac
  case "$body" in
    *"gitnexus"*) : ;;
    *) echo "the router never rejects gitnexus"; return 1 ;;
  esac
  case "$body" in
    *"PolyForm-Noncommercial"*) : ;;
    *) echo "the router's gitnexus rejection never names the licence"; return 1 ;;
  esac
}

@test "contract coverage: recon_min_files 0 / below-threshold / at-threshold are covered by RH3's boundary tests" {
  # RH5 cross-references rather than duplicates: the 19/20 boundary and the
  # disabling 0 are RH3's ACs, and re-asserting them here would fork the
  # contract. What RH5 owns is that the key is DOCUMENTED and defaulted.
  [ -f "$GUARD_BATS" ] || { echo "missing $GUARD_BATS — RH3's boundary tests"; return 1; }
  local c missing=""
  for c in "FILES=19" "20 tracked files" "recon_min_files 0"; do
    grep -l "$c" "$GUARD_BATS" >/dev/null 2>&1 || missing="$missing [$c]"
  done
  if [ -n "$missing" ]; then echo "recon_min_files cases missing from $GUARD_BATS:$missing"; return 1; fi
  grep -Eq "^# recon_min_files[[:space:]]+type: .+default: .+" "$EXAMPLE" \
    || { echo "recon_min_files has no type:/default: comment block in $EXAMPLE"; return 1; }
}

@test "contract coverage: recon_max_lines is exercised below the cap and over it, with TRUNCATED and COUNT both asserted" {
  local c missing=""
  # The env override is part of the key's documented contract (recon.sh:122-123),
  # so its two junk forms are exercised alongside the two config ones: a value
  # the guard misses reaches `[[ -lt ]]` and takes the router out entirely.
  for c in "recon_max_lines: 100" "recon_max_lines: 3" "TRUNCATED=3/10" "STATUS=OK COUNT=10" \
           "RECON_MAX_LINES=abc" "RECON_MAX_LINES=-5"; do
    grep -l "$c" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing="$missing [$c]"
  done
  if [ -n "$missing" ]; then echo "recon_max_lines cases never exercised:$missing"; return 1; fi
  case "$(_router_body)" in
    *"recon_max_lines"*) : ;;
    *) echo "the router never reads recon_max_lines — the cap is env-only"; return 1 ;;
  esac
  # And the env override is numerically guarded, not interpolated straight into
  # the arithmetic comparison.
  case "$(_router_body)" in
    *'"${RECON_MAX_LINES:-$(_config_value'*)
      echo "RECON_MAX_LINES reaches the line cap unvalidated"; return 1 ;;
  esac
}

@test "contract coverage: recon_probe_max_age_minutes is exercised within the TTL and expired" {
  local c missing=""
  for c in "recon_probe_max_age_minutes: 4320" "recon_probe_max_age_minutes: 5" \
           "_not_ran codegraph" "_ran codegraph"; do
    grep -l "$c" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing="$missing [$c]"
  done
  if [ -n "$missing" ]; then echo "recon_probe_max_age_minutes cases never exercised:$missing"; return 1; fi
  case "$(_router_body)" in
    *"_config_value recon_probe_max_age_minutes"*|*"read_config_scalar \"\$CONFIG_FILE\" recon_probe_max_age_minutes"*) : ;;
    *) echo "the router never reads recon_probe_max_age_minutes from the config"; return 1 ;;
  esac
}

@test "contract coverage: every STATUS RH5 emits is asserted here, and the router emits nothing outside the closed seven" {
  local v missing_test="" body seen bad=""
  body="$(_router_body)"
  # The four RH5 produces: SKIP (off), DEGRADED (auto, zero providers),
  # UNAVAILABLE (both docs links down) and OK (the answer that still lands).
  for v in SKIP DEGRADED UNAVAILABLE OK; do
    grep -l "STATUS=$v" "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
      || missing_test="$missing_test $v"
    case "$body" in
      *"STATUS=$v"*) : ;;
      *) missing_test="$missing_test $v(router)" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "STATUS values RH5 owns but never asserts:$missing_test"; return 1; fi
  # RH5's own emission is the PAIR, not the two words: `disabled` is the only
  # REASON that can accompany SKIP without a FILES= count, and a router that
  # prints the status and the reason from two unrelated branches has not built
  # step 1 at all.
  case "$body" in
    *"STATUS=SKIP REASON=disabled"*) : ;;
    *) echo "the router never emits the pair STATUS=SKIP REASON=disabled"; return 1 ;;
  esac
  # The vocabulary is CLOSED at seven. A value outside it is a bug, not an
  # extension, so the router body is looped against the list rather than eyed.
  for seen in $(printf '%s\n' "$body" | grep -oE 'STATUS=[A-Z_]+' | sort -u); do
    case "$seen" in
      STATUS=OK|STATUS=EMPTY|STATUS=UNAVAILABLE|STATUS=SKIP|STATUS=DEGRADED|\
STATUS=NO_INTENT_MATCH|STATUS=DELEGATE) : ;;
      *) bad="$bad $seen" ;;
    esac
  done
  if [ -n "$bad" ]; then echo "router emits STATUS values outside the closed seven:$bad"; return 1; fi
}

@test "contract coverage: every recon key is documented, defaulted and read back — one list, four gates" {
  # The single list _recon_keys() feeds AC8, AC9, AC10 and the live-config DoD.
  # A key added to the router and to none of them would otherwise be invisible.
  local k missing_default="" missing_router="" body
  body="$(_router_body)"
  for k in $(_recon_keys); do
    grep -l "_assert_key_default" "$BATS_TEST_FILENAME" >/dev/null 2>&1 \
      || missing_default="$missing_default $k"
    case "$body" in
      *"$k"*) : ;;
      *) missing_router="$missing_router $k" ;;
    esac
  done
  if [ -n "$missing_default" ]; then echo "keys with no default assertion:$missing_default"; return 1; fi
  if [ -n "$missing_router" ]; then echo "keys the router never names:$missing_router"; return 1; fi
  # And the key set itself is the six the plan fixes — no more, no fewer.
  [ "$(_recon_keys | wc -l | tr -d ' ')" -eq 6 ]
}

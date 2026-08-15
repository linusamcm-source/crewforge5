#!/usr/bin/env bash
# recon.sh — capability router for the code-knowledge instruments. It collapses
# the providers' ~167 tools to 10 intents, resolves an ordered, language-filtered
# provider chain per intent, and prints exactly ONE STATUS= line per invocation.
# Agents declare WHAT they want to know; this script picks the access path from a
# probed capability catalogue cached in .recon/capabilities.json.
#
# The router answers *where*, never *what*: result lines carry file:line and a
# symbol, never source bodies, so a citation still costs the caller a Read.
#
# Usage:
#   recon.sh <intent> <arg…>   ask an intent (see the 10 below)
#   recon.sh --probe           resolve providers, refresh .recon/capabilities.json
#   recon.sh --no-delegate     caller cannot make MCP calls, so an MCP-only link
#                              is skipped exactly as an absent provider is and the
#                              chain advances (equivalently RECON_NO_MCP=1)
#   recon.sh --explain <intent> <arg…>   the plan only — see "--explain" below
#   recon.sh --help            this block, to stderr
#
#   Intents: text callers callees impact tests path dynamic coupling docs spans
#
# Single evaluation order — every status is decided in this sequence and the
# first match wins, so two live conditions can never race:
#   1. disabled          → STATUS=SKIP REASON=disabled
#   2. intent match      → STATUS=NO_INTENT_MATCH
#   3. small-repo guard  → STATUS=SKIP REASON=small-repo|not-a-repo
#   4. provider chain    → OK | EMPTY | DEGRADED | UNAVAILABLE | DELEGATE
#
# The small-repo guard (step 3) enforces the cost floor: below recon_min_files
# (default 20) a structural intent answers STATUS=SKIP REASON=small-repo
# FILES=<n> without touching a provider, because under about 20 files an agent
# can read everything directly and the graph adds overhead with no payoff. That
# rationale is quoted inline rather than cited because its source is untracked
# and never reaches a worktree; the owning story is RH3 of
# references/docs/plans/recon-harness-1.md. `text` is Tier 1 and stays cheap at any repo
# size, so it is exempt, and recon_min_files: 0 disables the guard entirely.
#
# Root resolution precedes the count. Outside a git repository the guard answers
# STATUS=SKIP REASON=not-a-repo FILES=0 and shells nothing at all; inside one
# the count is `git ls-files`, captured as `|| n=0` so a failing git can neither
# abort the script under pipefail nor invert the verdict — it counts zero and
# SKIPS, conservatively. The count shells no find at any point, so there is
# never an unscoped one (CLAUDE.md: never run find from / or ~).
#
# FRESHNESS is computed per provider against that provider's OWN max-age key, so
# moving one key never relabels another provider's answer:
#   codegraph  live only while a `codegraph status` daemon-liveness probe reports
#              an initialised project, read from STDOUT and never from the exit
#              code, which is 0 either way; otherwise the mtime fallback below.
#              Parsing that block needs python3, so with no interpreter the
#              probe cannot succeed and the answer takes the same fallback —
#              never a `live` the router did not verify.
#   graphify   graphify-out/graph.json vs graphify_max_age_minutes (default 240)
#   repomix    the pack vs repomix_max_age_minutes (default 240)
# fresh inside the max age, stale:<n>m outside it — staleness is reported, never
# silently corrected — and none when no index was consulted. Keys are read from
# ${TEAM_SPRINT_CONFIG:-<main-repo-root>/team-sprint.config.yaml}, resolved via
# repo_root() so a worktree CWD still reads the main tree's config, and each key
# carries its default here for the empty string an absent file or key returns.
#
# .recon/capabilities.json is revalidated against recon_probe_max_age_minutes
# (default 1440) on EVERY path, the bare intent form included — never merely
# checked for existence. A cache trusted past its TTL keeps a newly installed,
# newly indexed provider invisible and reports that silence as a confident
# not-installed, which is the worst answer this router can give. --probe reads
# NO entry from that cache: every provider's `indexed` and `languages` are
# re-resolved from the live index artifacts on each probe, so a graph built
# between two probes (phase-0.md step 9a, then 9b) is visible immediately
# instead of at the end of the TTL.
#
# Output: one grammar regardless of provider, so callers parse once.
#   PROVIDER=<name> INTENT=<intent> FRESHNESS=<live|fresh|stale:<n>m|none> QUERY=<arg>
#   <path>:<line>\t<symbol>\t<relation>
#   [TRUNCATED=<emitted>/<total>]
#   STATUS=<OK|EMPTY|UNAVAILABLE|SKIP|DEGRADED|NO_INTENT_MATCH|DELEGATE> …
#
#   STATUS= is mandatory and always last. The header line and COUNT= appear on
#   the two answer statuses (OK, EMPTY) only; every other status is a single
#   STATUS= line. REASON= is mandatory on SKIP/UNAVAILABLE/DEGRADED, from the
#   closed vocabulary disabled | small-repo | not-a-repo | not-installed |
#   no-index | language-unsupported | provider-error. FILES=<n> appears only on
#   STATUS=SKIP REASON=small-repo and on STATUS=SKIP REASON=not-a-repo FILES=0.
#   STATUS=DELEGATE additionally carries
#   PROVIDER=, INTENT= and ARGS=<json>; TOOL= only when a live MCP roster
#   supplied the name — bash cannot enumerate one, so it is never hardcoded.
#   --probe prints exactly one of STATUS=OK (every bash-probeable provider
#   resolved), STATUS=DEGRADED REASON=not-installed (some absent) or
#   STATUS=SKIP REASON=disabled (`recon: off`).
#   Result lines are capped at recon_max_lines (default 50); the trailing
#   TRUNCATED= marker is the only body line exempt from the result grammar and
#   COUNT= still reports the pre-truncation total.
#
# Exit codes:
#   0  verdict produced — every STATUS above is an answer, including
#      NO_INTENT_MATCH, DEGRADED and UNAVAILABLE, never an error
#   1  bad arguments (--help included), or a configuration this router refuses
#      to run under: `recon_providers` naming gitnexus, and `recon: on` with no
#      provider available at all — the Phase 0 gate, which fails LOUD where
#      `auto` degrades. Both WARN the reason to stderr through fail().
#
# Nothing else exits non-zero, so a capability probe that cannot PERSIST its
# cache (a read-only .recon/ or repo root) WARNs to stderr and degrades: every
# mode routes on "no capabilities" and still reaches its one STATUS= line.
# Aborting there printed ZERO STATUS lines and overloaded exit 1, which this
# table reserves for bad arguments.
#
# Config — six top-level scalars, read with lib.sh's read_config_scalar and each
# carrying its default HERE, because that helper returns the empty string for an
# absent file and an absent key alike and the two are indistinguishable:
#   recon                        off | auto | on (default auto). `off` is step 1
#                                of the evaluation order above; `on` makes
#                                --probe a hard Phase 0 gate that exits non-zero
#                                when NOT ONE provider resolved, while a partial
#                                set stays a reported degradation exactly as it
#                                is under `auto`.
#   recon_min_files              20 — the small-repo threshold; 0 disables it.
#   recon_providers              space-separated allow-list, default
#                                `codegraph graphify repomix tokensave`, and the
#                                ONLY provider opt-out: a name absent from it is
#                                skipped exactly as an absent binary is. An
#                                empty value takes the default chain, so zero
#                                providers is spelled `recon: off`. `gitnexus`
#                                is refused outright — it is licensed
#                                PolyForm-Noncommercial.
#   recon_log                    off | on (default on) — the call log below.
#   recon_max_lines              50 — the result-line cap; RECON_MAX_LINES in
#                                the environment overrides it for one call. Both
#                                take the same numeric guard, so a non-numeric or
#                                negative value in EITHER place falls back rather
#                                than reaching the arithmetic comparison.
#   recon_probe_max_age_minutes  1440 — the capability-cache TTL above.
#
# --explain prints the plan and runs nothing: one
# PROVIDER=<name> REASON=<why> or PROVIDER=<name> COMMAND=<argv> line per chain
# link — the PER-LINK reason vocabulary being not-installed | no-index |
# capability-mismatch | no-delegate — then exactly one
# STATUS=OK PROVIDER=<would-be> INTENT=<intent> when a link resolves, or
# STATUS=UNAVAILABLE REASON=<why> when none does. That terminal REASON comes
# from the CLOSED status vocabulary above, never from the wider per-link one:
# capability-mismatch maps to language-unsupported and no-delegate to
# not-installed, which is what the intent path reports for the same condition,
# so one condition never gets two names. The walk stops at the first link that
# resolves because the router stops there too. It shares step 3 with the intent
# path, so a sub-threshold repo answers STATUS=SKIP REASON=small-repo FILES=<n>
# here as well — describing a route the router would never walk is the one
# thing this mode cannot do. Being a mode and not an answer it carries no
# result header line and no COUNT=, exactly as --probe, it touches no provider,
# and it appends nothing to the call log.
#
# Call log — the evidence base for retiring a provider that never wins a chain,
# so it records the ROUTE taken and never the answer's content. Every intent
# invocation appends exactly ONE line to <main-repo-root>/.recon/calls.jsonl,
# resolved through repo_root() so a worktree CWD appends to the main tree's
# single log rather than growing an orphan one nobody reads. `.recon/` is added
# to the repo's .gitignore only when `git check-ignore -q .recon/` does not
# already match it, so a `/*`-whitelist .gitignore is left byte-identical, and
# a file whose last line carries no trailing newline gets one first so the
# appended rule cannot be concatenated onto — and destroy — that last rule.
# `recon_log: off` in the config disables the log; --probe and --explain answer
# no query and append nothing. Logging is an observer and never a gate: an
# unwritable .recon/ degrades to a stderr WARN and the query still answers.
#
#   Schema — a fixed-arity JSON object of exactly these eight keys:
#     {intent, provider, query, count, status, freshness, elapsed_ms, ts}
#   On the two answer statuses (OK, EMPTY) all eight carry values. On the five
#   non-answer statuses (SKIP, DEGRADED, UNAVAILABLE, NO_INTENT_MATCH,
#   DELEGATE) only intent, status, ts and elapsed_ms carry values, and
#   provider, count and freshness are explicit JSON null — present-and-null,
#   never absent, which is the fixed arity the Output grammar above already
#   commits the log to. An absent key is indistinguishable from a writer that
#   forgot the field. STATUS=DELEGATE names a PROVIDER= on its status line and
#   is still logged with a null provider: it is a delegation, not an answer,
#   and the two classes must stay distinguishable in the record.
#   elapsed_ms is a non-negative integer measured with lib.sh's now_ms(); ts is
#   a UTC ISO-8601 stamp.

set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "$0")/lib.sh"
# shellcheck source=/dev/null
source "$SCRIPTS/recon_providers.sh"

usage() {
  cat <<'USAGE' >&2
usage: recon.sh [--no-delegate] <intent> <arg...>
       recon.sh --explain [--no-delegate] <intent> <arg...>
       recon.sh --probe [--no-delegate]
       recon.sh --help

intents:
  text      where does this string occur          (repomix)
  callers   what calls X                          (codegraph -> graphify)
  callees   what does X call                      (codegraph -> graphify)
  impact    what breaks if I change X             (codegraph -> graphify)
  tests     which tests cover this change         (codegraph -> tokensave)
  path      how does A reach B                    (graphify -> codegraph)
  dynamic   who handles this callback/event       (codegraph -> tokensave)
  coupling  are A and B coupled                   (tokensave -> graphify)
  docs      what do the design docs say about X   (graphify -> repomix)
  spans     what files does feature W span        (graphify -> repomix)

modes:
  --probe         refresh .recon/capabilities.json and report provider health
  --explain       print the chain and the command each link would issue,
                  without running a provider and without logging the call
  --no-delegate   skip every MCP-only link (equivalently RECON_NO_MCP=1)
  --help          print this block and exit 1
USAGE
  exit 1
}

# Probe results older than this are re-resolved. Overwritten in main() from the
# config key recon_probe_max_age_minutes; with no config the default lives here.
RECON_PROBE_MAX_AGE_MINUTES=1440

# The default provider allow-list, taken by both an absent and an empty
# recon_providers: the two are indistinguishable to read_config_scalar.
RECON_DEFAULT_PROVIDERS="codegraph graphify repomix tokensave"

RECON_MODE="auto"
RECON_PROVIDERS="$RECON_DEFAULT_PROVIDERS"

MODE="intent"
NO_DELEGATE=0
INTENT=""
ARGS=()
ROOT=""
CAPS_FILE=""
CONFIG_FILE=""
PRIMARY_LANG=""
QUERY_LANG=""
START_MS=""

# recon_chain <intent> — echo the intent's ordered provider chain, or return 1
# when the intent is unknown. The chain is a preference: resolution filters each
# link by the languages that provider actually indexed.
recon_chain() {
  case "$1" in
    text)     printf 'repomix\n' ;;
    callers)  printf 'codegraph graphify\n' ;;
    callees)  printf 'codegraph graphify\n' ;;
    impact)   printf 'codegraph graphify\n' ;;
    tests)    printf 'codegraph tokensave\n' ;;
    path)     printf 'graphify codegraph\n' ;;
    dynamic)  printf 'codegraph tokensave\n' ;;
    coupling) printf 'tokensave graphify\n' ;;
    docs)     printf 'graphify repomix\n' ;;
    spans)    printf 'graphify repomix\n' ;;
    *)        return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Capability probe
# ---------------------------------------------------------------------------

recon_root() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root
  else
    pwd -P
  fi
}

_file_size() {
  stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

# _json_array <newline-list> — the list as a sorted, de-duplicated JSON array.
_json_array() {
  printf '%s\n' "$1" | jq -R -s 'split("\n") | map(select(length > 0)) | unique'
}

# _codegraph_facts — read `codegraph status` STDOUT (never its exit code, which
# is 0 even when the project is not initialised) and echo INDEXED=<bool> then one
# language per line from its `Files by Language:` block.
#
# The markers are the ones CodeGraph 1.5.0 actually prints: an un-initialised
# project gets a line ending `Not initialized`, an indexed one gets an
# `Index Statistics:` block and a trailing `Index is up to date`. It never
# prints a bare `Initialized`, so matching on that leaves codegraph permanently
# no-index in production.
#
# With no python3 the block cannot be parsed at all, so the catalogue is
# UNKNOWN and is reported as un-indexed — degrading the chain — rather than
# aborting: a bare heredoc here exits the router 127 with ZERO STATUS lines,
# breaking both the exit-code contract and the "STATUS= is mandatory and always
# last" grammar. The hint goes to stderr; stdout stays inside the grammar.
_codegraph_facts() {
  require_python3 || { printf 'INDEXED=false\n'; return 0; }
  python3 - "$1" <<'PY'
import re
import sys

ansi = re.compile(r"\x1b\[[0-9;]*m")
lines = [ansi.sub("", ln).rstrip() for ln in sys.argv[1].splitlines()]

indexed = False
for ln in lines:
    stripped = ln.strip()
    if stripped.endswith("Not initialized"):
        indexed = False
        break
    if stripped.startswith("Index Statistics:") or stripped.endswith(
        "Index is up to date"
    ):
        indexed = True
sys.stdout.write("INDEXED=%s\n" % ("true" if indexed else "false"))

in_block = False
for ln in lines:
    stripped = ln.strip()
    if stripped.startswith("Files by Language:"):
        in_block = True
        continue
    if in_block:
        if not stripped or not ln.startswith((" ", "\t")):
            break
        sys.stdout.write(stripped.split()[0] + "\n")
PY
}

# _probe_provider <name> — echo a one-key JSON object describing the provider.
#
# Nothing is served from the existing cache here, deliberately. A per-entry
# short-circuit on the (binary path, mtime, size) triple answered `indexed` and
# `languages` from the cache while the binary stood still — and an index is
# built without touching the binary, so a graph created between two probes
# stayed invisible for the whole recon_probe_max_age_minutes TTL (default 1440).
# That is the confident not-installed this router's header forbids, and it broke
# phase-0.md step 9a → 9b, which builds the graph and then probes it inside one
# Phase 0. The triple could never have covered it: it keys on the binary, and
# the index is not the binary. Re-resolution is what --probe IS.
_probe_provider() {
  local name="$1"
  local binname="$name" bin="" mt=0 sz=0 avail=false indexed=false langs='[]'
  local pack="${REPOMIX_PACK:-$ROOT/.repomix-output.xml}"
  local graph="$ROOT/graphify-out/graph.json"
  local facts line

  case "$name" in
    repomix)   binname="rtk" ;;
    tokensave) binname="" ;;
  esac

  if [[ -n "$binname" ]]; then
    bin="$(command -v "$binname" 2>/dev/null || true)"
  fi
  if [[ -n "$bin" ]]; then
    avail=true
    mt="$(mtime_epoch "$bin" 2>/dev/null || printf 0)"
    sz="$(_file_size "$bin" 2>/dev/null || printf 0)"
  fi

  case "$name" in
    repomix)
      if [[ -f "$pack" ]]; then
        indexed=true
        # Anchored, exactly as _recon_pack_hits indexes tags: a pack's own prose
        # quotes `<file path="…">` mid-line and those are not files.
        langs="$(_json_array "$(while IFS= read -r line; do
          line="${line#*<file path=\"}"
          _recon_lang_for_path "${line%%\"*}"
        done <<< "$(grep -o '^<file path="[^"]*">$' "$pack" 2>/dev/null || true)")")"
      fi
      ;;
    graphify)
      if [[ -f "$graph" ]]; then
        indexed=true
        langs="$(_json_array "$(jq -r '
          [.nodes[]?.metadata.language // empty] | unique | .[]' "$graph" 2>/dev/null || true)")"
      fi
      ;;
    codegraph)
      if [[ "$avail" == true ]]; then
        facts="$(_codegraph_facts "$(codegraph status 2>/dev/null || true)")"
        indexed="${facts%%$'\n'*}"
        indexed="${indexed#INDEXED=}"
        # With no `Files by Language:` block the payload is the INDEXED= line
        # alone; stripping "up to the first newline" from a string that has none
        # yields the marker itself, which would be cached as a language name.
        if [[ "$facts" == *$'\n'* ]]; then
          langs="$(_json_array "${facts#*$'\n'}")"
        fi
      fi
      ;;
    tokensave)
      # MCP-only and unreachable from bash, so the probe can neither confirm it
      # nor enumerate the languages it indexed. An unknown catalogue is treated
      # as "may answer" during chain resolution, never as a silent drop.
      ;;
  esac

  jq -n --arg p "$name" --argjson a "$avail" --argjson i "$indexed" \
        --argjson l "$langs" --arg v "" --arg b "$bin" \
        --argjson m "$mt" --argjson s "$sz" --argjson r "$(date +%s)" '
    {($p): {available: $a, indexed: $i, languages: $l, version: $v,
            binary: $b, binary_mtime: $m, binary_size: $s, resolved_at: $r}}'
}

# recon_probe — refresh the capability cache. Writes atomically: a validated
# temp file is moved into place, never an in-place edit.
#
# DEGRADES, never aborts: returns 1 after a stderr WARN when the cache cannot be
# created or persisted (a read-only .recon/ or repo root). Calling fail() here
# printed ZERO STATUS= lines and exited 1 — breaking both "STATUS= is mandatory
# and always last" and the exit-code table, which reserves 1 for bad arguments.
# Every caller routes on "no capabilities" instead, which resolves every
# provider not-installed: a reported degradation, still inside the grammar.
recon_probe() {
  local p entries tmp
  entries="$(mktemp "${TMPDIR:-/tmp}/recon-caps.XXXXXX" 2>/dev/null)" || {
    warn "recon.sh: cannot create a temp file for the capability probe"
    return 1
  }
  for p in repomix graphify codegraph tokensave; do
    _probe_provider "$p" >> "$entries"
  done
  mkdir -p "$(dirname "$CAPS_FILE")" 2>/dev/null || true
  tmp="$(mktemp "${CAPS_FILE}.tmp.XXXXXX" 2>/dev/null)" || {
    rm -f "$entries"
    warn "recon.sh: cannot write $CAPS_FILE — routing without a capability cache"
    return 1
  }
  jq -s --sort-keys --argjson r "$(date +%s)" \
    '{providers: add, resolved_at: $r}' "$entries" > "$tmp"
  rm -f "$entries"
  if jq -e '.providers' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$CAPS_FILE"
  else
    rm -f "$tmp"
    warn "recon.sh: capability probe produced invalid JSON — routing without a capability cache"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Config, small-repo guard and freshness
# ---------------------------------------------------------------------------

# _config_value <key> <default> — the config's top-level <key>, or <default>
# when the file, the key or a numeric value is absent. CONFIG_FILE is resolved
# from the MAIN repo root, never from $PWD: the config is untracked and is not
# copied into a node worktree, so a $PWD-relative lookup from a worktree CWD
# finds nothing and every recon key silently falls back to its default.
_config_value() {
  local v
  v="$(read_config_scalar "$CONFIG_FILE" "$1" 2>/dev/null || true)"
  v="$(printf '%s' "$v" | tr -d '[:space:]')"
  case "$v" in
    ''|*[!0-9]*) printf '%s\n' "$2" ;;
    *)           printf '%s\n' "$v" ;;
  esac
}

# _config_string <key> <default> — the config's top-level <key>, trimmed of its
# surrounding whitespace, or <default> when the file, the key or the value is
# empty. Sibling of _config_value for the keys that are not numeric; an empty
# value takes the default because read_config_scalar cannot tell one from an
# absent key.
_config_string() {
  local v
  v="$(read_config_scalar "$CONFIG_FILE" "$1" 2>/dev/null || true)"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  if [[ -z "$v" ]]; then
    printf '%s\n' "$2"
  else
    printf '%s\n' "$v"
  fi
}

# _reject_gitnexus — gitnexus is not a valid recon_providers value and naming it
# is a config error, not a silently dropped link. It is licensed
# PolyForm-Noncommercial, which this repo cannot use, and the message says so:
# a future reader must not have to rediscover why the obvious third tool is
# missing. Every position of the list is checked, not the first word.
_reject_gitnexus() {
  local p
  for p in $RECON_PROVIDERS; do
    [[ "$p" == "gitnexus" ]] || continue
    fail "recon.sh: recon_providers names gitnexus, which is licensed PolyForm-Noncommercial and cannot be used here — remove it from the list"
  done
}

# _filtered_chain <chain> — the intent's chain minus every provider absent from
# recon_providers. Dropping a name from that list is the ONLY provider opt-out,
# so a provider that is not on it is skipped exactly as an absent binary is, and
# a chain filtered empty reports UNAVAILABLE rather than answering.
_filtered_chain() {
  local p q out=""
  for p in $1; do
    for q in $RECON_PROVIDERS; do
      if [[ "$p" == "$q" ]]; then
        out="$out $p"
        break
      fi
    done
  done
  printf '%s\n' "${out# }"
}

# _tracked_count — the repo's tracked-file count, captured exactly as
# `n="$(git ls-files … | wc -l)" || n=0` so a git failure can neither abort the
# script under `set -euo pipefail` nor invert the guard's verdict: zero is below
# every positive threshold, so a broken git SKIPS. There is deliberately no
# working-tree `find` fallback — it counts UNTRACKED files, and a repo of 5
# tracked files beside 30 untracked ones would clear the threshold and proceed
# to full provider resolution precisely because git broke. No find also means no
# find to scope (CLAUDE.md: never run find from / or ~).
_tracked_count() {
  local n
  n="$(git -C "$ROOT" ls-files 2>/dev/null | wc -l)" || n=0
  printf '%s' "$n" | tr -d '[:space:]'
  printf '\n'
}

# recon_guard — step 3. Returns 1 after printing the terminal STATUS= line when
# the guard answers, 0 when the caller should proceed to provider resolution.
recon_guard() {
  local min n
  # `text` is Tier 1 and stays cheap at any repo size.
  [[ "$INTENT" != "text" ]] || return 0
  min="$(_config_value recon_min_files 20)"
  [[ "$min" -gt 0 ]] || return 0
  # Root validation precedes any find: outside a repo there is no scoped root to
  # search, and searching an unvalidated one means `find /`.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'STATUS=SKIP REASON=not-a-repo FILES=0\n'
    return 1
  fi
  n="$(_tracked_count)"
  if [[ "$n" -lt "$min" ]]; then
    printf 'STATUS=SKIP REASON=small-repo FILES=%s\n' "$n"
    return 1
  fi
  return 0
}

# _freshness_by_age <index> <max-minutes> — fresh inside the max age,
# stale:<n>m outside it. Callers guard on the index existing first: mtime_epoch
# aborts under `set -e` on an absent file.
_freshness_by_age() {
  local age
  age="$(( ( $(date +%s) - $(mtime_epoch "$1") ) / 60 ))"
  if [[ "$age" -le "$2" ]]; then
    printf 'fresh\n'
  else
    printf 'stale:%sm\n' "$age"
  fi
}

# _codegraph_live — true only while `codegraph status` reports an initialised,
# daemon-backed project. Read from STDOUT, never the exit code, which is 0 even
# when the project is not initialised: gating on the exit code claims `live` on
# a repo with no daemon at all.
_codegraph_live() {
  local facts
  command -v codegraph >/dev/null 2>&1 || return 1
  facts="$(_codegraph_facts "$(codegraph status 2>/dev/null || true)")"
  [[ "${facts%%$'\n'*}" == "INDEXED=true" ]]
}

# _freshness <provider> — the FRESHNESS= value for the provider that answered,
# graded against that provider's OWN max-age key so moving one key never
# relabels another provider's answer. `none` is the no-index-consulted value.
_freshness() {
  local idx
  case "$1" in
    graphify)
      idx="$ROOT/graphify-out/graph.json"
      [[ -f "$idx" ]] || { printf 'none\n'; return 0; }
      _freshness_by_age "$idx" "$(_config_value graphify_max_age_minutes 240)"
      ;;
    repomix)
      idx="${REPOMIX_PACK:-$ROOT/.repomix-output.xml}"
      [[ -f "$idx" ]] || { printf 'none\n'; return 0; }
      _freshness_by_age "$idx" "$(_config_value repomix_max_age_minutes 240)"
      ;;
    codegraph)
      if _codegraph_live; then
        printf 'live\n'
        return 0
      fi
      # No daemon confirmed the index, so codegraph falls back to the same
      # mtime computation the other two use. CodeGraph's own store is not
      # bash-discoverable, so the age is that of the capability cache — the
      # router's own record of when it last observed codegraph's index state —
      # graded against the TTL that record is trusted for.
      idx="$CAPS_FILE"
      [[ -f "$idx" ]] || { printf 'none\n'; return 0; }
      _freshness_by_age "$idx" "$RECON_PROBE_MAX_AGE_MINUTES"
      ;;
    *)
      printf 'none\n'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Chain resolution
# ---------------------------------------------------------------------------

_caps_bool() {
  jq -e --arg p "$1" --arg k "$2" '.providers[$p][$k] == true' \
    "$CAPS_FILE" >/dev/null 2>&1
}

# _any_provider_available — true when at least one ALLOWED provider resolved.
# The `recon: on` gate reads this, not the three-provider conjunction --probe
# reports STATUS=OK on: a partial set still answers questions.
_any_provider_available() {
  local p
  for p in $RECON_PROVIDERS; do
    if _caps_bool "$p" available; then
      return 0
    fi
  done
  return 1
}

# _caps_fresh — true when the capability cache exists AND was resolved inside
# RECON_PROBE_MAX_AGE_MINUTES. The intent path gates on this, not on mere file
# existence: a cache that is trusted forever keeps an installed, indexed
# provider invisible and turns "resolved absent once" into a permanent, and
# confidently reported, not-installed.
_caps_fresh() {
  [[ -f "$CAPS_FILE" ]] || return 1
  jq -e --argjson now "$(date +%s)" \
        --argjson ttl "$(( RECON_PROBE_MAX_AGE_MINUTES * 60 ))" \
        '($now - (.resolved_at // 0)) <= $ttl' "$CAPS_FILE" >/dev/null 2>&1
}

# _primary_language — the repo's dominant code language, from the tracked files
# of the resolved ROOT, never of the caller's CWD: `git ls-files` from a
# subdirectory lists only that subtree and would mis-read the repo's language.
_primary_language() {
  local f counted top
  counted="$( (git -C "$ROOT" ls-files 2>/dev/null || true) | while IFS= read -r f; do
    _recon_lang_for_path "$f"
  done | grep -v '^$' | sort | uniq -c | sort -rn || true)"
  [[ -n "$counted" ]] || return 0
  # `uniq -c` emits "<count> <language>"; the language is the trailing field.
  top="$(printf '%s\n' "$counted" | head -1)"
  printf '%s\n' "${top##*[[:space:]]}"
}

# _query_language — the language the ARGUMENT names, when one names a language
# at all: `recon.sh callers src/auth/session.ts` is a question about typescript
# whatever the rest of the repo is written in. A bare symbol name implies no
# language and yields the empty string, which falls the gate back to
# PRIMARY_LANG. The first argument that maps wins; the rest are companions
# (`coupling A B`, `path A B`) and cannot disagree usefully.
_query_language() {
  local a l
  for a in ${ARGS[@]+"${ARGS[@]}"}; do
    l="$(_recon_lang_for_path "$a")"
    if [[ -n "$l" ]]; then
      printf '%s\n' "$l"
      return 0
    fi
  done
}

# _lang_ok <provider> — true when the provider indexed the QUERY's language, or
# the repo's primary language when the query named none. A provider that did not
# is skipped exactly as if it were absent.
#
# The query's language wins because the repo's primary language is a majority
# vote: in a polyglot tree it let a provider that had indexed only the majority
# answer a question about a file in another language — codegraph indexes no
# shell at all, so it reported STATUS=EMPTY COUNT=0 for every bash symbol in a
# js-majority repo. That is the confident false negative this whole chain exists
# to prevent.
#
# Fails CLOSED when no language could be derived either way (an Elixir/Lua/Dart/…
# repo, a docs-only repo, a non-git directory): the catalogue cannot be checked,
# so the honest answer is language-unsupported. Failing open let a provider that
# had demonstrably indexed some other language answer STATUS=EMPTY COUNT=0 —
# a confident false negative, which AC 11 forbids outright.
#
# `text` is EXEMPT: it is a full-text grep over the pack, not a parse. repomix
# indexes no language, its catalogue is derived from the pack's own
# `<file path=…>` tags, and a query is a search string that may look like a
# filename — so gating it refused `text session.ts` in a repo with no TypeScript
# while the pack held real hits, on the one chain that could have answered.
_lang_ok() {
  [[ "$INTENT" != "text" ]] || return 0
  local lang="${QUERY_LANG:-$PRIMARY_LANG}"
  [[ -n "$lang" ]] || return 1
  jq -e --arg p "$1" --arg l "$lang" \
    '(.providers[$p].languages // []) | index($l) != null' \
    "$CAPS_FILE" >/dev/null 2>&1
}

# recon_answer <provider> <adapter-body> — emit the header, the capped result
# lines and the terminal STATUS= line.
recon_answer() {
  local provider="$1" body="$2" freshness
  # RECON_MAX_LINES is the one-invocation override; recon_max_lines is the
  # persistent setting and 50 the hardcoded default behind both.
  #
  # The override is guarded with the SAME numeric test _config_value applies to
  # the config value, and for the same reason: it lands in an arithmetic `-lt`
  # below, where a non-numeric value aborts the router under `set -u` — exit 1
  # and ZERO STATUS= lines, breaking both the mandatory-STATUS grammar and the
  # exit table, which reserves 1 for bad arguments and a refused config. A
  # negative one does not abort; it silently emits no rows at all. Junk in the
  # environment falls back to the configured cap rather than doing either.
  local max
  max="$(_config_value recon_max_lines 50)"
  case "${RECON_MAX_LINES:-}" in
    ''|*[!0-9]*) : ;;
    *)           max="$RECON_MAX_LINES" ;;
  esac
  local -a results=()
  local line total=0 i=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      TOTAL=*) total="${line#TOTAL=}"; continue ;;
    esac
    results[${#results[@]}]="$line"
  done <<< "$body"

  # FRESHNESS is mandatory on the answer statuses and is graded against the
  # answering provider's own max-age key.
  freshness="$(_freshness "$provider")"
  printf 'PROVIDER=%s INTENT=%s FRESHNESS=%s QUERY=%s\n' \
    "$provider" "$INTENT" "$freshness" "${ARGS[*]-}"
  while [[ "$i" -lt "${#results[@]}" && "$i" -lt "$max" ]]; do
    printf '%s\n' "${results[$i]}"
    i=$((i + 1))
  done
  if [[ "${#results[@]}" -gt "$max" ]]; then
    printf 'TRUNCATED=%s/%s\n' "$max" "$total"
  fi
  if [[ "${#results[@]}" -eq 0 && "$total" -eq 0 ]]; then
    printf 'STATUS=EMPTY COUNT=0\n'
  else
    printf 'STATUS=OK COUNT=%s\n' "$total"
  fi
}

# recon_resolve <chain> — walk the chain and emit exactly one STATUS= line.
# A link that cannot answer for ANY reason (absent binary, missing index, wrong
# language, MCP-only under --no-delegate, provider error) is skipped and the
# chain advances; only the terminal link's reason is reported. A zero-exit
# provider with no results is terminal: that is an answer (EMPTY), not a skip.
recon_resolve() {
  local chain="$1"
  local p reason="" all_absent=1 rc out

  for p in $chain; do
    if [[ "$p" == "tokensave" ]]; then
      if [[ "$NO_DELEGATE" -eq 1 ]]; then
        all_absent=0
        continue
      fi
      recon_adapter_tokensave "$INTENT" ${ARGS[@]+"${ARGS[@]}"}
      return 0
    fi

    if ! _caps_bool "$p" available; then
      reason="not-installed"
      continue
    fi
    if ! _caps_bool "$p" indexed; then
      reason="no-index"
      all_absent=0
      continue
    fi
    if ! _lang_ok "$p"; then
      reason="language-unsupported"
      all_absent=0
      continue
    fi

    rc=0
    out="$("recon_adapter_$p" "$INTENT" ${ARGS[@]+"${ARGS[@]}"})" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      reason="provider-error"
      all_absent=0
      continue
    fi
    recon_answer "$p" "$out"
    return 0
  done

  # No provider on the chain is installed at all — the whole instrument set is
  # missing rather than this one question being unanswerable.
  if [[ "$all_absent" -eq 1 && "$reason" == "not-installed" ]]; then
    printf 'STATUS=DEGRADED REASON=not-installed\n'
  else
    printf 'STATUS=UNAVAILABLE REASON=%s\n' "${reason:-not-installed}"
  fi
}

# ---------------------------------------------------------------------------
# --explain — the plan, never the query
# ---------------------------------------------------------------------------

# _explain_command <provider> — the command that provider's adapter WOULD run
# for the current intent and args. graphify's and codegraph's argv come from the
# very helpers their adapters use (recon_providers.sh), so what --explain prints
# is what would really be issued and not a second map free to drift.
_explain_command() {
  case "$1" in
    graphify)
      printf 'graphify %s %s\n' "$(_recon_graphify_sub "$INTENT")" "${ARGS[*]-}" ;;
    codegraph)
      printf 'codegraph %s %s\n' "$(_recon_codegraph_argv "$INTENT")" "${ARGS[*]-}" ;;
    repomix)
      printf 'rtk grep %s %s\n' "${ARGS[*]-}" "${REPOMIX_PACK:-$ROOT/.repomix-output.xml}" ;;
    tokensave)
      # MCP-only: there is no shell command, and no tool name is hardcoded
      # because bash cannot enumerate a roster.
      printf 'mcp-delegate\n' ;;
  esac
}

# recon_explain <chain> — print the plan for INTENT without touching a provider:
# one line per chain link — either the reason that link cannot answer or the
# command it would issue — then exactly one terminal STATUS= line.
#
# The walk stops at the first link that resolves because the router itself stops
# there; the links behind it are never reached, and listing them as if they were
# would misdescribe the route this is here to describe. The skip reasons are
# --explain's own vocabulary: `capability-mismatch` says the provider did not
# index this repo's language, which is the false negative the whole chain exists
# to prevent — silence from a provider that cannot parse the language must never
# read as "nothing found".
recon_explain() {
  local chain="$1"
  local p reason resolved="" last_reason=""
  for p in $chain; do
    reason=""
    if [[ "$p" == "tokensave" ]]; then
      [[ "$NO_DELEGATE" -eq 0 ]] || reason="no-delegate"
    elif ! _caps_bool "$p" available; then
      reason="not-installed"
    elif ! _caps_bool "$p" indexed; then
      reason="no-index"
    elif ! _lang_ok "$p"; then
      reason="capability-mismatch"
    fi
    if [[ -n "$reason" ]]; then
      printf 'PROVIDER=%s REASON=%s\n' "$p" "$reason"
      last_reason="$reason"
      continue
    fi
    printf 'PROVIDER=%s COMMAND=%s\n' "$p" "$(_explain_command "$p")"
    resolved="$p"
    break
  done

  if [[ -n "$resolved" ]]; then
    printf 'STATUS=OK PROVIDER=%s INTENT=%s\n' "$resolved" "$INTENT"
  else
    # The per-link vocabulary is --explain's own and wider than the STATUS=
    # one, so it is MAPPED into the closed set rather than leaked onto the
    # terminal line — and mapped to whatever the intent path reports for the
    # identical condition, so one condition never gets two names: a provider
    # that did not index this repo's language is language-unsupported there,
    # and an MCP-only link skipped under --no-delegate leaves the chain
    # reporting not-installed.
    case "$last_reason" in
      capability-mismatch) last_reason="language-unsupported" ;;
      no-delegate|'')      last_reason="not-installed" ;;
    esac
    printf 'STATUS=UNAVAILABLE REASON=%s\n' "$last_reason"
  fi
}

# ---------------------------------------------------------------------------
# The call log
# ---------------------------------------------------------------------------

# _recon_gitignore — make git ignore the .recon/ artifact dir, but ONLY when it
# does not already: against a `/*`-whitelist .gitignore (the shape ~/.claude
# itself uses) check-ignore already matches and an appended line would be
# redundant churn in a tracked file. rc 0 = already ignored, rc 1 = not ignored,
# anything else (128 outside a work tree) is an error this does not act on.
#
# A .gitignore whose last line carries no trailing newline gets one first: a
# bare `>>` otherwise CONCATENATES onto that rule, yielding `node_modules.recon/`
# — which ignores neither the destroyed rule nor .recon/, so check-ignore still
# misses and every subsequent invocation appends again.
_recon_gitignore() {
  local rc=0
  git -C "$ROOT" check-ignore -q .recon/ >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]] || return 0
  {
    if [[ -s "$ROOT/.gitignore" && -n "$(tail -c 1 "$ROOT/.gitignore")" ]]; then
      printf '\n' >> "$ROOT/.gitignore"
    fi
    printf '.recon/\n' >> "$ROOT/.gitignore"
  } 2>/dev/null \
    || warn "recon.sh: cannot append .recon/ to $ROOT/.gitignore"
}

# recon_log <router-output> — append this invocation's one line to
# <root>/.recon/calls.jsonl.
#
# The record is derived from the STATUS grammar the router just printed rather
# than from a variable every branch must remember to set: a status that forgot
# to log itself would otherwise be invisible, and this log exists precisely to
# make silence visible. The line is built by jq, never by printf, so a query
# carrying a quote, a backslash or a tab is escaped rather than corrupting the
# record — an unparseable line reads downstream as a provider that was never
# asked, the same false negative the UNAVAILABLE branch exists to prevent.
recon_log() {
  local out="$1"
  local cfg status sval header provider="" freshness="" count="" now line
  local elapsed=0
  local log="$ROOT/.recon/calls.jsonl"

  cfg="$(read_config_scalar "$CONFIG_FILE" recon_log 2>/dev/null || true)"
  case "$(printf '%s' "$cfg" | tr -d '[:space:]')" in
    off|false|no|0) return 0 ;;
  esac

  status="$(printf '%s\n' "$out" | grep '^STATUS=' | tail -n 1 || true)"
  sval="${status#STATUS=}"
  sval="${sval%% *}"
  # provider, count and freshness are read from the ANSWER header only, so the
  # five non-answer statuses log them as explicit null.
  case "$sval" in
    OK|EMPTY)
      header="$(printf '%s\n' "$out" \
        | grep -E '^PROVIDER=.*INTENT=.*FRESHNESS=.*QUERY=' | head -n 1 || true)"
      provider="${header#PROVIDER=}";    provider="${provider%% *}"
      freshness="${header#*FRESHNESS=}"; freshness="${freshness%% *}"
      count="${status#*COUNT=}";         count="${count%% *}"
      # A non-numeric count would abort the jq below on `tonumber` and cost the
      # whole record; an absent one is logged as null instead.
      case "$count" in ''|*[!0-9]*) count="" ;; esac
      ;;
  esac

  now="$(now_ms 2>/dev/null || true)"
  if [[ "$START_MS" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]]; then
    elapsed=$(( now - START_MS ))
  fi
  # elapsed_ms is contractually non-negative, so a clock that stepped backwards
  # mid-invocation records 0 rather than a negative integer.
  [[ "$elapsed" -ge 0 ]] || elapsed=0

  line="$(jq -cn --arg i "$INTENT" --arg q "${ARGS[*]-}" --arg s "$sval" \
        --arg p "$provider" --arg f "$freshness" --arg c "$count" \
        --argjson e "$elapsed" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {intent: $i,
     provider: (if $p == "" then null else $p end),
     query: $q,
     count: (if $c == "" then null else ($c | tonumber) end),
     status: $s,
     freshness: (if $f == "" then null else $f end),
     elapsed_ms: $e,
     ts: $t}')"

  mkdir -p "$ROOT/.recon" 2>/dev/null || true
  # The log is an observer, never a gate: an unwritable .recon/ is REPORTED and
  # the query still answers. A log that silently stops recording is the one
  # failure mode that corrupts the evidence base without showing up in an answer.
  if { printf '%s\n' "$line" >> "$log"; } 2>/dev/null; then
    _recon_gitignore
  else
    warn "recon.sh: cannot append to $log — this call went unrecorded"
  fi
}

# recon_query — steps 2 to 4 of the evaluation order, emitting the verdict for
# the intent mode. Its stdout is redirected to a temp file rather than captured
# with `$( )`: bash 3.2 has no `shopt -s inherit_errexit`, so inside a command
# substitution `set -e` is INERT, and a failing command anywhere under this
# function — recon_guard, _primary_language, recon_resolve or an adapter — would
# be silently stepped over instead of surfacing.
recon_query() {
  local chain
  # Step 1 — disabled. It precedes the intent match, so an unknown intent under
  # `recon: off` is still the SKIP: two live conditions never race.
  if [[ "$RECON_MODE" == "off" ]]; then
    printf 'STATUS=SKIP REASON=disabled\n'
    return 0
  fi

  # Step 2 — intent match. An unrecognised intent is an answer, not an error:
  # the caller falls back to free-form exploration.
  if ! chain="$(recon_chain "$INTENT")"; then
    printf 'STATUS=NO_INTENT_MATCH\n'
    return 0
  fi
  chain="$(_filtered_chain "$chain")"

  # Step 3 — the small-repo guard, ahead of provider resolution: below the
  # threshold no provider is touched at all, not even by the capability probe.
  recon_guard || return 0

  # Step 4 — provider resolution. The cache is revalidated HERE too, not only
  # under --probe: an existing but expired cache is re-resolved rather than
  # trusted forever. A probe that could not persist has already WARNed; the walk
  # then reads no cache and resolves every provider not-installed, which is a
  # STATUS= line rather than an abort.
  _caps_fresh || recon_probe || true
  PRIMARY_LANG="$(_primary_language)"
  QUERY_LANG="$(_query_language)"
  recon_resolve "$chain"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)     usage ;;
      --probe)       MODE="probe"; shift ;;
      --explain)     MODE="explain"; shift ;;
      --no-delegate) NO_DELEGATE=1; shift ;;
      -*)            usage ;;
      *)
        if [[ -z "$INTENT" ]]; then
          INTENT="$1"
        else
          ARGS[${#ARGS[@]}]="$1"
        fi
        shift ;;
    esac
  done

  [[ -z "${RECON_NO_MCP:-}" ]] || NO_DELEGATE=1
  require_jq || exit 1

  ROOT="$(recon_root)"
  CAPS_FILE="$ROOT/.recon/capabilities.json"
  CONFIG_FILE="${TEAM_SPRINT_CONFIG:-$ROOT/team-sprint.config.yaml}"
  # Read by recon_providers.sh so an adapter resolves the same cache — and the
  # same pack / interpreter cache — the router does, whatever the caller's CWD.
  # shellcheck disable=SC2034
  RECON_CAPS_FILE="$CAPS_FILE"
  # shellcheck disable=SC2034
  RECON_ROOT="$ROOT"

  RECON_MODE="$(_config_string recon auto)"
  RECON_PROVIDERS="$(_config_string recon_providers "$RECON_DEFAULT_PROVIDERS")"
  RECON_PROBE_MAX_AGE_MINUTES="$(_config_value recon_probe_max_age_minutes 1440)"
  # A refused config is refused in every mode, ahead of step 1: it is a broken
  # setting, not a route this router could take.
  _reject_gitnexus

  # Step 1 (disabled) for the two modes that are not a call. The intent mode
  # takes it inside recon_query instead, so a disabled SKIP is still recorded in
  # the call log exactly as every other intent invocation is.
  if [[ "$RECON_MODE" == "off" && "$MODE" != "intent" ]]; then
    printf 'STATUS=SKIP REASON=disabled\n'
    exit 0
  fi

  if [[ "$MODE" == "probe" ]]; then
    # A probe that could not persist its cache still owes exactly one STATUS=
    # line; with no cache to read every _caps_bool below is false, so that line
    # is STATUS=DEGRADED REASON=not-installed.
    recon_probe || true
    if _caps_bool repomix available \
       && _caps_bool graphify available \
       && _caps_bool codegraph available; then
      printf 'STATUS=OK\n'
      exit 0
    fi
    # `recon: on` is the Phase 0 gate and fails LOUD where `auto` degrades — but
    # on ABSENCE, never on the enum value: with any provider resolved the sprint
    # still has an instrument, which is a reported degradation and not a reason
    # to abort. Only "not one of them is here" removes the router's premise.
    if [[ "$RECON_MODE" == "on" ]] && ! _any_provider_available; then
      fail "recon.sh: recon: on but no provider is available — install one, drop a name back into recon_providers, or set recon: auto"
    fi
    printf 'STATUS=DEGRADED REASON=not-installed\n'
    exit 0
  fi

  if [[ "$MODE" == "explain" ]]; then
    local plan
    if plan="$(recon_chain "$INTENT")"; then
      # Step 3 is SHARED with the intent path, not skipped: the guard precedes
      # chain resolution in the single evaluation order, so below the threshold
      # the router walks no chain at all and a PROVIDER= line here would
      # describe a route that never runs — the one thing the mode whose whole
      # job is describing the route cannot do.
      recon_guard || exit 0
      _caps_fresh || recon_probe || true
      PRIMARY_LANG="$(_primary_language)"
      QUERY_LANG="$(_query_language)"
      recon_explain "$(_filtered_chain "$plan")"
    else
      printf 'STATUS=NO_INTENT_MATCH\n'
    fi
    exit 0
  fi

  # The intent mode is the only one that is a CALL. Its stdout is recorded so
  # the same bytes can be printed to the caller AND parsed into the single call
  # log line, and the clock starts before step 2 so elapsed_ms covers the whole
  # route rather than only the provider exec. A temp file, not `$( )`: on bash
  # 3.2 (no inherit_errexit) a command substitution runs the whole router with
  # `set -e` inert.
  START_MS="$(now_ms 2>/dev/null || true)"
  local out out_file
  out_file="$(mktemp "${TMPDIR:-/tmp}/recon-out.XXXXXX")"
  recon_query > "$out_file"
  out="$(cat "$out_file")"
  rm -f "$out_file"
  printf '%s\n' "$out"
  recon_log "$out"
  exit 0
}

main "$@"

#!/usr/bin/env bash
# shellcheck shell=bash
# recon_providers.sh — one provider adapter per recon provider (Story RH1).
# SOURCED, not executed: it defines functions and runs nothing at source time.
#
# Adapter contract:
#   recon_adapter_<provider> <intent> <arg>...
#     stdout : zero or more `<path>:<line>\t<symbol>\t<relation>` result lines,
#              then exactly one trailing `TOTAL=<n>` line carrying the
#              PRE-truncation hit total. recon.sh turns TOTAL= into COUNT= and
#              never re-emits it. The tokensave adapter is the documented
#              exception: being MCP-only it emits its own `STATUS=DELEGATE …`
#              line and no TOTAL.
#     return : 0 when the provider answered, else $RECON_ADAPTER_ERROR — the
#              documented failure sentinel — for an absent binary, an absent
#              index, no usable interpreter, a non-zero provider exit, provider
#              stdout this normaliser cannot parse at all, or an MCP-only link
#              under RECON_NO_MCP=1. recon.sh maps the sentinel to the next link
#              in the chain; an adapter never aborts the shell.
#
#              `rtk grep` is the documented exception to "non-zero exit": it
#              follows grep(1), so exit 1 with empty stdout means "nothing
#              matched" — an answer worth TOTAL=0, not a failure. Only exit >1
#              (or an exit 1 that still printed something) is the sentinel.
#
#              Unreadable output is a sentinel and NOT zero rows on purpose:
#              zero rows is an answer (STATUS=EMPTY COUNT=0) and a confident
#              empty over a real answer is the worst failure this router has.
#              Genuinely empty provider stdout still reports TOTAL=0. Rows that
#              parsed but that the intent's own filter then discarded are the
#              same case and take the same sentinel — see _recon_graphify_keep.
#              So is JSON that parses cleanly but carries no result key this
#              normaliser knows — see _recon_codegraph_json_known.
#
# Environment read from the router (recon.sh sets both before resolution):
#   RECON_ROOT       the resolved repo root. Every artifact an adapter opens —
#                    the repomix pack, graphify-out/.graphify_python — is
#                    resolved from it, never from the caller's CWD, and every
#                    provider CLI that resolves its own index relative to $PWD
#                    (graphify does) is RUN from it, so an answer does not
#                    depend on which directory the caller stood in.
#   RECON_CAPS_FILE  the capability cache the router already resolved.
#
# The router answers *where*, never *what*: no adapter emits source-code
# bodies. `codegraph explore` and `codegraph node` both fence real source, so
# the text normaliser drops every fenced block before extracting coordinates.

# Guard against double-source (set -u trips on re-sourcing if guard absent).
if [[ -n "${RECON_PROVIDERS_LOADED:-}" ]]; then
  return 0
fi
RECON_PROVIDERS_LOADED=1

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# The failure sentinel. Callers compare against this variable, never a literal.
RECON_ADAPTER_ERROR=3

# ---------------------------------------------------------------------------
# Shared emitters
# ---------------------------------------------------------------------------

# _recon_emit_body <body> — print every non-empty line of <body> followed by
# the mandatory trailing TOTAL= marker.
_recon_emit_body() {
  local body="$1" line n=0
  if [[ -n "$body" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf '%s\n' "$line"
      n=$((n + 1))
    done <<< "$body"
  fi
  printf 'TOTAL=%s\n' "$n"
}

# _recon_lang_for_path <path> — echo the language a source extension implies,
# or "" for a non-code file. Documents, configs and data deliberately map to
# nothing so they never win the primary-language vote.
_recon_lang_for_path() {
  case "$1" in
    *.sh|*.bash|*.bats) printf 'bash\n' ;;
    *.py)               printf 'python\n' ;;
    *.ts|*.tsx)         printf 'typescript\n' ;;
    *.js|*.jsx|*.mjs|*.cjs) printf 'javascript\n' ;;
    *.go)               printf 'go\n' ;;
    *.rb)               printf 'ruby\n' ;;
    *.rs)               printf 'rust\n' ;;
    *.java)             printf 'java\n' ;;
    *.c|*.h)            printf 'c\n' ;;
    *.cc|*.cpp|*.cxx|*.hpp) printf 'cpp\n' ;;
    *.cs)               printf 'csharp\n' ;;
    *.swift)            printf 'swift\n' ;;
    *.php)              printf 'php\n' ;;
    *.kt)               printf 'kotlin\n' ;;
    *.vue)              printf 'vue\n' ;;
    *)                  printf '\n' ;;
  esac
}

# _recon_caps_declares <provider> — true when the router's capability cache
# already resolved <provider> as available. The cache IS the probe result, so
# an adapter reached through the router does not re-probe what the probe
# already answered (same rationale as the --probe TTL).
_recon_caps_declares() {
  local caps="${RECON_CAPS_FILE:-.recon/capabilities.json}"
  [[ -f "$caps" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg p "$1" '.providers[$p].available == true' "$caps" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# repomix — `rtk grep` over the repomix pack
# ---------------------------------------------------------------------------

# The pack is a concatenation, so an rtk hit's line number is a PACK offset,
# not a source coordinate. Index the `<file path=` tag offsets once, then emit
# (owning path, pack line − tag line) for each hit.
#
# The tag pattern is ANCHORED to a whole line (`^<file path="…">$`). A pack
# carries prose ABOUT packs — the live one has 27 lines quoting `<file path=`
# mid-sentence — and an unanchored match promotes each of those to a tag, after
# which every downstream hit is credited to a fabricated path at a wrong line.
# A citation the caller cannot Read is worse than no citation.
#
# Returns $RECON_ADAPTER_ERROR when hits arrived and none of them could be
# attributed to a tag — a pack in a style this index cannot read is unreadable
# output, never zero results.
_recon_pack_hits() {
  local pack="$1" hits="$2"
  local more_re='\+([0-9]+) more in '
  local -a tag_lines=()
  local -a tag_paths=()
  local line num rest path i best more=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    num="${line%%:*}"
    rest="${line#*:}"
    path="${rest#*<file path=\"}"
    path="${path%%\"*}"
    tag_lines[${#tag_lines[@]}]="$num"
    tag_paths[${#tag_paths[@]}]="$path"
  done <<< "$(grep -n '^<file path="[^"]*">$' "$pack" 2>/dev/null || true)"

  local body="" emitted=0 candidates=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # A result line is STRICTLY `<n>:<text>` — the prefix must be WHOLLY
    # numeric, not merely digit-initial. Every truncated `rtk grep` run opens
    # with `<n> matches in <m> files:`, which passes the looser "starts with a
    # digit, has a colon" test; its prefix is then evaluated arithmetically
    # below, which aborts the adapter under `set -u` and makes the whole `text`
    # intent report REASON=provider-error against the live pack.
    num="${line%%:*}"
    case "$line" in
      [0-9]*:*) ;;
      *)        num="" ;;
    esac
    case "$num" in
      ''|*[!0-9]*)
        if [[ "$line" =~ $more_re ]]; then
          more="${BASH_REMATCH[1]}"
        fi
        continue ;;
    esac
    rest="${line#*:}"
    candidates=$((candidates + 1))
    best=-1
    i=0
    while [[ "$i" -lt "${#tag_lines[@]}" ]]; do
      if [[ "${tag_lines[$i]}" -lt "$num" ]]; then
        best="$i"
      fi
      i=$((i + 1))
    done
    [[ "$best" -ge 0 ]] || continue
    body="${body}$(printf '%s:%s\t%s\tmatch' \
      "${tag_paths[$best]}" "$(( num - ${tag_lines[$best]} ))" \
      "$(printf '%s' "$rest" | tr '\t' ' ')")
"
    emitted=$((emitted + 1))
  done <<< "$hits"

  # Hits arrived and NOT ONE could be credited to a tag: the pack is in a style
  # this index cannot read, which is "I do not know" and not "nothing found".
  # Returning the sentinel advances the chain, exactly as recon_adapter_graphify
  # does for output its normaliser cannot read; TOTAL=0 here would print a
  # confident STATUS=EMPTY COUNT=0 over hits rtk really returned. Genuinely
  # empty rtk output has no candidates at all and stays an answer.
  if [[ "$candidates" -gt 0 && "$emitted" -eq 0 ]]; then
    return "$RECON_ADAPTER_ERROR"
  fi

  if [[ -n "$body" ]]; then
    printf '%s' "$body"
  fi
  # COUNT= for `text` is the PRE-truncation total: rtk's `+<n> more in <file>`
  # trailer is the only source of it, and with no trailer it is the hit count.
  printf 'TOTAL=%s\n' "$(( emitted + more ))"
}

recon_adapter_repomix() {
  shift  # <intent> — repomix serves `text` (and `docs` as a fallback) alike
  local pattern="${1:-}"
  # RECON_ROOT is the router's resolved repo root. Resolving the pack from CWD
  # instead would make the same query answer OK from the root and UNAVAILABLE
  # from any subdirectory, blaming a provider that never errored.
  local pack="${REPOMIX_PACK:-${RECON_ROOT:-.}/.repomix-output.xml}"
  command -v rtk >/dev/null 2>&1 || return "$RECON_ADAPTER_ERROR"
  [[ -f "$pack" ]] || return "$RECON_ADAPTER_ERROR"
  local hits rc=0
  # Explicit `rtk grep`, never a bare grep/rg: a bare grep on a pack returns
  # full-width XML lines and floods context (CLAUDE.md "Codebase recon
  # instruments").
  hits="$(rtk grep "$pattern" "$pack" 2>/dev/null)" || rc=$?
  # `rtk grep` inherits grep(1)'s exit codes: 1 means "nothing matched", which
  # is an ANSWER (STATUS=EMPTY COUNT=0) and not a provider failure. Mapping it
  # to the sentinel made the commonest negative query on the single-link `text`
  # chain report UNAVAILABLE REASON=provider-error, blaming a provider that
  # worked. Only exit >1, or an exit 1 that nonetheless printed something we did
  # not expect, is a real failure.
  if [[ "$rc" -gt 1 ]] || { [[ "$rc" -eq 1 ]] && [[ -n "$hits" ]]; }; then
    return "$RECON_ADAPTER_ERROR"
  fi
  _recon_pack_hits "$pack" "$hits"
}

# ---------------------------------------------------------------------------
# graphify — CLI over graphify-out/, interpreter reused from graphify_ensure.sh
# ---------------------------------------------------------------------------

# _recon_graphify_cached_python — echo graphify-out/.graphify_python when it is
# VALID, validated exactly as graphify_ensure.sh:96-101 does (-x on the cached
# path plus `import graphify`). Echoes nothing otherwise.
_recon_graphify_cached_python() {
  local cache="${RECON_ROOT:-.}/graphify-out/.graphify_python" cached=""
  [[ -f "$cache" ]] || return 0
  cached="$(cat "$cache" 2>/dev/null || true)"
  if [[ -n "$cached" && -x "$cached" ]] && "$cached" -c 'import graphify' 2>/dev/null; then
    printf '%s\n' "$cached"
  fi
}

# _recon_graphify_python — a valid cache skips detection entirely; otherwise
# shell graphify_ensure.sh --check ONCE and re-read the cache. Detection is
# never reimplemented here.
_recon_graphify_python() {
  local py
  py="$(_recon_graphify_cached_python)"
  if [[ -n "$py" ]]; then
    printf '%s\n' "$py"
    return 0
  fi
  # --target-dir pins detection to the same root the cache is read from, so a
  # caller in a subdirectory does not write one cache and read another.
  "$SCRIPTS/graphify_ensure.sh" --check --target-dir "${RECON_ROOT:-.}" \
    >/dev/null 2>&1 || true
  _recon_graphify_cached_python
}

# graphify speaks two output shapes and `docs` needs the second one.
#   `explain`/`path` connection lines:
#     --> fail() [defines] [EXTRACTED] skills/team-sprint/scripts/lib.sh:L21
#   `query` node lines (never connection lines):
#     NODE fail() [src=skills/team-sprint/scripts/lib.sh loc=L21 community=lib.sh]
# Knowing only the first shape is how a live 62-node `query` answer was reported
# as STATUS=EMPTY COUNT=0.

# _recon_graphify_keep <intent> <direction> <relation> — true when a connection
# row belongs in <intent>'s answer.
#
# `<--` is an INBOUND edge (something points at the node) and `-->` an outbound
# one, so the marker IS the difference between "what calls X" and "what does X
# call". Parsing it and then emitting every row alike answered `callees` with
# `callers`' rows verbatim, under STATUS=OK — a confident wrong answer, which
# this router treats as worse than no answer.
#
# `defines` and `contains` are structural, not call edges: a file defines and
# contains the symbols declared in it. Counting them made a symbol with no known
# callers report COUNT=1 pointing at its own definition. They are DENIED by name
# rather than `calls` being the sole allow-listed relation, because the live
# graph carries calls, indirect_call, references, extends, method, imports and
# imports_from too, and dropping an unrecognised relation would manufacture the
# false negative the whole chain exists to prevent.
#
# Only the three call-graph intents filter. `spans`, `docs` and the rest ask
# which files a thing touches, where a definition edge is a legitimate answer.
_recon_graphify_keep() {
  case "$1" in
    callers|callees|impact) ;;
    *) return 0 ;;
  esac
  case "$1:$2" in
    'callers:-->') return 1 ;;
    'callees:<--') return 1 ;;
  esac
  case "$3" in
    defines|contains) return 1 ;;
  esac
  return 0
}

# _recon_graphify_lines <text> [<intent>] — normalise graphify stdout. With an
# intent, only the rows that intent asked for survive; with none, every row does.
# The adapter needs both to tell "output we cannot read" (nothing parsed at all)
# apart from "nothing matched the question" (parsed, then filtered away).
_recon_graphify_lines() {
  local text="$1" intent="${2:-}" line body=""
  local dir sym rel path lineno
  local re='^[[:space:]]*(<--|-->)[[:space:]]+(.+)[[:space:]]+\[([a-z_]+)\][[:space:]]+\[[A-Z]+\][[:space:]]+([^[:space:]]+):L([0-9]+)$'
  local node_re='^NODE[[:space:]]+(.+)[[:space:]]+\[src=([^[:space:]]+)[[:space:]]+loc=L([0-9]+)'
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      # Captured BEFORE the keep test: any further [[ =~ ]] clobbers BASH_REMATCH.
      dir="${BASH_REMATCH[1]}"
      sym="${BASH_REMATCH[2]}"
      rel="${BASH_REMATCH[3]}"
      path="${BASH_REMATCH[4]}"
      lineno="${BASH_REMATCH[5]}"
      _recon_graphify_keep "$intent" "$dir" "$rel" || continue
      body="${body}$(printf '%s:%s\t%s\t%s' "$path" "$lineno" "$sym" "$rel")
"
    elif [[ "$line" =~ $node_re ]]; then
      body="${body}$(printf '%s:%s\t%s\tnode' \
        "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}")
"
    fi
  done <<< "$text"
  printf '%s' "$body"
}

# _recon_graphify_sub <intent> — the graphify subcommand an intent maps to.
# Shared by the adapter below and by recon.sh's --explain, so the command
# --explain prints is the command that would really be issued rather than a
# second map free to drift from this one.
_recon_graphify_sub() {
  case "$1" in
    docs) printf 'query\n' ;;
    path) printf 'path\n' ;;
    *)    printf 'explain\n' ;;
  esac
}

recon_adapter_graphify() {
  local intent="$1"
  shift
  command -v graphify >/dev/null 2>&1 || return "$RECON_ADAPTER_ERROR"

  # `graphify query` is served by the graphify module rather than a guaranteed
  # CLI subcommand (graphify_ensure.sh:172-176), so `docs` always needs a real
  # interpreter. Every other intent needs one only when the router's capability
  # probe has not already resolved graphify.
  if [[ "$intent" == "docs" ]] || ! _recon_caps_declares graphify; then
    local py
    py="$(_recon_graphify_python)"
    [[ -n "$py" ]] || return "$RECON_ADAPTER_ERROR"
  fi

  local sub
  sub="$(_recon_graphify_sub "$intent")"

  local out lines kept
  # Run the CLI FROM the resolved root, not merely with root-resolved artifact
  # paths: graphify opens `graphify-out/graph.json` relative to its own $PWD, so
  # a caller standing in a subdirectory gets "graph file not found" and the
  # router blames a provider that never errored. Pinning the CWD also keeps the
  # adapter querying the same graph the probe graded `indexed`/`languages` from.
  out="$(cd "${RECON_ROOT:-.}" && graphify "$sub" "$@" 2>/dev/null)" \
    || return "$RECON_ADAPTER_ERROR"
  lines="$(_recon_graphify_lines "$out")"
  # Output this normaliser cannot read is "I do not know", not "nothing found".
  # Returning the sentinel advances the chain; reporting zero rows would let the
  # router print a confident STATUS=EMPTY COUNT=0 over a real answer. Genuinely
  # empty provider stdout stays an answer and still yields TOTAL=0.
  if [[ -n "$out" && -z "$lines" ]]; then
    return "$RECON_ADAPTER_ERROR"
  fi
  # Rows we READ but the intent does not want are not an answer either. graphify's
  # bash call graph is demonstrably incomplete — functions in this very repo have
  # real call sites and zero inbound call edges — so a chain that reported
  # STATUS=EMPTY COUNT=0 here would dress "graphify knows of none" up as "there
  # are none", and silence reads as safe-to-change. The sentinel advances the
  # chain instead. Genuinely empty provider stdout parses to no rows at all and
  # stays an answer, so it still yields TOTAL=0.
  kept="$(_recon_graphify_lines "$out" "$intent")"
  if [[ -n "$lines" && -z "$kept" ]]; then
    return "$RECON_ADAPTER_ERROR"
  fi
  _recon_emit_body "$kept"
}

# ---------------------------------------------------------------------------
# codegraph — CLI, JSON where it offers one, body-stripped markdown otherwise
# ---------------------------------------------------------------------------

# _recon_codegraph_json_known <payload> — true when the payload carries a result
# key this normaliser knows how to read. Only a RECOGNISED shape is allowed to
# answer zero rows: `affected -j` (the `tests` intent) names its answer in a flat
# `affectedTests` array carrying neither filePath nor startLine, so a normaliser
# that knew only the coordinate shape turned a real provider answer into
# STATUS=EMPTY COUNT=0 — and EMPTY is terminal in recon_resolve, so the link
# behind it never fired. Anything else (a new subcommand, a schema bump) is "I do
# not know" and takes the sentinel so the chain advances instead.
_recon_codegraph_json_known() {
  printf '%s' "$1" | jq -e '
    has("callers") or has("callees") or has("affected") or has("affectedTests")
  ' >/dev/null 2>&1
}

# _recon_codegraph_json_lines <payload> — the two result shapes CodeGraph 1.5.0
# answers in: coordinate objects (`callers`/`callees` rows, and `impact -j`'s
# `affected` rows) and `affected -j`'s flat `affectedTests` paths, which carry no
# line at all and are cited at their first line. Returns jq's own status: a
# normaliser that cannot read what it was handed is a failure the caller maps to
# the sentinel, never a silent zero.
_recon_codegraph_json_lines() {
  printf '%s' "$1" | jq -r '
    ([.. | objects | select(has("filePath") and has("startLine"))]
     | .[]
     | "\(.filePath):\(.startLine)\t\(.name // "")\t\(.kind // "")"),
    ((.affectedTests? // [])
     | .[]
     | "\(.):1\t\(split("/") | last)\ttest")
  ' 2>/dev/null
}

# _recon_symbol_refs — pull `<path>:<line>` coordinates out of body-bearing
# markdown (`codegraph explore` / `codegraph node`) while dropping every fenced
# block, so no source line can ever reach stdout.
_recon_symbol_refs() {
  python3 - "$1" <<'PY'
import re
import sys

SYM = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(([^()\s]+:\d+)\)")
LOC = re.compile(r"(?<![\w/.])([\w./-]+\.[A-Za-z0-9]+:\d+)")

fenced = False
seen = set()
out = []
for raw in sys.argv[1].splitlines():
    if raw.lstrip().startswith("```"):
        fenced = not fenced
        continue
    if fenced:
        continue
    line = raw.replace("`", "").replace("*", "")
    pairs = [(m.group(2), m.group(1)) for m in SYM.finditer(line)]
    if not pairs:
        pairs = [(m.group(1), "") for m in LOC.finditer(line)]
    for loc, sym in pairs:
        if (loc, sym) in seen:
            continue
        seen.add((loc, sym))
        out.append("%s\t%s\t" % (loc, sym))

sys.stdout.write("".join(line + "\n" for line in out))
PY
}

# _recon_codegraph_payload <text> — <text> with every ANSI SGR escape removed.
# codegraph colours its output even when piped, so the JSON test in the adapter
# must see the first REAL character: `\033[34m{` matches neither "{"* nor "["*
# and would send real JSON down the markdown branch, losing every row it carries.
_recon_codegraph_payload() {
  local esc
  esc=$'\033'
  printf '%s' "$1" | sed "s/${esc}\\[[0-9;]*m//g"
}

# _recon_codegraph_not_found <payload> — true when codegraph answered "I have no
# such symbol". CodeGraph 1.5.0 exits 0 for that AND for `{"symbol":…,
# "callers":[]}`, so the exit code cannot tell them apart and only stdout can:
# the second is an ANSWER (the symbol is indexed, nothing calls it), the first is
# "I do not know". It is also what codegraph says about every symbol of a
# language it has no grammar for — it ships none for shell — so reporting it as
# zero rows would print a confident STATUS=EMPTY COUNT=0 over a question the
# provider never even parsed.
_recon_codegraph_not_found() {
  case "$1" in
    *'Symbol "'*'" not found'*) return 0 ;;
  esac
  return 1
}

# _recon_codegraph_argv <intent> — the codegraph subcommand plus its flags, as
# one space-separated string. Shared by the adapter below and by recon.sh's
# --explain, so the printed plan is the real invocation.
#
# `-j` is offered by callers/callees/impact/affected and by NOTHING else
# (CodeGraph 1.5.0 `--help`). Without it those four answer in decorated text
# whose symbol and kind columns the adapter cannot recover, so its JSON branch
# would be dead against the real CLI; passing it to `explore` or `node` would
# make the real CLI reject the invocation.
_recon_codegraph_argv() {
  case "$1" in
    callers)     printf 'callers -j\n' ;;
    callees)     printf 'callees -j\n' ;;
    impact|path) printf 'impact -j\n' ;;
    tests)       printf 'affected -j\n' ;;
    *)           printf 'explore\n' ;;
  esac
}

recon_adapter_codegraph() {
  local intent="$1"
  shift
  command -v codegraph >/dev/null 2>&1 || return "$RECON_ADAPTER_ERROR"
  require_jq || return "$RECON_ADAPTER_ERROR"

  # The subcommand and its flags come from _recon_codegraph_argv, so --explain
  # prints exactly what this adapter issues.
  local argv sub flag
  local -a flags=()
  argv="$(_recon_codegraph_argv "$intent")"
  sub="${argv%% *}"
  flag="${argv#"$sub"}"
  flag="${flag# }"
  [[ -z "$flag" ]] || flags=("$flag")

  local out payload refs lines
  out="$(codegraph "$sub" ${flags[@]+"${flags[@]}"} "$@" 2>/dev/null)" \
    || return "$RECON_ADAPTER_ERROR"
  # The escapes come off BEFORE the shape test: codegraph decorates its output
  # even when piped, and the branch is chosen on the first real character.
  payload="$(_recon_codegraph_payload "$out")"
  if _recon_codegraph_not_found "$payload"; then
    return "$RECON_ADAPTER_ERROR"
  fi
  case "$payload" in
    "{"*|"["*)
      # Same rule as the markdown branch below — but applied to the SHAPE, since
      # JSON this normaliser cannot read parses cleanly and yields no rows, which
      # would print a confident STATUS=EMPTY COUNT=0 over an answer codegraph
      # really gave. Only a recognised shape may report zero.
      _recon_codegraph_json_known "$payload" || return "$RECON_ADAPTER_ERROR"
      lines="$(_recon_codegraph_json_lines "$payload")" \
        || return "$RECON_ADAPTER_ERROR"
      _recon_emit_body "$lines" ;;
    *)
      require_python3 || return "$RECON_ADAPTER_ERROR"
      refs="$(_recon_symbol_refs "$out")"
      # Same rule as recon_adapter_graphify:374-376 — output this normaliser
      # cannot read is "I do not know" and takes the sentinel, so the chain
      # advances instead of the router printing a confident STATUS=EMPTY COUNT=0
      # over stdout codegraph really produced. Genuinely empty provider stdout
      # parses to no rows either and stays an answer, still yielding TOTAL=0.
      if [[ -n "$out" && -z "$refs" ]]; then
        return "$RECON_ADAPTER_ERROR"
      fi
      _recon_emit_body "$refs" ;;
  esac
}

# ---------------------------------------------------------------------------
# tokensave — MCP-only: never executed, never named
# ---------------------------------------------------------------------------

# bash can neither call an MCP tool nor enumerate the roster, so this adapter
# emits a delegation the calling agent executes. No tool name is hardcoded:
# TOOL= is emitted only when a live roster supplied one, which bash never does.
recon_adapter_tokensave() {
  local intent="$1"
  shift
  # An MCP-only link is skipped exactly as an absent provider when the caller
  # declared it cannot delegate.
  [[ -z "${RECON_NO_MCP:-}" ]] || return "$RECON_ADAPTER_ERROR"
  require_jq || return "$RECON_ADAPTER_ERROR"
  local args_json
  args_json="$(jq -cn '{args: $ARGS.positional}' --args "$@")" \
    || return "$RECON_ADAPTER_ERROR"
  printf 'STATUS=DELEGATE PROVIDER=tokensave INTENT=%s ARGS=%s\n' \
    "$intent" "$args_json"
}

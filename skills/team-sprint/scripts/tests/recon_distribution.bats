#!/usr/bin/env bats
# recon_distribution.bats — RED-phase contract for Story RH6: distribution of the
# recon router to every agent, skill and phase that must reach it.
#
# RH6 ships NO new script. Its whole deliverable is four documents:
#   CLAUDE.md                                       — the inheritance surface
#   skills/team-sprint-planner/references/recon-instruments.md
#   skills/team-sprint/SKILL.md
#   skills/team-sprint/phases/phase-0.md
# and one deliberate NON-edit: nothing under `agents/`. That non-edit is the
# mechanism, not an omission — every custom subagent inherits `$CLAUDE_CONFIG_DIR/CLAUDE.md`
# automatically, so the ladder reaches all 51 of them through one file. A test
# suite that only asserted the four edits would let a well-meaning implementer
# "help" by copying the ladder into `agents/*.md`, which is exactly the
# duplication-drift the mechanism exists to avoid. So the absent case is
# fixtured too (see the contract-coverage loop at the bottom).
#
# WHY THE ASSERTIONS ARE STRING GREPS. There is no executable here to run, so the
# artefact IS the text. Each @test below pins one acceptance criterion of RH6 to
# the literal string that criterion names, and every criterion that names its own
# grep in the plan is asserted with exactly that grep.
#
# THE CLAUDE.md BUDGET IS ANCHORED, NOT WORKING-TREE. `≤8 net lines` is measured
# as `git diff --numstat BASE...HEAD -- CLAUDE.md`, the same anchoring
# per_story_diff.sh:81 and `coverage_check.sh --mode new` use. A bare working-tree
# diff is explicitly NOT a substitute (per_story_diff.sh:19-24: it misses
# untracked files and answers a different question). Consequence, stated here so
# it is not a surprise: the CLAUDE.md edit must be COMMITTED — a `wip(RH6)` commit
# is enough, which is what phases 3/5 land anyway — before that test can pass.
# BASE is resolved as TS_DIFF_BASE, else merge-base(HEAD, TS_TARGET_BRANCH|main|develop).
#
# CLOSED STATUS VOCABULARY. phase-0.md's recon step branches on router statuses,
# and the router's vocabulary is exactly seven values. phase-0.md already contains
# STATUS=FAIL / FRESH / STALE / MISSING / RESUME from graphify_ensure.sh and
# validate_plan_path.sh — none of which the router can ever emit — so the closed-set
# check below runs against the RECON STEP BLOCK only, not the whole file. A
# STATUS=FAIL copy-pasted from the graphify step at phase-0.md:42 into the recon
# step is a bug, and this is the test that catches it.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  REPO="$(cd "$SKILL/../.." && pwd -P)"
  # The ladder's home moved when the toolchain was packaged: in a plugin tree it
  # is a plugin-owned rule file, in the original config repo it is CLAUDE.md.
  # Same text, same assertions — only the surface that carries it differs.
  if [ -f "$REPO/rules/recon-ladder.md" ]; then
    CLAUDE_MD="$REPO/rules/recon-ladder.md"
  else
    CLAUDE_MD="$REPO/CLAUDE.md"
  fi
  INSTR="$REPO/skills/team-sprint-planner/references/recon-instruments.md"
  PHASE0="$SKILL/phases/phase-0.md"
  SKILL_MD="$SKILL/SKILL.md"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# _base_ref — the sprint base, resolved exactly as the diff scripts do:
# TS_DIFF_BASE short-circuit (per_story_diff.sh:64), else
# merge-base(HEAD, target) (lib.sh resolve_diff_base:156). Never a working tree.
_base_ref() {
  local b
  if [ -n "${TS_DIFF_BASE:-}" ]; then
    printf '%s\n' "$TS_DIFF_BASE"
    return 0
  fi
  for b in "${TS_TARGET_BRANCH:-}" main develop; do
    [ -n "$b" ] || continue
    if git -C "$REPO" rev-parse --verify --quiet "$b" >/dev/null 2>&1; then
      git -C "$REPO" merge-base HEAD "$b" && return 0
    fi
  done
  return 1
}

# _near <file> <anchor> <needle> [window] — is <needle> within <window> chars of
# some occurrence of <anchor>? Proximity, not same-line, so a table row plus the
# sentence under it both satisfy "folded into the Tier 1 row" without dictating
# the exact line breaks. python3 because this is text-window work, not grep work.
_near() {
  python3 - "$1" "$2" "$3" "${4:-600}" <<'PY'
import sys
path, anchor, needle, win = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
text = open(path, encoding="utf-8").read()
i = 0
while True:
    i = text.find(anchor, i)
    if i < 0:
        sys.exit(1)
    lo = max(0, i - win)
    hi = i + len(anchor) + win
    if needle in text[lo:hi]:
        sys.exit(0)
    i += 1
PY
}

# _p0_recon_block — the phase-0 step that owns recon: from the line carrying the
# `recon != off` gate to the next numbered step header. Everything asserted about
# "the same step" is asserted against THIS block, never the whole file.
_p0_recon_block() {
  awk '
    !f && /recon != off/ { f = 1; print; next }
    f  && /^[0-9]+[a-z]*\./ { exit }
    f  { print }
  ' "$PHASE0"
}

# _p0_codegraph_snippet — the fenced bash block inside the recon step that runs
# `codegraph init`. Extracted and EXECUTED rather than grepped: a snippet a lead
# copies verbatim into a `set -euo pipefail` shell is a program, and the only way
# to know which of its paths exit non-zero is to run them.
_p0_codegraph_snippet() {
  _p0_recon_block | awk '
    /```bash/     { f = 1; buf = ""; next }
    f && /```/    { if (buf ~ /codegraph init/) { printf "%s", buf; exit } f = 0; next }
    f             { buf = buf $0 "\n" }
  '
}

# _fake_codegraph <status-text> — a codegraph whose `status` prints <status-text>
# and whose every invocation is appended to $TMP/cg.log.
_fake_codegraph() {
  mkdir -p "$TMP/fakebin"
  : > "$TMP/cg.log"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >> %s\n' "$TMP/cg.log"
    printf 'if [ "$1" = status ]; then printf "%%s\\n" %s; fi\n' "'$1'"
    printf 'exit 0\n'
  } > "$TMP/fakebin/codegraph"
  chmod +x "$TMP/fakebin/codegraph"
}

# _skill_optional_section — SKILL.md's optional-sub-skills list.
_skill_optional_section() {
  awk '/^Optional sub-skills:/ { f = 1; next } f && /^#/ { f = 0 } f' "$SKILL_MD"
}

# _three_layers_hits — the plan's own grep, including the load-bearing
# --exclude-dir=plans (this plan file quotes the phrase and would match forever).
# The pattern is ASSEMBLED from two halves on purpose: written as one literal it
# would live in this file, which sits under skills/, so the check would match
# itself and stay red forever no matter what the implementer does.
_three_layers_hits() {
  local pat='Three layers'
  pat="$pat — the convention"
  (cd "$REPO" && grep -rn "$pat" CLAUDE.md skills/ --exclude-dir=plans 2>/dev/null) || true
}

# ---------------------------------------------------------------------------
# 1. CLAUDE.md — the inheritance surface
# ---------------------------------------------------------------------------

@test "AC1 CLAUDE.md documents all four escalation tiers and the never-escalate rule" {
  local t missing=""
  # One token per tier of the plan's ladder table (plan lines 196-204):
  #   0 live Read | 1 recon.sh text | 2 structural intent | 3 full index rebuild
  for t in 'Live `Read`' 'recon.sh text' 'structural intent' 'index rebuild'; do
    grep -qF "$t" "$CLAUDE_MD" || missing="$missing [$t]"
  done
  if [ -n "$missing" ]; then
    echo "CLAUDE.md names no tier for:$missing"
    return 1
  fi
  grep -qF 'never escalate a tier you can answer at a lower one' "$CLAUDE_MD" \
    || { echo "CLAUDE.md lost the escalation rule sentence"; return 1; }
}

@test "AC2 the CLAUDE.md rewrite is anchored to the sprint base and adds at most 8 net lines" {
  local base numstat added deleted net
  base="$(_base_ref)" || skip "no sprint base ref in this tree — this is a story-time budget AC, inert outside the repo the story ran in"
  numstat="$(git -C "$REPO" diff --numstat "$base"...HEAD -- CLAUDE.md)"
  if [ -z "$numstat" ]; then
    # Post-merge, `base` resolves to the merge commit and the story diff no
    # longer exists — the budget is a property of a change, and the change is
    # now history. Fall back to the invariant the budget existed to protect:
    # the ladder is present and the section is compact. Absent both, the work
    # genuinely was not done and this must still fail.
    if grep -qF 'never escalate a tier you can answer at a lower one' "$CLAUDE_MD"; then
      skip "no $base...HEAD diff for CLAUDE.md; ladder present, so this is a post-merge tree (budget asserted pre-merge)"
    fi
    echo "no CLAUDE.md change in $base...HEAD, and the ladder is absent."
    echo "the budget AC anchors to BASE...HEAD (per_story_diff.sh:81), never a"
    echo "working-tree diff — so the recon-section rewrite must be committed."
    return 1
  fi
  added="$(printf '%s\n' "$numstat" | awk '{ print $1 }')"
  deleted="$(printf '%s\n' "$numstat" | awk '{ print $2 }')"
  net=$(( added - deleted ))
  if [ "$net" -gt 8 ]; then
    echo "CLAUDE.md budget blown: +$added -$deleted = net $net (max 8)"
    return 1
  fi
  git -C "$REPO" diff "$base"...HEAD -- CLAUDE.md \
    | grep -qF 'never escalate a tier you can answer at a lower one' \
    || { echo "the committed CLAUDE.md diff never adds the escalation ladder"; return 1; }
}

@test "AC3 the Tier 1 row keeps the explicit rtk grep rule and the force-fresh-pack instruction" {
  # Both rules must survive in CLAUDE.md and stay folded into the ladder —
  # proximity to the Tier 1 row is what makes this the rewrite and not the
  # old three-layer list surviving underneath a new heading.
  #
  # The wording is pinned, not the phrasing of any one era: the rtk caveat
  # became "the hook is best-effort" (matching RTK.md, which is where that
  # rule now lives), and "delete the pack first" became `pack.sh 0`, the
  # scripted form of the same instruction. What the AC protects is that Tier 1
  # still says grep the pack through rtk, and still says how to force a fresh
  # one — not which sentence said it.
  local s
  for s in 'explicit `rtk grep`' 'the hook is best-effort' 'pack.sh 0'; do
    grep -qF "$s" "$CLAUDE_MD" || { echo "CLAUDE.md dropped the verbatim rule: $s"; return 1; }
  done
  _near "$CLAUDE_MD" 'recon.sh text' 'the hook is best-effort' 600 \
    || { echo "the rtk-hook rule is not folded into the Tier 1 row"; return 1; }
  _near "$CLAUDE_MD" 'recon.sh text' 'pack.sh 0' 600 \
    || { echo "the force-fresh-pack instruction is not folded into the Tier 1 row"; return 1; }
}

@test "AC4 nothing under skills or CLAUDE.md still calls the recon convention three layers" {
  local hits
  hits="$(_three_layers_hits)"
  if [ -n "$hits" ]; then
    echo "the three-layer convention still exists:"
    echo "$hits" | sed 's/^/    /'
    return 1
  fi
}

@test "AC5 the ladder is not duplicated into agents and the distribution goes through CLAUDE.md instead" {
  # Re-scoped 2026-08-13. This assertion used to read "no file under agents/ was
  # modified in this branch's diff", which is strictly broader than the mechanism
  # it protects: it forbade ANY edit to ANY agent for ANY reason, forever. The
  # epic-1 condensation had to repoint four agents off the `Skill` tool (their
  # sub-skills are now hidden) and tripped a guard that has nothing to do with the
  # recon ladder. What RH6 actually protects — see this file's header — is that a
  # well-meaning implementer must not COPY THE LADDER into agents/*.md, because
  # they inherit it from CLAUDE.md. That is what is asserted now.
  local f hits=""
  for f in "$REPO"/agents/*.md; do
    [ -f "$f" ] || continue
    if grep -qF 'recon.sh' "$f"; then
      hits="$hits $(basename "$f")"
    fi
  done
  if [ -n "$hits" ]; then
    echo "agent(s) name recon.sh directly —  the ladder reaches them by CLAUDE.md inheritance,"
    echo "so a per-agent copy is the duplication-drift RH6 exists to prevent:$hits"
    return 1
  fi
  # …and the substitute must actually exist, or "no copy in agents/" is satisfied
  # by a story that did nothing at all.
  grep -qF 'recon.sh' "$CLAUDE_MD" \
    || { echo "CLAUDE.md never names recon.sh — no agent can reach the router"; return 1; }
}

# ---------------------------------------------------------------------------
# 2. recon-instruments.md — the planner's reference
# ---------------------------------------------------------------------------

@test "AC6 recon-instruments routes structural questions through recon.sh and keeps the rtk grep instruction" {
  grep -qF 'recon.sh' "$INSTR" \
    || { echo "recon-instruments.md never mentions recon.sh"; return 1; }
  _near "$INSTR" 'recon.sh' 'structural' 800 \
    || { echo "recon-instruments.md never routes STRUCTURAL questions through recon.sh"; return 1; }
  # Verbatim retention of the existing pack instruction.
  local s
  for s in 'Search the pack through `rtk` — explicitly, not via the hook.' \
           'Call `rtk grep` directly for every pack sweep' \
           '${REPOMIX_PACK:-.repomix-output.xml}'; do
    grep -qF "$s" "$INSTR" || { echo "recon-instruments.md dropped verbatim: $s"; return 1; }
  done
}

@test "AC7 the recon.sh block is executable-guarded and the absent case has a stated fallback" {
  # Same guard shape as the graphify block at recon-instruments.md:42-43.
  grep -qF 'RS=${CREWFORGE5_ROOT}/skills/team-sprint/scripts/recon.sh' "$INSTR" \
    || { echo "recon-instruments.md has no RS= assignment for the router"; return 1; }
  grep -qF -- '-x "$RS"' "$INSTR" \
    || { echo "the recon.sh block is not guarded by [ -x \"\$RS\" ]"; return 1; }
  _near "$INSTR" 'recon.sh' 'absent' 600 \
    || { echo "recon-instruments.md never states the fallback when recon.sh is absent"; return 1; }
}

@test "DoD the misleading -B 2 comment on the pack grep is corrected" {
  # `-B 2` cannot reach the owning <file path=…> tag — it routinely sits hundreds
  # of lines above the hit. The code line stays; the false claim goes.
  if grep -qF '# -B 2 to catch the <file path' "$INSTR"; then
    echo "recon-instruments.md still claims -B 2 reaches the <file path=...> tag"
    return 1
  fi
  grep -qF 'rtk grep' "$INSTR" \
    || { echo "the rtk grep code line was removed instead of its comment"; return 1; }
}

# ---------------------------------------------------------------------------
# 3. phase-0.md — the probe step
# ---------------------------------------------------------------------------

@test "AC8 phase-0 probes the router under recon not off and carries the phase-0 line 42 disposition" {
  local block
  block="$(_p0_recon_block)"
  [ -n "$block" ] || { echo "phase-0.md has no step gated on 'recon != off'"; return 1; }
  printf '%s\n' "$block" | grep -- '--probe' | grep -q 'recon.sh' \
    || { echo "the recon step never invokes recon.sh --probe"; return 1; }
  printf '%s\n' "$block" | grep -qF 'STOP under `recon: on`' \
    || { echo "the recon step lacks the STOP-under-recon:on disposition worded as phase-0.md:42"; return 1; }
  printf '%s\n' "$block" | grep -F 'recon_degraded' | grep -q 'WARN' \
    || { echo "the recon step never pairs WARN with recon_degraded"; return 1; }
}

@test "AC8b the same phase-0 step persists recon_degraded through state.sh update" {
  local block
  block="$(_p0_recon_block)"
  printf '%s\n' "$block" | grep -qF 'recon_degraded=true' \
    || { echo "the recon step never sets recon_degraded=true"; return 1; }
  # Mirrors the graphify_degraded writer at phase-0.md:61 — one step both
  # branches and persists, so a degraded probe cannot be lost before step 10.
  grep -F 'recon_degraded=' "$PHASE0" | grep -qF 'state.sh" update' \
    || { echo "recon_degraded is never written through state.sh update"; return 1; }
}

@test "AC8c the STATUS=OK disposition claims only what --probe measures: binaries, never indexes" {
  # recon.sh's probe grades `available` for the three bash-probeable providers and
  # never reads `indexed`, so STATUS=OK is compatible with a router that answers
  # REASON=no-index for every structural intent. A phase-0 line promising "the
  # ladder runs at full strength" makes the lead persist recon_degraded=false over
  # exactly that router — the confident-silence failure the whole story exists to
  # prevent. The claim is pinned to the code that backs it, not to prose alone.
  local block ok
  if ! grep -q '_caps_bool codegraph available' "$SKILL/scripts/recon.sh"; then
    echo "recon.sh's --probe no longer grades availability — re-read its STATUS=OK contract"
    return 1
  fi
  if grep -q '_caps_bool codegraph indexed' "$SKILL/scripts/recon.sh"; then
    echo "recon.sh's --probe now grades indexes too; phase-0's STATUS=OK line may be strengthened"
    return 1
  fi
  block="$(_p0_recon_block)"
  ok="$(printf '%s\n' "$block" | grep -F 'STATUS=OK' || true)"
  [ -n "$ok" ] || { echo "the recon step never branches on STATUS=OK"; return 1; }
  if printf '%s\n' "$ok" | grep -qi 'full strength'; then
    echo "the STATUS=OK branch claims full strength, but --probe never opens an index:"
    printf '%s\n' "$ok" | sed 's/^/    /'
    return 1
  fi
  if ! printf '%s\n' "$ok" | grep -qE 'no-index|not graded|not checked'; then
    echo "the STATUS=OK branch never says indexes are ungraded here:"
    printf '%s\n' "$ok" | sed 's/^/    /'
    return 1
  fi
}

@test "AC9 phase-0 runs codegraph init when codegraph status reports the project uninitialised" {
  local block
  block="$(_p0_recon_block)"
  printf '%s\n' "$block" | grep -qF 'codegraph init' \
    || { echo "the recon step never runs codegraph init — a present-but-unindexed CodeGraph stays no-index forever"; return 1; }
  printf '%s\n' "$block" | grep -qF 'codegraph status' \
    || { echo "the recon step never consults codegraph status"; return 1; }
  # `codegraph status` exits 0 whether or not the project is initialised, so the
  # verdict MUST be parsed from stdout. Branching on its exit code is the bug.
  printf '%s\n' "$block" | grep -qF 'stdout' \
    || { echo "the recon step does not say the codegraph verdict is parsed from stdout"; return 1; }
}

@test "AC9b the codegraph snippet exits 0 on both of its healthy paths, so Phase 0 never false-STOPs" {
  # phase-0.md:11 — "Any failure → STOP" — and :15 — "Each check is
  # short-circuiting". A trailing `&&` chain therefore STOPs the sprint on the two
  # states that are not failures at all: codegraph absent (the commonest machine)
  # and codegraph present-but-already-indexed. Only present-and-unindexed exits 0,
  # which inverts the fail-soft intent of `recon: auto` and aborts Phase 0 before
  # `recon.sh --probe` ever runs.
  local snip
  snip="$(_p0_codegraph_snippet)"
  if [ -z "$snip" ]; then
    echo "the recon step has no fenced bash block running codegraph init"
    return 1
  fi
  printf 'set -euo pipefail\n%s' "$snip" > "$TMP/snip.sh"

  # 1. codegraph ABSENT — nothing to index, nothing to fail.
  run env PATH=/usr/bin:/bin bash "$TMP/snip.sh"
  if [ "$status" -ne 0 ]; then
    echo "codegraph absent: the snippet exits $status, which phase-0.md:11 turns into a STOP"
    return 1
  fi

  # 2. codegraph present and ALREADY indexed — the steady state after the first
  #    sprint. `codegraph init` must not run, and the step must not fail.
  _fake_codegraph 'Index is up to date'
  run env PATH="$TMP/fakebin:/usr/bin:/bin" bash "$TMP/snip.sh"
  if [ "$status" -ne 0 ]; then
    echo "codegraph already initialized: the snippet exits $status — a false STOP"
    return 1
  fi
  if grep -q '^init' "$TMP/cg.log"; then
    echo "codegraph init ran against an already-initialized project"
    return 1
  fi

  # 3. codegraph present and UNINDEXED — the one path that must actually index.
  _fake_codegraph 'Not initialized'
  run env PATH="$TMP/fakebin:/usr/bin:/bin" bash "$TMP/snip.sh"
  if [ "$status" -ne 0 ]; then
    echo "codegraph uninitialized: the snippet exits $status"
    return 1
  fi
  if ! grep -q '^init' "$TMP/cg.log"; then
    echo "codegraph init never ran on an uninitialized project: $(cat "$TMP/cg.log")"
    return 1
  fi
}

@test "AC10 the recon step is gated on recon not off and builds or probes at least one real index" {
  local block producer found=""
  block="$(_p0_recon_block)"
  printf '%s\n' "$block" | grep -qF 'recon != off' \
    || { echo "the recon step carries no 'recon != off' gate"; return 1; }
  for producer in 'codegraph init' 'graphify_ensure.sh'; do
    case "$block" in
      *"$producer"*) found="$found [$producer]" ;;
    esac
  done
  if [ -z "$found" ]; then
    echo "the recon step builds no index at all — FRESHNESS=fresh and FRESHNESS=live"
    echo "would have no live producer this sprint, only fixtures"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 4. SKILL.md — the skill's own surface
# ---------------------------------------------------------------------------

@test "AC11 the optional sub-skills section describes the router in one bullet matching the graphify format" {
  local section n
  section="$(_skill_optional_section)"
  [ -n "$section" ] || { echo "SKILL.md has no 'Optional sub-skills:' section"; return 1; }
  n="$(printf '%s\n' "$section" | grep -c '^- \*\*`recon`\*\* (`recon != off`)' || true)"
  if [ "$n" -ne 1 ]; then
    echo "expected exactly one recon bullet in the graphify bullet's format"
    echo "  ( - **\`recon\`** (\`recon != off\`) — … ), found $n"
    return 1
  fi
  printf '%s\n' "$section" | grep '^- \*\*`recon`\*\*' | grep -q 'recon.sh' \
    || { echo "the recon bullet never names the recon.sh router"; return 1; }
}

@test "AC12 the SKILL.md config block gains one recon key per line in the key value comment format" {
  local k missing="" badfmt=""
  for k in 'recon' 'recon_min_files' 'recon_providers' 'recon_log'; do
    if ! grep -qE "^$k: " "$SKILL_MD"; then
      missing="$missing [$k]"
      continue
    fi
    # Same column shape as graphify:/graphify_max_age_minutes: at SKILL.md:57-58 —
    # value, padding, then a `#` comment.
    grep -qE "^$k: +[^# ].*  +#" "$SKILL_MD" || badfmt="$badfmt [$k]"
  done
  if [ -n "$missing" ]; then echo "SKILL.md config block missing keys:$missing"; return 1; fi
  if [ -n "$badfmt" ]; then echo "keys not in the 'key: value  # comment' column format:$badfmt"; return 1; fi
}

# ---------------------------------------------------------------------------
# 5. CONTRACT COVERAGE loops (the substitute for the disabled coverage gate)
# ---------------------------------------------------------------------------

@test "contract coverage: all four escalation tiers are exercised here and named in CLAUDE.md" {
  local t missing_test="" missing_doc=""
  for t in 'Live `Read`' 'recon.sh text' 'structural intent' 'index rebuild'; do
    grep -l "$t" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing_test="$missing_test [$t]"
    grep -qF "$t" "$CLAUDE_MD"                          || missing_doc="$missing_doc [$t]"
  done
  if [ -n "$missing_test" ]; then echo "tiers no test in this file exercises:$missing_test"; return 1; fi
  if [ -n "$missing_doc" ];  then echo "tiers CLAUDE.md never names:$missing_doc"; return 1; fi
  # A ladder that never names the router is a list, not a ladder.
  grep -qF 'recon.sh' "$CLAUDE_MD" || { echo "the ladder never names recon.sh"; return 1; }
}

@test "contract coverage: every recon STATUS phase-0 branches on is asserted here and inside the closed seven" {
  local v block emitted bad="" missing_test="" missing_doc=""
  block="$(_p0_recon_block)"
  [ -n "$block" ] || { echo "phase-0.md has no recon step to branch in"; return 1; }
  for v in OK DEGRADED SKIP; do
    grep -l "STATUS=$v" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing_test="$missing_test [$v]"
    case "$block" in
      *"STATUS=$v"*) : ;;
      *) missing_doc="$missing_doc [$v]" ;;
    esac
  done
  if [ -n "$missing_test" ]; then echo "probe statuses no test names:$missing_test"; return 1; fi
  if [ -n "$missing_doc" ];  then echo "probe statuses the phase-0 recon step never branches on:$missing_doc"; return 1; fi
  # The vocabulary is CLOSED at seven. STATUS=FAIL / FRESH / STALE / MISSING are
  # graphify_ensure.sh's, not the router's; copying the graphify step wholesale is
  # the mistake this catches.
  emitted="$(printf '%s\n' "$block" | grep -oE 'STATUS=[A-Z_]+' | sort -u)"
  for v in $emitted; do
    case "$v" in
      STATUS=OK|STATUS=EMPTY|STATUS=UNAVAILABLE|STATUS=SKIP|STATUS=DEGRADED|STATUS=NO_INTENT_MATCH|STATUS=DELEGATE) : ;;
      *) bad="$bad [$v]" ;;
    esac
  done
  if [ -n "$bad" ]; then
    echo "the recon step branches on statuses outside the closed seven:$bad"
    return 1
  fi
}

@test "contract coverage: all four new config keys are exercised here and documented in SKILL.md" {
  local k missing_test="" missing_doc=""
  for k in 'recon' 'recon_min_files' 'recon_providers' 'recon_log'; do
    grep -l "'$k'" "$BATS_TEST_FILENAME" >/dev/null 2>&1 || missing_test="$missing_test [$k]"
    grep -qE "^$k: " "$SKILL_MD"                          || missing_doc="$missing_doc [$k]"
  done
  if [ -n "$missing_test" ]; then echo "config keys no test in this file exercises:$missing_test"; return 1; fi
  if [ -n "$missing_doc" ];  then echo "config keys SKILL.md never documents:$missing_doc"; return 1; fi
}

@test "contract coverage: every distribution surface reaches the router, including the deliberately absent one" {
  local f missing=""
  # The four surfaces RH6 edits…
  for f in "$CLAUDE_MD" "$INSTR" "$PHASE0" "$SKILL_MD"; do
    grep -l 'recon.sh' "$f" >/dev/null 2>&1 || missing="$missing [$(basename "$f")]"
  done
  if [ -n "$missing" ]; then
    echo "surfaces that never reach recon.sh:$missing"
    return 1
  fi
  # …and the fifth surface, which must never carry a COPY of the ladder: agents/
  # inherits CLAUDE.md, so naming recon.sh there is duplication-drift, not
  # distribution. The absent case is part of the contract, not an omission from it.
  # Re-scoped 2026-08-13 alongside the AC5 test above — see the rationale there.
  local dup=""
  for f in "$REPO"/agents/*.md; do
    [ -f "$f" ] || continue
    grep -qF 'recon.sh' "$f" && dup="$dup [$(basename "$f")]"
  done
  [ -z "$dup" ] || { echo "the absent surface is no longer absent — agents naming recon.sh:$dup"; return 1; }
}

#!/usr/bin/env bats
# validator_grading.bats — contract for the mechanical half of both validators.
#
# THE HOLE THIS FILLS. CI shellchecks every shipped script and runs bats over
# `scripts/` and the team-sprint tree, which left the validator scripts linted
# but never exercised. `grade.sh` graded a skill A while that skill's own
# structural script reported two warnings on the same file — the scripts emit
# JSON, the grader grepped for prose, and the mechanical grade silently counted
# only what the model had typed by hand. That is the precise inversion of what
# the validators promise, and nothing caught it, so it is pinned here.
#
# The description checks are pinned too. They were floors ("recommend > 30
# words") sitting beside a release gate that charges every description against a
# budget with ~57 tokens of headroom — the validator rewarded exactly what the
# gate fails you for. Ceilings are the contract now; a future edit that flips one
# back to a floor breaks this file.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  GRADE="$ROOT/skills/skill-validator/scripts/grade.sh"
  AGENT_V="$ROOT/skills/agent-validator/scripts/validate_agent.sh"
  SKILL_V="$ROOT/skills/skill-validator/scripts/validate_structure.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  LEDGER="$TMP/ledger"
  : > "$LEDGER"
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

# json <status> — one finding in the shape the validator scripts actually emit
json() {
  printf '{"status":"%s","check":"c","detail":"d"}\n' "$1" >> "$LEDGER"
}

# mkagent <file> <description> [body...]
mkagent() {
  local f="$1" desc="$2"; shift 2
  {
    printf -- '---\nname: %s\ndescription: %s\ntools: Read\ncolor: blue\n---\n\n' \
      "$(basename "$f" .md)" "$desc"
    printf 'You are a test agent.\n\n'
    printf '%s\n' "$@"
  } > "$f"
}

field() { # field <key> <output>  — pull key=value from grade.sh output
  printf '%s\n' "$2" | grep "^$1=" | cut -d= -f2
}

# --- grade.sh: the JSON half ------------------------------------------------

@test "grade.sh counts JSON findings — the regression that shipped" {
  json FAIL
  json WARN
  run bash "$GRADE" "$LEDGER"
  [ "$status" -eq 0 ]
  [ "$(field fails "$output")" = "1" ]
  [ "$(field warns "$output")" = "1" ]
}

@test "grade.sh counts prose findings appended by the model" {
  printf 'FAIL [compliance]: ambiguous instruction\nWARN [sim]: skipped a step\n' >> "$LEDGER"
  run bash "$GRADE" "$LEDGER"
  [ "$(field fails "$output")" = "1" ]
  [ "$(field warns "$output")" = "1" ]
}

@test "grade.sh sums both shapes rather than picking one" {
  json FAIL
  json WARN
  printf 'FAIL [compliance]: x\nWARN [sim]: y\nWARN [sim]: z\n' >> "$LEDGER"
  run bash "$GRADE" "$LEDGER"
  [ "$(field fails "$output")" = "2" ]
  [ "$(field warns "$output")" = "3" ]
  [ "$(field grade "$output")" = "C" ]
}

@test "grade.sh never counts PASS or INFO" {
  json PASS
  json INFO
  json PASS
  printf 'INFO [efficiency]: 3 safety directives exempt\n' >> "$LEDGER"
  run bash "$GRADE" "$LEDGER"
  [ "$(field fails "$output")" = "0" ]
  [ "$(field warns "$output")" = "0" ]
  [ "$(field grade "$output")" = "A" ]
}

@test "grade.sh: a SKIPPED phase is reported but does not block grade A" {
  printf 'SKIPPED [simulation]: no subagents\n' >> "$LEDGER"
  json WARN
  run bash "$GRADE" "$LEDGER"
  [ "$(field skipped "$output")" = "1" ]
  [ "$(field grade "$output")" = "A" ]
}

@test "grade.sh on a missing ledger returns F rather than crashing" {
  run bash "$GRADE" "$TMP/does-not-exist"
  [ "$status" -eq 0 ]
  [ "$(field grade "$output")" = "F" ]
}

# --- the scale itself, pinned at every boundary -----------------------------
#
# Two report templates carried a prose copy of this scale that had drifted a full
# grade from the code — 1 failure read as D on paper and C in `grade.sh`, 3 read
# as F on paper and D in code. The prose copies are gone; this is what replaces
# them, because a scale nobody exercises is a scale that drifts again.

nfindings() { # nfindings <status> <count>
  local i
  for i in $(seq 1 "$2"); do printf '%s [t]: finding %s\n' "$1" "$i" >> "$LEDGER"; done
}

@test "grade scale: 2 warns is A, 3 is B, 6 is C" {
  nfindings WARN 2
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "A" ]
  nfindings WARN 1
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "B" ]
  nfindings WARN 3
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "C" ]
}

@test "grade scale: 1-2 failures is C, 3-5 is D, 6 is F" {
  nfindings FAIL 1
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "C" ]
  nfindings FAIL 1
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "C" ]
  nfindings FAIL 1
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "D" ]
  nfindings FAIL 2
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "D" ]
  nfindings FAIL 1
  [ "$(field grade "$(bash "$GRADE" "$LEDGER")")" = "F" ]
}

@test "no report template restates the grade scale in prose" {
  for t in "$ROOT/skills/skill-validator/references/report-template.md" \
           "$ROOT/skills/agent-validator/references/report-template.md"; do
    ! grep -qE '^- [A-F]: ' "$t"
  done
}

# --- description: ceiling, never a floor ------------------------------------

@test "agent validator WARNs a description over the ~200 char house limit" {
  long="Use when you need a very thorough agent that does an extremely large number of \
distinct things across many domains and situations, described here at wasteful length so \
that the always-loaded catalogue entry costs far more than it needs to every session."
  mkagent "$TMP/long.md" "$long"
  run bash "$AGENT_V" "$TMP/long.md"
  printf '%s\n' "$output" | grep -q '"status":"WARN","check":"description_length"'
}

@test "agent validator does NOT penalise a short description" {
  mkagent "$TMP/short.md" "Reviews Go diffs for correctness. Use when reviewing a Go change."
  run bash "$AGENT_V" "$TMP/short.md"
  printf '%s\n' "$output" | grep -q '"status":"PASS","check":"description_length"'
}

@test "agent validator does not demand <example> blocks" {
  mkagent "$TMP/noex.md" "Reviews Go diffs for correctness. Use when reviewing a Go change."
  run bash "$AGENT_V" "$TMP/noex.md"
  ! printf '%s\n' "$output" | grep -q '"status":"WARN","check":"description_examples"'
}

@test "skill validator WARNs a description over the ~200 char house limit" {
  mkdir -p "$TMP/sk"
  {
    printf -- '---\nname: sk\n'
    printf 'description: Use when you need a skill whose description runs on well past the point of usefulness, restating its own purpose several times over so the always-loaded catalogue line costs many more tokens than the trigger phrases alone would have\n'
    printf -- '---\n\n# Sk\n\nBody.\n'
  } > "$TMP/sk/SKILL.md"
  run bash "$SKILL_V" "$TMP/sk"
  printf '%s\n' "$output" | grep -q '"status":"WARN","check":"description_length"'
}

@test "skill validator does NOT penalise a short description" {
  mkdir -p "$TMP/sk2"
  printf -- '---\nname: sk2\ndescription: Trims skill descriptions. Use on "slim my skills"\n---\n\n# Sk2\n\nBody.\n' \
    > "$TMP/sk2/SKILL.md"
  run bash "$SKILL_V" "$TMP/sk2"
  printf '%s\n' "$output" | grep -q '"status":"PASS","check":"description_length"'
}

# --- heavy directives: safety guards are exempt -----------------------------

@test "directives guarding irreversible actions are exempt, not counted" {
  body=""
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    body="$body
NEVER force push to main — rule $i, it destroys a colleague's work."
  done
  mkagent "$TMP/safe.md" "Guards releases. Use when releasing." "$body"
  run bash "$AGENT_V" "$TMP/safe.md"
  ! printf '%s\n' "$output" | grep -q '"status":"WARN","check":"directive_count"'
  printf '%s\n' "$output" | grep -q '"check":"directive_safety_exempt"'
}

@test "directives about taste are still counted" {
  body=""
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    body="$body
ALWAYS name the variable in camelCase — rule $i."
  done
  mkagent "$TMP/taste.md" "Names things. Use when naming." "$body"
  run bash "$AGENT_V" "$TMP/taste.md"
  printf '%s\n' "$output" | grep -q '"status":"WARN","check":"directive_count"'
}

@test "an agent with no heavy directives at all does not error" {
  mkagent "$TMP/plain.md" "Reads files. Use when reading." "Read the file. Report what it says."
  run bash "$AGENT_V" "$TMP/plain.md"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '"status":"PASS","check":"directive_count"'
  ! printf '%s\n' "$output" | grep -qi 'syntax error\|unbound variable'
}

# --- frontmatter must PARSE, not merely have delimiters ---------------------
#
# `skills/init/SKILL.md` shipped with an unquoted description containing `: `.
# The block did not parse, so the plugin's main entry point ran with no name, no
# model and no description — and `validate_all.sh` called it structurally clean,
# because every other check asks whether a field appears in the TEXT and a
# broken block has no fields to find. `claude plugin tag` caught it; nothing in
# this repo did. The reserved-character set was measured against PyYAML rather
# than reasoned out, so these cases pin the measurement, not an opinion.

fmcheck() { bash "$ROOT/scripts/frontmatter_check.sh" "$1"; }

# mkfm <file> <frontmatter-line>
mkfm() {
  printf -- '---\nname: t\n%s\n---\n\nBody.\n' "$2" > "$1"
}

@test "frontmatter_check: the exact bug that shipped — unquoted value with a colon" {
  mkfm "$TMP/f.md" 'description: Gated config hygiene: measure, slim, validate'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 1 ]
  [[ "$output" == FAIL:* ]]
}

@test "frontmatter_check: quoting the same value makes it legal" {
  mkfm "$TMP/f.md" 'description: "Gated config hygiene: measure, slim, validate"'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "frontmatter_check: a URL's colon is not a mapping" {
  mkfm "$TMP/f.md" 'description: see https://example.com/x for detail'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
}

@test "frontmatter_check: closed flow collections are legal, unclosed ones are not" {
  mkfm "$TMP/f.md" 'tools: [Read, Write]'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
  mkfm "$TMP/f.md" 'tools: [Read, Write'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 1 ]
}

@test "frontmatter_check: the quoted wildcard this repo's house rules require" {
  mkfm "$TMP/f.md" 'tools: "*"'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
  mkfm "$TMP/f.md" 'tools: *all'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 1 ]
}

@test "frontmatter_check: a truncating comment warns without failing" {
  mkfm "$TMP/f.md" 'description: real text # this half is silently lost'
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
  [[ "$output" == WARN:* ]]
}

@test "frontmatter_check: block scalars carry colons legally" {
  printf -- '---\nname: t\ndescription: |\n  free: text with colons\n  more: here\ntools: Read\n---\n\nBody.\n' > "$TMP/f.md"
  run fmcheck "$TMP/f.md"
  [ "$status" -eq 0 ]
}

@test "frontmatter_check: every shipped manifest parses" {
  for f in "$ROOT"/skills/*/SKILL.md "$ROOT"/agents/*.md; do
    run fmcheck "$f"
    [ "$status" -eq 0 ] || { echo "$f: $output"; return 1; }
  done
}

@test "both validators report the parse failure, and their JSON stays valid" {
  mkfm "$TMP/broken.md" 'description: Reviews things: badly'
  run bash "$AGENT_V" "$TMP/broken.md"
  printf '%s\n' "$output" | grep -q '"status":"FAIL","check":"frontmatter_parses"'
  printf '%s\n' "$output" | python3 -c 'import sys,json; json.load(sys.stdin)'

  mkdir -p "$TMP/sk3"
  mkfm "$TMP/sk3/SKILL.md" 'description: Reviews things: badly'
  run bash "$SKILL_V" "$TMP/sk3"
  printf '%s\n' "$output" | grep -q '"status":"FAIL","check":"frontmatter_parses"'
  printf '%s\n' "$output" | python3 -c 'import sys,json; json.load(sys.stdin)'
}

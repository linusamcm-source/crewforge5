#!/usr/bin/env bats
# parse_stories.bats — fixtures for scripts/parse_stories.sh

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  PS_SH="$SCRIPTS/parse_stories.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP

  PLAN="$TMP/plan.md"
}

teardown() {
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# 0 stories — fallback to filename basename
# ---------------------------------------------------------------------------
@test "no recognised heading -> single implicit story named after the file" {
  PLAN="$TMP/bug-fix-417.md"
  cat > "$PLAN" <<'EOF'
# Single-story plan
just some prose, no headings that match.

## Acceptance Criteria
- one criterion

## Definition of Done
- it works
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "bug-fix-417" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "bug-fix-417" ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "one criterion" ]
  [ "$(jq -r '.[0].definition_of_done[0]' <<<"$output")" = "it works" ]
}

# ---------------------------------------------------------------------------
# 1 story canonical heading
# ---------------------------------------------------------------------------
@test "1 story canonical '## Story' heading" {
  cat > "$PLAN" <<'EOF'
# Sprint plan

## Story alpha-1: Solo story

### Acceptance Criteria
- ac one
- ac two

### Definition of Done
- dod one
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "alpha-1" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "Solo story" ]
  [ "$(jq '.[0].heading_line' <<<"$output")" -eq 3 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "ac one" ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "ac two" ]
  [ "$(jq -r '.[0].definition_of_done[0]' <<<"$output")" = "dod one" ]
}

# ---------------------------------------------------------------------------
# 5 stories canonical
# ---------------------------------------------------------------------------
@test "5 canonical '## Story' headings yield 5 stories in order" {
  {
    for n in 1 2 3 4 5; do
      printf '## Story s-%d: title %d\n\n### Acceptance Criteria\n- ac %d\n\n### Definition of Done\n- dod %d\n\n' "$n" "$n" "$n" "$n"
    done
  } > "$PLAN"
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 5 ]
  [ "$(jq -r '[.[].story_id] | join(",")' <<<"$output")" = "s-1,s-2,s-3,s-4,s-5" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "title 1" ]
  [ "$(jq -r '.[4].title' <<<"$output")" = "title 5" ]
  # Heading line numbers strictly increase
  prev=0
  for i in 0 1 2 3 4; do
    line="$(jq ".[$i].heading_line" <<<"$output")"
    [ "$line" -gt "$prev" ]
    prev="$line"
  done
}

# ---------------------------------------------------------------------------
# amendment-style plan: only '### <id> amendment' headings
# ---------------------------------------------------------------------------
@test "amendment-style plan ('### N amendment') parses all amendments" {
  cat > "$PLAN" <<'EOF'
# Amendment plan

### mech-1 amendment

### Acceptance Criteria
- amend mech-1

### Definition of Done
- done mech-1

### mech-2 amendment

### Acceptance Criteria
- amend mech-2

### Definition of Done
- done mech-2

### mech-3 amendment

### Acceptance Criteria
- amend mech-3

### Definition of Done
- done mech-3
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 3 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "mech-1" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "mech-1 amendment" ]
  [ "$(jq -r '.[1].story_id' <<<"$output")" = "mech-2" ]
  [ "$(jq -r '.[2].story_id' <<<"$output")" = "mech-3" ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "amend mech-1" ]
  [ "$(jq -r '.[2].definition_of_done[0]' <<<"$output")" = "done mech-3" ]
}

# ---------------------------------------------------------------------------
# Mixed: one '## NEW Story' + several '### N amendment'
# ---------------------------------------------------------------------------
@test "mixed plan with one '## NEW Story' and several '### N amendment'" {
  cat > "$PLAN" <<'EOF'
# Mixed plan

## NEW Story mech-99: brand new story

### Acceptance Criteria
- new ac

### Definition of Done
- new dod

### mech-1 amendment

### Acceptance Criteria
- amend ac

### Definition of Done
- amend dod

### mech-2 amendment

### Acceptance Criteria
- amend2 ac
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 3 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "mech-99" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "brand new story" ]
  [ "$(jq -r '.[1].story_id' <<<"$output")" = "mech-1" ]
  [ "$(jq -r '.[1].title' <<<"$output")" = "mech-1 amendment" ]
  [ "$(jq -r '.[2].story_id' <<<"$output")" = "mech-2" ]
  # mech-2 amendment has AC but no DoD — DoD should be empty array.
  [ "$(jq '.[2].definition_of_done | length' <<<"$output")" -eq 0 ]
  [ "$(jq -r '.[2].acceptance_criteria[0]' <<<"$output")" = "amend2 ac" ]
}

# ---------------------------------------------------------------------------
# Unicode story id and title
# ---------------------------------------------------------------------------
@test "unicode story id and title parsed correctly" {
  cat > "$PLAN" <<'EOF'
## Story 機能-1: ユーザー認証機能 — café & naïve façade ☕

### Acceptance Criteria
- 入力検証

### Definition of Done
- テスト合格
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "機能-1" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "ユーザー認証機能 — café & naïve façade ☕" ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "入力検証" ]
  [ "$(jq -r '.[0].definition_of_done[0]' <<<"$output")" = "テスト合格" ]
}

# ---------------------------------------------------------------------------
# Story with no Acceptance Criteria section
# ---------------------------------------------------------------------------
@test "story missing Acceptance Criteria section -> empty array" {
  cat > "$PLAN" <<'EOF'
## Story s-1: no AC here

### Definition of Done
- only dod
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 0 ]
  [ "$(jq '.[0].definition_of_done | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].definition_of_done[0]' <<<"$output")" = "only dod" ]
}

# ---------------------------------------------------------------------------
# Story with malformed DoD (paragraph, not bullets) -> single item
# ---------------------------------------------------------------------------
@test "malformed Definition of Done (paragraph) treated as one item" {
  cat > "$PLAN" <<'EOF'
## Story s-1: paragraph dod

### Acceptance Criteria
- ac one

### Definition of Done
The team agrees that this story is complete when the tests pass
and the docs are updated. No bullet list here — just prose.
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].definition_of_done | length' <<<"$output")" -eq 1 ]
  item="$(jq -r '.[0].definition_of_done[0]' <<<"$output")"
  [[ "$item" == *"tests pass"* ]]
  [[ "$item" == *"docs are updated"* ]]
}

# ---------------------------------------------------------------------------
# Trailing-whitespace heading robustness
# ---------------------------------------------------------------------------
@test "heading with trailing whitespace still recognised" {
  printf '## Story s-1: title with trail   \n\n### Acceptance Criteria\n- ac\n' > "$PLAN"
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "s-1" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "title with trail" ]
}

# ---------------------------------------------------------------------------
# Wrapped bullet — continuation line joins into one item (FL1)
# ---------------------------------------------------------------------------
@test "wrapped bullet joins continuation line into a single item" {
  cat > "$PLAN" <<'EOF'
## Story s-1: wrapped bullet

### Acceptance Criteria
- returns exactly one
  STATUS line.
- second item
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "returns exactly one STATUS line." ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "second item" ]
}

# ---------------------------------------------------------------------------
# FINDING marker between a bullet's first line and its continuation (FL1)
# ---------------------------------------------------------------------------
@test "FINDING marker inside a wrapped bullet neither appears nor breaks the join" {
  cat > "$PLAN" <<'EOF'
## Story s-1: marker-interrupted bullet

### Acceptance Criteria
- returns exactly one
<!-- FINDING id=BND-X4 severity=high: parser truncates wrapped bullets -->
  STATUS line.
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "returns exactly one STATUS line." ]
  run jq -e 'any(.[].acceptance_criteria[]; contains("FINDING"))' <<<"$output"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Comment-only line inside an un-bulleted (prose-mode) section (FL1)
# ---------------------------------------------------------------------------
@test "comment line in prose-mode AC section is excluded from the joined item" {
  cat > "$PLAN" <<'EOF'
## Story s-1: prose with marker

### Acceptance Criteria
The gate passes when every marker
<!-- FINDING id=Y1: this must not leak into the item -->
has been folded away.
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "The gate passes when every marker has been folded away." ]
}

# ---------------------------------------------------------------------------
# Multi-line comment skipped entirely (FL1)
# ---------------------------------------------------------------------------
@test "multi-line HTML comment inside a section body is skipped entirely" {
  cat > "$PLAN" <<'EOF'
## Story s-1: multi-line comment

### Acceptance Criteria
- keeps the first
<!-- FINDING id=Z9
  spans several lines
-->
  and the last word.
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "keeps the first and the last word." ]
}

# ---------------------------------------------------------------------------
# Terminators — blank line and new bullet end continuation joining (FL1)
# ---------------------------------------------------------------------------
@test "blank line and new bullet terminate continuation joining" {
  cat > "$PLAN" <<'EOF'
## Story s-1: terminators

### Acceptance Criteria
- first item
  still first.
- second item

stray line after blank is not a continuation
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "first item still first." ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "second item" ]
}

# ---------------------------------------------------------------------------
# Fenced code blocks never leak into items (FL1 review)
# ---------------------------------------------------------------------------
@test "fenced code block content is never joined into the preceding criterion" {
  cat > "$PLAN" <<'EOF'
## Story s-1: fenced example

### Acceptance Criteria
- the gate emits:
```
STATUS=OK
COUNT=0
- not really an item
```
- second criterion
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "the gate emits:" ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "second criterion" ]
  [ "$(jq '[.[] | .acceptance_criteria[]?] | map(select(contains("```"))) | length' <<<"$output")" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Unterminated comment is never a silent truncation (FL1 review)
# ---------------------------------------------------------------------------
@test "unterminated HTML comment warns on stderr and keeps prior items" {
  cat > "$PLAN" <<'EOF'
## Story s-1: unterminated comment

### Acceptance Criteria
- first criterion
<!-- FINDING: unterminated comment
- second criterion
- third criterion
EOF
  out="$("$PS_SH" "$PLAN" 2>"$TMP/stderr.txt")"
  [ "$(jq -c '.[0].acceptance_criteria' <<<"$out")" = '["first criterion"]' ]
  grep -q "unterminated" "$TMP/stderr.txt"
}

# ---------------------------------------------------------------------------
# Text sharing a line with a comment delimiter survives (FL1 review)
# ---------------------------------------------------------------------------
@test "text after an inline comment close survives as continuation" {
  cat > "$PLAN" <<'EOF'
## Story s-1: inline delimiter residue

### Acceptance Criteria
- the parser keeps
<!-- FINDING id=Q1 --> every word of the criterion.
- second item
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "the parser keeps every word of the criterion." ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "second item" ]
}

@test "text after a multi-line comment close line survives as continuation" {
  cat > "$PLAN" <<'EOF'
## Story s-1: close-line residue

### Acceptance Criteria
- the parser keeps
<!-- FINDING id=Q1
  more comment text
  --> every word of the criterion.
- second item
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "the parser keeps every word of the criterion." ]
}

# ---------------------------------------------------------------------------
# Headings deeper than H3 terminate the join (FL1 review)
# ---------------------------------------------------------------------------
@test "H4 heading terminates continuation joining and is not absorbed" {
  cat > "$PLAN" <<'EOF'
## Story s-1: h4 terminator

### Acceptance Criteria
- first criterion
#### Notes
- second criterion
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq '.[0].acceptance_criteria | length' <<<"$output")" -eq 2 ]
  [ "$(jq -r '.[0].acceptance_criteria[0]' <<<"$output")" = "first criterion" ]
  [ "$(jq -r '.[0].acceptance_criteria[1]' <<<"$output")" = "second criterion" ]
}

# ---------------------------------------------------------------------------
# Touches bullets stay verbatim globs — no continuation join (FL1 review)
# ---------------------------------------------------------------------------
@test "touches bullets are never joined with continuation lines" {
  cat > "$PLAN" <<'EOF'
## Story s-1: touches wrap

### Touches:
- skills/team-sprint/scripts/parse_stories.sh
  (the parse_body function only)
- skills/team-sprint/scripts/lib.sh
EOF
  run "$PS_SH" "$PLAN"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[0].touches' <<<"$output")" = '["skills/team-sprint/scripts/parse_stories.sh","skills/team-sprint/scripts/lib.sh"]' ]
}

# ---------------------------------------------------------------------------
# Real sprint plan smoke test — must yield 15 mech-* stories.
# ---------------------------------------------------------------------------
@test "real sprint plan parses to 15 stories named mech-1..mech-15" {
  REAL="$SKILL_DIR/docs/plans/sprint-team-sprint-mech-refactor-v3.md"
  [ -f "$REAL" ] || skip "real plan absent"
  run "$PS_SH" "$REAL"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" -eq 15 ]
  [ "$(jq -r '.[0].story_id' <<<"$output")" = "mech-1" ]
  [ "$(jq -r '.[14].story_id' <<<"$output")" = "mech-15" ]
  # Fence-leak regression guard: every fenced block in this plan opens with an
  # info string (```json / ```yaml / ```markdown) on its own line, so none may
  # appear inside a parsed item. (A bare ``` can occur legitimately — one
  # mech-10 bullet mentions triple backticks inline in its own prose.)
  [ "$(jq '[.[] | .acceptance_criteria[]?, .definition_of_done[]?] | map(select(test("```(json|yaml|markdown)"))) | length' <<<"$output")" -eq 0 ]
}

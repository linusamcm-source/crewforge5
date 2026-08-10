#!/usr/bin/env bats
# build_commit_msg.bats — fixtures for scripts/build_commit_msg.sh (Story mech-6).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  BCM_SH="$SCRIPTS/build_commit_msg.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP

  PLAN="$TMP/plan.md"
}

teardown() {
  rm -rf "$TMP"
}

# Helper: count unicode code points (LC_ALL=en_US.UTF-8 forces Python len() to
# match how the script truncates).
codepoint_len() {
  LC_ALL=en_US.UTF-8 python3 -c 'import sys; print(len(sys.argv[1]))' "$1"
}

# ---------------------------------------------------------------------------
# Title ≤72 codepoints — passes through unchanged in the subject.
# ---------------------------------------------------------------------------
@test "title ≤72 code points: subject unchanged" {
  cat > "$PLAN" <<'EOF'
# plan

## Story mech-1: Short title

### Acceptance Criteria
- ac one
- ac two

### Definition of Done
- dod one
EOF
  run "$BCM_SH" "$PLAN" mech-1 feat
  [ "$status" -eq 0 ]

  subject="$(printf '%s\n' "$output" | head -n1)"
  [ "$subject" = "feat(mech-1): Short title" ]
  # Subject length is the literal byte/codepoint count — both are 24 here.
  [ "$(codepoint_len "$subject")" -le 72 ]
}

# ---------------------------------------------------------------------------
# Title >72 codepoints -> truncated to 71 + "…" (total 72 code points).
# ---------------------------------------------------------------------------
@test "title >72 code points: truncated to 71 + '…' (total 72)" {
  long_title="$(printf 'X%.0s' $(seq 1 200))"  # 200 X's; raw subject far over 72
  {
    printf '## Story mech-2: %s\n\n' "$long_title"
    printf '### Acceptance Criteria\n- ac\n\n### Definition of Done\n- dod\n'
  } > "$PLAN"

  run "$BCM_SH" "$PLAN" mech-2 feat
  [ "$status" -eq 0 ]

  subject="$(printf '%s\n' "$output" | head -n1)"
  # Truncated subject is exactly 72 code points, ends with "…".
  [ "$(codepoint_len "$subject")" -eq 72 ]
  [[ "$subject" == *"…" ]]
  # And the first 71 chars are the literal-truncated raw subject.
  # raw subject = "feat(mech-2): XXXXX..."; the truncation cuts at codepoint 71.
}

# ---------------------------------------------------------------------------
# Multi-byte title (Japanese) — valid UTF-8 output, ≤72 codepoints.
# Spec example: "feat(BUG-417): フィードバック表示の修正"
# ---------------------------------------------------------------------------
@test "multi-byte (Japanese) title: valid UTF-8, subject ≤72 code points" {
  cat > "$PLAN" <<'EOF'
# plan

## Story BUG-417: フィードバック表示の修正

### Acceptance Criteria
- バグの再現テストを書く
- 修正を適用する

### Definition of Done
- テストが通る
EOF
  run "$BCM_SH" "$PLAN" BUG-417 feat
  [ "$status" -eq 0 ]

  subject="$(printf '%s\n' "$output" | head -n1)"
  [ "$subject" = "feat(BUG-417): フィードバック表示の修正" ]
  # Valid UTF-8 (round-trips through python).
  LC_ALL=en_US.UTF-8 python3 -c 'import sys; sys.argv[1].encode("utf-8").decode("utf-8")' "$subject"
  # ≤72 code points.
  [ "$(codepoint_len "$subject")" -le 72 ]

  # Body contains the AC bullets verbatim.
  [[ "$output" == *"- バグの再現テストを書く"* ]]
  [[ "$output" == *"- 修正を適用する"* ]]
}

# ---------------------------------------------------------------------------
# Body contains `Story: mech-N` literal line (mech-9 snapshot regen depends
# on this).
# ---------------------------------------------------------------------------
@test "body contains literal 'Story: mech-N' line" {
  cat > "$PLAN" <<'EOF'
# plan

## Story mech-9: SKILL.md split

### Acceptance Criteria
- phase docs exist

### Definition of Done
- wc -l SKILL.md <= 250
EOF
  run "$BCM_SH" "$PLAN" mech-9 docs
  [ "$status" -eq 0 ]

  # Match the EXACT line via grep -F line-mode so the assertion is byte-precise.
  printf '%s\n' "$output" | grep -F -x "Story: mech-9 — SKILL.md split"
  # And the Plan line.
  printf '%s\n' "$output" | grep -F -x "Plan: $PLAN"
}

# ---------------------------------------------------------------------------
# All AC bullets present in body.
# ---------------------------------------------------------------------------
@test "body contains every acceptance-criteria bullet" {
  cat > "$PLAN" <<'EOF'
# plan

## Story mech-3: many criteria

### Acceptance Criteria
- alpha criterion
- beta criterion
- gamma criterion
- delta criterion

### Definition of Done
- done
EOF
  run "$BCM_SH" "$PLAN" mech-3 refactor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Acceptance criteria met:"* ]]
  [[ "$output" == *"- alpha criterion"* ]]
  [[ "$output" == *"- beta criterion"* ]]
  [[ "$output" == *"- gamma criterion"* ]]
  [[ "$output" == *"- delta criterion"* ]]
}

# ---------------------------------------------------------------------------
# Gates summary line + Co-Authored-By trailer present.
# ---------------------------------------------------------------------------
@test "body has Gates summary line + Co-Authored-By trailer" {
  cat > "$PLAN" <<'EOF'
## Story mech-1: foo

### Acceptance Criteria
- ac

### Definition of Done
- dod
EOF
  run "$BCM_SH" "$PLAN" mech-1 chore
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gates: typecheck"* ]]
  [[ "$output" == *"Co-Authored-By: Claude"* ]]
}

# ---------------------------------------------------------------------------
# Missing story_id arg -> usage error.
# ---------------------------------------------------------------------------
@test "missing args -> usage error (exit 2)" {
  cat > "$PLAN" <<'EOF'
## Story mech-1: foo

### Acceptance Criteria
- ac

### Definition of Done
- dod
EOF
  run "$BCM_SH" "$PLAN" mech-1
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Unknown story_id -> error (exit 1).
# ---------------------------------------------------------------------------
@test "unknown story_id -> error (exit 1)" {
  cat > "$PLAN" <<'EOF'
## Story mech-1: foo

### Acceptance Criteria
- ac

### Definition of Done
- dod
EOF
  run "$BCM_SH" "$PLAN" mech-999 feat
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# Empty story_id -> error.
# ---------------------------------------------------------------------------
@test "empty story_id -> error (exit 1)" {
  cat > "$PLAN" <<'EOF'
## Story mech-1: foo

### Acceptance Criteria
- ac

### Definition of Done
- dod
EOF
  run "$BCM_SH" "$PLAN" "" feat
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Invalid type -> error.
# ---------------------------------------------------------------------------
@test "invalid type -> error (exit 1)" {
  cat > "$PLAN" <<'EOF'
## Story mech-1: foo

### Acceptance Criteria
- ac

### Definition of Done
- dod
EOF
  run "$BCM_SH" "$PLAN" mech-1 bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid type"* ]]
}

#!/usr/bin/env bats
# check.bats — fixtures for check.sh's four assertion classes and sweep.py.
# Self-contained: builds throwaway skill dirs + a fixture baseline.json.

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/../scripts" && pwd)"
  CHECK="$SCRIPTS/check.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  SKILLS="$TMP/skills"
  mkdir -p "$SKILLS/good/references" "$SKILLS/bad"

  cat > "$SKILLS/good/SKILL.md" <<'EOF'
---
name: good
description: Use when the user says "do the thing" or "run it". Short and compliant.
---

## Workflow

Steps here. See [details](references/detail.md).

## When to use

Also trigger on "the long tail phrase".
EOF
  cat > "$SKILLS/good/references/detail.md" <<'EOF'
## Moved Section

Relocated conditional content.
EOF

  LONG_DESC="$(printf 'x%.0s' {1..520})"
  cat > "$SKILLS/bad/SKILL.md" <<EOF
---
name: bad
description: $LONG_DESC
---

## Workflow

Body with a [broken link](references/missing.md).
EOF

  cat > "$TMP/baseline.json" <<'EOF'
{
  "good": {
    "desc_chars": 76,
    "body_chars": 100,
    "trigger_phrases": ["do the thing", "run it", "the long tail phrase"],
    "headings": ["Workflow", "When to use", "Moved Section"]
  },
  "bad": {
    "desc_chars": 520,
    "body_chars": 50,
    "trigger_phrases": ["a phrase that was deleted"],
    "headings": ["Workflow", "A Heading That Vanished"]
  }
}
EOF
}

teardown() { rm -rf "$TMP"; }

@test "passes a fully compliant skill (desc cap, phrases, headings, links)" {
  run "$CHECK" good "$SKILLS" "$TMP/baseline.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails when description exceeds the desc cap" {
  run "$CHECK" bad "$SKILLS" "$TMP/baseline.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"desc 520 chars > 300"* ]]
}

@test "desc cap is overridable via the fourth argument" {
  run "$CHECK" bad "$SKILLS" "$TMP/baseline.json" 600
  [[ "$output" != *"desc 520 chars"* ]]
}

@test "fails when a baseline trigger phrase is lost" {
  run "$CHECK" bad "$SKILLS" "$TMP/baseline.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *'trigger phrase lost: "a phrase that was deleted"'* ]]
}

@test "passes phrase retention when phrase lives in references/" {
  perl -pi -e 's/Also trigger on "the long tail phrase"\./See references./' "$SKILLS/good/SKILL.md"
  echo 'Trigger: "the long tail phrase"' >> "$SKILLS/good/references/detail.md"
  run "$CHECK" good "$SKILLS" "$TMP/baseline.json"
  [ "$status" -eq 0 ]
}

@test "fails when a baseline heading is lost" {
  run "$CHECK" bad "$SKILLS" "$TMP/baseline.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"heading lost: A Heading That Vanished"* ]]
}

@test "fails when a references link does not resolve" {
  run "$CHECK" bad "$SKILLS" "$TMP/baseline.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken link: references/missing.md"* ]]
}

@test "fails for a skill with no baseline entry" {
  mkdir -p "$SKILLS/orphan"
  printf -- '---\nname: orphan\ndescription: ok\n---\nbody\n' > "$SKILLS/orphan/SKILL.md"
  run "$CHECK" orphan "$SKILLS" "$TMP/baseline.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no baseline entry"* ]]
}

@test "sweep passes compliant fixtures and enforces body ceilings" {
  # baseline covering only the compliant fixture; generous ceiling passes
  cat > "$TMP/base2.json" <<'EOF'
{ "good": { "desc_chars": 76, "body_chars": 100,
            "trigger_phrases": ["do the thing", "run it", "the long tail phrase"],
            "headings": ["Workflow", "When to use", "Moved Section"] } }
EOF
  echo '{ "good": 2.0 }' > "$TMP/ceilings.json"
  run python3 "$SCRIPTS/sweep.py" --skills-dir "$SKILLS" --baseline "$TMP/base2.json" --ceilings "$TMP/ceilings.json" --legacy-cap 600
  [ "$status" -eq 0 ]
  [[ "$output" == *"sweep OK"* ]]

  # impossible ceiling fails
  echo '{ "good": 0.01 }' > "$TMP/ceilings.json"
  run python3 "$SCRIPTS/sweep.py" --skills-dir "$SKILLS" --baseline "$TMP/base2.json" --ceilings "$TMP/ceilings.json" --legacy-cap 600
  [ "$status" -ne 0 ]
  [[ "$output" == *"ceiling"* ]]
}

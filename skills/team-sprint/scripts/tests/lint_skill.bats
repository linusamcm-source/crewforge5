#!/usr/bin/env bats
# lint_skill.bats — fixtures for scripts/lint_skill.sh
#
# Each test builds a minimal synthetic skill layout in $TMP that the real
# lint_skill.sh is copied into, then asserts the expected check passes or
# fails. The synthetic layout keeps the surface small (one trivial script,
# one trivial bats fixture) so checks #7 (shellcheck) and #8 (bats) are
# fast and deterministic.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# build_clean_skill <root>
#   Populates <root> with a layout that passes every lint check (1..9, 11, 12).
build_clean_skill() {
  local root="$1"
  mkdir -p "$root/scripts/tests/lib" "$root/references/phases" "$root/references"

  # Copy the real lint_skill.sh + the bats-fallback shim into the synthetic
  # skill so it can self-locate.
  cp "$REAL_LINT_SH"      "$root/scripts/lint_skill.sh"
  cp "$REAL_BATS_FB"      "$root/scripts/tests/lib/bats-fallback.sh"
  chmod +x "$root/scripts/lint_skill.sh"

  # One trivial script + its matching bats fixture (so check #3 + #4 trivially
  # satisfied, check #7 passes shellcheck, check #8 runs the fixture).
  cat > "$root/scripts/dummy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ok\n'
SH
  chmod +x "$root/scripts/dummy.sh"

  cat > "$root/scripts/tests/dummy.bats" <<'BATS'
#!/usr/bin/env bats
source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

@test "dummy script prints ok" {
  run bash "$BATS_TEST_DIRNAME/../dummy.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
BATS

  # One reference doc — content doesn't matter, just existence + back-reference.
  cat > "$root/references/example.md" <<'REF'
**WHO READS THIS / WHEN:** test fixture.

Example reference doc.
REF

  # $REF/subskill-hooks.md — required by check #10 (mech-15 deliverable).
  cat > "$root/references/subskill-hooks.md" <<'REF'
**WHO READS THIS / WHEN:** test fixture.

Sub-skill hook contract stub.
REF

  # Eight phase docs (0..7) — each with marker + at least one $SCRIPTS/<x>.sh.
  for n in 0 1 2 3 4 5 6 7; do
    cat > "$root/references/phases/phase-${n}.md" <<PHASE
# Phase ${n}

Steps reference \$SCRIPTS/dummy.sh.

## Extensions
<!-- subskill-hooks:phase-${n} -->
Reserved.
PHASE
  done

  # SKILL.md mentions every phase doc + the ref doc. dummy.sh is exempted via
  # the dummy.bats fixture rule.
  {
    printf -- '---\n'
    printf 'name: synthetic-skill\n'
    printf 'description: synthetic.\n'
    printf -- '---\n\n'
    printf '# Synthetic skill\n\n'
    printf 'See `$REF/example.md`.\n\n'
    printf 'See `$REF/subskill-hooks.md`.\n\n'
    printf 'Lint runs via `$SCRIPTS/lint_skill.sh`.\n\n'
    for n in 0 1 2 3 4 5 6 7; do
      printf 'Load `$PHASES/phase-%s.md`.\n' "$n"
    done
  } > "$root/SKILL.md"

  # Config example with every v3 field grep #9 checks.
  cat > "$root/team-sprint.config.yaml.example" <<'CFG'
plan_path: docs/plans/x.md
target_branch: develop
coverage_threshold: 80
coverage_mode: new
adversarial_iterations: 3
adversarial_model: opus
max_wall_clock_minutes: 240
repomix_max_age_minutes: 240
integration_diagram: off
subskill_hooks:
  phase-0: []
CFG
}

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REAL_LINT_SH="$SKILL_DIR/scripts/lint_skill.sh"
  REAL_BATS_FB="$SKILL_DIR/scripts/tests/lib/bats-fallback.sh"
  export REAL_LINT_SH REAL_BATS_FB

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  SKILL="$TMP/skill"
  build_clean_skill "$SKILL"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "clean-state layout: lint exits 0" {
  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -eq 0 ]
}

@test "missing subskill-hooks marker fails check #5" {
  # Strip the marker from phase-3.md.
  grep -v 'subskill-hooks:phase-3' "$SKILL/references/phases/phase-3.md" \
    > "$SKILL/references/phases/phase-3.md.new"
  mv "$SKILL/references/phases/phase-3.md.new" "$SKILL/references/phases/phase-3.md"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check5]"*) : ;;
    *) printf 'expected [check5] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

@test "allow-bootstrap residue in SKILL.md fails check #11" {
  printf '\nLegacy: --allow-bootstrap was a transient flag.\n' >> "$SKILL/SKILL.md"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check11]"*) : ;;
    *) printf 'expected [check11] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

@test "forbidden bats-assert helper in fixture fails check #12" {
  # We inject a bats-assert helper that is not in the bats-fallback.sh
  # allow-list. The identifier is assembled in two parts so the literal
  # token does not appear in THIS source file (the lint we're testing greps
  # every .bats in $SCRIPTS/tests/ for forbidden helpers — including this
  # one — so an inline literal would break check #12 on the real skill).
  local prefix="re""fute"
  local helper="${prefix}_count"
  {
    printf '\n@test "uses forbidden helper" {\n'
    printf '  run true\n'
    printf '  %s 0\n' "$helper"
    printf '}\n'
  } >> "$SKILL/scripts/tests/dummy.bats"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check12]"*) : ;;
    *) printf 'expected [check12] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
  case "$output" in
    *"$helper"*) : ;;
    *) printf 'expected %s in output, got: %s\n' "$helper" "$output" >&2; return 1 ;;
  esac
}

@test "missing phase doc fails check #1" {
  rm "$SKILL/references/phases/phase-4.md"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check1]"*) : ;;
    *) printf 'expected [check1] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

@test "dangling internal anchor in SKILL.md fails check #6" {
  printf '\nSee [the plan path](#plan-path-naming) for naming.\n' >> "$SKILL/SKILL.md"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check6]"*) : ;;
    *) printf 'expected [check6] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

@test "missing \$REF/subskill-hooks.md fails check #10" {
  rm "$SKILL/references/subskill-hooks.md"
  # Also strip the SKILL.md back-reference so check #2 doesn't fire first.
  grep -v 'subskill-hooks.md' "$SKILL/SKILL.md" > "$SKILL/SKILL.md.new"
  mv "$SKILL/SKILL.md.new" "$SKILL/SKILL.md"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check10]"*) : ;;
    *) printf 'expected [check10] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

@test "missing team-sprint.config.yaml.example fails check #9" {
  rm "$SKILL/team-sprint.config.yaml.example"

  run bash "$SKILL/scripts/lint_skill.sh"
  [ "$status" -ne 0 ]
  case "$output" in
    *"[check9]"*) : ;;
    *) printf 'expected [check9] in output, got: %s\n' "$output" >&2; return 1 ;;
  esac
}

#!/usr/bin/env bash
# shellcheck shell=bash
# lint_skill.sh — structural lint for the team-sprint skill.
#
# Runs checks #1..#12 from sprint plan v3 mech-14 (Phase doc lint).
# Check #10 ($REF/subskill-hooks.md existence) was added in mech-14b once
# mech-15 shipped the file.
#
# Exit 0 on all-checks-pass; non-zero on any failure. Each failure prints
# `[checkN] <message>` to stderr.

set -euo pipefail

# --- locate skill layout ----------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
SCRIPTS="$HERE"
PHASES="$SKILL_DIR/references/phases"
REF="$SKILL_DIR/references"
SKILL_MD="$SKILL_DIR/SKILL.md"
CONFIG_EXAMPLE="$SKILL_DIR/team-sprint.config.yaml.example"

FAILED=0

fail_check() {
  # $1 = check id, remaining = message
  local id="$1"
  shift
  printf '[check%s] %s\n' "$id" "$*" >&2
  FAILED=1
}

# --- pre-flight -------------------------------------------------------------
if [[ ! -f "$SKILL_MD" ]]; then
  printf '[lint_skill] SKILL.md not found at %s\n' "$SKILL_MD" >&2
  exit 2
fi

# --- check 1: SKILL.md mentions phase-N.md (N=0..7) and each file exists ----
for n in 0 1 2 3 4 5 6 7; do
  needle="\$PHASES/phase-${n}.md"
  if ! grep -qF "$needle" "$SKILL_MD"; then
    fail_check 1 "SKILL.md does not reference $needle"
  fi
  if [[ ! -f "$PHASES/phase-${n}.md" ]]; then
    fail_check 1 "$PHASES/phase-${n}.md is missing"
  fi
done

# --- check 2: SKILL.md mentions every $REF/*.md and vice versa --------------
if [[ -d "$REF" ]]; then
  shopt -s nullglob
  for r in "$REF"/*.md; do
    bn="$(basename "$r")"
    needle="\$REF/$bn"
    if ! grep -qF "$needle" "$SKILL_MD"; then
      fail_check 2 "$REF/$bn exists but SKILL.md does not reference \$REF/$bn"
    fi
  done
  # Reverse: every $REF/<file>.md mentioned in SKILL.md must exist on disk.
  while IFS= read -r mentioned; do
    [[ -z "$mentioned" ]] && continue
    if [[ ! -f "$REF/$mentioned" ]]; then
      fail_check 2 "SKILL.md mentions \$REF/$mentioned but no such file under $REF/"
    fi
  done < <(
    # shellcheck disable=SC2016  # literal '$REF/' is intentional
    grep -oE '\$REF/[A-Za-z0-9_./-]+\.md' "$SKILL_MD" \
      | sed 's#^\$REF/##' \
      | sort -u
  )
  shopt -u nullglob
fi

# --- check 3: SKILL.md mentions every $SCRIPTS/*.sh OR script has a -------
# --- corresponding fixture under $SCRIPTS/tests/ (test harness exempt)  -----
shopt -s nullglob
for s in "$SCRIPTS"/*.sh; do
  bn="$(basename "$s")"
  needle="\$SCRIPTS/$bn"
  if grep -qF "$needle" "$SKILL_MD"; then
    continue
  fi
  # Exempt if a matching .bats fixture exists under $SCRIPTS/tests/.
  fixture="$SCRIPTS/tests/${bn%.sh}.bats"
  if [[ -f "$fixture" ]]; then
    continue
  fi
  fail_check 3 "$SCRIPTS/$bn not referenced in SKILL.md and no fixture at $fixture"
done
shopt -u nullglob

# --- check 4: every phase-N.md references at least one $SCRIPTS/*.sh --------
# Scope: $PHASES/phase-*.md at depth 1 only.
while IFS= read -r phase_doc; do
  # shellcheck disable=SC2016  # literal '$SCRIPTS/' is intentional
  if ! grep -qE '\$SCRIPTS/[a-z_]+\.sh' "$phase_doc"; then
    fail_check 4 "$phase_doc does not reference any \$SCRIPTS/<name>.sh"
  fi
done < <(find "$PHASES" -maxdepth 1 -name 'phase-*.md' 2>/dev/null | sort)

# --- check 5: every phase-N.md has <!-- subskill-hooks:phase-N --> exactly --
# --- once. Scope: $PHASES/phase-*.md at depth 1 only.                    ---
for n in 0 1 2 3 4 5 6 7; do
  doc="$PHASES/phase-${n}.md"
  if [[ ! -f "$doc" ]]; then
    # Already reported by check #1; skip here.
    continue
  fi
  marker="<!-- subskill-hooks:phase-${n} -->"
  count="$(grep -cF "$marker" "$doc" || true)"
  if [[ "$count" -ne 1 ]]; then
    fail_check 5 "$doc contains marker '$marker' $count times (expected exactly 1)"
  fi
done

# --- check 6: no dangling internal anchors in SKILL.md ----------------------
# Capture once and branch on emptiness — the pattern lived in two places, so the
# presence test and the capture could drift apart. Same shape as check 11.
hits="$(grep -nE '\(#plan-path-naming|#reviewer-return-contract|#state-schema|#sendmessage-protocol\)' "$SKILL_MD" || true)"
if [[ -n "$hits" ]]; then
  fail_check 6 "SKILL.md contains dangling internal anchor(s):"$'\n'"$hits"
fi

# --- check 7: shellcheck over every $SCRIPTS/*.sh (excluding tests/lib) -----
if ! command -v shellcheck >/dev/null 2>&1; then
  fail_check 7 "shellcheck not on PATH — install: brew install shellcheck (>=0.9)"
else
  shopt -s nullglob
  sc_files=("$SCRIPTS"/*.sh)
  shopt -u nullglob
  if [[ ${#sc_files[@]} -gt 0 ]]; then
    if ! sc_out="$(shellcheck "${sc_files[@]}" 2>&1)"; then
      fail_check 7 "shellcheck reported findings:"$'\n'"$sc_out"
    fi
  fi
fi

# --- check 8: bats over $SCRIPTS/tests/ (or fallback runner) ----------------
# We run only the .bats files at depth 1 under $SCRIPTS/tests/, matching the
# layout produced by mech-8.
shopt -s nullglob
bats_files=("$SCRIPTS"/tests/*.bats)
shopt -u nullglob
if [[ ${#bats_files[@]} -eq 0 ]]; then
  fail_check 8 "$SCRIPTS/tests/ contains no .bats files"
else
  if command -v bats >/dev/null 2>&1; then
    if ! bats_out="$(bats "${bats_files[@]}" 2>&1)"; then
      fail_check 8 "bats reported failures:"$'\n'"$bats_out"
    fi
  else
    # Fallback: invoke each .bats as a plain bash script (bats-fallback.sh
    # makes this work — every fixture sources it at the top).
    for bf in "${bats_files[@]}"; do
      if ! fb_out="$(bash "$bf" 2>&1)"; then
        fail_check 8 "bats-fallback run of $bf failed:"$'\n'"$fb_out"
      fi
    done
  fi
fi

# --- check 9: team-sprint.config.yaml.example exists with full v3 surface ---
if [[ ! -f "$CONFIG_EXAMPLE" ]]; then
  fail_check 9 "$CONFIG_EXAMPLE is missing"
else
  # Sample the known v3 fields; absence of any signals an incomplete example.
  required_fields=(
    'plan_path:'
    'target_branch:'
    'coverage_threshold:'
    'coverage_mode:'
    'adversarial_iterations:'
    'adversarial_model:'
    'max_wall_clock_minutes:'
    'repomix_max_age_minutes:'
    'integration_diagram:'
    'subskill_hooks:'
  )
  for field in "${required_fields[@]}"; do
    if ! grep -qE "^[[:space:]]*${field}" "$CONFIG_EXAMPLE"; then
      fail_check 9 "$CONFIG_EXAMPLE missing field: $field"
    fi
  done
fi

# --- check 10: $REF/subskill-hooks.md exists -------------------------------
# mech-15 ships this file; mech-14b wires the existence check in.
if [[ ! -f "$REF/subskill-hooks.md" ]]; then
  fail_check 10 "$REF/subskill-hooks.md is missing (mech-15 deliverable)"
fi

# --- check 11: no `allow-bootstrap` residue in SKILL.md or phases/ ----------
# Scope intentionally narrow — $REF/ + team-sprint.config.yaml.example may
# legitimately document the retired flag (per plan v3 mech-14 AC).
ab_hits="$(grep -rn 'allow-bootstrap' "$SKILL_MD" "$PHASES" 2>/dev/null || true)"
if [[ -n "$ab_hits" ]]; then
  fail_check 11 "allow-bootstrap residue found (lint scope: SKILL.md + phases/):"$'\n'"$ab_hits"
fi

# --- check 12: every .bats under $SCRIPTS/tests/ uses only helpers ----------
# --- exported by $SCRIPTS/tests/lib/bats-fallback.sh                ---------
# Subtractive detection per plan v3 mech-14 AC:
#   enumerate (assert|refute)_[a-z_]+ in *.bats; subtract the allow-list.
shopt -s nullglob
bats_top=("$SCRIPTS"/tests/*.bats)
shopt -u nullglob
if [[ ${#bats_top[@]} -gt 0 ]]; then
  forbidden="$(grep -hoE '\b(assert|refute)_[a-z_]+\b' "${bats_top[@]}" \
                 | sort -u \
                 | grep -vxE '(refute_output|refute_stderr|assert_line|refute_line|assert_regex|assert_not_equal|assert_equal|assert_success|assert_failure|assert_output|assert_stderr)' \
                 || true)"
  if [[ -n "$forbidden" ]]; then
    fail_check 12 "forbidden bats-assert helper(s) used (not exported by bats-fallback.sh):"$'\n'"$forbidden"$'\n'"fix: either add the helper to bats-fallback.sh or use an exported alternative"
  fi
fi

exit "$FAILED"

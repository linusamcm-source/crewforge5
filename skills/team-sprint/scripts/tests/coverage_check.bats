#!/usr/bin/env bats
# coverage_check.bats — fixtures for scripts/coverage_check.sh (Story mech-5).
#
# Story LS2 (finding SCR6, folds SCR10) additionally pins the --mode new
# coverage-gate denominator: only added lines that live in coverable files
# (files present in the coverage report) may count toward the ratio. Added
# markdown/YAML/other non-coverable lines must neither inflate the pass rate nor
# produce a silent 100% / divide-by-zero when they are the ONLY thing in a diff.
# It also asserts the superseded single-file ADDED_LINES_FILE cleanup trap is
# gone (exactly one such trap remains).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  CC_SH="$SCRIPTS/coverage_check.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  # Run every fixture from a clean tmp dir so coverage-file autodetection sees
  # only what the fixture stages, and so we don't accidentally trip on the
  # skill repo's own team-sprint.config.yaml (coverage_threshold:0 there).
  cd "$TMP"
  # Default config path points inside TMP; fixtures opt in by writing one.
  export TEAM_SPRINT_CONFIG="$TMP/team-sprint.config.yaml"
}

teardown() {
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Skip path: commands.coverage="true"
# ---------------------------------------------------------------------------
@test "skip path: commands.coverage=\"true\" -> mode:skipped, gate_status:disabled, pass:null, stderr line" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "true"
EOF
  # Capture stdout-only (stderr -> /dev/null) so jq sees pure JSON.
  stdout="$("$CC_SH" --mode whole --threshold 80 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.mode'        <<<"$stdout")" = "skipped"  ]
  [ "$(jq -r '.gate_status' <<<"$stdout")" = "disabled" ]
  [ "$(jq -r '.pass'        <<<"$stdout")" = "null"     ]
  [ "$(jq -r '.reason'      <<<"$stdout")" = 'commands.coverage="true"' ]
  [ "$(jq -r '.story_id'    <<<"$stdout")" = "mech-5"   ]

  # Capture stderr (stdout -> /dev/null) and check the disabled-by-config line.
  stderr="$("$CC_SH" --mode whole --threshold 80 --story-id mech-5 2>&1 >/dev/null)"
  [[ "$stderr" == *"coverage gate disabled by config"* ]]
  [[ "$stderr" == *'commands.coverage="true"'* ]]
}

# ---------------------------------------------------------------------------
# Skip path: coverage_threshold=0
# ---------------------------------------------------------------------------
@test "skip path: coverage_threshold=0 -> mode:skipped, gate_status:disabled, pass:null, stderr line" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 0
commands:
  coverage: "npm test -- --coverage"
EOF
  stdout="$("$CC_SH" --mode whole --threshold 80 --story-id mech-7 2>/dev/null)"
  [ "$(jq -r '.mode'        <<<"$stdout")" = "skipped"  ]
  [ "$(jq -r '.gate_status' <<<"$stdout")" = "disabled" ]
  [ "$(jq -r '.pass'        <<<"$stdout")" = "null"     ]
  [ "$(jq -r '.reason'      <<<"$stdout")" = "coverage_threshold=0" ]
  [ "$(jq -r '.story_id'    <<<"$stdout")" = "mech-7"   ]

  stderr="$("$CC_SH" --mode whole --threshold 80 --story-id mech-7 2>&1 >/dev/null)"
  [[ "$stderr" == *"coverage gate disabled by config"* ]]
}

# ---------------------------------------------------------------------------
# No coverage file AND threshold > 0 AND commands.coverage != "true": exit 1
# with stderr detection-chain explanation.
# ---------------------------------------------------------------------------
@test "no coverage file + command produces nothing -> exit 1 with detection chain on stderr" {
  # The configured command is attempted once (auto-run); when it still yields
  # no report the original loud-failure contract holds.
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "false"
EOF
  run bash -c "\"$CC_SH\" --mode whole --threshold 80 --story-id mech-1 2>&1 >/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no coverage report detected"* ]]
  [[ "$output" == *"coverage/coverage-final.json"* ]]
  [[ "$output" == *"coverage.out"* ]]
}

@test "no coverage file + command that writes a report -> auto-run then measured" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "printf 'mode: set\nexample.com/pkg/f.go:1.1,2.2 1 1\n' > coverage.out"
EOF
  run bash -c "\"$CC_SH\" --mode whole --threshold 80 --story-id mech-1 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gate_status' <<<"$output")" = "measured" ]
  [ "$(jq -r '.format_detected' <<<"$output")" = "go" ]
}

@test "existing report is used as-is; coverage command NOT re-run" {
  # A pre-existing report short-circuits the auto-run (the command here would
  # clobber the report with an empty one and change the result if executed).
  printf 'mode: set\nexample.com/pkg/f.go:1.1,2.2 1 1\n' > coverage.out
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "printf 'mode: set\n' > coverage.out"
EOF
  run "$CC_SH" --mode whole --threshold 80 --story-id mech-1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.pct' <<<"$output")" = "100" ] || [ "$(jq -r '.pct' <<<"$output")" = "100.0" ]
}

# ---------------------------------------------------------------------------
# Istanbul JSON: pct + uncovered list correct.
# Fixture: 5 statements (lines 1..5); 4 covered, 1 uncovered (line 5) -> 80.0
# ---------------------------------------------------------------------------
@test "istanbul JSON: pct + uncovered + format_detected correct" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "/proj/src/a.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}},
      "2": {"start":{"line":3},"end":{"line":3}},
      "3": {"start":{"line":4},"end":{"line":4}},
      "4": {"start":{"line":5},"end":{"line":5}}
    },
    "s": {"0":1,"1":1,"2":1,"3":1,"4":0}
  }
}
EOF
  out="$("$CC_SH" --mode whole --threshold 80 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.format_detected'      <<<"$out")" = "istanbul" ]
  [ "$(jq -r '.mode'                 <<<"$out")" = "whole"    ]
  [ "$(jq -r '.gate_status'          <<<"$out")" = "measured" ]
  [ "$(jq -r '.pct == 80'            <<<"$out")" = "true"     ]
  [ "$(jq -r '.pass'                 <<<"$out")" = "true"     ]
  [ "$(jq -r '.uncovered | length'   <<<"$out")" = "1"        ]
  [ "$(jq -r '.uncovered[0].file'    <<<"$out")" = "/proj/src/a.ts" ]
  [ "$(jq -c '.uncovered[0].lines'   <<<"$out")" = "[5]"      ]
}

# Istanbul: failing-threshold case -> pass:false (pct < threshold).
@test "istanbul JSON: pct < threshold -> pass:false" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 90
commands:
  coverage: "npm test"
EOF
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/b.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}},
      "2": {"start":{"line":3},"end":{"line":3}},
      "3": {"start":{"line":4},"end":{"line":4}}
    },
    "s": {"0":1,"1":1,"2":0,"3":0}
  }
}
EOF
  out="$("$CC_SH" --mode whole --threshold 90 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.pct == 50' <<<"$out")" = "true"  ]
  [ "$(jq -r '.pass'      <<<"$out")" = "false" ]
  [ "$(jq -r '.format_detected' <<<"$out")" = "istanbul" ]
  [ "$(jq -r '.uncovered | length' <<<"$out")" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Go coverprofile: pct + uncovered correct.
# Fixture: 4 stmts total, 3 covered (lines 10-12 + 15-16), 1 uncovered (line 13-14)
# -> 75.0
# ---------------------------------------------------------------------------
@test "go coverprofile: pct + uncovered + format_detected correct" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 70
commands:
  coverage: "go test -coverprofile=coverage.out ./..."
EOF
  cat > coverage.out <<'EOF'
mode: set
github.com/x/y/foo.go:10.2,12.3 2 1
github.com/x/y/foo.go:13.2,14.3 1 0
github.com/x/y/foo.go:15.2,16.3 1 1
EOF
  out="$("$CC_SH" --mode whole --threshold 70 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.format_detected'    <<<"$out")" = "go"   ]
  [ "$(jq -r '.pct == 75'          <<<"$out")" = "true" ]
  [ "$(jq -r '.pass'               <<<"$out")" = "true" ]
  [ "$(jq -r '.uncovered | length' <<<"$out")" = "1"    ]
  [ "$(jq -r '.uncovered[0].file'  <<<"$out")" = "github.com/x/y/foo.go" ]
  [ "$(jq -c '.uncovered[0].lines' <<<"$out")" = "[13,14]" ]
}

# ---------------------------------------------------------------------------
# Python coverage.json: pct + uncovered correct.
# Fixture: 8 executed + 2 missing = 10 total -> 80.0
# ---------------------------------------------------------------------------
@test "python coverage.json: pct + uncovered + format_detected correct" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "pytest --cov --cov-report=json"
EOF
  cat > coverage.json <<'EOF'
{
  "files": {
    "src/foo.py": {"executed_lines": [1,2,3,4,5,6,7,8], "missing_lines": [9,10]}
  }
}
EOF
  out="$("$CC_SH" --mode whole --threshold 80 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.format_detected'    <<<"$out")" = "python" ]
  [ "$(jq -r '.pct == 80'          <<<"$out")" = "true"   ]
  [ "$(jq -r '.pass'               <<<"$out")" = "true"   ]
  [ "$(jq -c '.uncovered[0].lines' <<<"$out")" = "[9,10]" ]
  [ "$(jq -r '.uncovered[0].file'  <<<"$out")" = "src/foo.py" ]
}

# ---------------------------------------------------------------------------
# --mode new with --diff-base: only lines INTRODUCED by the diff are
# considered; pct is computed against added lines only; mode == "new".
# Seed: 2 commits modifying one file; lines 4-5 are newly added and uncovered;
# lines 1-2 are pre-existing and (in this fixture) covered. The whole-file
# coverage report flags line 5 as uncovered too — so the "new" gate sees only
# the diff intersection (lines 4 and 5).
# ---------------------------------------------------------------------------
@test "mode new + --diff-base: uncovered lines intersected with diff; pct vs added lines; mode==new" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  mkdir -p src
  cat > src/a.ts <<'EOF'
line1
line2
EOF
  git add -A && git commit -q -m "c1"
  base_sha="$(git rev-parse HEAD)"
  cat > src/a.ts <<'EOF'
line1
line2
line3
line4
line5
EOF
  git add -A && git commit -q -m "c2"

  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/a.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}},
      "2": {"start":{"line":3},"end":{"line":3}},
      "3": {"start":{"line":4},"end":{"line":4}},
      "4": {"start":{"line":5},"end":{"line":5}}
    },
    "s": {"0":1,"1":1,"2":1,"3":0,"4":0}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base_sha" --threshold 80 --story-id mech-5 2>/dev/null)"
  [ "$(jq -r '.mode'                 <<<"$out")" = "new" ]
  [ "$(jq -r '.format_detected'      <<<"$out")" = "istanbul" ]
  [ "$(jq -r '.uncovered | length'   <<<"$out")" = "1" ]
  [ "$(jq -r '.uncovered[0].file'    <<<"$out")" = "src/a.ts" ]
  # Only diff-introduced uncovered lines surface (4,5). Line 3 was added but
  # is covered; lines 1-2 are pre-existing so must not appear.
  [ "$(jq -c '.uncovered[0].lines'   <<<"$out")" = "[4,5]" ]
  # Added lines = {3,4,5}; covered-of-added = {3}; pct = 1/3 * 100 = 33.33.
  [ "$(jq -r '.pct == 33.33' <<<"$out")" = "true" ]
  [ "$(jq -r '.pass' <<<"$out")" = "false" ]
}

# ---------------------------------------------------------------------------
# Story LS2 (finding SCR6): --mode new denominator must exclude non-coverable
# files. A diff adding a code file (10 lines, 5 covered) plus a 100-line
# markdown file (absent from coverage data) must report the CODE coverage
# (5/10 = 50%) and FAIL an 80% gate — the markdown lines must not inflate the
# denominator. RED while coverage_check.sh sums ALL added lines into new_total
# (today it reports ~95.45% and PASSES).
# ---------------------------------------------------------------------------
@test "mode new (LS2): non-coverable added lines excluded from denominator; code=50% fails 80 gate" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"
  base_sha="$(git rev-parse HEAD)"

  mkdir -p src
  cat > src/code.ts <<'EOF'
l1
l2
l3
l4
l5
l6
l7
l8
l9
l10
EOF
  # 100 non-coverable added lines (markdown), absent from coverage data.
  mkdir -p docs
  seq 1 100 > docs/notes.md
  git add -A && git commit -q -m "c1"

  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/code.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}},
      "2": {"start":{"line":3},"end":{"line":3}},
      "3": {"start":{"line":4},"end":{"line":4}},
      "4": {"start":{"line":5},"end":{"line":5}},
      "5": {"start":{"line":6},"end":{"line":6}},
      "6": {"start":{"line":7},"end":{"line":7}},
      "7": {"start":{"line":8},"end":{"line":8}},
      "8": {"start":{"line":9},"end":{"line":9}},
      "9": {"start":{"line":10},"end":{"line":10}}
    },
    "s": {"0":1,"1":1,"2":1,"3":1,"4":1,"5":0,"6":0,"7":0,"8":0,"9":0}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base_sha" --threshold 80 --story-id ls2 2>/dev/null)"
  # Documented, currently-green invariants: mode + which uncovered lines surface.
  [ "$(jq -r '.mode'               <<<"$out")" = "new" ]
  [ "$(jq -r '.format_detected'    <<<"$out")" = "istanbul" ]
  [ "$(jq -r '.uncovered | length' <<<"$out")" = "1" ]
  [ "$(jq -r '.uncovered[0].file'  <<<"$out")" = "src/code.ts" ]
  [ "$(jq -c '.uncovered[0].lines' <<<"$out")" = "[6,7,8,9,10]" ]
  # LS2 contract (RED): denominator = coverable added lines only (10 code lines),
  # covered-of-added = 5 -> 50%. The 100 markdown lines must NOT dilute the ratio.
  [ "$(jq -r '.pct == 50' <<<"$out")" = "true" ]
  [ "$(jq -r '.pass'      <<<"$out")" = "false" ]
}

# ---------------------------------------------------------------------------
# Story LS2 (finding SCR6/SCR10): --mode new where the diff adds ONLY
# non-coverable files (all absent from coverage data). The gate must resolve to
# a defined, DOCUMENTED result — it PASSES with an explicit "no coverable lines"
# note — rather than a silent 100% or a divide-by-zero. RED today: the script
# emits pct:100 with no note.
# ---------------------------------------------------------------------------
@test "mode new (LS2): diff of only non-coverable files -> pass with explicit 'no coverable lines' note, not silent 100" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"
  base_sha="$(git rev-parse HEAD)"

  # Only markdown added: 20 + 10 = 30 non-coverable lines.
  mkdir -p docs
  seq 1 20 > docs/a.md
  seq 1 10 > docs/b.md
  git add -A && git commit -q -m "c1"

  # Coverage data exists (so detection succeeds) but references a file NOT in the
  # diff — so no added line is coverable.
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/real.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}}
    },
    "s": {"0":1,"1":0}
  }
}
EOF
  run "$CC_SH" --mode new --diff-base "$base_sha" --threshold 80 --story-id ls2
  # Must not divide-by-zero / crash.
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mode' <<<"$output")" = "new" ]
  # Gate still passes (no coverable code was touched)...
  [ "$(jq -r '.pass' <<<"$output")" = "true" ]
  # ...but the result is explicit, not a silent 100%. RED today (note:null, pct:100).
  [[ "$(jq -r '.note' <<<"$output")" == *"no coverable lines"* ]]
  [ "$(jq -r '.pct == null' <<<"$output")" = "true" ]
}

# ---------------------------------------------------------------------------
# Story LS2: the superseded single-file ADDED_LINES_FILE cleanup trap (installed
# then immediately replaced by the two-file trap) must be removed, leaving
# exactly one such trap. RED today: grep -c returns 2.
# ---------------------------------------------------------------------------
@test "LS2: exactly one ADDED_LINES_FILE cleanup trap remains (dead single-file trap removed)" {
  run grep -c "trap 'rm -f \"\$ADDED_LINES_FILE\"" "$CC_SH"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Detection priority: when istanbul + go both present, istanbul wins.
# ---------------------------------------------------------------------------
@test "detection priority: istanbul wins over go when both files present" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 50
commands:
  coverage: "npm test"
EOF
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/x.ts": {
    "statementMap": {"0":{"start":{"line":1},"end":{"line":1}}},
    "s": {"0": 1}
  }
}
EOF
  cat > coverage.out <<'EOF'
mode: set
github.com/x/y/foo.go:10.2,12.3 2 0
EOF
  run "$CC_SH" --mode whole --threshold 50 --story-id mech-5
  [ "$status" -eq 0 ]
  [ "$(jq -r '.format_detected' <<<"$output")" = "istanbul" ]
}

# ---------------------------------------------------------------------------
# Override coverage_report_path via env wins over autodetect.
# ---------------------------------------------------------------------------
@test "TS_COVERAGE_REPORT_PATH override picks the path explicitly" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "go test ..."
EOF
  # Stage an istanbul file at the default path AND a go file at a custom path.
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{"src/x.ts":{"statementMap":{"0":{"start":{"line":1},"end":{"line":1}}},"s":{"0":1}}}
EOF
  mkdir -p custom
  cat > custom/cov.out <<'EOF'
mode: set
github.com/x/y/foo.go:1.2,2.3 1 1
EOF
  TS_COVERAGE_REPORT_PATH="custom/cov.out" run "$CC_SH" --mode whole --threshold 80 --story-id mech-5
  [ "$status" -eq 0 ]
  [ "$(jq -r '.format_detected' <<<"$output")" = "go" ]
}

# ---------------------------------------------------------------------------
# Env override for skip path: TS_COMMANDS_COVERAGE="true" triggers skip even
# when the file says otherwise.
# ---------------------------------------------------------------------------
@test "env TS_COMMANDS_COVERAGE=\"true\" forces skip path" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  out="$(TS_COMMANDS_COVERAGE="true" "$CC_SH" --mode whole --threshold 80 --story-id mech-9 2>/dev/null)"
  [ "$(jq -r '.mode'        <<<"$out")" = "skipped"  ]
  [ "$(jq -r '.gate_status' <<<"$out")" = "disabled" ]
  [ "$(jq -r '.reason'      <<<"$out")" = 'commands.coverage="true"' ]
}

# ---------------------------------------------------------------------------
# Usage / arg validation.
# ---------------------------------------------------------------------------
@test "missing required --mode flag -> exit 2" {
  run "$CC_SH" --threshold 80
  [ "$status" -eq 2 ]
}

@test "invalid --mode value -> exit 2" {
  run "$CC_SH" --mode bogus --threshold 80
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Story P1-1: a brand-new source file absent from the coverage report must be
# treated as coverable by extension and FAIL closed (0% covered), not vacuously
# pass. Report references a different file so detection succeeds but src/new.ts
# has no per-line data.
# ---------------------------------------------------------------------------
@test "mode new (P1-1): new untested .ts absent from report -> 0% covered, fails gate" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"
  base_sha="$(git rev-parse HEAD)"

  mkdir -p src
  seq 1 10 | sed 's/^/l/' > src/new.ts
  git add -A && git commit -q -m "c1"

  # Coverage report exists (detection succeeds) but references only src/other.ts.
  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/other.ts": {
    "statementMap": {"0": {"start":{"line":1},"end":{"line":1}}},
    "s": {"0":1}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base_sha" --threshold 80 --story-id p1-1 2>/dev/null)"
  [ "$(jq -r '.mode'               <<<"$out")" = "new" ]
  # src/new.ts is coverable by extension, absent from report -> all 10 added
  # lines uncovered -> 0%, gate fails. RED before P1-1 (was pct:null -> pass).
  [ "$(jq -r '.pct == 0'           <<<"$out")" = "true" ]
  [ "$(jq -r '.pass'               <<<"$out")" = "false" ]
  [ "$(jq -r '.uncovered | length' <<<"$out")" = "1" ]
  [ "$(jq -r '.uncovered[0].file'  <<<"$out")" = "src/new.ts" ]
  [ "$(jq -c '.uncovered[0].lines' <<<"$out")" = "[1,2,3,4,5,6,7,8,9,10]" ]
}

# ---------------------------------------------------------------------------
# Story P1-2: a bogus --diff-base must fail closed (exit non-zero), NOT report a
# PASS from an error-caused empty diff.
# ---------------------------------------------------------------------------
@test "mode new (P1-2): bogus --diff-base -> exit non-zero, not PASS" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"

  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/a.ts": {
    "statementMap": {"0": {"start":{"line":1},"end":{"line":1}}},
    "s": {"0":1}
  }
}
EOF
  run "$CC_SH" --mode new --diff-base deadbeefdeadbeefdeadbeefdeadbeefdeadbeef --threshold 80 --story-id p1-2
  [ "$status" -ne 0 ]
  [[ "$output" == *"git diff failed"* ]]
}

# ---------------------------------------------------------------------------
# Story P1-2: a legitimately empty diff (base == HEAD, no changes) must still
# pass as the documented vacuous-pass-on-no-coverable-lines case.
# ---------------------------------------------------------------------------
@test "mode new (P1-2): legitimate empty diff still passes" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"
  head_sha="$(git rev-parse HEAD)"

  mkdir -p coverage
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/a.ts": {
    "statementMap": {"0": {"start":{"line":1},"end":{"line":1}}},
    "s": {"0":1}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$head_sha" --threshold 80 --story-id p1-2 2>/dev/null)"
  [ "$(jq -r '.pass'         <<<"$out")" = "true" ]
  [ "$(jq -r '.pct == null'  <<<"$out")" = "true" ]
}

# ---------------------------------------------------------------------------
# Story P1-3: non-executable added lines (comments/blank/import) must NOT count
# toward the numerator or denominator. A file with 5 executable lines (3 covered,
# 2 missing) plus 5 comment lines absent from the report reports 60% (3/5), not
# the inflated 80% (8/10) the old added-lines denominator produced.
# ---------------------------------------------------------------------------
@test "mode new (P1-3): non-executable added lines excluded -> executable-only pct" {
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "pytest"
EOF
  git init -q .
  git config user.email "t@t" && git config user.name "t"
  echo seed > seed.txt
  git add -A && git commit -q -m "c0"
  base_sha="$(git rev-parse HEAD)"

  mkdir -p src
  seq 1 10 | sed 's/^/l/' > src/a.py
  git add -A && git commit -q -m "c1"

  # coverage.py JSON: executable = executed(1,2,3) + missing(4,5) = 5 lines.
  # Lines 6-10 are non-executable (comments) and appear in NEITHER list.
  cat > coverage.json <<'EOF'
{
  "files": {
    "src/a.py": {
      "executed_lines": [1, 2, 3],
      "missing_lines": [4, 5]
    }
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base_sha" --threshold 80 --story-id p1-3 2>/dev/null)"
  [ "$(jq -r '.format_detected'    <<<"$out")" = "python" ]
  # 3 covered / 5 executable = 60%. Comment lines 6-10 excluded from denominator.
  [ "$(jq -r '.pct == 60'          <<<"$out")" = "true" ]
  [ "$(jq -r '.pass'               <<<"$out")" = "false" ]
  [ "$(jq -r '.uncovered[0].file'  <<<"$out")" = "src/a.py" ]
  [ "$(jq -c '.uncovered[0].lines' <<<"$out")" = "[4,5]" ]
}

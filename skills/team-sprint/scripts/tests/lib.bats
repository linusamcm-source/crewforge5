#!/usr/bin/env bats
# lib.bats — contracts for lib.sh shared helpers.
#   require_all           — tool-presence probe; accumulates every missing hint.
#   LS4 dedup helpers (RED until LS4 GREEN extracts them into lib.sh and
#   repoints the 7 product scripts — see plan-final Story LS4):
#     resolve_diff_base   — story-aware diff base (SCR2; was inline jq in
#                           coverage_check.sh + per_story_diff.sh)
#     read_config_command — single commands: block reader (SCR3; was two python
#                           parsers in detect_commands.sh + coverage_check.sh)
#     repo_root           — main-repo root via git-common-dir (SCR4)
#     mtime_epoch         — BSD/GNU stat mtime fallback (SCR5)
#   The grep cases assert the old inline copies are gone from their call sites.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  LIB_SH="$SCRIPTS/lib.sh"

  TMP="$(mktemp -d)"
  export TMP
  # Stub dir contains shadows for each tool; PATH=STUB only -> all missing.
  STUB="$TMP/stub"
  mkdir -p "$STUB"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Helper: make a stub for a tool that exists on PATH (so require_<x> passes).
_present() {
  local tool="$1"
  cat > "$STUB/$tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB/$tool"
}

@test "require_all passes when every tool present" {
  for t in jq bats shellcheck repomix python3; do _present "$t"; done
  PATH="$STUB" run /bin/bash -c "source '$LIB_SH' && require_all"
  [ "$status" -eq 0 ]
}

@test "require_all single-missing emits single hint" {
  for t in jq bats shellcheck python3; do _present "$t"; done
  PATH="$STUB" run /bin/bash -c "source '$LIB_SH' && require_all"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repomix missing"* ]]
  [[ "$output" != *"jq missing"* ]]
  [[ "$output" != *"bats missing"* ]]
  [[ "$output" != *"shellcheck missing"* ]]
  [[ "$output" != *"python3 missing"* ]]
}

@test "require_all multi-missing emits all hints concatenated" {
  _present python3
  PATH="$STUB" run /bin/bash -c "source '$LIB_SH' && require_all"
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq missing"* ]]
  [[ "$output" == *"bats missing"* ]]
  [[ "$output" == *"shellcheck missing"* ]]
  [[ "$output" == *"repomix missing"* ]]
  [[ "$output" != *"python3 missing"* ]]
}

@test "require_all probes ALL tools (does not exit on first failure)" {
  PATH="$STUB" run /bin/bash -c "source '$LIB_SH' && require_all"
  [ "$status" -ne 0 ]
  for hint in "jq missing" "bats missing" "shellcheck missing" "repomix missing" "python3 missing"; do
    [[ "$output" == *"$hint"* ]]
  done
}

# ---------------------------------------------------------------------------
# LS4 dedup helpers — RED until LS4 GREEN extracts them into lib.sh and
# repoints the product scripts. Each helper is asserted defined-after-source
# and behaviourally correct; the grep cases assert the old inline copies are
# gone from their former call sites.
# ---------------------------------------------------------------------------

# Build a two-story sprint repo: develop(seed) -> sprint/x(s1, s2).
# Sets S1_SHA, S2_SHA, BASE_SHA in the caller's scope. CWD ends at the repo.
_init_sprint_repo() {
  cd "$TMP"
  rm -rf repo
  mkdir repo
  cd repo
  git init -q -b develop .
  git config user.email "test@example.com"
  git config user.name  "test"
  printf 'seed\n' > seed.txt
  git add -A && git commit -q -m seed
  git checkout -q -b sprint/x
  printf '1\n' > a.txt && git add -A && git commit -q -m s1
  S1_SHA="$(git rev-parse HEAD)"
  printf '2\n' > b.txt && git add -A && git commit -q -m s2
  S2_SHA="$(git rev-parse HEAD)"
  BASE_SHA="$(git merge-base sprint/x develop)"
}

# --- SCR2: resolve_diff_base -----------------------------------------------

@test "resolve_diff_base: defined as a function after sourcing lib.sh (SCR2)" {
  run /bin/bash -c "source '$LIB_SH' && declare -F resolve_diff_base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolve_diff_base"* ]]
}

@test "resolve_diff_base: no-prior / first / mid-sprint bases match old inline jq (SCR2)" {
  _init_sprint_repo

  # Contract (mirrors coverage_check.sh:245-272 + per_story_diff.sh:53-71,
  # which produce identical bases on every input):
  #   resolve_diff_base <state_json> <story_id> <sprint_branch> <target_branch>
  #   -> prior story's sha, else merge-base(sprint_branch, target_branch).

  # (1) No prior story: empty story_commits -> merge-base.
  empty='{"target_branch":"develop","story_commits":[]}'
  run /bin/bash -c "source '$LIB_SH' && resolve_diff_base '$empty' 'S9' 'sprint/x' 'develop'"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE_SHA" ]

  # (2) First story: present at index 0 -> still merge-base (no prior entry).
  first="{\"target_branch\":\"develop\",\"story_commits\":[{\"story_id\":\"S1\",\"sha\":\"$S1_SHA\"}]}"
  run /bin/bash -c "source '$LIB_SH' && resolve_diff_base '$first' 'S1' 'sprint/x' 'develop'"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE_SHA" ]

  # (3) Mid-sprint story: query S2 (index 1) -> prior entry S1's sha.
  mid="{\"target_branch\":\"develop\",\"story_commits\":[{\"story_id\":\"S1\",\"sha\":\"$S1_SHA\"},{\"story_id\":\"S2\",\"sha\":\"$S2_SHA\"}]}"
  run /bin/bash -c "source '$LIB_SH' && resolve_diff_base '$mid' 'S2' 'sprint/x' 'develop'"
  [ "$status" -eq 0 ]
  [ "$output" = "$S1_SHA" ]
}

# --- SCR3: read_config_command ---------------------------------------------

@test "read_config_command: defined as a function after sourcing lib.sh (SCR3)" {
  run /bin/bash -c "source '$LIB_SH' && declare -F read_config_command"
  [ "$status" -eq 0 ]
  [[ "$output" == *"read_config_command"* ]]
}

@test "read_config_command: resolves commands.coverage the old parsers agree on (SCR3)" {
  # One fixture config with a commands: block, incl. a leading-whitespace line.
  cfg="$TMP/team-sprint.config.yaml"
  cat > "$cfg" <<'YAML'
# team-sprint config fixture
coverage_threshold: 80
commands:
  # leading-whitespace comment line under commands:
  coverage:   "go test -cover"
  test: "go test ./..."
YAML

  # detect_commands.sh and coverage_check.sh both resolve commands.coverage to
  # this exact value today (verified agreeing — the dedup removes duplicated
  # code that happens to agree, not a divergence); the shared helper must match.
  run /bin/bash -c "source '$LIB_SH' && read_config_command '$cfg' coverage"
  [ "$status" -eq 0 ]
  [ "$output" = "go test -cover" ]
}

@test "P2-5: read_config_commands batches N keys, one line each, matching read_config_command" {
  cfg="$TMP/team-sprint.config.yaml"
  cat > "$cfg" <<'YAML'
coverage_threshold: 80
commands:
  typecheck: "tsc --noEmit"
  test: "go test ./..."
  coverage: "go test -cover"
YAML

  # Four keys in one call: present values resolve, an absent key -> empty line.
  run /bin/bash -c "source '$LIB_SH' && read_config_commands '$cfg' typecheck lint test coverage"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | sed -n '1p')" = "tsc --noEmit" ]
  [ "$(printf '%s' "$output" | sed -n '2p')" = "" ]
  [ "$(printf '%s' "$output" | sed -n '3p')" = "go test ./..." ]
  [ "$(printf '%s' "$output" | sed -n '4p')" = "go test -cover" ]

  # Each batched value matches the single-key reader (no divergence).
  single="$(/bin/bash -c "source '$LIB_SH' && read_config_command '$cfg' coverage")"
  [ "$single" = "go test -cover" ]
}

# --- SCR4: repo_root --------------------------------------------------------

@test "repo_root: defined and returns the main-repo root via git-common-dir (SCR4)" {
  _init_sprint_repo
  expected="$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"
  run /bin/bash -c "source '$LIB_SH' && repo_root"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "repo_root: fails loud outside a git repo instead of resolving to / (RH3)" {
  # `git rev-parse --git-common-dir` prints nothing outside a repo, so
  # `cd "$common/.."` lands on `/` and every caller — art_dir, recon.sh's
  # capability cache, RH3's file-count guard — inherits a root of `/`. A guard
  # that then shells `find /` is the hazard; failing loud is the fix.
  local outside="$TMP/notarepo"
  mkdir -p "$outside"
  run /bin/bash -c "cd '$outside' && source '$LIB_SH' && repo_root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[fail]"* ]]
  [[ "$output" == *"repo_root"* ]]
  [[ "$output" != "/" ]]
}

@test "repo_root: state.sh no longer inlines git-common-dir resolution (SCR4)" {
  # After LS4 GREEN both former copy-paste sites call repo_root; count is 0.
  run /bin/bash -c "grep -c 'git-common-dir' '$SCRIPTS/state.sh'"
  [ "$output" -eq 0 ]
}

# --- SCR5: mtime_epoch ------------------------------------------------------

@test "mtime_epoch: defined and returns an integer epoch for a known file (SCR5)" {
  local f="$TMP/known.txt"
  printf 'x\n' > "$f"
  run /bin/bash -c "source '$LIB_SH' && mtime_epoch '$f'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "mtime_epoch: repomix_refresh.sh no longer inlines stat -f %m (SCR5)" {
  run /bin/bash -c "grep -c 'stat -f %m' '$SCRIPTS/repomix_refresh.sh'"
  [ "$output" -eq 0 ]
}

@test "mtime_epoch: graphify_ensure.sh no longer inlines stat -f %m (SCR5)" {
  run /bin/bash -c "grep -c 'stat -f %m' '$SCRIPTS/graphify_ensure.sh'"
  [ "$output" -eq 0 ]
}

# --- RH4: now_ms — the millisecond clock behind recon.sh's elapsed_ms ---------
# /bin/bash here is 3.2.57 and has no EPOCHREALTIME, and `date +%s%3N` is
# GNU-only — BSD date prints a literal `3N`, which would land in the call log as
# a corrupt elapsed_ms. So now_ms() shells python3, the same convention
# read_config_scalar already uses at lib.sh:195.

@test "now_ms: defined as a function after sourcing lib.sh (RH4)" {
  run /bin/bash -c "source '$LIB_SH' && declare -F now_ms"
  [ "$status" -eq 0 ]
  [[ "$output" == *"now_ms"* ]]
}

@test "now_ms: echoes an integer millisecond epoch (RH4)" {
  run /bin/bash -c "source '$LIB_SH' && now_ms"
  [ "$status" -eq 0 ]
  # An INTEGER: no decimal point, no exponent, no trailing `3N` from a BSD date.
  [[ "$output" =~ ^[0-9]+$ ]]
  # Milliseconds, not seconds: a seconds epoch is ~1.7e9 and fails this floor,
  # so a `date +%s` implementation cannot pass by accident.
  [ "$output" -gt 1000000000000 ]
  # …and it is a real clock, not a constant: within a minute of `date +%s`.
  local secs
  secs="$(date +%s)"
  [ "$(( output / 1000 - secs ))" -lt 60 ]
  [ "$(( secs - output / 1000 ))" -lt 60 ]
}

@test "now_ms: two successive calls separated by a sleep differ (RH4)" {
  run /bin/bash -c "source '$LIB_SH' && a=\"\$(now_ms)\" && sleep 1 && b=\"\$(now_ms)\" && printf '%s %s\n' \"\$a\" \"\$b\""
  [ "$status" -eq 0 ]
  local a b
  a="${output%% *}"
  b="${output##* }"
  [[ "$a" =~ ^[0-9]+$ ]]
  [[ "$b" =~ ^[0-9]+$ ]]
  [ "$b" -gt "$a" ]
  # A 1-second sleep is ~1000ms: enough to prove millisecond RESOLUTION rather
  # than a second-granularity clock multiplied by 1000 — that one would also
  # differ here, so the delta is bounded below only.
  [ "$(( b - a ))" -ge 900 ]
}

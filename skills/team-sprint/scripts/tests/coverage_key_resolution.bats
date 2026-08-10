#!/usr/bin/env bats
# coverage_key_resolution.bats — the diff-path → report-key resolver.
#
# Before resolve_key(), coverage_check.sh matched a diff path to a report key by
# BARE BASENAME, first-match-wins. With src/a/index.ts in the report and a wholly
# untested src/b/index.ts in the diff, the untested file inherited the tested
# file's lines and the gate returned pass:true at 100%. Basename collisions are
# the norm (index.ts, __init__.py, mod.rs, main.go) and — because report keys are
# usually absolute while git diff emits repo-relative paths — the basename branch
# was the PRIMARY matching path, not a fallback. This defeated the fail-closed
# P1-1 invariant outright.
#
# resolve_key: exact -> bidirectional path-suffix -> None when zero OR >1
# candidate survives. Ambiguity falls into the existing fail-closed branch.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CC_SH="$SKILL_DIR/scripts/coverage_check.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"
  export TEAM_SPRINT_CONFIG="$TMP/team-sprint.config.yaml"
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
coverage_threshold: 80
commands:
  coverage: "npm test"
EOF
  git init -q .
  git config user.email "t@t"; git config user.name "t"
}

teardown() { rm -rf "$TMP"; }

# Stage a repo where src/a/index.ts is fully covered and src/b/index.ts is a new,
# wholly untested file that SHARES ITS BASENAME.
stage_collision() {
  mkdir -p src/a src/b coverage
  printf 'x\n' > src/a/index.ts
  git add -A && git commit -q -m c1
  BASE_SHA="$(git rev-parse HEAD)"
  printf 'n1\nn2\nn3\nn4\n' > src/b/index.ts
  git add -A && git commit -q -m c2
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/a/index.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}}
    },
    "s": {"0":1}
  }
}
EOF
}

@test "REGRESSION: an untested file colliding on basename does NOT inherit coverage" {
  stage_collision
  out="$("$CC_SH" --mode new --diff-base "$BASE_SHA" --threshold 80 --story-id c1 2>/dev/null)"
  # src/b/index.ts is absent from the report -> fail closed, every added line uncovered.
  [ "$(jq -r '.pass' <<<"$out")" = "false" ]
  [ "$(jq -r '.pct < 80' <<<"$out")" = "true" ]
}

@test "REGRESSION: the colliding file is reported as uncovered, by its own path" {
  stage_collision
  out="$("$CC_SH" --mode new --diff-base "$BASE_SHA" --threshold 80 --story-id c1 2>/dev/null)"
  [ "$(jq -r '[.uncovered[].file] | index("src/b/index.ts") != null' <<<"$out")" = "true" ]
}

@test "exact path match still resolves" {
  mkdir -p src coverage
  printf 'x\n' > src/only.ts
  git add -A && git commit -q -m c1
  base="$(git rev-parse HEAD)"
  printf 'x\ny\n' > src/only.ts
  git add -A && git commit -q -m c2
  cat > coverage/coverage-final.json <<'EOF'
{
  "src/only.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}}
    },
    "s": {"0":1,"1":1}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base" --threshold 80 --story-id c1 2>/dev/null)"
  [ "$(jq -r '.pass' <<<"$out")" = "true" ]
}

@test "absolute report key still resolves against a repo-relative diff path" {
  mkdir -p src coverage
  printf 'x\n' > src/uniq.ts
  git add -A && git commit -q -m c1
  base="$(git rev-parse HEAD)"
  printf 'x\ny\n' > src/uniq.ts
  git add -A && git commit -q -m c2
  cat > coverage/coverage-final.json <<'EOF'
{
  "/build/workspace/src/uniq.ts": {
    "statementMap": {
      "0": {"start":{"line":1},"end":{"line":1}},
      "1": {"start":{"line":2},"end":{"line":2}}
    },
    "s": {"0":1,"1":1}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base" --threshold 80 --story-id c1 2>/dev/null)"
  # suffix match report_key.endswith("/" + diff_path) keeps Istanbul working
  [ "$(jq -r '.pass' <<<"$out")" = "true" ]
}

@test "an AMBIGUOUS suffix match fails closed rather than guessing" {
  mkdir -p src/x src/y coverage
  printf 'x\n' > src/x/dup.ts
  git add -A && git commit -q -m c1
  base="$(git rev-parse HEAD)"
  printf 'n1\nn2\n' > src/y/dup.ts
  git add -A && git commit -q -m c2
  # TWO report keys both suffix-match a bare "dup.ts"-style lookup.
  cat > coverage/coverage-final.json <<'EOF'
{
  "/p/one/src/y/dup.ts": {
    "statementMap": {"0": {"start":{"line":1},"end":{"line":1}}},
    "s": {"0":1}
  },
  "/p/two/src/y/dup.ts": {
    "statementMap": {"0": {"start":{"line":1},"end":{"line":1}}},
    "s": {"0":1}
  }
}
EOF
  out="$("$CC_SH" --mode new --diff-base "$base" --threshold 80 --story-id c1 2>/dev/null)"
  [ "$(jq -r '.pass' <<<"$out")" = "false" ]
}

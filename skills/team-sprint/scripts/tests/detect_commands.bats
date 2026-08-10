#!/usr/bin/env bats
# detect_commands.bats — fixtures for scripts/detect_commands.sh (Story mech-7).

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  DC_SH="$SCRIPTS/detect_commands.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"
  # Point config probe at TMP so the skill repo's own config never leaks in.
  export TEAM_SPRINT_CONFIG="$TMP/team-sprint.config.yaml"
}

teardown() {
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Pure node repo: package.json with all 4 scripts -> stack:node, confidence:high.
# ---------------------------------------------------------------------------
@test "pure node repo: stack=node, confidence=high, all 4 npm commands" {
  cat > "$TMP/package.json" <<'EOF'
{
  "name": "demo",
  "scripts": {
    "typecheck": "tsc --noEmit",
    "lint":      "eslint .",
    "test":      "jest",
    "coverage":  "jest --coverage"
  }
}
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "node" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "high" ]
  [ "$(jq -r '.typecheck'          <<<"$out")" = "npm run typecheck" ]
  [ "$(jq -r '.lint'               <<<"$out")" = "npm run lint" ]
  [ "$(jq -r '.test'               <<<"$out")" = "npm run test" ]
  [ "$(jq -r '.coverage'           <<<"$out")" = "npm run coverage" ]
  [ "$(jq -r '.ambiguities | length' <<<"$out")" = "0" ]
}

# ---------------------------------------------------------------------------
# Pure go repo: go.mod -> stack:go, confidence:high (defaults for all 4 targets).
# ---------------------------------------------------------------------------
@test "pure go repo: stack=go, confidence=high, default go commands" {
  cat > "$TMP/go.mod" <<'EOF'
module example.com/demo

go 1.22
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "go" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "high" ]
  [ "$(jq -r '.typecheck'          <<<"$out")" = "go build ./..." ]
  [ "$(jq -r '.lint'               <<<"$out")" = "go vet ./..." ]
  [ "$(jq -r '.test'               <<<"$out")" = "go test ./..." ]
  [[ "$(jq -r '.coverage'          <<<"$out")" == "go test -coverprofile="* ]]
  [ "$(jq -r '.ambiguities | length' <<<"$out")" = "0" ]
}

# ---------------------------------------------------------------------------
# Node + justfile: justfile wins for command extraction, but if the justfile
# only defines a subset of targets the confidence drops to "medium".
# ---------------------------------------------------------------------------
@test "node + justfile (partial recipes): justfile wins, confidence=medium" {
  cat > "$TMP/package.json" <<'EOF'
{
  "name": "demo",
  "scripts": {
    "typecheck": "tsc --noEmit",
    "lint":      "eslint ."
  }
}
EOF
  # justfile defines only test and lint. typecheck + coverage unresolved.
  cat > "$TMP/justfile" <<'EOF'
test:
	jest

lint:
	eslint .
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "node" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "medium" ]
  # justfile beats package.json for lint and test.
  [ "$(jq -r '.lint'               <<<"$out")" = "just lint" ]
  [ "$(jq -r '.test'               <<<"$out")" = "just test" ]
  # typecheck falls through to package.json (justfile didn't define it).
  [ "$(jq -r '.typecheck'          <<<"$out")" = "npm run typecheck" ]
  # coverage truly unresolved -> empty + ambiguity.
  [ "$(jq -r '.coverage'           <<<"$out")" = "" ]
  [ "$(jq -r '.ambiguities | length >= 1' <<<"$out")" = "true" ]
}

# ---------------------------------------------------------------------------
# Bash-only repo: shell scripts but no language-marker file and no command
# provider -> stack:bash, confidence:low (none of 4 targets).
# ---------------------------------------------------------------------------
@test "bash-only repo: stack=bash, confidence=low, all targets empty" {
  cat > "$TMP/run.sh" <<'EOF'
#!/usr/bin/env bash
echo hi
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "bash" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "low" ]
  [ "$(jq -r '.typecheck'          <<<"$out")" = "" ]
  [ "$(jq -r '.lint'               <<<"$out")" = "" ]
  [ "$(jq -r '.test'               <<<"$out")" = "" ]
  [ "$(jq -r '.coverage'           <<<"$out")" = "" ]
  [ "$(jq -r '.ambiguities | length' <<<"$out")" -ge 4 ]
}

# ---------------------------------------------------------------------------
# Repo with literally no marker file -> low + ambiguities populated.
# ---------------------------------------------------------------------------
@test "empty repo: stack=bash, confidence=low, ambiguities populated" {
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "bash" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "low" ]
  [ "$(jq -r '.ambiguities | length' <<<"$out")" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Explicit-config precedence: Makefile defines only `test` and `lint`, BUT
# team-sprint.config.yaml supplies commands.typecheck and commands.coverage.
# All four targets resolve -> confidence:high (no ask).
# ---------------------------------------------------------------------------
@test "Makefile partial + config supplies missing targets -> confidence=high" {
  cat > "$TMP/Makefile" <<'EOF'
.PHONY: test lint
test:
	bats tests/

lint:
	shellcheck *.sh
EOF
  cat > "$TEAM_SPRINT_CONFIG" <<'EOF'
plan_path: ignored
commands:
  typecheck: "bash -n *.sh"
  coverage: "true"
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.confidence'         <<<"$out")" = "high" ]
  # Explicit config wins for typecheck + coverage.
  [ "$(jq -r '.typecheck'          <<<"$out")" = "bash -n *.sh" ]
  [ "$(jq -r '.coverage'           <<<"$out")" = "true" ]
  # Makefile supplies test + lint.
  [ "$(jq -r '.test'               <<<"$out")" = "make test" ]
  [ "$(jq -r '.lint'               <<<"$out")" = "make lint" ]
  # No ambiguities; lead does not need to ask.
  [ "$(jq -r '.ambiguities | length' <<<"$out")" = "0" ]
}

# ---------------------------------------------------------------------------
# Mixed-language: package.json + Cargo.toml from different families ->
# stack:mixed, confidence:low (lead must ask which to use).
# ---------------------------------------------------------------------------
@test "package.json + Cargo.toml: stack=mixed, confidence=low, ambiguity logged" {
  cat > "$TMP/package.json" <<'EOF'
{"name":"x","scripts":{"typecheck":"tsc","lint":"e","test":"j","coverage":"jc"}}
EOF
  cat > "$TMP/Cargo.toml" <<'EOF'
[package]
name = "x"
version = "0.1.0"
edition = "2021"
EOF
  out="$("$DC_SH" "$TMP")"
  [ "$(jq -r '.stack'              <<<"$out")" = "mixed" ]
  [ "$(jq -r '.confidence'         <<<"$out")" = "low" ]
  # ambiguities should mention multiple language markers.
  [[ "$(jq -r '.ambiguities | join(" ")' <<<"$out")" == *"multiple language markers"* ]]
}

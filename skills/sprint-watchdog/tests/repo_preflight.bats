#!/usr/bin/env bats
# repo_preflight.bats — fixtures for scripts/repo_preflight.sh.
# Self-contained: uses only core bats ($status/$output), no helper lib, so the
# sprint-watchdog skill carries no cross-skill test dependency.

setup() {
  PF="$(cd "$BATS_TEST_DIRNAME/../scripts" && pwd)/repo_preflight.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  cd "$TMP"
  git init -q -b feature/x .
  git config user.email "t@example.com"
  git config user.name  "t"
  printf 'seed\n' > seed.txt
  git add -A && git commit -q -m "seed"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "clean tree on feature branch -> exit 0, OK" {
  run "$PF" --repo "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREFLIGHT: OK"* ]]
  [[ "$output" == *"branch=feature/x"* ]]
}

@test "dirty tree -> exit 1, BLOCKED, lists files" {
  printf 'change\n' >> seed.txt
  printf 'new\n' > untracked.txt
  run "$PF" --repo "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED: working tree dirty"* ]]
  [[ "$output" == *"untracked.txt"* ]]
}

@test "protected branch (clean) -> exit 2" {
  git checkout -q -b main
  run "$PF" --repo "$TMP"
  [ "$status" -eq 2 ]
  [[ "$output" == *"protected branch 'main'"* ]]
}

@test "dirty takes precedence over protected -> exit 1" {
  git checkout -q -b dev
  printf 'x\n' >> seed.txt
  run "$PF" --repo "$TMP"
  [ "$status" -eq 1 ]
}

@test "SPRINT_WATCHDOG_ALLOW_DIRTY bypasses dirty -> exit 0" {
  printf 'change\n' >> seed.txt
  SPRINT_WATCHDOG_ALLOW_DIRTY=1 run "$PF" --repo "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PREFLIGHT: OK"* ]]
}

@test "SPRINT_WATCHDOG_ALLOW_PROTECTED bypasses protected -> exit 0" {
  git checkout -q -b master
  SPRINT_WATCHDOG_ALLOW_PROTECTED=1 run "$PF" --repo "$TMP"
  [ "$status" -eq 0 ]
}

@test "custom --protected list matches" {
  git checkout -q -b release
  run "$PF" --repo "$TMP" --protected release,hotfix
  [ "$status" -eq 2 ]
}

@test "not a git repo -> exit 3" {
  nonrepo="$(mktemp -d)"
  run "$PF" --repo "$nonrepo"
  rm -rf "$nonrepo"
  [ "$status" -eq 3 ]
}

@test "--json emits parseable object with verdict" {
  run "$PF" --repo "$TMP" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert d["branch"]=="feature/x";assert d["protected"] is False;assert d["exit_code"]==0'
}

@test "bad --log-oneline -> usage exit 64" {
  run "$PF" --repo "$TMP" --log-oneline abc
  [ "$status" -eq 64 ]
}

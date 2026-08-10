#!/usr/bin/env bats
# retention_gate.bats — contract for the CLAUDE.md slim gate.
#
# The gate's whole value is asymmetric: a false PASS silently destroys a rule
# somebody wrote for a reason, while a false FAIL costs one reread. So the
# must-catch cases below matter more than the must-not-fire ones, and both are
# tested — a gate that fires on every reflow is a gate people learn to bypass.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  GATE="$ROOT/scripts/retention_gate.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  ORIG="$TMP/original.md"
  PROP="$TMP/proposed.md"

  cat > "$ORIG" <<'EOF'
# House rules

## Shell

- Never run `find` from `/` or `~`. Scope it to the project tree.
- Stage explicit paths: `git add <file>`, never `git add -A`.
- Always run `bash scripts/tests/run-all.sh` before you push.

## Tooling

We pin `bats-core >=1.10` and `shellcheck >=0.9`. The suite lives at
`skills/team-sprint/scripts/tests/`.

When the resolver fails it prints "no such subagent type registered" — that
means the manifest points at an agent that is not on disk.

## Style

Prefer clear names over clever ones. Comments explain why, not what.
EOF
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

@test "an honest slim that only drops prose passes" {
  # "Style" is genuinely re-derivable advice — exactly what a trim should take.
  sed '/^## Style/,$d' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "dropping a never line FAILS the gate" {
  grep -v 'Never run' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"directive lost"* ]]
}

@test "dropping an always line FAILS the gate" {
  grep -v 'Always run' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"directive lost"* ]]
}

@test "dropping an exact command FAILS the gate" {
  sed 's|`bash scripts/tests/run-all.sh`|the test suite|' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exact text lost"* ]]
}

@test "dropping a pinned version FAILS the gate" {
  sed 's|`bats-core >=1.10`|bats|' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exact text lost"* ]]
}

@test "dropping a path FAILS the gate" {
  sed 's|`skills/team-sprint/scripts/tests/`|the tests directory|' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exact text lost"* ]]
}

@test "dropping a quoted error string FAILS the gate" {
  sed 's|"no such subagent type registered"|an error|' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"quoted string lost"* ]]
}

@test "reordering and reformatting is NOT a loss" {
  # The gate asserts survival somewhere, not position — otherwise it blocks
  # every legitimate reorganisation and gets bypassed.
  # Whole sections moved, nothing dropped. Extracting by grep is what an earlier
  # draft of this fixture did, and it silently lost a paragraph's second line —
  # the gate caught it, correctly, which is the behaviour under test here.
  {
    printf '# House rules\n\n'
    sed -n '/^## Tooling/,/^## Style/p' "$ORIG" | sed '/^## Style/d'
    sed -n '/^## Shell/,/^## Tooling/p' "$ORIG" | sed '/^## Tooling/d'
  } > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "case changes on a directive do not trip it" {
  sed 's|Never run|never run|' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 0 ]
}

@test "an identical file passes and reports zero savings" {
  cp "$ORIG" "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
}

@test "it reports how much was saved, so the trade is visible" {
  sed '/^## Style/,$d' "$ORIG" > "$PROP"
  run bash "$GATE" "$ORIG" "$PROP"
  [[ "$output" == *"bytes"* ]]
  [[ "$output" == *"smaller"* ]]
}

@test "a missing file is a usage error, not a pass" {
  run bash "$GATE" "$ORIG" "$TMP/does-not-exist.md"
  [ "$status" -eq 2 ]
}

@test "it cannot modify either file — propose-only by construction" {
  local before_o before_p
  sed '/^## Style/,$d' "$ORIG" > "$PROP"
  before_o="$(shasum "$ORIG" | cut -d' ' -f1)"
  before_p="$(shasum "$PROP" | cut -d' ' -f1)"
  bash "$GATE" "$ORIG" "$PROP" >/dev/null 2>&1 || true
  [ "$before_o" = "$(shasum "$ORIG" | cut -d' ' -f1)" ]
  [ "$before_p" = "$(shasum "$PROP" | cut -d' ' -f1)" ]
}

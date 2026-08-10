#!/usr/bin/env bats
# self-improve.bats — the gate's value is that growth FAILS, so the negative
# cases are the ones that matter. Each test builds a throwaway config root.

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CEILING="$SCRIPTS/ceiling.sh"
  LEDGER="$SCRIPTS/ledger.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export CLAUDE_CONFIG_DIR="$TMP"
  mkdir -p "$TMP/skills/demo" "$TMP/agents"
  cat > "$TMP/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: A demo skill. Use on "run the demo"
---
Body text here.
EOF
  cat > "$TMP/agents/demo-agent.md" <<'EOF'
---
name: demo-agent
description: A demo agent
---
Agent body.
EOF
  # ceilings.json lives next to the script, so isolate it per test
  CEILDATA="$SCRIPTS/../data/ceilings.json"
  BACKUP="$TMP/ceilings.backup.json"
  [ -f "$CEILDATA" ] && cp "$CEILDATA" "$BACKUP"
  echo '{}' > "$CEILDATA"
}

teardown() {
  [ -f "$BACKUP" ] && cp "$BACKUP" "$SCRIPTS/../data/ceilings.json"
  rm -rf "$TMP"
}

@test "check fails for a target with no recorded budget" {
  run bash "$CEILING" check demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"no recorded budget"* ]]
}

@test "check passes immediately after record" {
  bash "$CEILING" record demo
  run bash "$CEILING" check demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "a longer description FAILS the gate" {
  bash "$CEILING" record demo
  sed -i.bak 's/^description: .*/description: A demo skill with a great deal more explanatory prose bolted on than the budget ever allowed for. Use on "run the demo"/' "$CLAUDE_CONFIG_DIR/skills/demo/SKILL.md"
  run bash "$CEILING" check demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"description"* ]]
}

@test "a much longer body FAILS the gate" {
  bash "$CEILING" record demo
  python3 -c "
import sys
p='$CLAUDE_CONFIG_DIR/skills/demo/SKILL.md'
open(p,'a').write('padding '*500)
"
  run bash "$CEILING" check demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"body"* ]]
}

@test "body growth within slack PASSES so a real learning can land" {
  bash "$CEILING" record demo
  printf 'a few more words\n' >> "$CLAUDE_CONFIG_DIR/skills/demo/SKILL.md"
  run bash "$CEILING" check demo
  [ "$status" -eq 0 ]
}

@test "losing a trigger phrase FAILS even when the file shrinks" {
  bash "$CEILING" record demo
  cat > "$CLAUDE_CONFIG_DIR/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: A demo skill
---
Short.
EOF
  run bash "$CEILING" check demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"trigger phrase lost"* ]]
}

@test "record moves the budget deliberately" {
  bash "$CEILING" record demo
  printf '%s\n' "$(python3 -c "print('padding '*500)")" >> "$CLAUDE_CONFIG_DIR/skills/demo/SKILL.md"
  run bash "$CEILING" check demo
  [ "$status" -eq 1 ]
  bash "$CEILING" record demo
  run bash "$CEILING" check demo
  [ "$status" -eq 0 ]
}

@test "agents are covered as well as skills" {
  bash "$CEILING" record demo-agent
  run bash "$CEILING" check demo-agent
  [ "$status" -eq 0 ]
}

@test "ledger add then count then clear" {
  run bash "$LEDGER" count demo
  [ "$output" = "0" ]
  bash "$LEDGER" add demo hook "script exited 1"
  bash "$LEDGER" add demo user "prefer the scripted path"
  run bash "$LEDGER" count demo
  [ "$output" = "2" ]
  run bash "$LEDGER" list demo
  [[ "$output" == *"prefer the scripted path"* ]]
  bash "$LEDGER" clear demo
  run bash "$LEDGER" count demo
  [ "$output" = "0" ]
}

@test "clear archives rather than deletes" {
  bash "$LEDGER" add demo hook "something broke"
  bash "$LEDGER" clear demo
  run bash -c "cat '$CLAUDE_CONFIG_DIR'/ledger/archive/*.jsonl"
  [[ "$output" == *"something broke"* ]]
}

@test "ledger entries are valid json with the expected fields" {
  bash "$LEDGER" add demo hook "a note"
  run bash -c "bash '$LEDGER' list demo | python3 -c 'import json,sys; d=json.loads(sys.stdin.readline()); print(d[\"target\"], d[\"source\"], d[\"note\"])'"
  [ "$status" -eq 0 ]
  [ "$output" = "demo hook a note" ]
}

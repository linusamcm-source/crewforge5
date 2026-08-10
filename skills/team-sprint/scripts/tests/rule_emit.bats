#!/usr/bin/env bats
# rule_emit.bats — contract for the stack-scoped rule file crew-factory writes
# beside the crew manifest.
#
# Two things are load-bearing and asserted here. The `paths:` frontmatter, which
# is the whole reason a rule this long is affordable — without it the body loads
# in every session, matching file or not. And the non-gating relationship with
# `crew_check.sh`: a crew that predates rule files must stay CACHED, because the
# alternative is regenerating every existing crew at ~470s apiece to produce a
# document that can be written in place.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  EMIT="$SCRIPTS/rule_emit.sh"
  CHECK="$SCRIPTS/crew_check.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  REPO="$TMP/repo"
  mkdir -p "$REPO"
}

teardown() {
  cd / || return 0
  rm -rf "$TMP"
}

# A minimal manifest that passes crews.schema.json, with an agent on disk so the
# resolution check is satisfied and the verdict is genuinely CACHED.
_seed_crew() {
  mkdir -p "$REPO/.claude/crews" "$REPO/.claude/agents"
  cat > "$REPO/.claude/agents/go-developer.md" <<'EOF'
---
name: go-developer
description: Writes Go.
tools: Read, Write, Edit, Bash
---

## Stack Knowledge

go1.22, gotestsum, golangci-lint.
EOF
  cat > "$REPO/.claude/crews/go.json" <<'EOF'
{
  "language": "go",
  "stack_profile": ".claude/crews/go-profile.md",
  "commands": {},
  "crew": { "developer": "go-developer" },
  "validation": {},
  "skills": {},
  "generated": ["go-developer"],
  "reused": []
}
EOF
  printf '# go profile\n\nVerified 2099-01-01\n' > "$REPO/.claude/crews/go-profile.md"
}

@test "the emitted rule carries paths: frontmatter scoped to the stack" {
  run bash "$EMIT" go --project-dir "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=WROTE"* ]]
  [ -f "$REPO/.claude/rules/go.md" ]
  grep -q '^paths: \["\*\*/\*\.go","\*\*/go\.mod"\]$' "$REPO/.claude/rules/go.md"
}

@test "each stack gets its own globs, never a shared catch-all" {
  bash "$EMIT" bash --project-dir "$REPO"
  grep -q '\*\*/\*\.bats' "$REPO/.claude/rules/bash.md"
  grep -qv '\*\*/\*\.go' "$REPO/.claude/rules/bash.md"
}

@test "an unmapped language fails loudly rather than writing an unscoped rule" {
  run bash "$EMIT" cobol --project-dir "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REASON=no-glob-mapping:cobol"* ]]
  [ ! -f "$REPO/.claude/rules/cobol.md" ]
}

@test "an existing rule is never silently overwritten" {
  bash "$EMIT" go --project-dir "$REPO"
  printf 'hand-edited\n' >> "$REPO/.claude/rules/go.md"
  run bash "$EMIT" go --project-dir "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=EXISTS"* ]]
  grep -q 'hand-edited' "$REPO/.claude/rules/go.md"
}

@test "a crew with no rule file still reports CACHED, with the gap as a signal" {
  _seed_crew
  run bash "$CHECK" check go --project-dir "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS=CACHED"* ]]
  [[ "$output" == *"RULE_FILE=missing"* ]]
  [[ "$output" != *"REBUILD"* ]]
}

@test "emitting the rule does not touch a single agent file" {
  _seed_crew
  local before after
  before="$(cd "$REPO" && find .claude/agents -type f -exec shasum {} \; | sort)"
  bash "$EMIT" go --project-dir "$REPO"
  after="$(cd "$REPO" && find .claude/agents -type f -exec shasum {} \; | sort)"
  [ "$before" = "$after" ]
  run bash "$CHECK" check go --project-dir "$REPO"
  [[ "$output" == *"STATUS=CACHED"* ]]
  [[ "$output" == *"RULE_FILE=present"* ]]
}

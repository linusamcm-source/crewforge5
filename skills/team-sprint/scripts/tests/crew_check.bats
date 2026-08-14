#!/usr/bin/env bats
# crew_check.bats — mechanised crew-manifest gates (crew-factory Phase 0 /
# team-sprint phase-0 step 10a.2): cached-vs-rebuild verdict, pure-jq schema
# validation, verified-command re-runs, and generated-name collision checks.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  AGENTS="$TMP/agents"
  REGISTRY="$TMP/registry"
  mkdir -p "$TMP/.claude/crews" "$AGENTS" "$REGISTRY"
}

teardown() { rm -rf "$TMP"; }

C() { CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" "$@" --project-dir "$TMP" --agents-dir "$AGENTS"; }

# Minimal file satisfying the generation contract agent_structure_issue checks.
# Optional $2 overrides the target dir (default $AGENTS).
write_agent() {
  cat > "${2:-$AGENTS}/$1.md" <<EOF
---
name: $1
description: "test agent"
tools: Read
---

## Stack Knowledge (inherited)
verified facts
EOF
}

write_manifest() {
  cat > "$TMP/.claude/crews/bash.json" <<'JSON'
{
  "language": "bash",
  "stack_profile": ".claude/crews/bash.profile.md",
  "commands": { "test": "true", "lint": "" },
  "crew": { "developer": "bash-developer", "tester": "bash-tester" },
  "validation": { "bash-developer": "A" },
  "generated": ["bash-developer"],
  "reused": ["bash-tester"]
}
JSON
}

# --- check ------------------------------------------------------------------

@test "check: no manifest -> REBUILD manifest_missing" {
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=REBUILD'
  printf '%s' "$out" | grep -q 'REASON=manifest_missing'
}

@test "check: valid manifest, all agents on disk -> CACHED" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "check: missing agent file -> REBUILD unresolved names it" {
  write_manifest
  touch "$AGENTS/bash-developer.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=REBUILD'
  printf '%s' "$out" | grep -q 'REASON=unresolved:bash-tester'
}

@test "check: schema violation -> REBUILD with schema reason" {
  echo '{"language":"bash"}' > "$TMP/.claude/crews/bash.json"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=REBUILD'
  printf '%s' "$out" | grep -q 'REASON=schema:'
}

@test "check: empty-string crew value fails schema" {
  write_manifest
  jq '.crew.tester = ""' "$TMP/.claude/crews/bash.json" > "$TMP/m.json" \
    && mv "$TMP/m.json" "$TMP/.claude/crews/bash.json"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'REASON=schema:'
}

@test "check: missing profile -> STALE=unknown, still CACHED" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
  printf '%s' "$out" | grep -q 'STALE=unknown'
}

@test "check: old 'Verified' stamp in profile -> STALE=true" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  printf '# profile\nVerified 2020-01-01 by crew-factory\n' > "$TMP/.claude/crews/bash.profile.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STALE=true'
}

@test "check: stamp 6 days old crosses the 5-day default -> STALE=true" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  stamp="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=6))')"
  printf '# profile\nVerified %s by crew-factory\n' "$stamp" > "$TMP/.claude/crews/bash.profile.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STALE=true'
}

@test "check: stamp from today -> STALE=false" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  stamp="$(python3 -c 'import datetime; print(datetime.date.today())')"
  printf '# profile\nVerified %s by crew-factory\n' "$stamp" > "$TMP/.claude/crews/bash.profile.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STALE=false'
}

@test "check: empty generated agent file -> REBUILD malformed" {
  write_manifest
  touch "$AGENTS/bash-developer.md" "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=REBUILD'
  printf '%s' "$out" | grep -q 'REASON=malformed:bash-developer:no_frontmatter'
}

@test "check: generated agent missing Stack Knowledge seed -> malformed" {
  write_manifest
  cat > "$AGENTS/bash-developer.md" <<'EOF'
---
name: bash-developer
description: "x"
tools: Read
---

## Role
EOF
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'malformed:bash-developer:no_stack_knowledge'
}

@test "check: reused agent resolves from the registry dir -> CACHED" {
  write_manifest
  write_agent bash-developer
  touch "$REGISTRY/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "check: default agents dir is <project-dir>/.claude/agents" {
  write_manifest
  mkdir -p "$TMP/.claude/agents"
  AGENTS_SAVE="$AGENTS"; AGENTS="$TMP/.claude/agents"
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  AGENTS="$AGENTS_SAVE"
  out="$(CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" check bash --project-dir "$TMP")"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "check: WORKTREE_AGENTS=not_git when project is not a git repo" {
  write_manifest
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'WORKTREE_AGENTS=not_git'
}

@test "check: WORKTREE_AGENTS=ok for a global agents dir outside the project" {
  write_manifest
  GLOBAL="$(mktemp -d)"
  write_agent bash-developer "$GLOBAL"
  touch "$GLOBAL/bash-tester.md"
  out="$(CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" check bash --project-dir "$TMP" --agents-dir "$GLOBAL")"
  rm -rf "$GLOBAL"
  printf '%s' "$out" | grep -q 'WORKTREE_AGENTS=ok'
}

@test "check: untracked generated agent in a git repo -> WORKTREE_AGENTS=untracked" {
  git init -q "$TMP"
  write_manifest
  mkdir -p "$TMP/.claude/agents"
  write_agent bash-developer "$TMP/.claude/agents"
  touch "$TMP/.claude/agents/bash-tester.md"
  out="$(CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" check bash --project-dir "$TMP")"
  printf '%s' "$out" | grep -q 'WORKTREE_AGENTS=untracked:bash-developer'
}

@test "check: tracked generated agent -> WORKTREE_AGENTS=ok" {
  git init -q "$TMP"
  write_manifest
  mkdir -p "$TMP/.claude/agents"
  write_agent bash-developer "$TMP/.claude/agents"
  touch "$TMP/.claude/agents/bash-tester.md"
  git -C "$TMP" add .claude/agents/bash-developer.md
  out="$(CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" check bash --project-dir "$TMP")"
  printf '%s' "$out" | grep -q 'WORKTREE_AGENTS=ok'
}

@test "check: gitignored agents dir -> WORKTREE_AGENTS=ignored" {
  git init -q "$TMP"
  echo '.claude/agents' > "$TMP/.gitignore"
  write_manifest
  mkdir -p "$TMP/.claude/agents"
  write_agent bash-developer "$TMP/.claude/agents"
  touch "$TMP/.claude/agents/bash-tester.md"
  out="$(CREW_REGISTRY_DIR="$REGISTRY" bash "$SCRIPTS/crew_check.sh" check bash --project-dir "$TMP")"
  printf '%s' "$out" | grep -q 'WORKTREE_AGENTS=ignored'
}

@test "check: reused agent is never structure-checked (empty file, still CACHED)" {
  write_manifest
  write_agent bash-developer
  : > "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "check: skills-assigned generated role without ## Skills -> malformed" {
  write_manifest
  jq '.skills = {"developer": ["ac-validate"]}' "$TMP/.claude/crews/bash.json" > "$TMP/m.json" \
    && mv "$TMP/m.json" "$TMP/.claude/crews/bash.json"
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'malformed:bash-developer:no_skills_section'
}

@test "check: skills-assigned role with ## Skills section -> CACHED" {
  write_manifest
  jq '.skills = {"developer": ["ac-validate"]}' "$TMP/.claude/crews/bash.json" > "$TMP/m.json" \
    && mv "$TMP/m.json" "$TMP/.claude/crews/bash.json"
  write_agent bash-developer
  printf '\n## Skills\n- ac-validate: validate acceptance criteria\n' >> "$AGENTS/bash-developer.md"
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "check: skills on a reused role are not enforced" {
  write_manifest
  jq '.skills = {"tester": ["ac-validate"]}' "$TMP/.claude/crews/bash.json" > "$TMP/m.json" \
    && mv "$TMP/m.json" "$TMP/.claude/crews/bash.json"
  write_agent bash-developer
  touch "$AGENTS/bash-tester.md"
  out="$(C check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

# --- verify -----------------------------------------------------------------

@test "verify: passing command -> CMD PASS, STATUS=OK; empty command skipped" {
  write_manifest
  out="$(C verify bash)"
  printf '%s' "$out" | grep -q 'CMD test PASS'
  ! printf '%s' "$out" | grep -q 'CMD lint'
  printf '%s' "$out" | grep -q 'STATUS=OK'
}

@test "verify: failing command -> CMD FAIL, STATUS=FAIL" {
  write_manifest
  jq '.commands.test = "false"' "$TMP/.claude/crews/bash.json" > "$TMP/m.json" \
    && mv "$TMP/m.json" "$TMP/.claude/crews/bash.json"
  out="$(C verify bash)"
  printf '%s' "$out" | grep -q 'CMD test FAIL'
  printf '%s' "$out" | grep -q 'STATUS=FAIL'
}

# --- collision --------------------------------------------------------------

@test "collision: clean names -> STATUS=OK" {
  write_manifest
  out="$(C collision bash architect tester)"
  printf '%s' "$out" | grep -q 'STATUS=OK'
}

@test "collision: unrelated existing file -> COLLISION named" {
  write_manifest
  touch "$AGENTS/bash-architect.md"
  out="$(C collision bash architect)"
  printf '%s' "$out" | grep -q 'COLLISION bash-architect'
  printf '%s' "$out" | grep -q 'STATUS=COLLISION'
}

@test "collision: our own prior generated agent is NOT a collision" {
  write_manifest
  touch "$AGENTS/bash-developer.md"
  out="$(C collision bash developer)"
  printf '%s' "$out" | grep -q 'STATUS=OK'
}

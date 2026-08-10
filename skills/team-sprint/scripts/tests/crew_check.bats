#!/usr/bin/env bats
# crew_check.bats — mechanised crew-manifest gates (crew-factory Phase 0 /
# team-sprint phase-0 step 10a.2): cached-vs-rebuild verdict, pure-jq schema
# validation, verified-command re-runs, and generated-name collision checks.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  AGENTS="$TMP/agents"
  mkdir -p "$TMP/.claude/crews" "$AGENTS"
}

teardown() { rm -rf "$TMP"; }

C() { bash "$SCRIPTS/crew_check.sh" "$@" --project-dir "$TMP" --agents-dir "$AGENTS"; }

# Minimal file satisfying the generation contract agent_structure_issue checks.
write_agent() {
  cat > "$AGENTS/$1.md" <<EOF
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

# --- project-local agents, user-catalogue fallback ---------------------------
#
# Generated agents belong to the project; only reused ones may come from the
# user catalogue. These exercise the DEFAULT agents dir, which every test above
# bypasses by passing --agents-dir.

# Like C(), but without --agents-dir, and with an isolated user catalogue.
D() {
  CLAUDE_CONFIG_DIR="$TMP/userconfig" \
    bash "$SCRIPTS/crew_check.sh" "$@" --project-dir "$TMP"
}

write_agent_at() { # <dir> <name>
  mkdir -p "$1"
  cat > "$1/$2.md" <<AGENT
---
name: $2
description: "test agent"
tools: Read
---

## Stack Knowledge (inherited)
verified facts
AGENT
}

write_user_agent()    { write_agent_at "$TMP/userconfig/agents" "$1"; }
write_project_agent() { write_agent_at "$TMP/.claude/agents" "$1"; }

@test "default agents dir is the project, not the user catalogue" {
  write_manifest
  write_project_agent bash-developer
  write_project_agent bash-tester
  out="$(D check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "an agent only in the user catalogue does not silently satisfy a project crew" {
  write_manifest
  write_user_agent bash-developer
  out="$(D check bash)"
  printf '%s' "$out" | grep -q 'STATUS=REBUILD'
  printf '%s' "$out" | grep -q 'unresolved:bash-tester'
}

@test "a reused role resolves from the user catalogue" {
  write_manifest
  write_project_agent bash-developer
  write_user_agent bash-tester
  out="$(D check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "project agent wins over a user agent of the same name" {
  write_manifest
  write_project_agent bash-developer
  write_project_agent bash-tester
  mkdir -p "$TMP/userconfig/agents"
  printf 'no frontmatter at all\n' > "$TMP/userconfig/agents/bash-developer.md"
  out="$(D check bash)"
  printf '%s' "$out" | grep -q 'STATUS=CACHED'
}

@test "collision: a name taken in the user catalogue is still a collision" {
  write_user_agent bash-architect
  out="$(D collision bash architect)"
  printf '%s' "$out" | grep -q 'COLLISION bash-architect'
  printf '%s' "$out" | grep -q 'STATUS=COLLISION'
}

@test "collision: clean when the name is taken nowhere" {
  out="$(D collision bash architect)"
  printf '%s' "$out" | grep -q 'STATUS=OK'
}

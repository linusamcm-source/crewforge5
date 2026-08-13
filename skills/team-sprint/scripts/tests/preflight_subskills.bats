#!/usr/bin/env bats
# preflight_subskills.bats — fixtures for scripts/preflight_subskills.sh

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPTS="$SKILL_DIR/scripts"
  PRE_SH="$SCRIPTS/preflight_subskills.sh"
  STATE_SH="$SCRIPTS/state.sh"

  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  export TMP
  cd "$TMP"

  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name  "test"
  git commit -q --allow-empty -m "init"

  PLAN="docs/plans/sprint-mech-15.md"
  mkdir -p docs/plans
  printf '# plan\n' > "$PLAN"
  ART="$TMP/.team-sprint/sprints/sprint-sprint-mech-15"
  STATE="$ART/state.json"

  # Fake HOME so filesystem probes hit a sandbox we control.
  FAKE_HOME="$TMP/home"
  mkdir -p "$FAKE_HOME/.claude/skills"
  export HOME="$FAKE_HOME"

  # Probe-fn fixtures: PASS / FAIL canned scripts.
  PROBE_PASS="$TMP/probe-pass.sh"
  PROBE_FAIL="$TMP/probe-fail.sh"
  cat > "$PROBE_PASS" <<'EOF'
#!/usr/bin/env bash
# Canned probe: always present.
exit 0
EOF
  cat > "$PROBE_FAIL" <<'EOF'
#!/usr/bin/env bash
# Canned probe: always absent.
exit 1
EOF
  chmod +x "$PROBE_PASS" "$PROBE_FAIL"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

_init_state() {
  "$STATE_SH" init "$PLAN" develop sprint-mech-15 >/dev/null
}

_set_hooks() {
  local json="$1"
  "$STATE_SH" update "$PLAN" subskill_hooks="$json"
}

_make_skill_dir() {
  local name="$1"
  mkdir -p "$FAKE_HOME/.claude/skills/$name"
  printf '# skill\n' > "$FAKE_HOME/.claude/skills/$name/SKILL.md"
}

# --- --probe-only via filesystem ------------------------------------------

@test "--probe-only: present skill via filesystem -> exit 0" {
  _make_skill_dir "real-skill"
  run "$PRE_SH" --probe-only real-skill
  [ "$status" -eq 0 ]
}

@test "--probe-only: missing skill via filesystem -> exit 1" {
  run "$PRE_SH" --probe-only nonexistent-skill
  [ "$status" -eq 1 ]
}

@test "--probe-only: a plugin-root-only skill probes present" {
  # `token-slim` ships inside this plugin and is absent from the sandboxed
  # $HOME. The old probe looked only under $HOME/.claude/skills, so it declared
  # every plugin-installed sub-skill missing — the exact preflight that Phase 0
  # runs against skills the plugin itself supplies.
  [ ! -f "$FAKE_HOME/.claude/skills/token-slim/SKILL.md" ]
  run "$PRE_SH" --probe-only token-slim
  [ "$status" -eq 0 ]
}

# --- --probe-fn injection point -------------------------------------------

@test "--probe-fn passing stub overrides filesystem (exit 0)" {
  # Skill is absent on disk, but the stub says present.
  run "$PRE_SH" --probe-only ghost-skill --probe-fn "$PROBE_PASS"
  [ "$status" -eq 0 ]
}

@test "--probe-fn failing stub overrides filesystem (exit 1)" {
  # Skill IS on disk, but the stub says absent.
  _make_skill_dir "exists-skill"
  run "$PRE_SH" --probe-only exists-skill --probe-fn "$PROBE_FAIL"
  [ "$status" -eq 1 ]
}

# --- cache enrichment -----------------------------------------------------

@test "cache: present-skill via cache (no fs probe needed)" {
  _init_state
  cache="$ART/preflight-cache.json"
  cat > "$cache" <<EOF
{ "cached-skill": { "present": true, "probed_at": "2026-05-20T12:00:00Z", "source": "agent-tool" } }
EOF
  # Note: skill is NOT on disk; cache should win.
  run "$PRE_SH" --probe-only cached-skill --cache "$cache"
  [ "$status" -eq 0 ]
}

@test "cache: absent-skill via cache (cache wins over filesystem)" {
  _init_state
  _make_skill_dir "cached-skill"  # exists on disk
  cache="$ART/preflight-cache.json"
  cat > "$cache" <<EOF
{ "cached-skill": { "present": false, "probed_at": "2026-05-20T12:00:00Z", "source": "agent-tool" } }
EOF
  # Cache says absent → exit 1, even though disk says present.
  run "$PRE_SH" --probe-only cached-skill --cache "$cache"
  [ "$status" -eq 1 ]
}

@test "cache: missing key falls back to filesystem" {
  _init_state
  _make_skill_dir "fs-skill"
  cache="$ART/preflight-cache.json"
  cat > "$cache" <<EOF
{ "other-skill": { "present": true, "probed_at": "2026-05-20T12:00:00Z", "source": "agent-tool" } }
EOF
  # `fs-skill` not in cache → check filesystem (present).
  run "$PRE_SH" --probe-only fs-skill --cache "$cache"
  [ "$status" -eq 0 ]
}

# --- --probe-all honours `required` ---------------------------------------

@test "--probe-all: required:true missing -> exit 1" {
  _init_state
  _set_hooks '[{"skill":"missing-req","command":"true","required":true,"phase":"phase-6","source":"user"}]'
  run "$PRE_SH" --probe-all "$PLAN" --probe-fn "$PROBE_FAIL"
  [ "$status" -eq 1 ]
  # Expect the WARN line mentioning the missing skill.
  [[ "$output" == *"missing-req"* ]]
}

@test "--probe-all: required:false missing -> exit 0 + WARN" {
  _init_state
  _set_hooks '[{"skill":"missing-opt","command":"true","required":false,"phase":"phase-6","source":"user"}]'
  run "$PRE_SH" --probe-all "$PLAN" --probe-fn "$PROBE_FAIL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing-opt"* ]]
  [[ "$output" == *"optional"* ]]
}

@test "--probe-all: all present -> exit 0 silent (no WARN)" {
  _init_state
  _set_hooks '[
    {"skill":"a","command":"true","required":true,"phase":"phase-6","source":"user"},
    {"skill":"b","command":"true","required":false,"phase":"phase-7","source":"user"}
  ]'
  run "$PRE_SH" --probe-all "$PLAN" --probe-fn "$PROBE_PASS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"FAILED"* ]]
}

@test "--probe-all: empty hook list -> exit 0 (no probes)" {
  _init_state
  _set_hooks '[]'
  run "$PRE_SH" --probe-all "$PLAN"
  [ "$status" -eq 0 ]
}

@test "--probe-all: mixed required + optional, one of each failing" {
  _init_state
  # Custom probe-fn: present when name starts with "ok-", absent otherwise.
  PROBE_MIXED="$TMP/probe-mixed.sh"
  cat > "$PROBE_MIXED" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ok-*) exit 0 ;;
  *)    exit 1 ;;
esac
EOF
  chmod +x "$PROBE_MIXED"
  _set_hooks '[
    {"skill":"ok-present","command":"true","required":true,"phase":"phase-6","source":"user"},
    {"skill":"missing-opt","command":"true","required":false,"phase":"phase-6","source":"user"},
    {"skill":"missing-req","command":"true","required":true,"phase":"phase-7","source":"user"}
  ]'
  run "$PRE_SH" --probe-all "$PLAN" --probe-fn "$PROBE_MIXED"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing-req"* ]]
}

# --- usage errors ---

@test "no args -> exit 2 usage" {
  run "$PRE_SH"
  [ "$status" -eq 2 ]
}

@test "--probe-only with no argument -> exit 2" {
  run "$PRE_SH" --probe-only
  [ "$status" -eq 2 ]
}

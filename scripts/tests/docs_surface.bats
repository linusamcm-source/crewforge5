#!/usr/bin/env bats
# docs_surface.bats — contract for the documented surface of the bundle.
#
# The numbers in README.md and CHANGELOG.md are claims about what a session
# actually carries, so they are checked against `budget_check.sh` rather than
# against a literal copied out of a plan document: a doc figure that is only
# ever compared to itself drifts the moment a description changes.
#
# `/init`, `/plan` and `/execute` are all live built-ins or ambiguous in Claude
# Code — the bare form of `/crewforge:init` reaches the built-in CLAUDE.md
# initializer, which is a different tool doing a different job. Every trigger
# phrase in the docs is asserted namespaced for that reason.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  README="$ROOT/README.md"
  CHANGELOG="$ROOT/CHANGELOG.md"
  PLUGIN="$ROOT/.claude-plugin/plugin.json"
  MARKET="$ROOT/.claude-plugin/marketplace.json"
}

# The gate is the source of truth for every measured figure below.
measured() {
  bash "$ROOT/scripts/budget_check.sh" | sed -n 's/^always-loaded: .*/&/p'
}
measured_tokens()  { measured | sed -n 's/.*(~\([0-9]*\) tok).*/\1/p'; }
measured_entries() { measured | sed -n 's/.*across \([0-9]*\) descriptions.*/\1/p'; }
measured_hidden()  { measured | sed -n 's/.*; \([0-9]*\) skills hidden.*/\1/p'; }

hidden_skills() {
  local d
  for d in "$ROOT"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    if grep -qi '^disable-model-invocation: *true' "$d/SKILL.md"; then
      basename "$d"
    fi
  done
}

# --- AC: README's budget section carries the post-condensation figures -------

@test "README quotes the token total budget_check.sh actually reports" {
  local tok
  tok="$(measured_tokens)"
  [ -n "$tok" ]
  grep -q "\*\*~$tok tokens\*\*" "$README"
}

@test "README quotes the catalogue-entry count budget_check.sh reports" {
  local entries
  entries="$(measured_entries)"
  [ -n "$entries" ]
  grep -q "$entries catalogue entries" "$README"
}

@test "README quotes the hidden-skill count budget_check.sh reports" {
  local hidden
  hidden="$(measured_hidden)"
  [ -n "$hidden" ]
  grep -q "$hidden skills" "$README"
}

@test "README states the budget as the measured value, not a slack ceiling" {
  local tok
  tok="$(measured_tokens)"
  grep -q "budget of \*\*$tok\*\*" "$README"
}

@test "no stale ~1,141-token figure survives in README" {
  ! grep -q '1,141' "$README"
}

@test "no stale ten-hidden-skills claim survives in README" {
  ! grep -qi 'ten skills' "$README"
  ! grep -qi 'the ten hidden' "$README"
}

@test "no stale 1,200 budget survives in README" {
  ! grep -q '1,200' "$README"
}

# --- AC: exactly three entry points, namespaced, with trigger phrases --------

@test "README documents all three entry points in namespaced form" {
  grep -q '/crewforge:init' "$README"
  grep -q '/crewforge:plan' "$README"
  grep -q '/crewforge:execute' "$README"
}

@test "README never writes an entry point in the bare form" {
  # `(/init` or ` /init` etc. — anything not preceded by `crewforge:`.
  ! grep -nE '(^|[^:[:alnum:]_-])/(init|plan|execute)\b' "$README"
}

@test "README carries a trigger phrase for each entry point" {
  local s
  for s in init plan execute; do
    grep -qE "^\| \`/crewforge:$s\` \|" "$README"
  done
}

@test "README maps every hidden sub-skill to an entry point" {
  local n missing=""
  for n in $(hidden_skills); do
    grep -q "\`$n\`" "$README" || missing="$missing $n"
  done
  [ -z "$missing" ]
}

@test "README names exactly three slash commands and no fourth" {
  # A hidden skill is still reachable by slash, so it is easy to document one
  # as if it were an entry point. The catalogue shape says otherwise.
  local named
  named="$(grep -oE '/crewforge:[a-z_-]+' "$README" | sed 's|/crewforge:||' \
           | sort -u | tr '\n' ' ')"
  [ "$named" = "execute init plan " ]
}

# --- AC: CHANGELOG records before/after always-loaded totals ----------------

@test "CHANGELOG records the measured after-total from budget_check.sh" {
  local tok entries
  tok="$(measured_tokens)"
  entries="$(measured_entries)"
  grep -q "~$tok tok" "$CHANGELOG"
  grep -q "$entries entries" "$CHANGELOG"
}

@test "CHANGELOG records the before-total it was measured against" {
  grep -q '~1,098 tok\|~1098 tok' "$CHANGELOG"
  grep -q '23 entries' "$CHANGELOG"
}

@test "CHANGELOG has an entry for the version the manifests declare" {
  local v
  v="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN" | head -1)"
  [ -n "$v" ]
  grep -q "^## $v " "$CHANGELOG"
}

# --- AC: manifests match the three-skill shape and are version-bumped -------

@test "plugin.json is bumped off 0.1.0" {
  ! grep -q '"version": "0.1.0"' "$PLUGIN"
}

@test "marketplace.json is bumped off 0.1.0" {
  ! grep -q '"version": "0.1.0"' "$MARKET"
}

@test "both manifests declare the same version" {
  local a b
  a="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN" | head -1)"
  b="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$MARKET" | head -1)"
  [ "$a" = "$b" ]
}

@test "plugin.json's description describes the three-entry-point shape" {
  local d
  d="$(sed -n 's/.*"description": *"\([^"]*\)".*/\1/p' "$PLUGIN" | head -1)"
  case "$d" in
    *init*plan*execute*) : ;;
    *) return 1 ;;
  esac
}

@test "marketplace.json's plugin description describes the same shape" {
  local hits
  hits="$(grep -c 'init.*plan.*execute' "$MARKET")"
  [ "$hits" -ge 2 ]
}

@test "both manifests remain valid JSON" {
  run jq -e . "$PLUGIN"
  [ "$status" -eq 0 ]
  run jq -e . "$MARKET"
  [ "$status" -eq 0 ]
}

# --- AC: no README link points at a path that no longer exists --------------

@test "every relative link target in README exists on disk" {
  local broken="" target
  for target in $(grep -oE '\]\([^)#]+\)' "$README" | sed 's/^](//; s/)$//'); do
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    [ -e "$ROOT/${target%%#*}" ] || broken="$broken $target"
  done
  [ -z "$broken" ]
}

@test "every backticked repo path in README exists on disk" {
  local broken="" target
  for target in $(grep -oE '`(skills|scripts|agents|hooks|rules|commands)/[A-Za-z0-9._/-]+`' "$README" \
                  | tr -d '`'); do
    [ -e "$ROOT/$target" ] || broken="$broken $target"
  done
  [ -z "$broken" ]
}

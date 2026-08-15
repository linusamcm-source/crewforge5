#!/usr/bin/env bash
# Structural validation for a Claude Code agent .md file
# Usage: validate_agent.sh <agent-file.md>
# Outputs JSON with check results

set -euo pipefail

AGENT_FILE="${1:?Usage: validate_agent.sh <agent-file.md>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_CHECK="$HERE/../../../scripts/frontmatter_check.sh"

# Escape backslashes, quotes, and control whitespace so details can't break the
# JSON. The parse-failure details quote the offending value, which is exactly the
# kind of string that contains a quote character.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

# Helper to emit a check result
result() {
  local status="$1" check="$2" detail="$3"
  printf '{"status":"%s","check":"%s","detail":"%s"}\n' "$status" "$check" "$(json_escape "$detail")"
}

echo "["

FIRST=true
emit() {
  if [ "$FIRST" = true ]; then FIRST=false; else echo ","; fi
  echo "$1"
}

# --- Agent file existence ---
if [ ! -f "$AGENT_FILE" ]; then
  emit "$(result FAIL "agent_file_exists" "Agent file not found at $AGENT_FILE")"
  echo "]"
  exit 0
fi
emit "$(result PASS "agent_file_exists" "Agent file found")"

# --- File extension ---
if [[ "$AGENT_FILE" != *.md ]]; then
  emit "$(result WARN "file_extension" "Agent file should have .md extension")"
else
  emit "$(result PASS "file_extension" ".md extension present")"
fi

# --- Frontmatter presence ---
FIRST_LINE=$(head -1 "$AGENT_FILE")
if [ "$FIRST_LINE" != "---" ]; then
  emit "$(result FAIL "frontmatter_present" "No YAML frontmatter (missing opening ---)")"
  echo "]"
  exit 0
else
  # Check closing ---
  CLOSE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$AGENT_FILE")
  if [ -z "$CLOSE" ]; then
    emit "$(result FAIL "frontmatter_present" "No closing --- for frontmatter")"
    echo "]"
    exit 0
  else
    emit "$(result PASS "frontmatter_present" "Frontmatter delimiters found (lines 1-$CLOSE)")"

    # Delimiters present is not the same claim as parses. Every other check here
    # asks whether a field is in the text; a block that does not parse has no
    # fields at all, so those checks read a broken manifest as a clean one. This
    # shipped: the plugin's own entry point ran with empty metadata and every
    # gate called it clean.
    if [ -f "$FM_CHECK" ]; then
      FM_OUT="$(bash "$FM_CHECK" "$AGENT_FILE" 2>&1)" && FM_RC=0 || FM_RC=$?
      case "${FM_OUT:-}" in
        FAIL:*) emit "$(result FAIL "frontmatter_parses" "${FM_OUT#FAIL: } — at runtime this agent loads with NO metadata")" ;;
        WARN:*) emit "$(result WARN "frontmatter_parses" "${FM_OUT#WARN: }")" ;;
        *)      [ "$FM_RC" -eq 0 ] && emit "$(result PASS "frontmatter_parses" "frontmatter parses as a flat mapping")" ;;
      esac
    else
      emit "$(result WARN "frontmatter_parses" "frontmatter_check.sh not found at $FM_CHECK — parse validation skipped")"
    fi

    # Extract frontmatter
    FM=$(sed -n "2,$((CLOSE-1))p" "$AGENT_FILE")

    # --- name field ---
    if echo "$FM" | grep -qE '^name:'; then
      NAME=$(echo "$FM" | grep -E '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'")
      if [ -z "$NAME" ]; then
        emit "$(result FAIL "name_field" "name field is empty")"
      else
        emit "$(result PASS "name_field" "name: $NAME")"
      fi
    else
      emit "$(result FAIL "name_field" "name field missing from frontmatter")"
    fi

    # --- description field ---
    if echo "$FM" | grep -qE '^description:'; then
      # Grab description — may be multi-line (folded or literal block)
      DESC_BLOCK=$(echo "$FM" | sed -n '/^description:/,/^[a-z_]*:/{ /^description:/p; /^[a-z_]*:/!p; }' | head -30)
      WORD_COUNT=$(echo "$DESC_BLOCK" | wc -w | tr -d ' ')
      # An agent description is always-loaded rent: it renders into the catalogue
      # for every session whether or not the agent is ever spawned, and unlike a
      # skill it has no `disable-model-invocation` escape. So the bar is a
      # ceiling, not a floor — trigger phrases plus one line of purpose, at the
      # ~200 char house limit claude-config sets. See budget_check.sh, which
      # charges this same string against the release gate.
      DESC_CHARS=$(printf '%s' "$DESC_BLOCK" | sed 's/^description:[[:space:]]*//' | wc -c | tr -d ' ')
      if [ "$WORD_COUNT" -lt 5 ]; then
        emit "$(result FAIL "description_field" "description is too short ($WORD_COUNT words)")"
      elif [ "$DESC_CHARS" -gt 200 ]; then
        emit "$(result WARN "description_length" "description is $DESC_CHARS chars (~$((DESC_CHARS / 4)) tok always-loaded; house limit ~200 — trim to trigger phrases plus one line of purpose)")"
      else
        emit "$(result PASS "description_length" "description is $DESC_CHARS chars (~$((DESC_CHARS / 4)) tok always-loaded)")"
      fi

      # Trigger phrases are the one part of a description that must never be
      # trimmed away — they are how the agent gets found at all.
      if echo "$DESC_BLOCK" | grep -qiE '(use when|trigger|invoke|use this)'; then
        emit "$(result PASS "description_triggers" "description includes trigger context phrases")"
      else
        emit "$(result WARN "description_triggers" "description lacks trigger phrases (Use when..., Trigger on...)")"
      fi

      # `<example>` blocks are reported, never demanded. An expressive
      # description carries the same semantics for a fraction of the rent, so an
      # absent example block is not a defect — only a present one is worth
      # pricing, because the reader is paying for it every session.
      if echo "$DESC_BLOCK" | grep -qE '<example>'; then
        emit "$(result INFO "description_examples" "description carries <example> blocks — confirm the triggering they buy is worth their always-loaded cost")"
      fi
    else
      emit "$(result FAIL "description_field" "description field missing from frontmatter")"
    fi

    # --- tools field ---
    if echo "$FM" | grep -qE '^tools:'; then
      TOOLS=$(echo "$FM" | grep -E '^tools:' | sed 's/^tools:[[:space:]]*//')
      if [ -z "$TOOLS" ]; then
        emit "$(result WARN "tools_field" "tools field is empty — agent will have no tool access")"
      else
        TOOL_COUNT=$(echo "$TOOLS" | tr ',' '\n' | wc -l | tr -d ' ')
        emit "$(result PASS "tools_field" "tools: $TOOLS ($TOOL_COUNT tools declared)")"
      fi
    else
      emit "$(result WARN "tools_field" "tools field missing — agent inherits parent tools only")"
    fi

    # --- color field ---
    if echo "$FM" | grep -qE '^color:'; then
      COLOR=$(echo "$FM" | grep -E '^color:' | sed 's/^color:[[:space:]]*//')
      emit "$(result PASS "color_field" "color: $COLOR")"
    else
      emit "$(result WARN "color_field" "color field missing — agent has no visual identity in UI")"
    fi
  fi
fi

# --- Body content ---
BODY_START=$((CLOSE + 1))
TOTAL_LINES=$(wc -l < "$AGENT_FILE" | tr -d ' ')
BODY_LINES=$((TOTAL_LINES - BODY_START + 1))
if [ "$BODY_LINES" -le 1 ]; then
  emit "$(result FAIL "body_nonempty" "Agent body is empty — no instructions for the agent")"
else
  emit "$(result PASS "body_nonempty" "Agent body has $BODY_LINES lines")"
fi

# --- Size checks (agents are single files, so thresholds differ from skills) ---
if [ "$TOTAL_LINES" -gt 500 ]; then
  emit "$(result FAIL "size_limit" "Agent file is $TOTAL_LINES lines (max 500 — agents load fully into context)")"
elif [ "$TOTAL_LINES" -gt 300 ]; then
  emit "$(result WARN "size_limit" "Agent file is $TOTAL_LINES lines (recommended < 300 for optimal context usage)")"
else
  emit "$(result PASS "size_limit" "Agent file is $TOTAL_LINES lines")"
fi

# --- Token estimate ---
WORD_COUNT=$(wc -w < "$AGENT_FILE" | tr -d ' ')
TOKEN_EST=$((WORD_COUNT * 4 / 3))
emit "$(result INFO "token_estimate" "~$TOKEN_EST tokens ($WORD_COUNT words)")"

# --- Heavy directive count ---
# The count exists to catch rules written to compensate for a weaker model. It is
# NOT a reason to soften a guard on something irreversible or expensive: a hard
# directive around a push, a delete, a credential or a spend is doing real work,
# and counting it here would pressure the rectifier into deleting it. Those lines
# are excluded from the tally and reported separately.
SAFETY_RE='secret|credential|token|password|api[ _-]?key|force|delete|destructiv|irreversib|rm -rf|git push|--hard|overwrit|production|billing|spend|cost|budget'
DIRECTIVE_RE='\b(MUST|ALWAYS|NEVER|IMPORTANT)\b'
# `grep -c` prints 0 AND exits 1 on no match, so `|| echo 0` would emit a second
# zero and turn the arithmetic below into a syntax error. `|| true` keeps the count.
DIRECTIVE_TOTAL=$(grep -cEi "$DIRECTIVE_RE" "$AGENT_FILE" 2>/dev/null || true)
SAFETY_COUNT=$(grep -Ei "$DIRECTIVE_RE" "$AGENT_FILE" 2>/dev/null | grep -cEi "$SAFETY_RE" || true)
DIRECTIVE_COUNT=$((DIRECTIVE_TOTAL - SAFETY_COUNT))
if [ "$SAFETY_COUNT" -gt 0 ]; then
  emit "$(result INFO "directive_safety_exempt" "$SAFETY_COUNT directives guard irreversible or costly actions — exempt from the tally, do not soften")"
fi
if [ "$DIRECTIVE_COUNT" -gt 10 ]; then
  emit "$(result WARN "directive_count" "$DIRECTIVE_COUNT non-safety heavy directives (MUST/ALWAYS/NEVER/IMPORTANT) — explain reasoning instead")"
else
  emit "$(result PASS "directive_count" "$DIRECTIVE_COUNT non-safety heavy directives")"
fi

# --- Role/identity statement ---
BODY=$(tail -n +"$BODY_START" "$AGENT_FILE")
if echo "$BODY" | head -20 | grep -qiE '(you are|you .* a|your role|your job)'; then
  emit "$(result PASS "role_statement" "Agent has role/identity statement in first 20 lines of body")"
else
  emit "$(result WARN "role_statement" "No clear role statement found in first 20 lines — agents perform better with identity framing")"
fi

# --- Completion gate ---
if grep -qiE '(completion gate|before reporting done|before marking.*complete)' "$AGENT_FILE" 2>/dev/null; then
  emit "$(result PASS "completion_gate" "Completion gate section detected")"
else
  emit "$(result WARN "completion_gate" "No completion gate found — agents may report tasks done prematurely without exit criteria")"
fi

# --- Skill references consistency ---
SKILL_REFS=$(grep -oE '/[a-z][a-z0-9-]+' "$AGENT_FILE" 2>/dev/null | sort -u | grep -vE '^/(dev|tmp|usr|etc|var|home|Users|bin|opt)' || true)
if [ -n "$SKILL_REFS" ]; then
  emit "$(result INFO "skill_references" "Skill references found: $(echo "$SKILL_REFS" | tr '\n' ' ')")"
fi

# --- Tool usage vs declaration coherence ---
if echo "$FM" | grep -qE '^tools:'; then
  DECLARED_TOOLS=$(echo "$FM" | grep -E '^tools:' | sed 's/^tools:[[:space:]]*//')
  # Check if body references tools not in declaration
  for TOOL in Bash Read Write Edit Glob Grep; do
    if echo "$BODY" | grep -qw "$TOOL" 2>/dev/null; then
      if ! echo "$DECLARED_TOOLS" | grep -qw "$TOOL" 2>/dev/null; then
        emit "$(result WARN "tool_coherence" "Body references '$TOOL' but it's not in the tools declaration")"
      fi
    fi
  done
fi

echo ""
echo "]"

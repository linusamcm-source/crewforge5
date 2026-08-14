#!/usr/bin/env bash
# Structural validation for a Claude Code skill directory
# Usage: validate_structure.sh <skill-directory>
# Outputs a JSON array of {status, check, detail} objects

set -euo pipefail

SKILL_DIR="${1:?Usage: validate_structure.sh <skill-directory>}"
SKILL_DIR="${SKILL_DIR%/}"
SKILL_MD="$SKILL_DIR/SKILL.md"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_CHECK="$HERE/../../../scripts/frontmatter_check.sh"

# Escape backslashes, quotes, and control whitespace so details can't break the JSON
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

# --- SKILL.md existence ---
if [ ! -f "$SKILL_MD" ]; then
  emit "$(result FAIL "skill_md_exists" "SKILL.md not found at $SKILL_MD")"
  echo "]"
  exit 0
fi
emit "$(result PASS "skill_md_exists" "SKILL.md found")"

# --- Frontmatter presence ---
CLOSE=""
FIRST_LINE=$(head -1 "$SKILL_MD")
if [ "$FIRST_LINE" != "---" ]; then
  emit "$(result FAIL "frontmatter_present" "No YAML frontmatter (missing opening ---)")"
else
  # Check closing ---
  CLOSE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_MD")
  if [ -z "$CLOSE" ]; then
    emit "$(result FAIL "frontmatter_present" "No closing --- for frontmatter")"
  else
    emit "$(result PASS "frontmatter_present" "Frontmatter delimiters found")"

    # Delimiters present is not the same claim as parses. Every other check here
    # asks whether a field is in the text; a block that does not parse has no
    # fields at all, so those checks read a broken manifest as a clean one. This
    # shipped: the plugin's own entry point ran with empty metadata and every
    # gate called it clean.
    if [ -f "$FM_CHECK" ]; then
      FM_OUT="$(bash "$FM_CHECK" "$SKILL_MD" 2>&1)" && FM_RC=0 || FM_RC=$?
      case "${FM_OUT:-}" in
        FAIL:*) emit "$(result FAIL "frontmatter_parses" "${FM_OUT#FAIL: } — at runtime this skill loads with NO metadata")" ;;
        WARN:*) emit "$(result WARN "frontmatter_parses" "${FM_OUT#WARN: }")" ;;
        *)      [ "$FM_RC" -eq 0 ] && emit "$(result PASS "frontmatter_parses" "frontmatter parses as a flat mapping")" ;;
      esac
    else
      emit "$(result WARN "frontmatter_parses" "frontmatter_check.sh not found at $FM_CHECK — parse validation skipped")"
    fi

    # Extract frontmatter
    FM=$(sed -n "2,$((CLOSE-1))p" "$SKILL_MD")

    # Check name field
    if echo "$FM" | grep -qE '^name:'; then
      NAME=$(echo "$FM" | grep -E '^name:' | head -1 | sed 's/^name:[[:space:]]*//')
      if [ -z "$NAME" ]; then
        emit "$(result FAIL "name_field" "name field is empty")"
      else
        emit "$(result PASS "name_field" "name: $NAME")"
        if ! printf '%s' "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
          emit "$(result WARN "name_format" "name '$NAME' is not lowercase-kebab-case")"
        fi
        DIR_BASE=$(basename "$SKILL_DIR")
        if [ "$NAME" != "$DIR_BASE" ]; then
          emit "$(result WARN "name_matches_dir" "name '$NAME' does not match directory '$DIR_BASE' — slash-command lookup uses the directory name")"
        fi
      fi
    else
      emit "$(result FAIL "name_field" "name field missing from frontmatter")"
    fi

    # Check description field (multi-line aware: capture from the key until the next top-level key)
    if echo "$FM" | grep -qE '^description:'; then
      DESC=$(printf '%s\n' "$FM" | awk '
        /^description:/ { sub(/^description:[[:space:]]*/, ""); sub(/^[>|][+-]?$/, ""); print; found=1; next }
        found && /^[A-Za-z0-9_-]+:/ { exit }
        found { print }')
      WORD_COUNT=$(printf '%s\n' "$DESC" | wc -w | tr -d ' ')
      # The bar is a ceiling, not a floor. A visible skill's description renders
      # into the always-loaded catalogue every session whether or not the skill is
      # ever invoked, and budget_check.sh charges this exact string against the
      # release gate — so a rule that rewards padding fights the gate it ships
      # beside. claude-config sets the house limit at ~200 chars; trigger phrases
      # plus one line of purpose is the shape that fits.
      DESC_CHARS=$(printf '%s' "$DESC" | wc -c | tr -d ' ')
      if [ "$WORD_COUNT" -lt 5 ]; then
        emit "$(result FAIL "description_field" "description is too short ($WORD_COUNT words)")"
      elif [ "$DESC_CHARS" -gt 200 ]; then
        emit "$(result WARN "description_length" "description is $DESC_CHARS chars (~$((DESC_CHARS / 4)) tok always-loaded; house limit ~200 — trim to trigger phrases plus one line of purpose)")"
      else
        emit "$(result PASS "description_length" "description is $DESC_CHARS chars (~$((DESC_CHARS / 4)) tok always-loaded)")"
      fi
    else
      emit "$(result FAIL "description_field" "description field missing from frontmatter")"
    fi
  fi
fi

# --- Body content ---
TOTAL_LINES=$(wc -l < "$SKILL_MD" | tr -d ' ')
if [ -n "$CLOSE" ]; then
  BODY_LINES=$((TOTAL_LINES - CLOSE))
else
  BODY_LINES=$TOTAL_LINES
fi
if [ "$BODY_LINES" -le 1 ]; then
  emit "$(result FAIL "body_nonempty" "SKILL.md body is empty")"
else
  emit "$(result PASS "body_nonempty" "SKILL.md body has $BODY_LINES lines")"
fi

# --- Size checks ---
if [ "$TOTAL_LINES" -gt 1000 ]; then
  emit "$(result FAIL "size_limit" "SKILL.md is $TOTAL_LINES lines (max 1000)")"
elif [ "$TOTAL_LINES" -gt 500 ]; then
  emit "$(result WARN "size_limit" "SKILL.md is $TOTAL_LINES lines (recommended < 500)")"
else
  emit "$(result PASS "size_limit" "SKILL.md is $TOTAL_LINES lines")"
fi

# --- Token estimate ---
WORD_COUNT=$(wc -w < "$SKILL_MD" | tr -d ' ')
TOKEN_EST=$((WORD_COUNT * 4 / 3))
emit "$(result INFO "token_estimate" "~$TOKEN_EST tokens ($WORD_COUNT words)")"

# --- Referenced files exist ---
# Paths under scripts/, references/, assets/ mentioned in SKILL.md must exist on disk
DEAD_REFS=""
REF_COUNT=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  ref="${ref%.}"   # strip a trailing sentence period
  ref="${ref%/}"
  REF_COUNT=$((REF_COUNT + 1))
  if [ ! -e "$SKILL_DIR/$ref" ]; then
    DEAD_REFS="$DEAD_REFS $ref"
  fi
done < <(grep -oE '(^|[^A-Za-z0-9._/-])(references|scripts|assets)/[A-Za-z0-9._/-]+' "$SKILL_MD" 2>/dev/null \
  | sed -E 's~^[^A-Za-z0-9]~~' | sort -u || true)
if [ -n "$DEAD_REFS" ]; then
  emit "$(result FAIL "referenced_files_exist" "Referenced in SKILL.md but missing on disk:$DEAD_REFS")"
else
  emit "$(result PASS "referenced_files_exist" "All $REF_COUNT referenced scripts/references/assets paths exist")"
fi

# --- Orphan files ---
# Files in the skill directory that SKILL.md never mentions (by basename)
ORPHANS=""
while IFS= read -r f; do
  base=$(basename "$f")
  if ! grep -qF "$base" "$SKILL_MD"; then
    ORPHANS="$ORPHANS ${f#"$SKILL_DIR"/}"
  fi
done < <(find "$SKILL_DIR" -type f ! -name 'SKILL.md' \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/__pycache__/*' 2>/dev/null)
if [ -n "$ORPHANS" ]; then
  emit "$(result WARN "no_orphan_files" "Files never mentioned in SKILL.md:$ORPHANS")"
else
  emit "$(result PASS "no_orphan_files" "Every bundled file is referenced from SKILL.md")"
fi

# --- Sensitive files check ---
# High-confidence secret artifacts → FAIL
SENSITIVE_FOUND=""
while IFS= read -r f; do
  SENSITIVE_FOUND="$SENSITIVE_FOUND ${f#"$SKILL_DIR"/}"
done < <(find "$SKILL_DIR" \
  \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name 'id_rsa*' -o -name 'id_ed25519*' \
     -o -name '*credentials*' -o -name '*.keystore' -o -name '*.p12' \) \
  ! -name '*.md' -not -path '*/node_modules/*' 2>/dev/null)
if [ -n "$SENSITIVE_FOUND" ]; then
  emit "$(result FAIL "no_sensitive_files" "Likely secret files found:$SENSITIVE_FOUND")"
else
  emit "$(result PASS "no_sensitive_files" "No high-confidence secret files detected")"
fi

# Name-only matches (a doc or script *about* tokens is usually fine) → WARN for manual review
SUSPECT_FOUND=""
while IFS= read -r f; do
  SUSPECT_FOUND="$SUSPECT_FOUND ${f#"$SKILL_DIR"/}"
done < <(find "$SKILL_DIR" \
  \( -iname '*secret*' -o -iname '*apikey*' -o -iname '*api_key*' -o -iname '*token*' \) \
  ! -name '*.md' -not -path '*/node_modules/*' 2>/dev/null)
if [ -n "$SUSPECT_FOUND" ]; then
  emit "$(result WARN "suspect_filenames" "Filenames suggest secrets — inspect contents manually:$SUSPECT_FOUND")"
fi

# --- Directory structure conventions ---
for dir in "$SKILL_DIR"/*/; do
  [ -d "$dir" ] || continue
  DIRNAME=$(basename "$dir")
  case "$DIRNAME" in
    scripts|references|assets|evals|tests) ;;
    __pycache__|.git|node_modules) ;;
    *) emit "$(result WARN "dir_conventions" "Non-standard directory: $DIRNAME/")" ;;
  esac
done

# --- Script checks ---
if [ -d "$SKILL_DIR/scripts" ]; then
  for script in "$SKILL_DIR/scripts/"*; do
    [ -f "$script" ] || continue
    SNAME=$(basename "$script")

    # Executable check
    if [ -x "$script" ]; then
      emit "$(result PASS "script_executable" "$SNAME is executable")"
    else
      emit "$(result WARN "script_executable" "$SNAME is not executable (missing chmod +x)")"
    fi

    # Shebang check
    SHEBANG=$(head -1 "$script")
    if echo "$SHEBANG" | grep -qE '^#!'; then
      emit "$(result PASS "script_shebang" "$SNAME has shebang: $SHEBANG")"
    else
      emit "$(result WARN "script_shebang" "$SNAME missing shebang line")"
    fi

    # Syntax check
    case "$SNAME" in
      *.py)
        if python3 -c "import ast; ast.parse(open('$script').read())" 2>/dev/null; then
          emit "$(result PASS "script_syntax" "$SNAME Python syntax OK")"
        else
          emit "$(result FAIL "script_syntax" "$SNAME has Python syntax errors")"
        fi
        ;;
      *.sh|*.bash)
        if bash -n "$script" 2>/dev/null; then
          emit "$(result PASS "script_syntax" "$SNAME shell syntax OK")"
        else
          emit "$(result FAIL "script_syntax" "$SNAME has shell syntax errors")"
        fi
        ;;
    esac
  done
fi

# --- Heavy directive count ---
DIRECTIVE_COUNT=$(grep -cE '\b(MUST|ALWAYS|NEVER|IMPORTANT)\b' "$SKILL_MD" 2>/dev/null || true)
if [ "$DIRECTIVE_COUNT" -gt 10 ]; then
  emit "$(result WARN "directive_count" "$DIRECTIVE_COUNT heavy directives (MUST/ALWAYS/NEVER/IMPORTANT) — consider explaining why instead")"
else
  emit "$(result PASS "directive_count" "$DIRECTIVE_COUNT heavy directives")"
fi

echo ""
echo "]"

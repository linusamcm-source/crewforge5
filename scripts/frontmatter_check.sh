#!/usr/bin/env bash
# frontmatter_check.sh — does this file's YAML frontmatter actually parse?
#
#   frontmatter_check.sh <file.md>
#
# THE PROBLEM. `skills/init/SKILL.md` shipped with an unquoted description
# containing `: `, which is not a plain scalar in YAML. The whole block failed to
# load, so the plugin's main entry point ran with name, model and description all
# silently dropped — and every gate in this repo called it clean, because they
# check that fields are PRESENT in the text without ever parsing the text. A
# manifest that does not parse has no fields at all, so field checks on a broken
# block are the one thing that cannot detect it. `claude plugin tag` caught it;
# nothing here did.
#
# NO YAML LIBRARY, DELIBERATELY. python3 is a declared dependency but PyYAML is
# not, and a gate that is stricter on the maintainer's laptop than in CI teaches
# people to distrust it. This reads the flat `key: value` shape that frontmatter
# actually uses and rejects the constructs that silently break it. It is narrower
# than a parser and identical everywhere, which is the trade being made.
#
# Three states, because "does not parse" and "parses but silently loses half the
# value" are different failures and collapsing them would misreport both:
#
#   exit 0, no output    frontmatter is sound
#   exit 0, WARN: <line> it parses, but content is silently dropped
#   exit 1, FAIL: <line> it does not parse; every field is lost
#   exit 2               usage error
#
# The reserved-character set below was not reasoned out — it was measured against
# PyYAML one character at a time. `&` and `?` lead valid plain scalars and are
# absent for that reason; `[` and `{` are legal when the collection they open is
# closed, so they are checked for balance rather than banned.
set -uo pipefail

FILE="${1:-}"
[ -n "$FILE" ] || { echo "usage: frontmatter_check.sh <file.md>" >&2; exit 2; }
[ -f "$FILE" ] || { echo "usage: frontmatter_check.sh <file.md>" >&2; exit 2; }

# No frontmatter at all is not this script's verdict to give — the validators
# already fail that case, and reporting it twice would double-count the finding.
head -1 "$FILE" | grep -q '^---$' || exit 0
CLOSE=$(awk 'NR>1 && /^---[[:space:]]*$/{print NR; exit}' "$FILE")
[ -n "$CLOSE" ] || exit 0

REASON=$(sed -n "2,$((CLOSE - 1))p" "$FILE" | awk '
  # A block scalar (key: | or key: >) makes every more-indented line that
  # follows literal text, not YAML. Those lines get skipped rather than parsed.
  in_block {
    if ($0 ~ /^[[:space:]]/ || $0 == "") next
    in_block = 0
  }
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }

  # Tabs are never legal YAML indentation and the error they raise names a
  # column, not a cause, so they are worth catching by name.
  /\t/ { print "FAIL: line " NR ": tab character — YAML forbids tabs in indentation"; exit }

  # Continuation of a multi-line plain scalar: indented, no key of its own.
  /^[[:space:]]+/ { next }

  {
    if ($0 !~ /^[A-Za-z0-9_-]+:/) {
      print "FAIL: line " NR ": not a `key: value` mapping — " substr($0, 1, 48)
      exit
    }
    key = $0; sub(/:.*$/, "", key)
    val = $0; sub(/^[A-Za-z0-9_-]+:[[:space:]]*/, "", val)
    sub(/[[:space:]]+$/, "", val)

    if (val == "") next
    if (val == "|" || val == ">" || val ~ /^[|>][+-]?[0-9]*$/) { in_block = 1; next }

    first = substr(val, 1, 1)

    last = substr(val, length(val), 1)

    if (first == "\"" || first == "'"'"'") {
      if (length(val) < 2 || last != first) {
        print "FAIL: line " NR ": `" key "` opens with " first " and never closes it"
        exit
      }
      next
    }

    # A flow collection is legal as long as it is closed on the same line.
    if (first == "[" || first == "{") {
      if ((first == "[" && last == "]") || (first == "{" && last == "}")) next
      print "FAIL: line " NR ": `" key "` opens a flow " (first == "[" ? "sequence" : "mapping") " and never closes it"
      exit
    }

    # Plain (unquoted) scalars. This is the shape almost every field uses, and
    # the shape with the sharpest edges.
    if (index(val, ": ") > 0 || val ~ /:$/) {
      print "FAIL: line " NR ": `" key "` is unquoted and contains a colon-space — YAML reads it as a nested mapping and the whole block fails"
      exit
    }
    if (index("@`%!*,]}|>", first) > 0) {
      print "FAIL: line " NR ": `" key "` is unquoted and starts with " first ", which YAML reserves"
      exit
    }
    # `-` and `?` are ordinary text when glued to a word and structural when
    # followed by a space: `-value` is a string, `- value` opens a sequence.
    if (val ~ /^[-?] /) {
      print "FAIL: line " NR ": `" key "` is unquoted and starts with " first " followed by a space, which opens a " (first == "-" ? "sequence entry" : "complex key")
      exit
    }
    # Parses, but not as written: everything from the hash on is a comment. The
    # field survives with its tail amputated, which is why this is a warning and
    # the cases above are not.
    if (index(val, " #") > 0) {
      warn = "WARN: line " NR ": `" key "` is unquoted and contains a space-hash — everything after it parses as a comment and is lost"
    }
  }
  END { if (warn != "") print warn }
')

[ -n "$REASON" ] || exit 0
printf '%s\n' "$REASON"
case "$REASON" in
  FAIL:*) exit 1 ;;
  *)      exit 0 ;;
esac

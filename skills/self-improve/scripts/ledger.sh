#!/usr/bin/env bash
# ledger.sh — the learning capture channel for skills, agents and hooks.
#
#   ledger.sh add <target> <source> <note>   append one entry
#   ledger.sh list [target]                  print entries, oldest first
#   ledger.sh count [target]                 entry count only
#   ledger.sh clear <target>                 archive a target's entries after distilling
#
# One JSONL file per target under $CLAUDE_CONFIG_DIR/ledger/. Nothing here is
# read at session start — the ledger costs zero tokens until /self-improve opens
# it, which is the whole point of capturing rather than remembering.
#
# <source> is `hook` for a mechanically observed failure and `user` for a lesson
# someone stated. The distiller weighs them differently: a hook entry is evidence
# something broke, a user entry is a judgement about what should change.
set -euo pipefail

# Runtime state, not config: with no CLAUDE_CONFIG_DIR the ledger lands in the
# user's state dir rather than assuming a ~/.claude exists to write into.
ROOT="${CLAUDE_CONFIG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/crewforge}"
DIR="$ROOT/ledger"
CMD="${1:-list}"
shift || true

# Targets become filenames; keep them to the shape a skill or agent name takes.
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

case "$CMD" in
  add)
    target="${1:?usage: ledger.sh add <target> <source> <note>}"
    source="${2:?usage: ledger.sh add <target> <source> <note>}"
    note="${3:?usage: ledger.sh add <target> <source> <note>}"
    mkdir -p "$DIR"
    python3 -c '
import json, sys, datetime
print(json.dumps({
    "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "target": sys.argv[1],
    "source": sys.argv[2],
    "note": sys.argv[3],
}))' "$target" "$source" "$note" >> "$DIR/$(safe "$target").jsonl"
    echo "recorded: $target ($source)"
    ;;

  list)
    target="${1:-}"
    if [ -n "$target" ]; then
      f="$DIR/$(safe "$target").jsonl"
      [ -f "$f" ] && cat "$f" || echo "no entries for $target"
    else
      shopt -s nullglob
      files=("$DIR"/*.jsonl)
      [ ${#files[@]} -gt 0 ] || { echo "ledger empty"; exit 0; }
      cat "${files[@]}"
    fi
    ;;

  count)
    target="${1:-}"
    if [ -n "$target" ]; then
      f="$DIR/$(safe "$target").jsonl"
      [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0
    else
      shopt -s nullglob
      files=("$DIR"/*.jsonl)
      [ ${#files[@]} -gt 0 ] && cat "${files[@]}" | wc -l | tr -d ' ' || echo 0
    fi
    ;;

  clear)
    target="${1:?usage: ledger.sh clear <target>}"
    f="$DIR/$(safe "$target").jsonl"
    # Archive rather than delete: a distillation that turns out wrong needs the
    # evidence that motivated it.
    [ -f "$f" ] || { echo "no entries for $target"; exit 0; }
    mkdir -p "$DIR/archive"
    mv "$f" "$DIR/archive/$(safe "$target").$(date +%Y%m%d-%H%M%S).jsonl"
    echo "archived: $target"
    ;;

  *)
    sed -n '2,10p' "${BASH_SOURCE[0]}" >&2
    exit 1
    ;;
esac

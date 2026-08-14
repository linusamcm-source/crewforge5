#!/usr/bin/env bash
# packs.sh <scenario> — resolve a register pack and its extends: chain.
# Prints:
#   files=<space-separated pack paths, base first>
#   <merged manifest key=value lines, child overrides parent, sorted>
# Manifest = key: value lines between the pack's leading --- markers.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SCEN="${1:?usage: packs.sh <scenario>}"
REG="$HUMANISE_SKILL_DIR/references/registers"

chain="" cur="$SCEN" depth=0
while [ -n "$cur" ]; do
  f="$REG/$cur.md"
  [ -f "$f" ] || die "no register pack: $cur ($f). Available: $(ls "$REG" | sed 's/\.md$//' | tr '\n' ' ')"
  chain="$cur $chain"   # prepend => base-first order
  cur="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$f" | awk -F': *' '$1=="extends"{print $2}')"
  depth=$((depth+1)); [ "$depth" -gt 5 ] && die "extends chain too deep at $SCEN"
done

files=""
for c in $chain; do files="$files $REG/$c.md"; done
echo "files=${files# }"

for c in $chain; do
  awk '/^---$/{n++; next} n==1 && /^[a-z_]+: */{print} n>=2{exit}' "$REG/$c.md"
done | awk -F': *' '$1!="extends"{v[$1]=$2} END{for (k in v) print k"="v[k]}' | sort

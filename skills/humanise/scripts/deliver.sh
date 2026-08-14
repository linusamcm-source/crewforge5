#!/usr/bin/env bash
# deliver.sh <scenario> [file] — log the delivered rewrite (from file or stdin)
# to $HUMANISE_DATA/deliveries/<timestamp>-<scenario>.md and print the path.
# The stored base is what makes feedback.sh capture diffable later.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SCEN="${1:?usage: deliver.sh <scenario> [file]}"
shift || true

mkdir -p "$HUMANISE_DATA/deliveries"
ts="$(date +%Y%m%dT%H%M%S)"
out="$HUMANISE_DATA/deliveries/$ts-$SCEN.md"
if [ $# -ge 1 ]; then cp "$1" "$out"; else cat >"$out"; fi
echo "$out"

#!/usr/bin/env bash
# estimate-agents.sh [uncached-file] — Part B dispatch estimate, mechanised.
# Reads graphify-out/.graphify_uncached.txt (chunk size 22, ~45s per parallel
# batch) and prints the line the skill requires before dispatching subagents.
set -euo pipefail

F="${1:-graphify-out/.graphify_uncached.txt}"
[ -f "$F" ] || { echo "files=0"; echo "agents=0"; echo "note=no uncached list — all files cached, skip to Part C"; exit 0; }

n=$(grep -c . "$F" || true)
agents=$(( (n + 21) / 22 ))
batches=$(( (agents + 9) / 10 ))
secs=$(( batches * 45 ))
echo "files=$n"
echo "agents=$agents"
echo "estimate=Semantic extraction: ~$n files → $agents agents, estimated ~${secs}s"

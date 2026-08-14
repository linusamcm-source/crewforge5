#!/usr/bin/env bash
# lib.sh — shared helpers for humanise scripts. Source, don't execute.
HUMANISE_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUMANISE_DATA="${HUMANISE_DATA:-$HOME/.claude/humanise-data}"

die() { echo "ERROR: $*" >&2; exit 1; }

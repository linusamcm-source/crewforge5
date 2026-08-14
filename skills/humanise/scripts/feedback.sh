#!/usr/bin/env bash
# feedback.sh — returns dock: capture what the user actually shipped, manage
# per-scenario learned corrections with two-strike promotion.
#   feedback.sh capture <scenario> <shipped-file>  diff latest delivery vs shipped
#   feedback.sh log <scenario> <correction text>   record/bump a correction candidate
#   feedback.sh corrections <scenario>             print APPLIED corrections (count >= 2)
# Corrections file: $HUMANISE_DATA/corrections/<scenario>.tsv  (count<TAB>date<TAB>text)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CMD="${1:?usage: feedback.sh capture|log|corrections ...}"
shift

case "$CMD" in
  capture)
    SCEN="${1:?usage: feedback.sh capture <scenario> <shipped-file>}"
    SHIPPED="${2:?usage: feedback.sh capture <scenario> <shipped-file>}"
    last="$(ls -1 "$HUMANISE_DATA/deliveries/"*"-$SCEN.md" 2>/dev/null | tail -1 || true)"
    [ -n "$last" ] || die "no logged delivery for scenario '$SCEN' — run deliver.sh first"
    mkdir -p "$HUMANISE_DATA/returns"
    ts="$(date +%Y%m%dT%H%M%S)"
    out="$HUMANISE_DATA/returns/$ts-$SCEN.diff"
    diff -u "$last" "$SHIPPED" >"$out" || true
    added=$(grep -c '^+[^+]' "$out" || true)
    removed=$(grep -c '^-[^-]' "$out" || true)
    echo "$out"
    echo "delivered=$last added_lines=$added removed_lines=$removed"
    ;;
  log)
    SCEN="${1:?usage: feedback.sh log <scenario> <correction text>}"
    shift
    TEXT="$*"
    [ -n "$TEXT" ] || die "empty correction text"
    mkdir -p "$HUMANISE_DATA/corrections"
    f="$HUMANISE_DATA/corrections/$SCEN.tsv"
    today="$(date +%Y-%m-%d)"
    if [ -f "$f" ] && awk -F'\t' -v t="$TEXT" '$3==t{found=1} END{exit !found}' "$f"; then
      awk -F'\t' -v OFS='\t' -v t="$TEXT" -v d="$today" '$3==t{$1=$1+1; $2=d} 1' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
    else
      printf '1\t%s\t%s\n' "$today" "$TEXT" >>"$f"
    fi
    awk -F'\t' -v t="$TEXT" '$3==t{print ($1>=2 ? "status=APPLIED (count="$1")" : "status=candidate (count="$1")")}' "$f"
    ;;
  corrections)
    SCEN="${1:?usage: feedback.sh corrections <scenario>}"
    f="$HUMANISE_DATA/corrections/$SCEN.tsv"
    [ -f "$f" ] || exit 0
    awk -F'\t' '$1>=2{print $3}' "$f"
    ;;
  *)
    die "unknown command: $CMD (capture|log|corrections)"
    ;;
esac

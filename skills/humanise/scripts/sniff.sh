#!/usr/bin/env bash
# sniff.sh — detect the writing scenario from destination path, hint, and draft features.
# Usage: sniff.sh [--path DEST] [--hint TEXT] [DRAFT_FILE]
# Draft read from DRAFT_FILE or stdin. Emits key=value lines:
#   scenario=<register pack name or unknown>
#   confidence=high|medium|low
#   evidence=<one line per signal>
# Pure signal scoring — no model judgment. bash 3.2 compatible (no assoc arrays).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PATH_ARG="" HINT="" DRAFT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) PATH_ARG="$2"; shift 2;;
    --hint) HINT="$2"; shift 2;;
    *) DRAFT="$1"; shift;;
  esac
done

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
if [ -n "$DRAFT" ]; then cat "$DRAFT" >"$TMP"; elif [ ! -t 0 ]; then cat >"$TMP"; fi

s_casual=0 s_email=0 s_formal=0 s_report=0 s_readme=0 s_docstring=0 s_pr=0 s_commit=0
EV=""
add() { # add <scenario-var-suffix> <points> <evidence>
  eval "s_$1=\$(( s_$1 + $2 ))"
  EV="${EV}evidence=$3
"
}

# --- destination path signals ---
if [ -n "$PATH_ARG" ]; then
  base="$(basename "$PATH_ARG")"
  case "$base" in
    README*|readme*) add readme 2 "destination basename $base";;
    COMMIT_EDITMSG)  add commit 3 "destination is COMMIT_EDITMSG";;
    *.py|*.js|*.ts|*.tsx|*.go|*.rb|*.rs|*.sh|*.java|*.kt|*.swift)
                     add docstring 2 "destination is source file $base";;
    *.md)            add report 1 "destination is markdown doc $base";;
  esac
  dir="$(dirname "$PATH_ARG")"
  if branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
    case "$branch" in main|master) :;; *) add pr 1 "on git branch '$branch'";; esac
  fi
fi

# --- hint signals ---
hint_lc="$(printf '%s' "$HINT" | tr '[:upper:]' '[:lower:]')"
if [ -n "$hint_lc" ]; then
  case "$hint_lc" in *slack*|*whatsapp*|*"text to"*|*" dm"*|*mate*|*chat*) add casual 2 "hint mentions casual channel";; esac
  case "$hint_lc" in *email*|*mail\ to*)                    add email 2 "hint mentions email";; esac
  case "$hint_lc" in *board*|*tender*|*proposal*|*client*)  add formal 2 "hint mentions formal audience";; esac
  case "$hint_lc" in *report*|*briefing*|*postmortem*|*post-mortem*) add report 2 "hint mentions report";; esac
  case "$hint_lc" in *"pull request"*|*"pr description"*|*"pr desc"*) add pr 2 "hint mentions pull request";; esac
  case "$hint_lc" in *commit*)                              add commit 2 "hint mentions commit";; esac
  case "$hint_lc" in *readme*)                              add readme 2 "hint mentions readme";; esac
  case "$hint_lc" in *docstring*|*"code comment"*)          add docstring 2 "hint mentions docstrings";; esac
fi

# --- draft feature signals ---
if [ -s "$TMP" ]; then
  first="$(head -1 "$TMP" | tr '[:upper:]' '[:lower:]')"
  case "$first" in
    hey*|hi\ *|hi,*|hiya*|g\'day*|yo\ *) add email 1 "greeting first line"; add casual 1 "greeting first line";;
    dear\ *)                             add formal 2 "opens with 'Dear'";;
    add\ *|fix\ *|update\ *|remove\ *|refactor\ *|implement\ *|bump\ *)
                                         add pr 2 "imperative first line"; add commit 1 "imperative first line";;
  esac
  words=$(wc -w <"$TMP" | tr -d ' ')
  [ "$words" -lt 50 ]  && add casual 1 "short draft ($words words)"
  [ "$words" -gt 600 ] && add report 1 "long draft ($words words)"
  heads=$(grep -c '^#' "$TMP" || true)
  if [ "$heads" -ge 3 ]; then
    add report 1 "$heads markdown headings"
    add readme 1 "$heads markdown headings"
  fi
  grep -q '^```' "$TMP" && add readme 1 "contains fenced code"
  grep -qiE 'kind regards|warm regards|^cheers,|sincerely' "$TMP" && add email 1 "email sign-off present"
fi

# --- pick winner ---
best="" best_score=0 second=0
for k in casual email formal report readme docstring pr commit; do
  v=$(eval echo "\$s_$k")
  if [ "$v" -gt "$best_score" ]; then
    second=$best_score; best_score=$v; best=$k
  elif [ "$v" -gt "$second" ]; then
    second=$v
  fi
done

case "$best" in
  casual) scen=casual-message;; email) scen=email;; formal) scen=formal-doc;;
  report) scen=report;; readme) scen=readme;; docstring) scen=docstring;;
  pr) scen=pr-description;; commit) scen=commit-message;; *) scen=unknown;;
esac

if [ "$scen" = "unknown" ] || [ "$best_score" -eq 0 ]; then
  echo "scenario=unknown"; echo "confidence=low"
elif [ "$best_score" -ge 3 ] && [ $((best_score - second)) -ge 2 ]; then
  echo "scenario=$scen"; echo "confidence=high"
elif [ "$best_score" -ge 2 ] && [ "$best_score" -gt "$second" ]; then
  echo "scenario=$scen"; echo "confidence=medium"
else
  echo "scenario=$scen"; echo "confidence=low"
fi
printf '%s' "$EV"

#!/usr/bin/env bats
# subskill_refs.bats — no shipped doc may still tell a model to `Skill`-invoke a
# skill that is hidden from the catalogue.
#
# WHY THIS IS A TEST AND NOT A REVIEW NOTE. `disable-model-invocation: true`
# removes a skill from the per-turn listing AND from the `Skill` tool's reach.
# Every "invoke the <X> skill" line left behind is therefore an instruction that
# cannot be carried out — and it fails *silently*, mid-flow, in a live run. The
# only thing that catches it before then is a grep, so the grep lives here.
#
# The predicate is deliberately narrow: it flags a MODEL-FACING IMPERATIVE to
# invoke a hidden skill. It does not flag prose that merely names one, because
# hidden skills are still real, still on disk, still openable by slash command,
# and their names legitimately appear in capability maps, phase tables and
# rationale. Widening this to "any mention" would force meaningless churn and
# train the next reader to ignore the check.
#
# Slash-command text addressed to a HUMAN survives untouched, for the same
# reason: `disable-model-invocation` blocks the model, not the user. Telling the
# user to run `/team-sprint-planner` is still correct advice.

source "$(dirname "${BATS_TEST_FILENAME:-${BASH_SOURCE[0]}}")/lib/bats-fallback.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  RESOLVE="$ROOT/scripts/flow/subskill_resolve.sh"
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# --- shared vocabulary -------------------------------------------------------

# Every skill whose SKILL.md carries the hiding flag, plus its `-`/`_` spelling
# variant, as one alternation. Derived from the tree rather than hardcoded: a
# 25th hidden skill must be covered the day it is hidden, not the day someone
# remembers to edit this list.
hidden_pattern() {
  local d n alt acc=""
  for d in "$ROOT"/skills/*/; do
    n="$(basename "$d")"
    grep -q '^disable-model-invocation:[[:space:]]*true' "$d/SKILL.md" 2>/dev/null || continue
    acc="$acc|$n"
    alt="$(printf '%s' "$n" | tr '_' '-')"
    [ "$alt" = "$n" ] || acc="$acc|$alt"
    alt="$(printf '%s' "$n" | tr '-' '_')"
    [ "$alt" = "$n" ] || acc="$acc|$alt"
  done
  printf '%s' "${acc#|}"
}

# The five skills that declare `context: fork`. They must be reached by `Agent`
# spawn and never by inline read — the fork declaration exists to keep their
# work OUT of the caller's window, and reading the body inline preserves the
# instructions while destroying exactly that isolation.
FORK_SKILLS="use-repo-code agent-validator skill-validator tech-debt-audit ac-validate"

# Docs this story owns: everything the bundle ships that a model reads.
shipped_docs() {
  find "$ROOT/skills" "$ROOT/agents" -name '*.md' -type f | sort
}

# Lines that name a hidden skill under an invocation verb, minus the four
# constructs that are NOT a model-facing imperative:
#   "the user invokes /x"     — describing the human's trigger
#   "does not auto-invoke"    — describing the absence of invocation
#   "do not invoke /x"        — a prohibition; already the desired behaviour
#   "offer to launch /x"      — handing the choice to the human
# and any line that already performs the resolver call.
invocation_sites() {
  local pat delim
  pat="$(hidden_pattern)"
  delim='[`*/"]*'
  # Four constructs, all of them a directive the `Skill` tool can no longer
  # satisfy. The last one — "via the `X` skill" — is the quiet one: it reads as
  # attribution but it is the only routing instruction those agent files give.
  grep -rnE "([Ii]nvoke|[Ii]nvokes|[Ii]nvoking|[Ll]aunch|[Ss]pawn)( the| a)? ?${delim}(${pat})${delim}|skill: \"(${pat})\"|(([Uu]se|[Rr]un|[Cc]all) ( the )?${delim}(${pat})${delim} skill)|((via|through) (the )?${delim}(${pat})${delim} skill)" \
    --include='*.md' "$ROOT/skills" "$ROOT/agents" \
    | grep -v 'subskill_resolve' \
    | grep -vE '[Tt]he user invokes|[Dd]oes not auto-invoke|[Dd]o not invoke|[Oo]ffer to launch' \
    | sed "s|^$ROOT/||"
}

# --- AC 1: nothing still Skill-invokes a hidden skill ------------------------

@test "no shipped doc instructs a model to Skill-invoke a hidden skill" {
  run invocation_sites
  if [ -n "$output" ]; then
    echo "Sites still telling a model to invoke a hidden skill:"
    echo "$output" | sed 's/^/    /'
    echo "Each must become a subskill_resolve.sh call."
  fi
  [ -z "$output" ]
}

@test "no invocation survives by being wrapped across a line break" {
  # The line-oriented grep above is blind to prose that wraps: `agents/sprint-watchdog.md`
  # said "use the\n`use-repo-code` skill" and read as clean. Fold each file's
  # whitespace to one line and re-ask, per file, so hard-wrapped markdown cannot
  # hide a directive that soft-wrapped markdown would have surfaced.
  local pat delim f hits=""
  pat="$(hidden_pattern)"
  delim='[`*/"]*'
  # The leading `[^"]` drops a phrase that opens with a double quote: a skill
  # quoting what the USER might say ("use the adhd skill") is documenting a
  # trigger, not issuing an instruction, and the `Skill` tool was never involved.
  while IFS= read -r f; do
    tr '\n' ' ' < "$f" \
      | grep -qE "[^\"]([Ii]nvoke|[Ii]nvoking|[Ll]aunch|[Ss]pawn|[Uu]se|[Rr]un|[Cc]all|via|through) (the |a )?${delim}(${pat})${delim} skill" \
      || continue
    tr '\n' ' ' < "$f" | grep -q 'subskill_resolve' && continue
    hits="$hits ${f#"$ROOT"/}"
  done < <(shipped_docs)
  if [ -n "$hits" ]; then
    echo "wrapped invocation prose still points at hidden skills in:$hits"
  fi
  [ -z "$hits" ]
}

@test "the invocation-site grep actually fires on a planted regression" {
  # A check that can never fail proves nothing. Plant the exact prose this
  # story removed and confirm the predicate still catches it.
  local pat delim
  pat="$(hidden_pattern)"
  delim='[`*/"]*'
  printf 'Invoke the `agent-validator` skill on the developer agent.\n' > "$TMP/planted.md"
  run grep -nE "([Ii]nvoke|[Ii]nvokes|[Ii]nvoking|[Ll]aunch|[Ss]pawn)( the| a)? ?${delim}(${pat})${delim}" "$TMP/planted.md"
  [ "$status" -eq 0 ]
}

# --- AC 3: fork skills are spawned, never read inline ------------------------

@test "every fork skill still declares MODE=agent through the resolver" {
  local s out
  for s in $FORK_SKILLS; do
    out="$(bash "$RESOLVE" --load-mode "$s")"
    case "$out" in
      "MODE=agent AGENT="*) : ;;
      *) echo "$s reports '$out', expected MODE=agent AGENT=<type>"; return 1 ;;
    esac
  done
}

@test "no call site tells a model to read a fork skill's body inline" {
  # The failure mode this guards is subtle: a well-meaning repoint that swaps
  # "invoke the use-repo-code skill" for "Read the path subskill_resolve.sh
  # prints" is WORSE than the line it replaced, because it silently moves a
  # whole repomix pack into the caller's context.
  #
  # The read has to be aimed at the SKILL ITSELF to count. "Reads an
  # agent-validator report" is a rectifier consuming output, not a caller
  # inlining a forked body, and flagging it would only teach people to mute
  # this check.
  local s hits="" line
  for s in $FORK_SKILLS; do
    while IFS= read -r line; do
      hits="$hits$line"$'\n'
    done < <(grep -rnE "[Rr]ead[^.]{0,50}\b${s}\b[^.]{0,30}(SKILL\.md|body|inline)|[Rr]ead (the )?[\`*/]*${s}[\`*/]* (skill|body|SKILL\.md)" \
               --include='*.md' "$ROOT/skills" "$ROOT/agents" \
             | grep -viE 'never|not |instead of|rather than|do not|MODE=agent' \
             | sed "s|^$ROOT/||" || true)
  done
  if [ -n "$hits" ]; then
    echo "Fork skills must be Agent-spawned, but these lines say to read them:"
    printf '%s' "$hits" | sed 's/^/    /'
  fi
  [ -z "$hits" ]
}

@test "every doc that resolves a fork skill also tells the caller to spawn it" {
  # Every doc that directs work at a fork skill must carry the spawn
  # instruction alongside it, so a reader cannot reach the name without also
  # reaching "spawn this, do not read it".
  #
  # It asserts the Agent tool is named, NOT which type — the shipped idiom is
  # "with the type its frontmatter names", deliberately, so the agent type lives
  # in exactly one place (the skill's own frontmatter) and cannot drift.
  local f s
  for f in $(grep -rlE 'subskill_resolve\.sh"? --load-mode' --include='*.md' "$ROOT/skills" "$ROOT/agents"); do
    for s in $FORK_SKILLS; do
      grep -qE "load-mode\"? $s" "$f" || continue
      grep -qE 'Agent` tool|Agent tool|`Agent`' "$f" || {
        echo "$f resolves --load-mode $s but never says to spawn via the Agent tool"
        return 1
      }
    done
  done
}

# --- AC 2: preflight still finds every sub-skill while they are all hidden ---

@test "team-sprint Phase 0 preflight probes every hidden sub-skill as present" {
  # This is the regression the resolver was built to prevent: preflight used to
  # probe \$HOME/.claude/skills only, so every plugin-installed sub-skill read
  # as missing. Hiding them all made that latent bug a sprint-stopper.
  local preflight d n
  preflight="$ROOT/skills/team-sprint/scripts/preflight_subskills.sh"
  [ -f "$preflight" ]
  for d in "$ROOT"/skills/*/; do
    n="$(basename "$d")"
    grep -q '^disable-model-invocation:[[:space:]]*true' "$d/SKILL.md" || continue
    CREWFORGE_ROOT="$ROOT" bash "$preflight" --probe-only "$n" || {
      echo "preflight reports hidden sub-skill '$n' as absent"
      return 1
    }
  done
}

# --- AC 6: every name a repointed doc resolves actually resolves -------------

@test "every skill name passed to subskill_resolve.sh in a shipped doc resolves" {
  # A repoint that names a skill the resolver cannot find is the same silent
  # mid-flow stop as the Skill-tool call it replaced, just later.
  local n bad=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    CREWFORGE_ROOT="$ROOT" bash "$RESOLVE" --probe "$n" || bad="$bad $n"
  done < <(grep -rhoE 'subskill_resolve\.sh"? (--load-mode |--probe )?[a-z0-9_-]+' \
             --include='*.md' "$ROOT/skills" "$ROOT/agents" \
           | sed -E 's/.*subskill_resolve\.sh"? (--load-mode |--probe )?//' \
           | grep -vE '^(--|$)' | sort -u)
  if [ -n "$bad" ]; then echo "unresolvable skill names in shipped docs:$bad"; fi
  [ -z "$bad" ]
}

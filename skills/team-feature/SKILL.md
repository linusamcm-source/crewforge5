---
name: team-feature
model: opus
description: Interactive feature-planning loop — repo grounding, per-decision
  divergence, user ratification, adversarially verified plan. Use on /team-feature,
  "plan this feature with me", "team feature plan", or when the user wants a feature
  plan built through questioning rather than handed down.
---

# Team Feature

You are the conductor. Parallel `Agent` tool fan-out does the autonomous work
— recon, divergence, drafting, verification — issued as direct Agent calls
(multiple Agent tool uses in one message, the same pattern adhd itself uses).
AskUserQuestion turns happen ONLY in the main loop. This skill must never run
under `context: fork`: it has an interactive grill loop and a forked subagent
has no user to ask.

The composition this skill exists to encode: **adhd manufactures the option
set and recommendation that each grill question needs.** grill-me's weakness
is single-shot recommended answers; adhd's weakness is that it converges to
an opinion nobody ratifies. Here, adhd's ★ pick becomes the recommended
AskUserQuestion option, its trap list becomes the warnings, and the user's
answers become a ratified decision ledger the plan is drafted from.

Every fan-out phase below (0, 1, 3) is parallel `Agent` tool calls followed by
a synthesis step — no separate orchestration tool, no opt-in, no script file
to write. Nothing below depends on a `Workflow` tool being present.

## Inputs

The user gives a feature description, however rough. If there is no feature
statement at all, ask for one sentence — that is the only question allowed
before Phase 0 completes. Facts come from the repo; only decisions go to the
user (grill-me's founding rule — this skill inherits it absolutely).

## Phase 0 — Ground

Before asking the user anything, build the fact base and the decision tree.
The target repo is the current working directory unless the user's feature
description names a different one. Spawn four `Agent` tool calls in
parallel — a single message containing all four Agent tool uses — one per
role below:

- **structure** — where the feature lands, module boundaries, ownership
- **patterns** — existing conventions the feature must match (error handling,
  naming, test style, DI/wiring)
- **integration** — every seam the feature touches: callers, schemas, config,
  external services
- **prior art** — anything in the repo that already half-does this

Each agent returns structured facts plus candidate decisions. Once all four
are back, synthesize them yourself (or with one more `Agent` call) into:

```
{
  facts: [{claim, evidence}],
  decisions: [{id, question, status: "open"|"closed", answer?, depends_on: []}]
}
```

**Triage aggressively.** A decision is `closed` when the repo convention or a
constraint already dictates the answer — record the answer and evidence,
never ask the user. A decision is `open` only when a senior engineer would
give multiple viable answers. The quality of this skill lives or dies on not
asking things the repo already answers.

Rank open decisions by stakes (blast radius of getting it wrong). Report the
fact sheet and decision tree to the user in one short summary before moving
on — they should see what will and won't be asked.

## Phase 1 — Diverge

Invoke the `adhd` skill now (Skill tool) so its loop, frames, and invariants
are in context — it is the single source of truth for the divergence method.
Do not restate its frame table here.

Then run adhd's own Diverge → Focus loop once per open decision, treating the
decision's question as adhd's problem P:

1. **Diverge.** Per adhd's Phase 1: spawn 5 parallel `Agent` tool calls (one
   message, 5 Agent uses), one per chosen frame, each given only the decision
   question, adhd's vantage prompt for that frame, and adhd's DIVERGENT-mode
   instruction. Branches must not see each other — that isolation comes for
   free because each is a separate `Agent` call in the same message, not a
   sequential one feeding the next.
2. **Converge + Deepen.** Per adhd's Phase 2: score and cluster the returned
   ideas, pick the shortlist, then spawn one more `Agent` call per top-3 idea
   (parallel, same message) to produce the deepened sketch.

If more than one decision is being diverged in the same pass, decision B's
divergence batch can be spawned while decision A is still in its Deepen
step — they are independent `Agent` calls, so nothing forces strictly one
decision at a time.

Honor adhd's pre-flight gate per decision: if on reflection a decision has
one canonical answer, it was mis-triaged — close it with a direct
recommendation instead of paying ~10 agent calls.

**Budget scaling.** With no token budget set, diverge only the top 2–3
decisions by stakes; remaining open decisions get a single-shot recommended
answer, labeled as such. With a `+Nk` budget, track spend against it yourself
as you go, diverging everything it covers, highest stakes first.

Output per decision: shortlist with score chips, ★ pick, traps with one-line
reasons, and the three deepened sketches.

## Phase 2 — Grill (inline)

Invoke the `grill-me` skill (Skill tool). Then walk the decision tree in
dependency order — a decision is askable only when everything in its
`depends_on` is ratified.

One AskUserQuestion per decision. Never batch. Build each question from the
Phase 1 output:

- Options = the adhd shortlist for that decision (2–4 of them).
- The ★ pick goes first, labeled "(Recommended)".
- Each option's description carries its load-bearing risk from the deepen
  sketch. Traps are disclosed in the question framing or as a described-but-
  warned option — never silently omitted, never presented clean.
- Decisions that skipped divergence get your single-shot recommendation
  first, honestly labeled as un-diverged.

**The reopen loop — this is the dynamic part.** After each answer, check the
downstream tree. If the answer invalidates a later decision's option set
(the chosen approach removes options, adds constraints, or spawns a new
decision), send that decision back to Phase 1 for a re-diverge with the new
constraint folded into the prompt. New decisions surfaced by an answer enter
the tree with correct `depends_on` edges. Tell the user when this happens —
"your pick on X reopens Y, re-diverging" — so the pacing is legible.

Record every ratification in the ledger as you go: decision, options
considered, what the user chose, their stated reasoning if any, what was
flagged as a trap.

## Phase 3 — Draft and verify

Only when every decision is ratified. Two rounds of direct `Agent` tool calls:

1. **Draft** — spawn parallel `Agent` calls (one message, one call per plan
   section: overview, design per ratified decision, task breakdown, test
   approach, risks) from the fact sheet and decision ledger. Sections must
   trace to ledger entries; nothing the user didn't ratify gets smuggled in
   as settled.
2. **Verify** — spawn parallel skeptic `Agent` calls that each check every
   repo claim in the draft against the live tree: files exist, APIs match
   their real signatures, no section contradicts a convention Phase 0
   recorded. Each skeptic is prompted to REFUTE. Loop — another parallel
   round of skeptics — until two consecutive rounds find nothing
   (loop-until-dry). Findings go back to the draft stage, not to the user.

If a verify finding invalidates a *ratified decision* (the repo contradicts
an assumption the user's choice rested on), that is not a drafting fix —
surface it inline, reopen that decision through Phase 2, and re-draft.

## Phase 4 — Deliver

Write two artifacts next to each other (ask nothing — default to
`docs/plans/<feature-slug>-1.md` and `<feature-slug>-1-decisions.md` in the
target repo, or the CWD if no docs convention exists). If the plan file
already exists, increment the numeric suffix (`-2`, `-3`, ...) until the
name is free — the digit satisfies team-sprint's validate_plan_path.sh
id-token check, and incrementing avoids clobbering earlier plans of the
same feature. The decision ledger always follows the plan's number:

1. **The plan** — the verified draft.
2. **The decision ledger** — the audit trail of every decision. This is the
   artifact that makes grill-me's "shared understanding" clause real: the
   user can see exactly what was considered, chosen, and rejected, and why.

Summarize both to the user. If the user wants the plan executed by
/team-sprint, invoke the `team-sprint-planner` skill with BOTH artifacts —
the plan file and the decision ledger — as source docs: the planner owns
story decomposition and the plan parse contract, so team-feature never
emits `## Story` headings itself. Then stop — grill-me's hard rule applies:
**do not implement anything until the user confirms the plan.** Planning
output is the deliverable of this skill; implementation is a new request.

## Anti-patterns

- **Asking a fact.** If Grep could answer it, the question is a failure.
  Phase 0 exists so Phase 2 contains only genuine decisions.
- **Skipping the grill because the ★ picks look obvious.** The ratification
  is the point. An unratified plan is adhd output with extra steps.
- **Batching questions.** grill-me is explicit: multiple questions at once is
  bewildering. One at a time, dependency order.
- **Running the grill inside a fan-out batch.** Parallel `Agent` calls cannot
  reach the user. Any AskUserQuestion belongs to the main loop, full stop.
- **Silent reopens.** Re-diverging a downstream decision without telling the
  user makes the pacing feel broken. Narrate every reopen.
- **Plan sections that outrun the ledger.** Every design statement in the
  plan traces to a ratified decision or a Phase 0 fact. Anything else is the
  model deciding for the user — the exact failure this skill exists to
  prevent.

## Cost

Phase 0 is ~4–6 agents. Phase 1 is ~10 agents per diverged decision (adhd's
own estimate). Phase 3 is ~5–10 agents plus verify rounds. A feature with
three open decisions lands around 40–50 agent calls — this is a deliberate,
session-length planning tool, not a quick-answer path. The pre-flight is the
user invoking it; don't run this shape uninvited.

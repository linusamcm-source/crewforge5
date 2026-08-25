# Phase 7 — Review

**Goal of the phase:** drive the plan to adversarial-clean, then stamp it. The
stamp is what `crewforge5:execute` checks before it will run anything, so it is a
claim about work done, not a formality.

## Who runs the review

**The reviewer is a spawned agent, not you.** `adversarial-review` is the
largest sub-skill this flow touches (~24k chars before its references), and
phase 7 arrives when this window is already carrying frames, decisions, the
audit, the impact map and the plan draft. Reading the reviewer's body here
would spend the fullest window on instructions only the reviewer needs — so it
loads in the reviewer's window instead, exactly as team-sprint's phase-2 graph
review seeds its reviewers.

The resolver still answers `MODE=inline` for this skill: inline **for whoever
reads it**, which is the spawned agent.

## Steps

1. Resolve the reviewer's body — the path, not the content:

   ```bash
   R="$(bash "${CREWFORGE5_ROOT:-.}/scripts/flow/subskill_resolve.sh" adversarial-review)"
   ```

2. Loop, one round per spawn:

   - **Spawn** a `general-purpose` agent via the `Agent` tool. Its prompt: read
     and follow the skill at `$R`; adversarially review the plan at
     `<plan_path>` against this repo; annotate each finding **into the plan
     file** as a `<!-- FINDING <id> (<severity>): <recommendation> -->` marker
     line; write one severity-tagged line per finding
     (`CRITICAL: <summary>`, `HIGH: ...`) to a findings file; return only the
     round's finding count and that file's path.
   - **Block-collect** the agent's final return. Never end a turn with a live
     child.
   - **Fold** each marker yourself: apply the recommendation into revised
     prose, delete the marker. The findings are yours to judge — a reviewer
     drafts criticism, the lead owns the plan. The loop converges only because
     markers are deleted; a plan that accumulates them ends up more comment
     than content.
   - **Decide the round exit with the gate, never by eye:**

     ```bash
     bash "$(dirname "$R")/scripts/round-gate.sh" <findings-file> <round> 6
     ```

     `continue` means **re-spawn** a fresh round over the folded plan — a fresh
     agent per round is the point: it re-reads the plan as it now stands, with
     no memory of what it meant to find. `escalate` means CRITICAL/HIGH
     findings survived the hard cap of 6 rounds, and the choice (extend, fix
     manually, or `status=user-override`) is the user's, not another round's.

3. When the gate says `done-clean` (or `stop-early` with the LOW/NIT polish
   folded), stamp the plan on its own line:

   ```markdown
   <!-- adversarial-review: status=clean rounds=<N> date=<YYYY-MM-DD> reviewer=crewforge5:plan -->
   ```

   `status=user-override` is the honest alternative when the user chooses to
   ship with a known open finding — that conversation happens **here**, with
   the user, which is why the fold-and-stamp half stays inline while the
   review half forks. Inventing `status=clean` over an unfolded finding is the
   one failure this phase exists to prevent.

## Gate

`findings_gate.sh <plan>` then a stamp grep. The findings gate fails while any
`<!-- FINDING ` marker remains, so the stamp cannot be reached with a finding
still open, and `flow_next.sh plan` re-offers phase 7 rather than advancing to
phase 8.

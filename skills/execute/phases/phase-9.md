# Phase 9 — Distil what the run learned

**Goal.** Land the lessons this sprint produced in the skills, agents and hooks that produced them — and land them without growing a single file. A sprint that only ever appends caveats converges on a rulebook nobody reads and every session pays for.

## Entry condition

Phase 8 recorded `PASS` (or skipped). The run's learnings are already in the ledger: `self-improve`'s `scripts/ledger.sh add <target> <source> <note>` is the capture channel, written during the sprint — Phase 9 distils, it does not go hunting for lessons in a transcript that has already scrolled away.

## Steps

1. **Read the ledger.** `bash "$(dirname "$(bash $ROOT/scripts/flow/subskill_resolve.sh self-improve)")/scripts/ledger.sh" count` — zero entries means there is nothing to distil. Say so and stop; an empty ledger is a clean run, not an invitation to invent improvements.
2. **Load `self-improve`.** Resolve it (`--load-mode` reports `MODE=inline`) and follow its Run section: group entries by target, one agent per target, each edit net-neutral or smaller.
3. **Pay for every lesson.** `scripts/ceiling.sh check` is the gate each agent has to pass. An agent that cannot land its lesson inside the target's byte budget returns the lesson unapplied and says so — that is a real answer, and the alternative is a file that grew.

## Gate

`bash $ROOT/scripts/flow/flow_gate.sh execute 9`, which runs `scripts/phase_gate.sh 9`:

- Ledger empty → `SKIP REASON=ledger-empty`, exit 0. The phase passes and the flow completes.
- Ledger non-empty → `ceiling.sh check` decides: within budget `PASS`, over it `FAIL REASON=ceiling-breach`, and the offending target goes back for tightening.

## Exit condition

`state.json` records phase 9 as `PASS`, and `flow_next.sh execute` prints `STATUS=DONE` — the sprint is finished, merged, drawn and distilled.

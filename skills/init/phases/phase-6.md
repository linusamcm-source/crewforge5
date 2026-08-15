# Phase 6 — Distil

Fold captured learnings back into the skills, agents and hooks they came from —
without letting any of them grow.

## Work

Load `self-improve` through the resolver (`MODE=inline`), then read the ledger:

```bash
bash "${CREWFORGE5_ROOT}/skills/self-improve/scripts/ledger.sh" list
```

Each entry names a target and a source: `hook` is a mechanically observed
failure, `user` is a lesson someone stated. They weigh differently — a hook
entry is evidence something broke, a user entry is a judgment about what should
change.

For each target with entries, distil them into the smallest edit that would have
prevented the failure, then `ledger.sh clear <target>` to archive what you
distilled.

**An empty ledger is a finished phase, not a prompt.** The failure mode of a
self-improvement pass is inventing an edit because it was asked to produce one.
With nothing captured, there is nothing to learn from: say "nothing to distil"
and move on.

## Gate

`init_gate.sh distil` — an empty ledger passes and says so. Otherwise
`ceiling.sh check` runs, and a target that grew past its recorded budget fails.
A learning loop that may only append converges on a rulebook nobody reads;
holding the budget flat forces each new lesson to be paid for by tightening
something else.

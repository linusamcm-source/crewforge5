---
name: self-improve
model: opus
description: Distil captured learnings into the skills, agents and hooks they came from, under a byte ceiling. Use on /self-improve, "apply what we learned", "update the skill from the ledger", "improve my agents"
disable-model-invocation: true
---

# Self-improve

Turns captured learnings into edits on the skill, agent, or hook that produced
them — without letting the file grow. Growth is the failure mode a learning loop
falls into by default: append a lesson, append a caveat, and a year later every
session pays for a rulebook nobody reads.

So the rule here is that **a learning must be paid for**. `scripts/ceiling.sh`
holds each target to its recorded budget. Landing a lesson means tightening
something else in the same file. Files get sharper, not longer.

## The two doors

Learnings arrive two ways, and they are weighted differently.

| Source | Written by | Means |
| --- | --- | --- |
| `hook` | `hooks/learn-capture.sh`, automatically | a script this config owns reported a failure — evidence something broke |
| `user` | `/learn <target> "<note>"` | someone judged that a target should behave differently |

A `hook` entry is a symptom and may distil to nothing. A `user` entry is a
decision and should almost always land somewhere.

Distilling is never automatic — this skill sets `disable-model-invocation`, so
it starts only when someone types `/self-improve`. `hooks/learn-nudge.sh` is the
reminder that closes the gap: at SessionStart, once the ledger passes five
entries, it prints one line naming the targets. Below that it says nothing.

## Run

**1. Read the ledger.** `scripts/ledger.sh list [target]`, or `count` for the
size of the job. No entries for a target means nothing to do — say so and stop
rather than inventing improvements.

**2. Group by target.** Entries name a skill slug, an agent name, or `hooks`.
Several entries about the same target are usually one lesson stated three times;
distil them together, not one edit each.

**3. Distil.** For each target with entries, spawn one agent per target — this is
a `Workflow` fan-out, one target per agent, since targets never touch each
other's files. Give each agent:

- the target's file and its ledger entries
- the instruction that the edit must be **net-neutral or smaller**, and that
  `scripts/ceiling.sh check <target>` is the gate it has to pass
- the reminder that detail belongs in `references/` with a citation from the
  body, not inline

An agent that cannot land its lesson within budget should say so and return the
lesson unapplied. That is a real answer — the alternative is a file that grew.

**4. Gate.** `scripts/ceiling.sh check` over every touched target. On a breach,
hand the failure back to that target's agent to tighten and retry. Two failed
attempts on the same target means the lesson genuinely needs more room: stop,
and put the `ceiling.sh record <target>` decision to the user with the diff.

**5. Validate.** Skills go through `skill-validator`, agents through
`agent-validator`; both have bounded rectifier loops (grade A, a 5-round cap, or
escalation). This step is where a distillation that broke structure gets caught.
Two outcomes need handling, not hope: if the rectifier **escalated** without
grade A, revert that target's distillation and return the lesson unapplied with
the escalation report; if the rectifier **edited** the target, re-run Step 4's
`ceiling.sh check` over it — a fix that regrew the file past its ceiling goes
back to Step 4's tighten-or-record path.

**6. Archive.** `scripts/ledger.sh clear <target>` — but only for targets whose
distillation survived Steps 4-5. A reverted target keeps its ledger entries; the
evidence that motivated a failed distillation is exactly what the next attempt
needs. Archiving moves entries to `ledger/archive/` rather than deleting them.

## Budgets

`scripts/ceiling.sh report` shows budget against actual, widest overrun first.

Descriptions get **no slack at all** — they load in every session, so a reworded
description must pay for itself. Bodies get 5% or 400 characters, whichever is
larger, which is room for one lesson without a same-breath rewrite.

`scripts/ceiling.sh record <target>` moves a budget deliberately. It is the
escape hatch, and it lands in a reviewable diff — never call it to make a failing
check pass.

Both scripts are covered by `scripts/tests/self-improve.bats`; run it after
editing either.

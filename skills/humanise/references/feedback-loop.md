# Feedback loop (returns dock)

The diff between what the skill delivered and what the user actually shipped is the highest-signal training data available. `scripts/deliver.sh` and `scripts/feedback.sh` capture it; this file says how to use it.

Data lives in `$HUMANISE_DATA` (default `~/.claude/humanise-data/`): `deliveries/`, `returns/`, `corrections/`.

## Capture channels

1. **Same-session**: every rewrite is logged via `deliver.sh` at Step 8. If the user edits the result before the session moves on ("shorter", hand-edit, re-run), run `feedback.sh capture <scenario> <edited-file>` and read the diff.
2. **Explicit**: the user says "humanise feedback" / "here's what I actually sent" and pastes or points at the shipped version. Same capture call.

## Distilling a correction

Read the captured diff and compress it to ONE line describing the recurring preference, not the document-specific edit:

- Good: "deletes closing summary lines", "cuts PR descriptions ~40%", "changes 'Hi' to 'Hey'"
- Bad: "removed the paragraph about Q2 numbers" (document-specific — do not log it)

Log with `feedback.sh log <scenario> "<correction>"`. First sighting stays a **candidate**; the script promotes to **APPLIED** on the second occurrence (two-strike rule — one diff might be document-specific, a corrupted correction file degrades output worse than no learning).

## Applying corrections

At Step 1 of every rewrite, run `feedback.sh corrections <scenario>` and apply every APPLIED line. Then always end the delivery with a transparency footer so a bad rule dies the moment it fires:

> applied corrections: no closing summary, -40% length

User vetoes a correction → delete its row from `corrections/<scenario>.tsv`.

## Graduation

A correction that shows up in three or more different scenario packs isn't register — it's voice. Propose (ask, don't act) adding it to the voice profile itself.

Keep each scenario's correction file under ~15 active rows; stale rows the user never re-triggers can be pruned when the file grows past that.

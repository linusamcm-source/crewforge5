---
name: email-triage
model: haiku
description: Triage a Gmail inbox and prepare (never send) replies — categorise, rank, label, and draft for review. Use when the user says "triage my inbox", "what needs a reply", "what's urgent in my inbox", or "draft a reply to X". Read-and-draft only; NEVER sends.
---

# Email Triage

Turn an inbox into a short, ranked action list — and get replies drafted and waiting — without
ever sending anything. Sending is the user's call, every time.

## When to use

Groups threads by what they need, surfaces what's urgent or waiting on you, optionally applies
labels, and drafts replies for your review. Also trigger on "go through my email", "summarise my
unread", "label these threads", or "clear out my inbox". Read-and-draft only — it categorises,
labels, and writes drafts, but NEVER sends. Pairs with humanise to put drafts in the user's own
voice before they send. Uses the Gmail MCP (search_threads, get_thread, label_*, create_draft).

## Hard boundary

- **Never send.** Draft only (`create_draft` / `update_draft`). The user reviews and sends.
- **Never delete or archive** without an explicit, specific instruction naming the threads.
- **Labelling is fine** (internal, reversible). Bulk label changes: show the plan and the count
  first, then apply.
- Treat inbox contents as private (per SOUL.md). Don't echo full message bodies into any external
  surface; summarise.

## The triage pass

1. **Pull the working set.** `mcp__claude_ai_Gmail__search_threads` — default to actionable,
   recent mail: `in:inbox is:unread newer_than:7d` unless the user scopes it differently
   ("from my boss", "about the invoice", "last 24h"). Don't page the entire mailbox; cap at a
   sensible window and say what you capped.
2. **Read enough to classify.** `get_thread` for each candidate. Read the latest message and
   enough of the thread to know what it wants. Don't over-fetch old threads that are clearly done.
3. **Categorise every thread** into exactly one bucket:
   - **Needs a reply from you** — someone is waiting. The primary bucket.
   - **Needs an action (not a reply)** — a task, a decision, something to file/pay/schedule.
   - **Waiting on someone else** — you replied; ball is in their court. Track, don't act.
   - **FYI / no action** — read and move on.
   - **Noise** — newsletters, notifications, receipts. Candidate for a label/filter, not a reply.
4. **Rank by urgency × importance.** Signals: explicit deadlines, direct questions to the user,
   named senders the user flags as important, thread age with the user as last-awaited party.
5. **Report** (see format). Then offer the next step, don't assume it.

## Output

```
## Inbox triage — <scope>, <N> threads

### Needs a reply (ranked)
1. **<subject>** — <sender> · <age> · <one-line what they want / deadline>
2. ...

### Needs an action
- **<subject>** — <what to do>

### Waiting on others
- **<subject>** — waiting on <who> since <when>

### FYI / noise
- <count> newsletters/notifications (offer to label)
```

Keep each line to one sentence. The point is a scannable list, not a re-read of the inbox.

## Drafting replies

Only when the user asks (or after they pick threads from the triage list):

- One `create_draft` per thread, replying in-thread (thread the reply, don't start a new subject).
- Match the incoming register — a terse internal thread gets a terse reply; a client email gets a
  fuller one. Don't pad.
- **Leave anything you're guessing as a bracketed placeholder** — `[confirm the date]`,
  `[amount?]`. Never invent facts, commitments, dates, or numbers on the user's behalf.
- For anything client-facing or high-stakes, hand the draft to **`humanise`** so it lands in the
  user's own voice before they send.
- Present each draft inline for review and say plainly: drafts are saved, nothing is sent.

## Labelling

When the user wants inbox hygiene: propose a small label scheme (e.g. `@reply`, `@waiting`,
`@fyi`), show which threads would get which label and the counts, and apply with
`label_thread` only after they confirm. Create missing labels with `create_label`. Use the
sensitive-label tools for anything flagged private.

## Staying useful

End the pass with the single highest-value next action ("Draft replies to the top 3?" /
"Want me to label the 12 newsletters?") — one offer, not a menu. The user decides what,
if anything, gets sent.

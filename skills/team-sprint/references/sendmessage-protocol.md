**WHO READS THIS / WHEN:** Every agent that spawns a child or reports a result reads this — spawners (team-lead, node executors) before collecting a child; children (test-writers, engineers, reviewers, fleet auditors) before delivering. sprint-watchdog reads it at Phase 5 step 1 to verify delivery (artifact-based for reviewers — see "Reviewer delivery" below); team-lead reads it when adjudicating a "no findings delivered" complaint.

This document is the canonical agent-communication contract for the team-sprint skill. The user-global `~/.claude/CLAUDE.md` may carry similar rules but is not authoritative for this skill.

### Two channels — final agent return is the default; SendMessage crosses an un-spawned layer

Every result travels exactly one of two channels, chosen by **who spawned the sender**:

1. **Final agent return — DEFAULT (child → its direct spawner).** A child delivers its result as the final response of its task; its direct spawner reads that return. This is the channel for **every reviewer and every direct child in both scheduling modes** — the Phase 3 test-writer and engineer, the Phase 4/5 AC reviewer and `ui-validator`, the Phase 2 graph reviewer, and the Phase 7 fleet reviewers (all lead-spawned direct children). No `SendMessage` is used or needed: the spawner IS the parent and collects the return directly, and the spawner persists the findings to `$ART/reviews-<story-id>-round-<N>.md` as the durable audit record.
2. **SendMessage — EXCEPTION (sender → an ancestor it did NOT spawn through).** When the recipient is not the sender's direct spawner, a final return cannot reach it, so `SendMessage` to the lead (canonically `team-lead`, verified or injected at spawn time — see "Recipient resolution" below) is mandatory. Exactly one sender qualifies: the graph-mode **node executor** (one `done`/`failed`, its last action, crossing the node boundary). Its inline-only description — however thorough — does not satisfy this: the lead's resume logic scans the message log, not the transcript body, and an undelivered `done`/`failed` signal causes silent regressions on resume.

The agent tree and its channels:

```
team-lead
├─ Phase 2 graph reviewer ······· final return → team-lead
├─ Phase 7 fleet reviewer ······· final return → team-lead
└─ node executor (graph mode) ··· SendMessage → team-lead   (one done/failed, crosses node boundary)
   ├─ test-writer (RED) ········· final return → executor
   ├─ engineer  (GREEN) ········· final return → executor
   └─ AC reviewer / ui-validator  final return → executor
```

Under `scheduling: sequential` the node-executor layer collapses into the lead: the lead spawns test-writer / engineer / reviewer directly and each returns to the lead — still channel 1, no `SendMessage`.

### The spawner's duty — block, collect, close (D1)

`Agent` spawns are async: a spawner that ends its turn with a live child is never auto-resumed and sleeps forever. After every spawn the spawner MUST:

1. **Block until the child is terminal** — `TaskOutput` (blocking read) or a `Monitor`/poll loop. If it cannot block, it must not spawn — do the work inline.
2. **Collect and verify the return** — for an implementation task, confirm the claimed source file exists on disk; never accept a task as done on passing/failing tests alone.
3. **Advance and close the child's task. The spawner owns task closure, not the child.** A child that finishes its work, delivers its return, then finds "no task to close" or sits idle is a *spawner* bookkeeping bug — the child surfaces it in its return; the spawner opens/closes the task. Neither side stalls silently.

### Call shape

`SendMessage` accepts exactly three fields:

- `to` — teammate name. Inside team-sprint the only *required* SendMessage is the graph-mode node executor's `done`/`failed` signal to `team-lead` (channel 2 — see "Where SendMessage applies"). Reviewers deliver by final return and set no `to`; a reviewer that additionally sends a belt-and-braces copy (optional) also targets `team-lead`.
- `message` — string body of the report. Embed the task id and the story id inside this string; there is no separate `taskId` / `recipient` / `content` / `metadata` field.
- `summary` — 5–10 word UI preview, required whenever `message` is a string.

**`message` must be a plain string.** The only non-string shapes the schema accepts are three control-protocol objects (`shutdown_request`, `shutdown_response`, `plan_approval_response`) — a findings payload is not one of them. Passing a findings JSON object directly as `message` fails schema validation with `Invalid tool parameters`. When a findings payload does travel over SendMessage (the optional belt-and-braces copy), stringify it:

```json
{
  "to": "team-lead",
  "message": "{\"reviewer\":\"performance\",\"task\":\"<task-id>\",\"story\":\"<story-id>\",\"findings\":[...]}",
  "summary": "perf review: 3 findings, 1 HIGH"
}
```

The three ways this call fails validation, all producing `Invalid tool parameters`:

1. `message` is a raw JSON object instead of a stringified one.
2. `summary` omitted while `message` is a string.
3. Legacy field names — `recipient`, `content`, `metadata` — instead of `to` / `message` / `summary`.

On that error the message was **not** delivered. Do not mark the task complete; rebuild the call in the correct shape and resend.

### Post-delivery verification

After every `SendMessage` call, inspect the returned tool result. "No error thrown" is not the same as "message accepted" — a transport-level success can still produce an empty receipt. If the receipt does not confirm delivery, treat the message as undelivered and resend before marking the task complete.

### Where SendMessage applies inside team-sprint

The SendMessage protocol is mandatory in exactly one place:

1. **Node executors (graph mode).** Each node executor sends the lead exactly one message — `done <node-id> <sha>` or `failed <node-id> <reason>` — as the last action of its task. The `done` message references the review artifact path (`$ART/reviews-<story-id>-round-<N>.md`) so the lead can locate the audit record without scanning the executor's transcript.

   **Recipient resolution — canonical `team-lead`, verified at spawn time, injected fallback.** `team-lead` is the **canonical** recipient name. It is never assumed registered: before spawning each executor the lead verifies `team-lead` resolves to itself in the session's addressable registry. When it resolves, the executor is spawned with `<LEAD_RECIPIENT>` = `team-lead`. When the harness registered the lead under a different name instead (the surf-seer run exposed it only as `main`), the lead substitutes its actual addressable name for the `<LEAD_RECIPIENT>` placeholder in the executor's spawn prompt. The canonical name is used whenever it resolves; the injected identity is a fallback only. Either way the executor addresses a name known to be present in the registry, so the `done`/`failed` signal cannot fail to route (`references/phases/phase-execute.md`, step 3 → "Lead-recipient resolution").

Every reviewer — Phase 2 graph, Phase 4/5 AC, and the Phase 7 pre-commit fleet — is governed by the deliver-to-spawner contract below (final agent return + persisted artifact), not by SendMessage. All Phase 7 fleet reviewers are lead-spawned direct children, so their final return reaches `team-lead` with no boundary to cross. A lead-spawned reviewer that happens to carry SendMessage MAY send a belt-and-braces copy to `team-lead`, but its absence is never a stop condition.

### Reviewer delivery — deliver-to-spawner (all reviewer phases)

Every reviewer — Phase 2 graph, Phase 4/5 AC, and the Phase 7 pre-commit fleet — delivers its findings as the structured JSON payload (`references/phases/phase-4.md` step 5 shape) in its **final agent return** to its spawner. The spawner persists the aggregate to `$ART/reviews-<story-id>-round-<N>.md` (story-keyed — parallel executors and successive stories never collide) and is responsible for onward relay. Phase 2/7 reviewers are spawned directly by `team-lead`, so their spawner and `team-lead` are the same agent; the Phase 4/5 rows below show the story-level executor case:

| Mode | Spawner | Reviewer delivers | Spawner persists | Onward relay |
|------|---------|-------------------|------------------|--------------|
| sequential | team-lead | final agent return (JSON findings) | `$ART/reviews-<story-id>-round-<N>.md` | none needed — the lead is the aggregation point; persistence alone satisfies the contract |
| graph | node executor | final agent return (JSON findings) | `$ART/reviews-<story-id>-round-<N>.md` | the executor's single `done`/`failed` SendMessage references the artifact path |

- **The artifact is the audit record.** sprint-watchdog verifies reviewer delivery by artifact existence + per-AC checklist presence — NOT by scanning the message log for reviewer-originated messages. This supersedes the earlier message-log-only doctrine.
- **Works with SendMessage-less reviewers by construction.** The crew-resolved `code-reviewer` agent type carries only Read/Write/Edit/Bash/Glob/Grep — no SendMessage — and needs no relay workaround: its final return IS the delivery.
- Lead-spawned reviewers that DO have SendMessage may additionally send the stringified payload to `team-lead` (belt-and-braces, not required).

### Failure mode

For any reviewer (Phase 2/4/5/7), `SendMessage` being unavailable in its tool set is NOT a stop condition — final-return delivery is the contract; finish the task by returning the findings payload. For the one mandatory sender above (the graph-mode node executor), a missing `SendMessage` tool must be surfaced immediately — do not complete work that cannot be delivered. Per the skill's anti-fabrication rules, a review whose findings never reached the persisted artifact is functionally equivalent to no review at all, regardless of how thorough the inline write-up was.

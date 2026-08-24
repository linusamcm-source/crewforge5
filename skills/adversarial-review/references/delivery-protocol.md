## Delivery Protocol (when invoked as a sprint teammate)

The delivery channel is chosen by **who spawned you** (`$REF/sendmessage-protocol.md`, two-channel model — the session team is implicit; the `team_name` parameter is deprecated and ignored, so do not wait for one):

- **`/team-sprint-planner` chunk reviewer or `/team-sprint` Phase 2 graph reviewer — the only orchestrator-teammate cases for this skill.** Your direct spawner is the orchestrating lead (the planner session for chunk reviews, `team-lead` for graph reviews), so deliver by **final agent return**: the structured report (the fenced `json adversarial-summary` block in chunked mode) in your final response IS the delivery. Do **not** SendMessage — there is no boundary to cross (matches team-sprint's `references/sendmessage-protocol.md` channel 1, the planner's `references/adversarial-review-loop.md`, and team-sprint's `references/phases/phase-2.md` step 5). The lead blocks on your task and reads your return directly, then closes the task itself.
- **Genuine cross-boundary sender** (recipient is not your direct spawner). Only then is a SendMessage-before-complete required. Among team-sprint roles this is the graph-mode node executor alone — never an adversarial-review invocation. Use the schema below only if you are ever spawned in such a role.

Workflow (final-return case — the normal one):

1. `TaskGet({ taskId })` — read current state and confirm ownership. Ownership and status drift across parallel agents; read before writing.
2. `TaskUpdate({ taskId, status: "in_progress" })`.
3. Conduct review (Steps 1–5 above, plus chunked contract if applicable).
4. Return the full structured report (task ID + severity-tagged findings, plus the JSON tail block verbatim if in chunked mode) as your **final agent response**. The spawner reads it and closes your task — task closure belongs to the spawner, not you.

SendMessage schema (cross-boundary case only): `SendMessage({ to: "team-lead", summary: "Spec review <id>: PASS|FAIL|NEEDS_FIXES", message: "<full structured report — include the task ID>" })` — `to` is the teammate name (not `recipient`), the body parameter is `message` (not `content`), `summary` is required when `message` is a string, and there is no `metadata` field (embed the task ID inside `message`). Inspect the returned tool result to confirm delivery before proceeding.

A correctly final-returned chunk or graph review **is** delivered — it is not treated as incomplete. Only findings that reach neither the final return nor a persisted artifact are undelivered; that is what the watchdog reopens.


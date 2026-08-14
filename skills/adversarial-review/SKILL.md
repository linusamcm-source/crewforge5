---
name: adversarial-review
model: opus
description: Use when asked to "review", "audit", "stress-test", "find holes in", "adversarially review", or "validate" a plan/story/spec/ADR/PRD/design doc, or "is this plan solid" — runs review rounds against the current codebase to catch contradictions, drift, and missing edge cases before implementation.
---

# Adversarial Review

## TL;DR — Three Non-Negotiables

1. **First response = real `tool_use` block** — full rules:
   § First Action Requirement.
2. **Every codebase claim is backed by an in-session tool call** — per
   CLAUDE.md "Evidence rules for review and audit roles" (skill deltas:
   § Evidence Rules).
3. **Orchestrator teammate? Deliver your report to your direct spawner via final
   agent return.** For `/team-sprint-planner` chunk reviews the spawner is the
   planner lead; for `/team-sprint` Phase 2 graph reviews it is `team-lead` —
   either way the structured report (the fenced
   `json adversarial-summary` block in chunked mode) in your final return IS the
   delivery; no `SendMessage` is used or required. A review that reaches neither
   the final return nor a persisted artifact = task incomplete. (Full flow:
   § Delivery Protocol.)

## Why This Skill Exists

Plans, stories, ADRs, and tech specs that look polished often contain
contradictions with the current codebase, hidden ambiguities, missing edge
cases, and impossible requirements. Catching these costs minutes during review
and days during implementation. Past sprints have hit 60+ findings across 6
review rounds on single plan documents, and several review rounds resulted in
HIGH-severity issues being caught before code ever shipped.

This skill formalises that loop:

1. Read the target document.
2. Validate every concrete claim against the **current codebase** using the
   `use-repo-code` skill (Repomix snapshot grep) plus live `Read`/`Grep`.
3. Produce a severity-ranked findings list with file:line evidence.
4. Apply surgical edits that resolve findings.
5. Re-read and repeat until the doc reaches zero blocking findings or a hard
   round cap, then report the version bump and any remaining open questions.

The output is a doc that is grounded in code reality, not a doc that merely
sounds coherent.

## Intake gate — ask before reviewing

Before starting round 1, if not already clear from the invocation, call **AskUserQuestion** to confirm depth and disposition. Skip this gate entirely when running as a `/team-sprint-planner` chunk reviewer or `/team-sprint` Phase 2 graph reviewer — depth and delivery are fixed by the orchestrator. Otherwise ask only the open questions.

- **Depth** — How many review rounds? Options: `Single pass — findings, no loop` / `Loop until zero blocking findings (cap 3) (Recommended)` / `Exhaustive — hard cap 6 rounds`.
- **On findings** — What should I do with findings? Options: `Apply surgical edits in place (Recommended)` / `Report only, leave the doc untouched`.

Honour the chosen depth as the round cap and the chosen action for whether edits are written.

## When To Use

Trigger on any of:

- Pre-implementation review of plans, stories, ADRs, PRDs, tech specs,
  design docs, sprint plans, execution plans
- "v2/v3/next round" — continuing an in-flight review
- User shares a doc and asks if it is "solid", "ready", "grounded in code",
  or "complete" — "is this ready to implement", "any issues with this",
  "what am I missing in", "before I start coding this",
  "is this grounded in the code"
- Drift checks: "does this still match the code?", "does this match the codebase"
- Any explicit /adversarial-review invocation

Default to triggering on planning-artifact reviews — this is the team's
go-to gate before implementation.

Do **not** use for:

- Code reviews of diffs (use `/review` or `pre-commit-review-fleet`)
- Subjective writing/copy review (different skill)
- Brand-new exploratory ideation where the doc is a sketch (premature)

## How To Run A Round

### Step 1 — Read The Target Document Fully

Read the entire doc first, top to bottom. Do not skim. Build a mental
list of every concrete claim:

- File paths mentioned (`src/foo/bar.ts`)
- Function/symbol names (`useCanvasStore`, `reviewRepository.upsert`)
- API shapes / type signatures
- MMKV keys, env vars, feature flags, route names
- Library names + versions
- Behavioural claims ("the X store already supports Y")
- Acceptance criteria, test counts, performance numbers

Each claim is a hypothesis. The next step verifies it.

### Step 2a — Assumption Inversion (run BEFORE claim validation)

Claim validation is structurally blind to **unstated premises**. A plan that never
claims anything false can still be built entirely on assumptions no one checked.
Every high-severity miss in the `spot-paywall-SP1` post-mortem was of this shape:
the plan never claimed `pre_token.py` could mint `trial` — it never asked what
produces `custom:tier` at all.

So before validating what the document says, enumerate what it **depends on**:

```markdown
### Assumption Inversion

| Input this story CONSUMES | Who PRODUCES it | Can the producer emit the assumed value? | Evidence |
|---|---|---|---|
| `custom:tier == "trial"` | `services/lambdas/auth/pre_token.py` | **NO** — returns TIER_FREE when no PROFILE row; a trial user has none | pre_token.py:77 |
```

Rules:

1. Enumerate every input the story's correctness depends on — claims, headers, env
   vars, DB attributes, config values, token types — **not just the ones the plan
   mentions.** The inputs the plan forgot are the ones that bite.
2. Name the **producing** component by file path. `Unknown` is a finding, not a
   blank cell.
3. Verify the producer can actually emit the assumed value. A producer in another
   language or another repository **must still be checked** — see cross-repo
   evidence below.
4. Any row where the producer cannot emit the assumed value is **CRITICAL by
   default**.
5. **You may add boundaries the plan never listed.** A `Boundaries:` section is
   authored by the same person whose blind spot produced the gap; treat it as a
   floor, never a ceiling. A boundary you discover and the plan omitted is itself
   a finding.

**Cost control.** The table is mandatory in **round 1**. In later rounds, redo a
story's table only if that story's text changed, or if a prior round's finding
touched one of its rows — otherwise carry it forward unchanged and say so. The
table is largely idempotent across rounds; regenerating it every round burns
budget without adding signal.

### Step 2b — Deployment Reality

Three questions per story. Each needs a **file:line citation**:

| Q | Question | Catches |
|---|---|---|
| Q1 | Which environments actually run this code path? *(cite the infra/env config)* | a fix wired inside `env != "dev"` when dev is the only env running the handler |
| Q2 | What does the real caller actually send — token type, headers, auth scheme? *(cite the client call site)* | middleware that 401s because the app sends an **id** token and the middleware accepts **access** |
| Q3 | Which deployable unit receives this config, and which do not? *(cite the env block)* | an env var in `sharedEnv` that `os.Exit(1)`s two unrelated Lambdas at boot |

A story that cannot answer all three does not exit Phase 1.

**`N/A` is permitted, but it is a claim and needs the same citation.** A pure
internal refactor may genuinely have no deployment dimension — write
`N/A — no env-gated path; handler registered unconditionally at server.go:88`.
A bare `N/A` is a blank and fails the gate. This escape exists so the gate cannot
force a reviewer to invent an env citation to get past it; fabricating evidence to
satisfy a gate is worse than the gap the gate was protecting against.

**Cross-repo evidence is legitimate.** The repomix pack is repo-root-scoped, so a
companion repository is *physically unreachable* through it no matter how diligent
the reviewer. Read those paths live with `Read`/`Grep` using absolute paths —
`~/Development/surf-seer/src/...` is valid review evidence, and Q2 usually cannot
be answered without it. Read-only, and only paths the plan's `Boundaries:` section
names or that Step 2a identifies as producers; this is not licence to roam the
filesystem.

### Step 2 — Validate Each Claim Against The Codebase

Use the `use-repo-code` skill for **bulk searches** across the whole tree
(find all callers, locate a symbol, scan for a pattern) — it owns the repomix
pack mechanics and the explicit `rtk grep` search form (see also CLAUDE.md
Tier 1). One pack grep replaces 10+ live `Read` calls.

**Pack freshness is mode-aware:**

- **Standalone (whole-doc) mode** — the pack must be fresh for round 1, no
  exceptions: `rm -f "${REPOMIX_PACK:-.repomix-output.xml}"` before the first
  sweep so `use-repo-code`'s Step 1 rebuilds it. Same rule as
  `team-sprint-planner` recon — a finding grounded on a stale pack is itself
  drift.
- **Chunked (`/team-sprint-planner` review loop) mode** — do **NOT** delete or
  regenerate the pack. Parallel chunk reviewers share the loop-start pack so all
  findings cite the same snapshot; deleting it mid-review races the other chunks.
  Mtime-check it instead (§ Evidence Rules) and fall back to live
  `Read`/`Grep` if stale.

Freshness checks are mechanical — never eyeball mtimes:

```bash
bash ~/.claude/skills/adversarial-review/scripts/evidence-fresh.sh \
  "${REPOMIX_PACK:-.repomix-output.xml}" <plan-file>   # exit 1 = stale, quote its output
```

Pack search syntax, `rtk grep` flags, and no-rtk fallbacks: see the
`use-repo-code` skill — do not restate them here.

**For relationship and coupling claims, use `graphify` when a graph exists.** Grep is good
at "does this string occur"; it is poor at "what calls this", "what reaches this", and "is A
coupled to B" — which is exactly where plans drift ("the X store already supports Y", "removing
Z is safe, nothing depends on it", "this respects the existing layering invariant"). When
`graphify-out/graph.json` exists in the repo root (under `/team-sprint`, Phase 0 builds it before
this skill is spawned), query the knowledge graph instead of guessing from greps:

```
graphify query "what calls reviewRepository.upsert"   # callers / reachability
graphify path "CanvasStore" "Database"                # is there real coupling A→B?
graphify explain "useCanvasStore"                      # plain-language node summary
```

Each result reports a `source_location`; cite it as your evidence exactly like a file:line.
graphify **augments** grep — it does not replace it. Use grep for exact text/occurrence; use
graphify to verify the architecture/dependency claims grep answers badly. If no graph exists,
fall back to live `Grep` for caller enumeration (and triple-verify any "nothing depends on X"
negative — see § Evidence Rules).

**For decision, history, and convention claims, consult `claude-mem`.** Three complementary
sources back a review: **repomix + `rtk grep` / `rtk rg` (token-filtered, via `use-repo-code`)** — the default text instrument — for exact text, **graphify** for current structure and
coupling, **claude-mem** for what the project already decided/fixed/discovered. A plan that says
"we standardised on X" or "this is the established pattern" is a *history* claim — verify it against
recorded memory (`mem-search` skill, or `memory_search`/`observation_search` + `get_observations`),
not just grep. See § Working With `claude-mem` for the recall/record workflow and the rule that
memory grounds intent, never current code.

Use **live `Read`/`Grep`** instead of the snapshot when:

- The doc references code you are about to edit
- Code was changed in this branch since the snapshot
- You hit a contradiction and need to confirm the live tree wins

The hard rule from `use-repo-code`: **if the snapshot disagrees with the live
tree, the live tree wins.** Note the staleness in your findings if relevant.

### Step 3 — Categorise Findings By Severity

Each finding gets a severity tag:

- **CRITICAL** — Plan describes code that does not exist, contradicts itself,
  or makes an architecture decision that breaks an existing invariant.
  Implementation cannot proceed without resolving.
- **HIGH** — Missing acceptance criterion, missing edge case that will hit
  production, security or data-integrity gap, plan promises behaviour the
  code cannot deliver as written.
- **MEDIUM** — Ambiguity that two engineers would resolve differently,
  unclear ownership of a step, missing test coverage for a stated AC.
- **LOW** — Wording, naming, organisation, redundant sections.
- **NIT** — Pure polish.

Each finding includes:

- Claim from the doc (verbatim quote or paraphrase + section heading)
- Evidence from the codebase (file:line or snapshot grep result)
- Why it is a finding (the gap, contradiction, or risk)
- Proposed resolution

Without evidence the finding is opinion, not a finding.

### Step 4 — Apply Surgical Edits

> **Mode-aware:** In chunked-invocation mode (`/team-sprint-planner`'s review
> loop or any orchestrator that splits a plan into reviewer batches), **skip this step** —
> emit findings in the JSON tail block instead (see § Return Contract for
> Chunked Invocation) and let the orchestrator apply them. This step is
> whole-doc mode only.
>
> **Detecting which mode you are in:** you are in **chunked mode** if you were
> handed a single story (or a labelled chunk like `3-of-6`) rather than the whole
> document, OR the spawn prompt asks for the `adversarial-summary` JSON tail.
> Otherwise you are in **whole-doc mode** — apply edits here and emit the prose
> round summary. When unsure, default to whole-doc (edit + prose); a missing JSON
> tail is recoverable, an unwanted edit to an orchestrator's chunk is not.

Resolve findings in place via `Edit`. Prefer minimal precise patches over
large rewrites — the user has invested in the doc's structure. For each
applied edit, note in your running summary:

- Which finding it resolved
- Severity
- One-line description of the change

If a finding cannot be resolved by editing the doc (e.g. it surfaces an
unresolved product decision), record it under **Open Questions** at the end
of the doc rather than silently dropping it.

### Step 5 — Re-Read And Decide On Next Round

After edits, re-read the doc top to bottom with fresh eyes. Ask:

- Did the edits introduce new contradictions?
- Are CRITICAL/HIGH findings actually resolved or just papered over?
- Has any new claim been added that needs verification?

If new findings appear, run another round. Otherwise, finish.

## Round Discipline

- **Default cap: 6 rounds.** If you are still finding CRITICAL/HIGH issues
  at round 6, that is a signal to escalate to the user — the doc may need
  a structural rewrite, not more patches.
- **Bump the doc version** at the top of the file each round
  (`v1 → v2 → ... → v5`).
- **The round-exit decision is mechanical, not yours.** Write each round's
  findings one per line (`CRITICAL: ...` / `HIGH: ...` / `MEDIUM: ...` /
  `LOW: ...` / `NIT: ...`) to a scratch file and run
  `bash ~/.claude/skills/adversarial-review/scripts/round-gate.sh <file>`.
  Honour its verdict: `continue` = another round; `stop-early` = zero
  CRITICAL/HIGH, batch remaining LOW/NIT into a final polish pass;
  `done-clean` = finish. Never talk yourself into stopping while the gate
  says `continue`, and never pad rounds after it says `stop-early`.

Each round ends with a conversation summary block — template in [references/output-format.md](references/output-format.md).

For instrument details when verifying claims (repomix pack via `use-repo-code`, `graphify`, `claude-mem`): load [references/verification-sources.md](references/verification-sources.md).

## Tone & Posture

Adversarial does not mean hostile. Be cynical about **the doc's claims**, not
the author. The goal is to surface real risks early so implementation goes
smoothly. Phrase findings as risks and gaps, not as criticisms.

If a doc is genuinely solid, say so and finish in one round. Padding rounds
with NIT findings to look thorough wastes everyone's time.

Running as a subagent? Confirm required tools: see [references/caller-tools.md](references/caller-tools.md).

## First Action Requirement

Your **first response MUST contain a real `tool_use` block** — invoke the Read tool on the plan path, or Bash with a grep command. The tool call is what gets executed; everything else is prose the orchestrator ignores.

The following are NOT tool calls and will collapse the review:

- A markdown code fence containing `Read /path/to/file` or `Bash: grep ...`. That is a string. No tool was invoked.
- A bracket placeholder like `[Reading plan file]`, `[Tool: Read]`, `[Tool: Bash]`, or `<gathering evidence>`. Placeholders are not invocations.
- A line like `Tool: Read` or `→ Read foo.md`. These are descriptions of tool calls, not the calls themselves.
- Any narrative-only response that "describes the plan" before invoking a tool. There is no plan-of-attack message. Action first.

If you cannot invoke a tool for any reason, reply with exactly `BLOCKED: <one-line reason>` and stop. Do not write a fake tool call.

A documented prior failure mode: parallel chunks emitted assistant turns containing markdown pseudo-tool-syntax (e.g. ` ```Read /path``` `, `[Reading file]`, `[Tool: Read]`), no real `tool_use` blocks, then `end_turn`. Zero verifications were performed. The entire review batch was wasted.

## Evidence Rules

Evidence rules: per CLAUDE.md "Evidence rules for review and audit roles"
(in-session tool-call-backed claims, quoted literal evidence, triple-verified
negatives, Read-verified line citations, freshness-checked snapshots,
`UNVERIFIED` marking). Violation = the entire review is invalid and gets
redone. Skill-specific deltas:

1. **Negatives are mechanised.** One call runs all three checks and renders the verdict: `bash ~/.claude/skills/adversarial-review/scripts/verify-negative.sh '<term>' [dir]` (exit 0 = confirmed absent; quote its full output as the evidence).
2. **Freshness is mechanised.** For `.repomix-output.xml`, `graphify-out/graph.json`, or any packed/derived snapshot, run `bash ~/.claude/skills/adversarial-review/scripts/evidence-fresh.sh <artifact> <spec-file>` — exit 1 = stale; refuse the artifact and demand a refresh, or fall back to direct Read/Grep. A graphify edge or `source_location` is evidence only when the graph is fresh.
3. **`UNVERIFIED` downgrades severity by one level.** Never promote unverified claims to CRITICAL/HIGH; better a caveated possible issue than a fabricated finding.
4. **`claude-mem` retrievals ARE in-session tool calls** — valid evidence for *history/intent* claims, never a substitute for verifying *current code* with Read/Grep/graphify. See "Working With `claude-mem`" in [references/verification-sources.md](references/verification-sources.md).
5. **Chunked mode:** every finding's `quoted_evidence` must be a verbatim substring of the plan, and the `json adversarial-summary` tail block must be present and well-formed — see [references/chunked-return-contract.md](references/chunked-return-contract.md).

Before delivery, run the self-audit checklist: [references/self-audit.md](references/self-audit.md).

If invoked as an orchestrator teammate (`/team-sprint-planner` chunk reviewer or `/team-sprint` Phase 2 graph reviewer): load [references/delivery-protocol.md](references/delivery-protocol.md) for the delivery workflow and SendMessage schema.

If in chunked mode: load [references/chunked-return-contract.md](references/chunked-return-contract.md) for the mandatory `json adversarial-summary` tail block and validator rules.

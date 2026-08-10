# Dynamic review workflow (per-run authoring contract)

**WHO READS THIS / WHEN:** The invoking session, when the planner's final phase says to run
plan review as a dynamic `Workflow`. You author a **concrete script per run** — plan path,
repo roots, story IDs baked in as constants — from the template below. The template is the
contract, not a saved script: adapt it, don't reference it at runtime. Replaces the retired
prose loop + `plan-review.workflow.js`.

Core inversion: **the unit of iteration is the finding, not the plan revision.** Whole-plan
re-review happens exactly twice (discovery + close-out), never once per round. Depth is fixed
at three agent-generations regardless of finding count; only width scales, and concurrent
agents are nearly free in wall-clock terms.

## Why this shape

The old loop ran 7 rounds on one real plan, grew it 19 KB → 68 KB, and exited on user
override with unverified folds. Each failure mode below is structural in the old design; do
not reintroduce any of them.

- **F1 — Unreachable exit.** Every severity gated the loop, so LOW citation nits forced full
  fleet rounds forever. → Gate on CRITICAL/HIGH only.
- **F2 — Bloat feedback loop.** Every fold added caveat prose; prose is attack surface for
  the next round. → Delete-over-caveat instruction + in-script bloat gate.
- **F3 — Byte-exact quote validation killed true findings on typography.** Em-dashes and
  path abbreviations rejected genuine CRITICALs. → Schema-forced returns, verified on
  substance; quotes are of the code, judged not substring-matched.
- **F4 — No carry-forward for rejected-but-true findings.** A rejected CRITICAL vanished
  unless independently rediscovered. → Only a refutation kills a finding; ledger dedup
  merges refilings instead of bouncing them.
- **F5 — `unknown_story_id` rejected whole-plan findings.** Cross-story seams are the
  boundary reviewer's whole remit. → `story_id: "PLAN"` is a first-class enum value.
- **F6 — skipped.json was a black hole.** A plan-deciding ambiguity died in a sidecar file
  nobody read. → Unverifiable findings become explicit AskUserQuestion items.
- **F7 — Folds were never verified.** Folds introduced new defects billed as new findings
  next round. → Per-finding fold-checker with one bounce.
- **F8 — Cap governance.** Soft cap 3, ran 7; each extension a full-fleet spend with no
  trend shown. → Hard cap 2 close-out cycles; the user ask prints severity trend and spend.
- **F9 — Terminal state incoherent.** Stamp went onto a just-folded, never re-verified
  text. → Stamp only after a dry verifying sweep; canonical file is byte-identical to it.

**What worked — keep it:** the boundary reviewer. Nearly every CRITICAL across all 7 old
rounds was a cross-repo `BND-*` finding. It keeps the Assumption-Inversion /
Deployment-Reality mandate verbatim and gets high effort plus both repo roots.

## Invariant — the provenance stamp

team-sprint's Phase 1 gates on:

```bash
grep -m1 -E '^<!-- adversarial-review: status=(clean|user-override) '
```

The workflow must therefore write exactly this line (directly under the plan's `#` title):

```
<!-- adversarial-review: status=<clean|user-override> rounds=<N> date=<YYYY-MM-DD> reviewer=team-sprint-planner -->
```

Do not change the stamp shape — that grep must keep matching, unchanged, forever.

## Schemas

Three delivery contracts, machine-enforced at the tool layer (schema validation retries
there — no `lead_validator.sh`, no substring matching).

**FINDING** — what every reviewer returns, per finding:

- `story_id`: enum of the plan's story IDs **plus `"PLAN"`** for cross-story findings (F5)
- `severity`: enum `CRITICAL | HIGH | MEDIUM | LOW | UNVERIFIED`
- `issue`: string
- `evidence`: `{ file, line, quote }` — quote of the **code**, not of the plan (F3)
- `plan_anchor`: free-text pointer into the plan — judged by the skeptic, never
  substring-matched
- `recommendation`: string

**VERDICT** — what each skeptic returns: `{ verdict: real | refuted | unverifiable,
severity_adj }` where `severity_adj` is the corrected severity (same enum). Typography
cannot kill a finding; only a refutation can.

**FOLD** — what each fold-checker returns: `{ resolved: bool }` (plus an optional note the
bounce prompt reuses).

## Script template

Copy, bake the constants, adapt the prompts to the run. Everything in `<angle brackets>` is
per-run. The script has no filesystem access — file reads/writes happen inside agents; all
control flow, parsing, dedup, and gating stay in-script.

```js
export const meta = {
  name: 'plan-review-<plan-slug>',
  description: 'Dynamic adversarial plan review — finding-scoped pipelines, whole-plan review exactly twice',
  whenToUse: 'Authored per run by the invoking session. One review, then discarded.',
  phases: [
    { title: 'Discovery', detail: 'chunk reviewers (low effort) + boundary reviewer (high effort, both repos), one parallel wave' },
    { title: 'Adjudicate', detail: 'skeptic verify-on-substance per finding; in-script ledger dedup' },
    { title: 'Apply', detail: 'minimal-edit fixer + fold-checker per gating finding; bloat gate' },
    { title: 'Close-out', detail: 'one scoped sweep; stamp only after it comes back dry' },
  ],
}

// ---- Baked per run by the authoring session. Constants, not args. ----------
const PLAN = '<abs path to plan.md>'
const REPOS = ['<abs repo root A>', '<abs repo root B>']   // both roots, always
const REVIEW = '<abs artifact dir>'                        // review-ledger.json, plan-final.md, report.md
const STORY_IDS = ['<id-1>', '<id-2>' /* … from the plan's `## Story <id>:` headings */]
const CHUNK_SIZE = 5
// Effort tiers via the agent() `effort` opt (omit `model` — agents inherit the
// session model). See tiering table in the doc.
const LOW = 'low'
const HIGH = 'high'

// ---- Schemas ---------------------------------------------------------------
const SEVERITY = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNVERIFIED']

const FINDINGS = {
  type: 'object', additionalProperties: false, required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['story_id', 'severity', 'issue', 'evidence', 'plan_anchor', 'recommendation'],
        properties: {
          story_id: { type: 'string', enum: [...STORY_IDS, 'PLAN'] },   // "PLAN" = cross-story (F5)
          severity: { type: 'string', enum: SEVERITY },
          issue: { type: 'string', minLength: 1 },
          evidence: {                                   // file:line + quote of the CODE, not the plan (F3)
            type: 'object', additionalProperties: false, required: ['file', 'line', 'quote'],
            properties: {
              file: { type: 'string', minLength: 1 },
              line: { type: 'integer', minimum: 1 },
              quote: { type: 'string', minLength: 1 },
            },
          },
          plan_anchor: { type: 'string', minLength: 1 },  // free text, judged not matched
          recommendation: { type: 'string', minLength: 1 },
        },
      },
    },
  },
}

const VERDICT = {
  type: 'object', additionalProperties: false, required: ['verdict', 'severity_adj'],
  properties: {
    verdict: { type: 'string', enum: ['real', 'refuted', 'unverifiable'] },
    severity_adj: { type: 'string', enum: SEVERITY },
  },
}

const FOLD = {
  type: 'object', additionalProperties: false, required: ['resolved'],
  properties: { resolved: { type: 'boolean' }, note: { type: 'string' } },
}

const TEXT = {
  type: 'object', additionalProperties: false, required: ['text'],
  properties: { text: { type: 'string' } },
}

// ---- Phase 1 — Discovery (parallel fan-out) --------------------------------
phase('Discovery')

const planRead = await agent(
  `Return the full raw text of ${PLAN}, verbatim, as {text}.`,
  { label: 'read-plan', phase: 'Discovery', effort: LOW, schema: TEXT })
if (!planRead) throw new Error('could not read plan')

// In-script story parsing — regex on the headings, no parse_stories.sh.
const parsedIds = [...planRead.text.matchAll(/^## Story ([^:\n]+):/gm)].map(m => m[1].trim())
if (parsedIds.join('\n') !== STORY_IDS.join('\n')) {
  throw new Error(`baked STORY_IDS drifted from plan headings: plan has [${parsedIds}]`)
}

const chunks = []
for (let i = 0; i < STORY_IDS.length; i += CHUNK_SIZE) chunks.push(STORY_IDS.slice(i, i + CHUNK_SIZE))

const boundaryPrompt =
  `Review the WHOLE plan at ${PLAN} (not a chunk) for cross-boundary defects, across BOTH ` +
  `repo roots: ${REPOS.join(' and ')}.\n\n` +
  `Produce both mandatory sections, then the findings that fall out of them:\n` +
  `  1. Assumption Inversion — every input each story's correctness depends on, the ` +
  `component that PRODUCES it by file path, and whether that producer can emit the ` +
  `assumed value. "Unknown" is a finding, not a blank.\n` +
  `  2. Deployment Reality — Q1 which environments run this, Q2 what the real caller ` +
  `sends, Q3 which deployable unit gets this config. Each needs a file:line citation; ` +
  `a cited "N/A — <reason>" is allowed, a bare "N/A" is not.\n\n` +
  `Cross-story findings use story_id "PLAN". evidence.quote is a verbatim quote of the ` +
  `CODE you read, never of the plan.`

const wave = (await parallel([
  () => agent(boundaryPrompt,
    { label: 'review:boundary', phase: 'Discovery', agentType: 'boundary-reviewer', effort: HIGH, schema: FINDINGS }),
  ...chunks.map((ids, i) => () => agent(
    `Adversarially review ONLY stories ${ids.join(', ')} in the plan at ${PLAN} against the ` +
    `code under ${REPOS.join(' and ')}. Contradictions, drift from the code as it exists, ` +
    `missing edge cases, untestable ACs. evidence = {file, line, quote} where quote is a ` +
    `verbatim quote of the CODE (not the plan); plan_anchor is a free-text pointer to the ` +
    `plan text your finding is about. A claim you cannot ground in code is severity UNVERIFIED.`,
    { label: `review:chunk-${i + 1}`, phase: 'Discovery', effort: LOW, schema: FINDINGS })),
])).filter(Boolean)

const raw = wave.flatMap(r => r.findings)
log(`discovery: ${raw.length} raw finding(s) from ${wave.length} reviewer(s)`)

// ---- Phase 2 — Adjudication (pipeline, per finding) ------------------------
phase('Adjudicate')

// Ledger dedup — in-script seen-set keyed on evidence.file + normalized issue
// hash. Duplicates merge, never refile (F4).
const norm = s => s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(Boolean).slice(0, 12).join(' ')
const key = f => `${f.evidence.file}::${norm(f.issue)}`
const ledger = new Map()
for (const f of raw) {
  const k = key(f)
  if (ledger.has(k)) ledger.get(k).duplicates.push(f)
  else ledger.set(k, { ...f, duplicates: [] })
}
const deduped = [...ledger.values()]
log(`adjudicate: ${deduped.length} after dedup (${raw.length - deduped.length} merged)`)

// Verify on substance. One skeptic per finding, prompted to REFUTE. Typography
// cannot kill a finding; only a refutation can (F3, F4).
const adjudicated = await pipeline(deduped, async f => {
  const heavy = f.severity === 'CRITICAL' || f.severity === 'HIGH'
  const v = await agent(
    `Try to REFUTE this plan-review finding by reading the cited code and the plan section ` +
    `it points at.\n\nFinding: ${JSON.stringify(f)}\nPlan: ${PLAN}  Repos: ${REPOS.join(', ')}\n\n` +
    `Read ${f.evidence.file}:${f.evidence.line} yourself and locate the plan text via the ` +
    `plan_anchor (judge it — it is a pointer, not a substring to match). Answer three ` +
    `questions: is the claim true, is the severity right, is the recommendation actionable? ` +
    `verdict "unverifiable" is for claims whose answer lives outside the source (e.g. a live ` +
    `cloud account) — not for claims you were too lazy to check.`,
    { label: `skeptic:${key(f).slice(0, 40)}`, phase: 'Adjudicate', effort: heavy ? HIGH : LOW, schema: VERDICT })
  return v ? { ...f, verdict: v.verdict, severity: v.severity_adj } : { ...f, verdict: 'unverifiable' }
})

// Unverifiable ≠ skipped (F6): collected here, delivered to the user as explicit
// AskUserQuestion items by the invoking session AFTER the workflow returns.
const unverifiable = adjudicated.filter(f => f.verdict === 'unverifiable')
const real = adjudicated.filter(f => f.verdict === 'real')
log(`adjudicate: ${real.length} real, ${adjudicated.filter(f => f.verdict === 'refuted').length} refuted, ${unverifiable.length} unverifiable`)

// ---- Phase 3 — Apply + fold-verify (pipeline, per accepted finding) --------
phase('Apply')

// Gate set = CRITICAL + HIGH only. MEDIUM/LOW are applied in the same pass but
// never gate and never trigger re-review (F1).
const gating = real.filter(f => f.severity === 'CRITICAL' || f.severity === 'HIGH')
const nonGating = real.filter(f => f.severity === 'MEDIUM' || f.severity === 'LOW')

const surfacedFolds = []   // fold-check failed twice — user decides
async function applyAndVerify(findings) {
  return pipeline(findings, async f => {
    const fix = () => agent(
      `Apply this finding's recommendation to the plan at ${PLAN} with a MINIMAL edit to ` +
      `the relevant section only. Standing instruction: prefer DELETING a wrong claim over ` +
      `adding a caveat paragraph. Never restructure beyond the finding's scope.\n\n` +
      `Finding: ${JSON.stringify({ ...f, duplicates: undefined })}`,
      { label: `fix:${key(f).slice(0, 40)}`, phase: 'Apply', effort: LOW, schema: TEXT })
    await fix()
    let check = await agent(
      `Re-read the revised section of ${PLAN} that this finding targets and judge whether ` +
      `the recommendation is actually implemented (not merely mentioned): ` +
      `${JSON.stringify({ issue: f.issue, recommendation: f.recommendation, plan_anchor: f.plan_anchor })}`,
      { label: `fold:${key(f).slice(0, 40)}`, phase: 'Apply', effort: LOW, schema: FOLD })
    if (check && !check.resolved) {        // one bounce, then surface to user (F7)
      await fix()
      check = await agent(
        `Second check, same finding, same rules — the first fold was judged unresolved ` +
        `(${check.note || 'no note'}).`,
        { label: `fold2:${key(f).slice(0, 40)}`, phase: 'Apply', effort: LOW, schema: FOLD })
    }
    const resolved = !!(check && check.resolved)
    if (!resolved) surfacedFolds.push(f)
    return { ...f, resolved }
  })
}

await applyAndVerify(gating)
await applyAndVerify(nonGating)   // applied, never gate

// Bloat gate in-script (F2): >15% growth over the original triggers a simplifier.
const sizes = await agent(
  `Run: wc -c on ${PLAN}. Also report the original pre-review byte length ` +
  `(${planRead.text.length} — computed at discovery). Return text as "<current>".`,
  { label: 'bloat-measure', phase: 'Apply', effort: LOW, schema: TEXT })
const grew = sizes && Number(sizes.text) > planRead.text.length * 1.15
if (grew) {
  log(`bloat gate: plan grew >15% (${sizes.text} vs ${planRead.text.length}) — compressing`)
  await agent(
    `The plan at ${PLAN} grew >15% during review folds. Compress it: remove caveat prose ` +
    `and redundancy WITHOUT dropping any AC, DoD item, or applied finding. Delete, don't hedge.`,
    { label: 'simplifier', phase: 'Apply', effort: HIGH, schema: TEXT })
}

// ---- Phase 4 — Close-out sweep (single scoped round) -----------------------
phase('Close-out')

const digest = [...ledger.values()].map(f =>
  `${f.severity} ${f.story_id} ${f.evidence.file}: ${f.issue.slice(0, 120)}`).join('\n')
const trend = []            // severity counts per cycle, printed in the override ask (F8)
let outcome = 'not-clean'

for (let cycle = 1; cycle <= 2; cycle += 1) {          // hard cap: 2 cycles (F8)
  const sweep = (await parallel([
    () => agent(boundaryPrompt +
      `\n\nKNOWN AND FIXED (report only NEW CRITICAL/HIGH not in this ledger digest):\n${digest}`,
      { label: `closeout:boundary-${cycle}`, phase: 'Close-out', agentType: 'boundary-reviewer', effort: HIGH, schema: FINDINGS }),
    () => agent(
      `Review the FINAL text of the whole plan at ${PLAN} against ${REPOS.join(' and ')}. ` +
      `These findings are known and fixed — report only NEW CRITICAL/HIGH:\n${digest}`,
      { label: `closeout:plan-${cycle}`, phase: 'Close-out', effort: HIGH, schema: FINDINGS }),
  ])).filter(Boolean)

  const fresh = sweep.flatMap(r => r.findings)
    .filter(f => (f.severity === 'CRITICAL' || f.severity === 'HIGH') && !ledger.has(key(f)))
  trend.push({ cycle, new_gating: fresh.length })

  if (fresh.length === 0) {
    // Dry. Stamp AFTER the verifying sweep, never on a just-folded text (F9).
    // The stamp line and its gating grep are an INVARIANT — see the doc above.
    const stamped = await agent(
      `Insert the provenance stamp on the line directly under the plan's "#" title in ${PLAN}:\n` +
      `<!-- adversarial-review: status=clean rounds=${cycle} date=$(date +%F) reviewer=team-sprint-planner -->\n` +
      `(shell out for the date; do not guess it). Verify with:\n` +
      `grep -m1 -E '^<!-- adversarial-review: status=(clean|user-override) ' "${PLAN}"\n` +
      `Then write the artifacts under ${REVIEW}/: review-ledger.json (the ledger JSON below), ` +
      `plan-final.md (byte-identical copy of the stamped ${PLAN}), report.md (run summary). ` +
      `Return the grep's matching line as {text}.\n\nLedger:\n` +
      JSON.stringify([...ledger.values()], null, 2),
      { label: 'stamp', phase: 'Close-out', effort: LOW, schema: TEXT })
    if (!stamped || !/^<!-- adversarial-review: status=clean /.test(stamped.text)) {
      outcome = 'stamp_failed'; break
    }
    outcome = 'clean'
    break
  }

  log(`close-out cycle ${cycle}: ${fresh.length} NEW gating finding(s) — one more Phase 2-3 pass for those only`)
  for (const f of fresh) ledger.set(key(f), { ...f, duplicates: [] })
  const verified = await pipeline(fresh, async f => {
    const v = await agent(`<same skeptic prompt as Phase 2>`,
      { label: `skeptic2:${key(f).slice(0, 40)}`, phase: 'Close-out', effort: HIGH, schema: VERDICT })
    return v && v.verdict === 'real' ? { ...f, severity: v.severity_adj } : null
  })
  await applyAndVerify(verified.filter(Boolean)
    .filter(f => f.severity === 'CRITICAL' || f.severity === 'HIGH'))
}

// Not dry after 2 cycles → the USER decides (override → status=user-override),
// with the trend and spend in front of them (F8). The workflow never overrides itself.
return {
  outcome,                                   // 'clean' | 'not-clean' | 'stamp_failed'
  trend,                                     // severity trend for the override ask
  spend: budget.spent(),                     // token spend for the override ask
  unverifiable,                              // → AskUserQuestion batch (F6)
  unresolved_folds: surfacedFolds,           // fold-check failed twice (F7)
  ledger: [...ledger.values()],
}
```

## After the workflow returns — the two human interrupt points

Exactly two, both batched; never ask mid-run (each ask is a dead stop of wall-clock).

1. **Unverifiable questions, once, after adjudication.** Every `unverifiable` finding in the
   return (the answer-lives-in-the-live-account class) becomes one AskUserQuestion batch.
   Blocking questions to a human, not a JSON file nobody reads (F6). Fold failures in
   `unresolved_folds` join the same batch.
2. **Override ask, only if close-out was not dry.** `outcome !== 'clean'` → present the
   severity trend and token spend from the return and ask: extend, fix manually, or accept
   and stamp `status=user-override` (same stamp line, `status=user-override`). Never stamp
   without one or the other.

## Effort tiering

Spend where the evidence says findings live — the boundary reviewer produced nearly every
CRITICAL in the old run; chunk reviewers produced churn.

| Stage | Effort |
| --- | --- |
| Discovery chunk reviewers | low |
| Boundary reviewer (discovery and close-out) | high, both repo roots |
| Skeptics for CRITICAL/HIGH findings | high |
| Skeptics for MEDIUM/LOW findings | one cheap pass (low), batch-applied, never looped |
| Fixers | low — minimal edits, small prompts, small diffs |
| Fold-checkers | low |
| Simplifier (bloat gate) | high |
| Close-out whole-plan reviewer | high |

## Artifacts

Keep the audit-trail habit, lose the sprawl. Exactly three files in the review dir:

- `review-ledger.json` — every finding with verdicts, adjudication, and fix status
- `plan-final.md` — byte-identical copy of the stamped plan
- `report.md` — run summary (trend, spend, interrupt outcomes)

No per-round findings/accepted/rejected/diff constellation — the ledger is queryable and the
workflow journal (`journal.jsonl`) already records agent returns.

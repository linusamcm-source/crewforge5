export const meta = {
  name: 'team-sprint-story-executor',
  description: 'Per-story RED->GREEN->wip-commit->verify->review->fix->coverage executor with schema-validated returns and structurally bounded iteration',
  whenToUse: 'Phases 3-5 for one story. Replaces the prose loops, whose back-edges have no iteration cap.',
  phases: [
    { title: 'Red', detail: 'test-writer writes failing tests; measurement agent verifies right-reason failure (bounded)' },
    { title: 'Green', detail: 'engineer implements to green; declared source files verified on disk (bounded)' },
    { title: 'WipCommit', detail: 'provisional wip(<story>) commit so BASE...HEAD consumers see the work' },
    { title: 'Verify', detail: 'scoped tests + typecheck + lint (bounded)' },
    { title: 'Diff', detail: 'regenerate $ART/diff-<story>.patch so the reviewer sees THIS story only, never a stale patch' },
    { title: 'Review', detail: 'AC/DoD reviewers, schema-validated findings, artifact existence checked' },
    { title: 'Fix', detail: 'one RED->GREEN pass per CRITICAL/HIGH finding' },
    { title: 'Coverage', detail: 'story-scoped coverage gate with a bounded fix loop' },
  ],
}

// ---------------------------------------------------------------------------
// Why this exists: the prose loops have back-edges with no cap anywhere.
//
//   phase-3.md:28  RED bounce when tests fail for the wrong reason — uncapped
//   phase-3.md:30  GREEN retry when declared source files are phantom — uncapped
//   phase-3.md:55  the coverage iteration cap ("After 3 ... STOP") is prose a
//                  model must remember
//   phase-4.md:34  red-test bounce to Phase 3 step 2 — "NONE STATED ... the one
//                  unbounded back-edge in the three files"
//   phase-5.md:26  reviewer re-spawn when the artifact lacks a per-AC checklist —
//                  "a reviewer that keeps returning a checklist-less artifact
//                  loops forever as written"
//   phase-5.md:30  inner RED->GREEN retries — "UNCAPPED in the doc"
//
// A prose cap is a thing a model must remember on iteration 9 at 3am. Here the
// bound is the loop header: it cannot be forgotten, and exhausting it is a
// reported outcome rather than a silent spin.
// ---------------------------------------------------------------------------

const RED = {
  type: 'object', additionalProperties: false,
  required: ['test_files', 'evidence'],
  properties: {
    test_files: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string', minLength: 1 },
  },
}

const RED_VERIFY = {
  type: 'object', additionalProperties: false,
  required: ['failing_right_reason', 'non_test_files', 'evidence'],
  properties: {
    failing_right_reason: { type: 'boolean' },
    non_test_files: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string', minLength: 1 },
  },
}

const GREEN = {
  type: 'object', additionalProperties: false,
  required: ['source_files'],
  properties: {
    // minItems 1: an implementation with zero source files is a watchdog
    // violation, not a delivery.
    source_files: { type: 'array', items: { type: 'string' }, minItems: 1 },
    evidence: { type: 'string' },
  },
}

const GREEN_VERIFY = {
  type: 'object', additionalProperties: false,
  required: ['all_exist', 'missing'],
  properties: {
    all_exist: { type: 'boolean' },
    missing: { type: 'array', items: { type: 'string' } },
  },
}

const ARTIFACT_CHECK = {
  type: 'object', additionalProperties: false,
  required: ['exists'],
  properties: { exists: { type: 'boolean' } },
}

const DIFF = {
  type: 'object', additionalProperties: false,
  required: ['patch_written'],
  properties: { patch_written: { type: 'boolean' } },
}

const VERIFY = {
  type: 'object', additionalProperties: false,
  required: ['tests_pass', 'typecheck_pass', 'lint_pass', 'evidence'],
  properties: {
    tests_pass: { type: 'boolean' },
    typecheck_pass: { type: 'boolean' },
    lint_pass: { type: 'boolean' },
    evidence: { type: 'string', minLength: 1 },
    failing: { type: 'array', items: { type: 'string' } },
  },
}

const FINDINGS = {
  type: 'object', additionalProperties: false,
  required: ['artifact_path', 'per_ac_checklist_present', 'findings'],
  properties: {
    artifact_path: { type: 'string', minLength: 1 },
    // Structural, not advisory: the prose loop re-spawned forever waiting for it.
    per_ac_checklist_present: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'severity', 'ac_id', 'issue', 'evidence', 'recommendation'],
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'UNVERIFIED'] },
          ac_id: { type: 'string' },
          issue: { type: 'string', minLength: 1 },
          evidence: { type: 'string', minLength: 1 },
          recommendation: { type: 'string', minLength: 1 },
        },
      },
    },
  },
}

const FIX = {
  type: 'object', additionalProperties: false,
  required: ['finding_id', 'resolved', 'source_files'],
  properties: {
    finding_id: { type: 'string' },
    resolved: { type: 'boolean' },
    source_files: { type: 'array', items: { type: 'string' } },
    note: { type: 'string' },
  },
}

const COVERAGE = {
  type: 'object', additionalProperties: false,
  required: ['pass', 'gate_status'],
  properties: {
    pass: { type: ['boolean', 'null'] },
    gate_status: { type: 'string' },
    pct: { type: ['number', 'null'] },
    uncovered_files: { type: 'array', items: { type: 'string' } },
  },
}

// `args` can arrive as a JSON STRING rather than an object depending on how the
// caller passes it; `args || {}` silently yields a string whose .storyId is
// undefined, so the guard below fired and the workflow could never start.
function readArgs(a) {
  if (a == null) return {}
  if (typeof a === 'object') return a
  if (typeof a === 'string') {
    try { return JSON.parse(a) } catch (e) {
      throw new Error('story-executor: args was a string but not valid JSON: ' + a.slice(0, 200))
    }
  }
  return {}
}

const cfg = readArgs(args)
const STORY = cfg.storyId
const ART = cfg.artDir
const SCRIPTS = cfg.scriptsDir
const WORKTREE = cfg.worktree || '.'
// Agent types are INJECTED, never hardcoded — the crew manifest decides them.
const TEST_WRITER = cfg.testWriterAgent
const ENGINEER = cfg.engineerAgent
const REVIEWER = cfg.reviewerAgent || 'code-reviewer'
// coverage_check.sh --mode comes from config; hardcoding 'new' broke whole-mode repos.
const COVERAGE_MODE = cfg.coverageMode
// state.sh keys off the plan path; the counter cannot be persisted without it.
const PLAN_PATH = cfg.planPath

// Every bound is explicit and overridable, but never absent.
const MAX_RED = cfg.maxRedAttempts || 2        // phase-3.md step 1 RED bounce
const MAX_GREEN = cfg.maxGreenAttempts || 2    // phase-3.md step 2 phantom-file bounce
const MAX_VERIFY = cfg.maxVerify || 3          // phase-4.md:34 back-edge
const MAX_REVIEW_RESPAWN = cfg.maxReviewRespawn || 2  // phase-5.md:26
const MAX_FIX_ROUNDS = cfg.reviewFixIterations || 3   // phase-5.md:24 (existing config)
const MAX_INNER_FIX = cfg.maxInnerFix || 2     // phase-5.md:30 inner RED->GREEN
const MAX_COVERAGE_ITERS = cfg.maxCoverageIters || 3  // phase-3.md step 5 cap

if (!STORY || !ART || !SCRIPTS || !PLAN_PATH || !TEST_WRITER || !ENGINEER || !COVERAGE_MODE) {
  throw new Error(
    'story-executor requires args {storyId, artDir, scriptsDir, planPath, ' +
    'testWriterAgent, engineerAgent, coverageMode}; got ' + JSON.stringify(cfg)
  )
}
// S1: STORY and COVERAGE_MODE are interpolated into shell command text agents
// run verbatim. STORY comes from a plan heading via parse_stories.sh, whose
// [^:\s]+ admits $(...), backticks, semicolons — a malicious plan heading is
// arbitrary command execution in the worktree without this shape guard.
if (!/^[A-Za-z0-9._-]+$/.test(STORY)) {
  throw new Error('story-executor: storyId must match ^[A-Za-z0-9._-]+$; got ' + JSON.stringify(STORY))
}
if (!/^(new|whole)$/.test(COVERAGE_MODE)) {
  throw new Error('story-executor: coverageMode must be "new" or "whole"; got ' + JSON.stringify(COVERAGE_MODE))
}

const outcome = { story: STORY, verify: null, rounds: [], coverage: null, status: 'unresolved' }

// --- Provisional wip commit -------------------------------------------------
// Called after GREEN is verified and between coverage iterations: the diff
// scripts read committed HEAD (git diff BASE...HEAD), so uncommitted work is
// invisible to the coverage gate and the Phase 4 review (D6, phase-3.md step 4).
let wipN = 0
async function wipCommit() {
  wipN += 1
  // wf:p3-wip-commit
  return agent(
    `Story ${STORY}. Land the story's work-in-progress in HEAD before any ` +
    `BASE...HEAD consumer runs. From the worktree ${WORKTREE}, run:\n` +
    // Single-quoted (S1): the shape guard bans quotes/metacharacters in STORY,
    // and single quotes stop the shell expanding anything that slips through.
    `  git add -A && git commit -m 'wip(${STORY}): phase-3 green'\n` +
    `Phase 6 squashes every wip(${STORY}) commit into the single structured ` +
    `story commit, so the one-commit-per-story invariant is unaffected.`,
    { label: `wipcommit-${wipN}`, phase: 'WipCommit' }
  )
}

// --- Phase 3 RED: bounded failing-tests loop -------------------------------
phase('Red')
let redOk = false
let redBounce = ''
for (let a = 1; a <= MAX_RED; a += 1) {
  // wf:p3-red
  const red = await agent(
    `Story ${STORY}, worktree ${WORKTREE}, plan ${PLAN_PATH}. RED phase: write ` +
    `failing tests for each acceptance criterion of THIS story only. Test files ` +
    `only — do not touch source files. Declare every test file you wrote in ` +
    `test_files and quote the failing run in evidence.` +
    (redBounce ? `\n\nPrevious attempt was rejected:\n${redBounce}` : ''),
    { label: `red-${a}`, phase: 'Red', agentType: TEST_WRITER, schema: RED }
  )
  // wf:p3-red-verify
  const redVerify = await agent(
    `Story ${STORY}, worktree ${WORKTREE}. Measurement pass — do not fix anything. ` +
    `Confirm this story's new tests fail for the right reason: the missing ` +
    `implementation, not import/collection errors. Also confirm only test files ` +
    `were written` + (red ? ` (declared: ${JSON.stringify(red.test_files)})` : '') +
    ` — declare any non-test files touched in non_test_files.`,
    { label: `redverify-${a}`, phase: 'Red', schema: RED_VERIFY }
  )
  if (redVerify && redVerify.failing_right_reason && !(redVerify.non_test_files || []).length) {
    redOk = true
    break
  }
  redBounce = redVerify
    ? `failing_right_reason=${redVerify.failing_right_reason}, non_test_files=` +
      `${JSON.stringify(redVerify.non_test_files)}. Evidence: ${redVerify.evidence}`
    : 'RED verification returned nothing.'
  log(`${STORY}: RED attempt ${a} rejected (cap ${MAX_RED}) — ${redBounce}`)
}
if (!redOk) {
  outcome.status = 'blocked_red'
  log(`${STORY}: BLOCKED — RED still wrong after ${MAX_RED} attempts. Escalating rather than looping.`)
  return outcome
}

// --- Phase 3 GREEN: bounded implement loop, files verified on disk ---------
phase('Green')
let greenOk = false
let greenBounce = ''
for (let a = 1; a <= MAX_GREEN; a += 1) {
  // wf:p3-green
  const green = await agent(
    `Story ${STORY}, worktree ${WORKTREE}, plan ${PLAN_PATH}. GREEN phase: ` +
    `implement until THIS story's tests pass. Minimum code to flip RED to GREEN — ` +
    `no abstractions for hypothetical futures. Declare every source file you ` +
    `wrote in source_files; a task completed without them is a watchdog violation.` +
    (greenBounce ? `\n\nPrevious attempt was rejected:\n${greenBounce}` : ''),
    { label: `green-${a}`, phase: 'Green', agentType: ENGINEER, schema: GREEN }
  )
  // wf:p3-green-verify
  const greenVerify = await agent(
    `Story ${STORY}, worktree ${WORKTREE}. Measurement pass — do not fix anything. ` +
    `Confirm every declared source file exists on disk in the worktree` +
    (green ? ` (declared: ${JSON.stringify(green.source_files)})` : '') +
    `. List any that do not in missing.`,
    { label: `greenverify-${a}`, phase: 'Green', schema: GREEN_VERIFY }
  )
  if (greenVerify && greenVerify.all_exist) {
    greenOk = true
    break
  }
  greenBounce = greenVerify
    ? `declared files missing on disk: ${JSON.stringify(greenVerify.missing)}`
    : 'GREEN verification returned nothing.'
  log(`${STORY}: GREEN attempt ${a} rejected (cap ${MAX_GREEN}) — ${greenBounce}`)
}
if (!greenOk) {
  // A phantom declared file must never reach the wip commit.
  outcome.status = 'blocked_green'
  log(`${STORY}: BLOCKED — declared source files still missing after ${MAX_GREEN} attempts.`)
  return outcome
}

// --- Phase 3 provisional commit --------------------------------------------
phase('WipCommit')
await wipCommit()

// --- Phase 4 VERIFY: bounded red-test bounce -------------------------------
phase('Verify')
let verify = null
let vAttempt = 0
while (vAttempt < MAX_VERIFY) {
  vAttempt += 1
  // wf:p4-verify
  verify = await agent(
    `Story ${STORY}, worktree ${WORKTREE}. Run ONLY this story's scoped tests, plus the resolved ` +
    `commands.typecheck and commands.lint. Report each exit status separately and quote the ` +
    `failing output verbatim. Do not fix anything — this is a measurement pass.`,
    { label: `verify:${STORY}:${vAttempt}`, phase: 'Verify', schema: VERIFY }
  )
  if (!verify) break
  if (verify.tests_pass && verify.typecheck_pass && verify.lint_pass) break
  if (vAttempt >= MAX_VERIFY) break
  log(`${STORY}: verify attempt ${vAttempt} red — bouncing to fix (cap ${MAX_VERIFY})`)
  await agent(
    `Story ${STORY}: make the scoped tests, typecheck and lint pass. Failing evidence:\n${verify.evidence}\n` +
    `Minimal surgical change only — do not touch unrelated code.`,
    { label: `verify-fix:${STORY}:${vAttempt}`, phase: 'Verify' }
  )
}
outcome.verify = verify
if (!verify || !verify.tests_pass || !verify.typecheck_pass || !verify.lint_pass) {
  // The prose version loops here forever. Exhaustion is an outcome, not a spin.
  outcome.status = 'blocked_verify'
  log(`${STORY}: BLOCKED — verify still red after ${MAX_VERIFY} attempts. Escalating rather than looping.`)
  return outcome
}

// --- Phase 4/5 review + fix loop -------------------------------------------
let round = 0
while (round < MAX_FIX_ROUNDS) {
  round += 1

  // The patch has no other producer inside this workflow (phase-4.md step 1's
  // lead-side compute does not run on the workflow path — "Before: nothing"):
  // without this call the reviewer is pointed at a file nobody wrote, and later
  // rounds review a stale pre-fix diff. Mirrors phase-7.workflow.js's per-round
  // diff regeneration. Single-quoted STORY (S1), same as the wip commit.
  phase('Diff')
  // wf:p4-diff
  await agent(
    `From the worktree ${WORKTREE}, regenerate THIS story's diff so the reviewer ` +
    `never re-flags work approved in earlier stories and never reads a stale patch:\n` +
    `  TS_PLAN_PATH="${PLAN_PATH}" bash ${SCRIPTS}/per_story_diff.sh '${STORY}' > ${ART}/diff-${STORY}.patch\n` +
    `Report patch_written.`,
    { label: `diff:${STORY}:r${round}`, phase: 'Diff', schema: DIFF }
  )

  phase('Review')
  // Bounded re-spawn: the prose contract waits indefinitely for a checklist.
  let review = null
  for (let attempt = 1; attempt <= MAX_REVIEW_RESPAWN; attempt += 1) {
  // wf:p4-re-review
    review = await agent(
      `Story ${STORY}, round ${round}. Review the implementation against EVERY acceptance criterion ` +
      `and DoD item in the frozen plan. Review THIS story's diff at ${ART}/diff-${STORY}.patch — ` +
      `this story's changes only, so work approved in earlier stories is never re-flagged. ` +
      `Write the aggregate to ` +
      `${ART}/reviews-${STORY}-round-${round}.md including a per-AC checklist — one row per AC, ` +
      `each marked pass/fail with file:line evidence.\n` +
      `Your structured return IS the delivery; the artifact is the audit record. Set ` +
      `per_ac_checklist_present honestly — claiming it when absent is a fabrication.\n\n` +
      // wf:p5-persist-counter
      // phase-5.md step 7 ("Increment") makes this part of the loop contract, and a
      // resumed sprint reads it to know which round it died on. Folded into the one
      // agent call guaranteed to run EVERY round — the fix batch only runs when there
      // are gating findings, and coverage runs once at the end. Mildly impure (a
      // reviewer mutating sprint state) but cheaper than a spawn per round.
      `Finally, as a separate step, persist the loop counter:\n` +
      `  bash ${SCRIPTS}/state.sh update "${PLAN_PATH}" iterations.review_fix=${round}`,
      { label: `review:${STORY}:r${round}:a${attempt}`, phase: 'Review', agentType: REVIEWER, schema: FINDINGS }
    )
    if (!review) {
      log(`${STORY} round ${round}: reviewer returned nothing (attempt ${attempt}/${MAX_REVIEW_RESPAWN})`)
      continue
    }
    // The artifact is the audit record: a review whose artifact is missing on
    // disk is a lost return, not a delivery — re-spawn within the same bound.
    const artifactCheck = await agent(
      `Check whether the review artifact ${review.artifact_path} exists on disk. ` +
      `Measurement only — do not create or modify anything.`,
      { label: `artifactcheck-r${round}-a${attempt}`, phase: 'Review', schema: ARTIFACT_CHECK }
    )
    if (!artifactCheck || !artifactCheck.exists) {
      log(`${STORY} round ${round}: review artifact ${review.artifact_path} missing on disk — lost return (attempt ${attempt}/${MAX_REVIEW_RESPAWN})`)
      continue
    }
    if (review.per_ac_checklist_present) break
    log(`${STORY} round ${round}: reviewer returned no per-AC checklist (attempt ${attempt}/${MAX_REVIEW_RESPAWN})`)
  }
  if (!review) { outcome.status = 'blocked_review'; break }
  if (!review.per_ac_checklist_present) {
    log(`${STORY}: proceeding on a checklist-less review after ${MAX_REVIEW_RESPAWN} attempts — flagged, not silently retried`)
  }

  // wf:p5-triage
  const gating = review.findings.filter(f => f.severity === 'CRITICAL' || f.severity === 'HIGH')
  outcome.rounds.push({ round, total: review.findings.length, gating: gating.length, artifact: review.artifact_path })
  log(`${STORY} round ${round}: ${review.findings.length} finding(s), ${gating.length} gating`)

  // Status stays 'unresolved' on the clean break: only a green coverage loop
  // below may promote it to ready_to_commit.
  if (!gating.length) break
  if (round >= MAX_FIX_ROUNDS) { outcome.status = 'cap_reached'; break }

  // --- Fix: one bounded RED->GREEN pass per gating finding, in parallel ----
  phase('Fix')
  // wf:p5-fix
  const fixes = (await parallel(gating.map(f => async () => {
    for (let inner = 1; inner <= MAX_INNER_FIX; inner += 1) {
      const r = await agent(
        `Story ${STORY}, finding ${f.id} [${f.severity}] on ${f.ac_id}.\n` +
        `Issue: ${f.issue}\nEvidence: ${f.evidence}\nRecommendation: ${f.recommendation}\n\n` +
        `RED->GREEN: add or adjust the failing test first, then make it pass. Attempt ${inner}/${MAX_INNER_FIX}. ` +
        `Declare every source file you wrote in source_files — a task completed without them is a ` +
        `watchdog violation. Set resolved honestly.`,
        { label: `fix:${STORY}:${f.id}:${inner}`, phase: 'Fix', schema: FIX }
      )
      if (r && r.resolved) return r
      if (inner >= MAX_INNER_FIX) {
        log(`${STORY}: finding ${f.id} unresolved after ${MAX_INNER_FIX} inner attempts — carried to next round`)
        return r
      }
    }
  }))).filter(Boolean)
  log(`${STORY} round ${round}: ${fixes.filter(f => f.resolved).length}/${gating.length} findings resolved`)

  // Land the fix work in HEAD: per_story_diff.sh reads committed BASE...HEAD
  // only, so without this the next round's regenerated patch misses the fixes.
  await wipCommit()
}

// --- Coverage gate: bounded fix loop ---------------------------------------
// Runs ONLY when the review loop ended clean (status still 'unresolved') —
// cap_reached/blocked_review carry their status to the caller unchanged.
if (outcome.status === 'unresolved') {
  phase('Coverage')
  // `--threshold` must be a real number: coverage_check.sh now rejects a non-numeric
  // value with usage exit 2, so the old literal `<configured>` placeholder would have
  // failed the gate rather than running it. 0 is the documented disable value.
  const THRESHOLD = cfg.coverageThreshold != null ? cfg.coverageThreshold : 80
  let cov = null
  let covIters = 0
  // wf:p3-coverage-loop
  for (let iter = 1; iter <= MAX_COVERAGE_ITERS; iter += 1) {
    covIters = iter
    // wf:p5-coverage
    cov = await agent(
      `Run, from ${WORKTREE}:\n` +
      `  bash ${SCRIPTS}/coverage_check.sh --mode '${COVERAGE_MODE}' --story-id '${STORY}' --threshold ${THRESHOLD}\n\n` +
      `Return its JSON verdict verbatim — do not re-interpret it. gate_status "disabled" ` +
      `(emitted when coverage_threshold is 0 or commands.coverage is "true") is a legitimate ` +
      `pass-through with pass:null, not a failure.`,
      { label: `coverage:${STORY}:${iter}`, phase: 'Coverage', schema: COVERAGE }
    )
    if (cov && (cov.pass === true || cov.gate_status === 'disabled')) break
    if (iter >= MAX_COVERAGE_ITERS) {
      outcome.coverage = cov
      outcome.status = 'coverage_cap_reached'
      outcome.residuals = { uncovered_files: (cov && cov.uncovered_files) || [] }
      log(`${STORY}: coverage still below threshold after ${MAX_COVERAGE_ITERS} iterations — surfacing, not shipping silently`)
      return outcome
    }
    const uncovered = JSON.stringify((cov && cov.uncovered_files) || [])
    log(`${STORY}: coverage iteration ${iter} below threshold — dispatching fix pass (cap ${MAX_COVERAGE_ITERS})`)
    await agent(
      `Story ${STORY}, worktree ${WORKTREE}. Coverage gate failed; uncovered files: ${uncovered}. ` +
      `Write tests covering the uncovered lines/branches this story introduced. Test files only.`,
      { label: `covfix-test-${iter}`, phase: 'Coverage', agentType: TEST_WRITER, schema: RED }
    )
    await agent(
      `Story ${STORY}, worktree ${WORKTREE}. Make the new coverage tests pass; uncovered files: ${uncovered}. ` +
      `Minimal surgical change only. Declare every source file you wrote in source_files.`,
      { label: `covfix-eng-${iter}`, phase: 'Coverage', agentType: ENGINEER, schema: GREEN }
    )
    // Another wip commit so the re-run measures the iteration's new work.
    await wipCommit()
  }
  outcome.coverage = cov
  outcome.coverage_iterations = covIters
}

if (outcome.status === 'unresolved') outcome.status = 'ready_to_commit'
return outcome

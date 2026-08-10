export const meta = {
  name: 'team-sprint-phase-7',
  description: 'Sprint-level regression gate, diff regeneration, four-lane review fleet and bounded fix loop; merge/push/cleanup stay lead-side',
  whenToUse: 'Phase 7 steps 1, 1b, 2 and 3 for the whole sprint. Steps 4-10 (merge, push, cleanup, report, finalisation) need git authority and the no-merge-without-confirmation guardrail, so they remain with the lead.',
  phases: [
    { title: 'RegressionGate', detail: 'one agent runs the full-suite gate from the worktree (phase-7.md step 3, moved first: no point reviewing a red tree)' },
    { title: 'Diff', detail: 'regenerate $ART/diff-sprint.patch from the worktree before every fleet round' },
    { title: 'Fleet', detail: 'security/performance/consistency/simplifier lanes over the sprint diff, each writing its own artifact (steps 1/1b)' },
    { title: 'Fix', detail: 'triage CRITICAL/HIGH from any lane plus every simplifier finding; bounded fix loop (step 2)' },
  ],
}

// ---------------------------------------------------------------------------
// Why this exists: phase-7.md steps 1/1b/2/3 as a bounded machine. Steps 4-10
// (merge, push, cleanup, report, finalisation) stay lead-side — they need git
// authority and the no-merge-without-confirmation guardrail (phase-7.md:36-92).
//
//   phase-7.md:34  step 3's whole-tree run happens FIRST here: it is the
//                  sprint's only full-suite regression gate, and reviewing a
//                  red tree is wasted fleet work.
//   phase-7.md:12  the Gate's full pass, with the unavailable-coverage
//                  exception: detect_commands.sh:292 seeds coverage (and
//                  typecheck/lint) to "" when nothing is detectable, and
//                  Phase 0 gates only the test runner (phase-0.md:28) — an
//                  empty leg is skipped with a non-blocking note, never
//                  blocked_regression.
//   phase-7.md:19  step 1's sprint diff. Regenerated HERE before every fleet
//                  round: the patch has no other producer inside the
//                  workflow, and a fix round must never re-review stale bytes.
//   phase-7.md:25  step 1b delivery-completeness. A null lane return is
//                  re-spawned exactly once; still null means blocked_fleet
//                  naming the lane — an undelivered HIGH must never score
//                  green as "no findings".
//   phase-7.md:27  step 2 triage. CRITICAL/HIGH from any lane plus EVERY
//                  simplifier finding regardless of severity gate the loop,
//                  bounded by reviewFixIterations; exhaustion is cap_reached
//                  with the unresolved findings as residuals — per-finding
//                  user waivers are the lead's job after return, never asked
//                  in-workflow.
//
// The four lanes REPLACE pre-commit-review-fleet rather than wrap it: that
// skill cannot run inside a workflow (AskUserQuestion intake gate at its
// SKILL.md:51; staged-diff-only input at :62). Lane agent types arrive as
// OPTIONAL args resolved lead-side (config-key > crew-key > static default
// 'general-purpose'); performanceAgent resolves from crew key `profiler` (the
// manifest has no `performance` key), and the consistency lane has no crew
// tier and no agent file anywhere — its review charter lives entirely in its
// prompt. Under `crew: off` no lane arg is passed and every lane falls to the
// static default, so none of the four may be hard-required.
// ---------------------------------------------------------------------------

const GATE = {
  type: 'object', additionalProperties: false,
  required: ['tests_pass', 'evidence'],
  properties: {
    tests_pass: { type: 'boolean' },
    typecheck_pass: { type: 'boolean' },
    lint_pass: { type: 'boolean' },
    coverage_pass: { type: 'boolean' },
    evidence: { type: 'string', minLength: 1 },
  },
}

const DIFF = {
  type: 'object', additionalProperties: false,
  required: ['patch_written'],
  properties: { patch_written: { type: 'boolean' } },
}

const FLEET_FINDINGS = {
  type: 'object', additionalProperties: false,
  // artifact_path is REQUIRED: the reviewer writes its own per-lane artifact
  // so a lost final return stays recoverable (phase-7.md step 1b), and a
  // zero-findings lane still writes one — "delivered, zero findings" and
  // "never delivered" must stay distinguishable.
  required: ['artifact_path', 'findings'],
  properties: {
    artifact_path: { type: 'string', minLength: 1 },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'severity', 'issue', 'evidence', 'recommendation'],
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'] },
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

// `args` can arrive as a JSON STRING rather than an object depending on how
// the caller passes it; `args || {}` silently yields a string whose .artDir
// is undefined, so the guard below would fire on every launch.
function readArgs(a) {
  if (a == null) return {}
  if (typeof a === 'object') return a
  if (typeof a === 'string') {
    try { return JSON.parse(a) } catch (e) {
      throw new Error('phase-7: args was a string but not valid JSON: ' + a.slice(0, 200))
    }
  }
  return {}
}

const cfg = readArgs(args)
const ART = cfg.artDir
const SCRIPTS = cfg.scriptsDir
const PLAN_PATH = cfg.planPath
const TARGET = cfg.targetBranch
const WORKTREE = cfg.worktree
// The four command strings are lead-resolved from detect_commands.sh output
// and arrive VERBATIM — the agent must never re-derive them (the exact drift
// detect_commands.sh exists to eliminate; a wrongly re-derived commands.test
// would short-circuit the whole fleet via blocked_regression).
const TEST_CMD = cfg.testCommand
const TYPECHECK_CMD = cfg.typecheckCommand
const LINT_CMD = cfg.lintCommand
const COVERAGE_CMD = cfg.coverageCommand
// Lead-resolved from config coverage_threshold (TS_COVERAGE_THRESHOLD
// override, phase-0.md:99; lead-side default 80 when no config file exists).
const THRESHOLD = cfg.coverageThreshold

// Lane agent types: optional, static default 'general-purpose'. Under
// `crew: off` no producer tier can fill them, so a required-args guard here
// would throw on every off-mode launch.
const SECURITY_AGENT = cfg.securityAgent || 'general-purpose'
const PERFORMANCE_AGENT = cfg.performanceAgent || 'general-purpose'
const CONSISTENCY_AGENT = cfg.consistencyAgent || 'general-purpose'
const SIMPLIFIER_AGENT = cfg.simplifierAgent || 'general-purpose'
// Lead-resolved from config review_fix_iterations — a user who set 5 must
// not be silently capped at 3, and a user who set 0 ("report, don't
// auto-fix") must get ZERO fix rounds, not a truthiness rewrite to 3. The
// non-negative-integer regex keeps 0 and "0" identical and sends anything
// non-numeric to the default — Number("garbage") is NaN, and
// `fixRounds >= NaN` is always false, an UNBOUNDED fix loop.
const RFI_RAW = cfg.reviewFixIterations
const MAX_FIX_ROUNDS = RFI_RAW != null && /^[0-9]+$/.test(String(RFI_RAW)) ? Number(RFI_RAW) : 3

// The command strings guard with `v != null`, NEVER truthiness: "" is a
// legitimate detect_commands.sh value (:292) and must pass the guard — the
// precedent shape (`if (!STORY || !ART || ...)`, story-executor) must not be
// copied for them.
const cmdOk = (v) => v != null
// coverageThreshold: 0 is the documented DISABLE value (config example,
// coverage_check.sh:149) and falsy in JS, so no truthiness here either; a
// non-numeric value dies at this boundary because coverage_check.sh would
// reject it with usage exit 2 mid-run.
const thresholdOk = (v) => v != null && /^[0-9]+(\.[0-9]+)?$/.test(String(v))

if (!ART || !SCRIPTS || !PLAN_PATH || !TARGET || !WORKTREE
    || !cmdOk(TEST_CMD) || !cmdOk(TYPECHECK_CMD) || !cmdOk(LINT_CMD) || !cmdOk(COVERAGE_CMD)
    || !thresholdOk(THRESHOLD)) {
  throw new Error(
    'phase-7 requires args {artDir, scriptsDir, planPath, targetBranch, worktree, ' +
    'testCommand, typecheckCommand, lintCommand, coverageCommand, coverageThreshold}; got ' +
    JSON.stringify(cfg)
  )
}

// --- Step 3 first: full-suite regression gate -------------------------------
// One agent call, explicitly split by consumer. Empty typecheck/lint/coverage
// legs are SKIPPED — neither run nor scored, and no word about them reaches
// the prompt — and recorded as a non-blocking unavailable note in the result.
phase('RegressionGate')

const unavailable = (leg) => `unavailable — no ${leg} command resolved`

const legs = [
  `- Full test suite: run \`${TEST_CMD}\` and report tests_pass.`,
]
if (TYPECHECK_CMD !== '') {
  legs.push(`- Typecheck: run \`${TYPECHECK_CMD}\` and report typecheck_pass.`)
}
if (LINT_CMD !== '') {
  legs.push(`- Lint: run \`${LINT_CMD}\` and report lint_pass.`)
}
if (COVERAGE_CMD !== '') {
  // Run-then-score: coverage_check.sh never executes commands.coverage — it
  // detects and parses a pre-existing report and exits 1 "no coverage report
  // detected." when none exists (coverage_check.sh:194-196) — so the report
  // must be produced FIRST. The TS_COMMANDS_COVERAGE= prefix is emitted ONLY
  // when the command is non-empty: coverage_check.sh:133 uses single-dash
  // ${TS_COMMANDS_COVERAGE-...}, so a set-but-empty prefix would clobber the
  // config value including the commands.coverage "true" disable sentinel.
  legs.push(
    `- Coverage, run-then-score: first run \`${COVERAGE_CMD}\` to produce the report, ` +
    `then score it with\n` +
    `    TS_COMMANDS_COVERAGE='${COVERAGE_CMD}' bash ${SCRIPTS}/coverage_check.sh --mode whole --threshold ${THRESHOLD}\n` +
    `  and report coverage_pass.`
  )
}

// wf:regression-first
const gate = await agent(
  `Sprint regression gate, from the worktree ${WORKTREE}. Run each command below ` +
  `EXACTLY as written — never re-derive or substitute a command. Measurement only, ` +
  `fix nothing. Report each leg's boolean honestly and quote any failing output ` +
  `verbatim in evidence.\n\n` +
  legs.join('\n'),
  { label: 'regression-gate', phase: 'RegressionGate', schema: GATE }
)

// Every leg that RAN needs its boolean === true: an agent that ran out of
// context or forgot a field must not score a fabricated 'pass' on the
// sprint's ONLY whole-suite gate — an unreported leg is the gate-side twin
// of the fleet's "delivered, zero findings" != "never delivered".
const regression = {
  test: gate && gate.tests_pass === true ? 'pass' : 'fail',
  typecheck: TYPECHECK_CMD === '' ? unavailable('typecheck')
    : (gate && gate.typecheck_pass === true ? 'pass' : 'fail'),
  lint: LINT_CMD === '' ? unavailable('lint')
    : (gate && gate.lint_pass === true ? 'pass' : 'fail'),
  coverage: COVERAGE_CMD === '' ? unavailable('coverage')
    : (gate && gate.coverage_pass === true ? 'pass' : 'fail'),
}

// RED = null return, or any leg that RAN does not report true (false OR
// silently omitted). A skipped leg can never block — the unavailable note
// must reach the fleet, not the exit. The scoring above already encodes
// exactly this: a null gate scores regression.test = 'fail', and a skipped
// leg scores the non-'fail' unavailable note.
const gateRed = Object.values(regression).includes('fail')

if (gateRed) {
  log('phase-7: regression gate RED — short-circuiting before any fleet round. '
    + 'Evidence: ' + ((gate && gate.evidence) || 'gate agent returned nothing'))
  // rounds is 0 here and an INTEGER on every status: the lead's
  // `state.sh update ... iterations.review_fix=<rounds>` write aborts on an
  // empty value (state.sh:252) or a non-integer (state.sh:89).
  return {
    status: 'blocked_regression',
    rounds: 0,
    residuals: null,
    artifacts: [],
    regression,
    evidence: (gate && gate.evidence) || null,
  }
}

// --- Steps 1/1b/2: diff regen + fleet + bounded fix loop --------------------

const LANES = [
  {
    lane: 'security', agentType: SECURITY_AGENT,
    charter: 'security review — injection, unsafe expansion or eval of derived input, ' +
      'secret leakage, insecure temp-file or lock handling, authz/authn gaps.',
  },
  {
    lane: 'performance', agentType: PERFORMANCE_AGENT,
    charter: 'performance review — hot-path waste, needless subprocess or I/O in loops, ' +
      'algorithmic regressions introduced by the sprint.',
  },
  {
    // No crew role and no agent file exists for this lane anywhere: this
    // prompt IS its entire review charter.
    lane: 'consistency', agentType: CONSISTENCY_AGENT,
    charter: 'codebase-consistency review — the diff must match the surrounding ' +
      'house conventions: naming, error handling, module boundaries, test idioms. ' +
      'Flag anything a maintainer would call foreign to this repo.',
  },
  {
    lane: 'simplifier', agentType: SIMPLIFIER_AGENT,
    charter: 'simplification review — duplication, needless abstraction or ' +
      'indirection, code that could be half the size. Your findings are ' +
      'mandatory-fix regardless of severity: the cleanup IS your output.',
  },
]

const fleetPrompt = (l, round) =>
  `Sprint review fleet, lane ${l.lane}, round ${round}. Plan ${PLAN_PATH}.\n` +
  `Review the FULL sprint diff at ${ART}/diff-sprint.patch (worktree ${WORKTREE}).\n` +
  `Charter: ${l.charter}\n\n` +
  `Write your findings to your own artifact ` +
  `${ART}/reviews-sprint-round-${round}-${l.lane}.md EVEN WITH ZERO FINDINGS — ` +
  `"delivered, zero findings" and "never delivered" must stay distinguishable, and ` +
  `the artifact makes a lost return recoverable. Return artifact_path and findings ` +
  `(id, severity CRITICAL|HIGH|MEDIUM|LOW, issue, evidence, recommendation).`

const fixPrompt = (g, round) => {
  const f = g.finding
  const head =
    `Sprint fix round ${round}, ${g.lane} finding ${f.id} [${f.severity}]. ` +
    `Plan ${PLAN_PATH}, worktree ${WORKTREE}.\n` +
    `Issue: ${f.issue}\nEvidence: ${f.evidence}\nRecommendation: ${f.recommendation}\n\n`
  if (g.lane === 'simplifier') {
    // Simplifier fixes are behaviour-preserving refactors: there is no
    // behaviour change to pin, so no new RED test (phase-7.md step 2).
    return head +
      `This is a behaviour-preserving refactor — no new RED test. Apply the ` +
      `simplification; the full tests, typecheck and lint must stay green. Commit ` +
      `with a Conventional Commits "refactor:" subject referencing the finding ` +
      `(no Story: line — this is not a story commit). Declare every source file ` +
      `you wrote in source_files and set resolved honestly.`
  }
  return head +
    `TDD micro-cycle against the sprint branch tip: write the regression test ` +
    `RED first, then fix to GREEN with the suite kept green. Commit with a ` +
    `Conventional Commits "fix:" subject referencing the finding (no Story: ` +
    `line — this is not a story commit). Declare every source file you wrote in ` +
    `source_files and set resolved honestly.`
}

let fixRounds = 0
let fleetRound = 0
const artifacts = new Set()
let status = null
let residuals = null
let missingLane = null

for (;;) {
  fleetRound += 1

  // The patch has no other producer inside this workflow (step 1's "lead
  // computes the patch" happens outside it): without this call the first
  // round reads a file nobody wrote, and later rounds review a stale pre-fix
  // diff.
  phase('Diff')
  // wf:diff-regen
  await agent(
    `From the worktree ${WORKTREE}, regenerate the full sprint diff so the review ` +
    `fleet never reads a stale patch:\n` +
    `  git diff ${TARGET}...HEAD > ${ART}/diff-sprint.patch\n` +
    `Report patch_written.`,
    { label: `diff:r${fleetRound}`, phase: 'Diff', schema: DIFF }
  )

  phase('Fleet')
  const spawnLane = (l, attempt) => agent(fleetPrompt(l, fleetRound), {
    label: `fleet:${l.lane}:r${fleetRound}:a${attempt}`,
    phase: 'Fleet',
    agentType: l.agentType,
    schema: FLEET_FINDINGS,
  })

  const returns = await parallel(LANES.map((l) => () => spawnLane(l, 1)))

  // wf:fleet-completeness
  // Delivery-completeness (step 1b): a null return (agent died/skipped) gets
  // exactly ONE re-spawn; still null blocks the merge naming the lane — an
  // undelivered HIGH must never be scored green as "no findings".
  for (let i = 0; i < LANES.length; i += 1) {
    if (returns[i] == null) {
      log(`phase-7 round ${fleetRound}: fleet lane ${LANES[i].lane} returned nothing — re-spawning once`)
      returns[i] = await spawnLane(LANES[i], 2)
    }
  }
  const missingIdx = returns.findIndex((r) => r == null)
  if (missingIdx !== -1) {
    missingLane = LANES[missingIdx].lane
    status = 'blocked_fleet'
    log(`phase-7 round ${fleetRound}: fleet lane ${missingLane} still undelivered after one re-spawn — blocking, not scoring an incomplete fleet`)
    break
  }

  // wf:simplifier-mandatory
  // Gating set = CRITICAL/HIGH from ANY lane plus EVERY simplifier finding
  // regardless of severity: simplifier findings file as MEDIUM/LOW by nature
  // and would otherwise slip through as "surfaced, non-blocking".
  const gating = []
  for (let i = 0; i < LANES.length; i += 1) {
    const lane = LANES[i].lane
    for (const f of returns[i].findings || []) {
      if (lane === 'simplifier' || f.severity === 'CRITICAL' || f.severity === 'HIGH') {
        gating.push({ lane, finding: f })
      }
    }
    if (returns[i].artifact_path) artifacts.add(returns[i].artifact_path)
  }
  log(`phase-7 round ${fleetRound}: ${gating.length} gating finding(s)`)

  if (!gating.length) {
    status = 'clean'
    break
  }
  // wf:cap-residuals
  // Exhaustion is a reported outcome with the unresolved findings attached —
  // per-finding user waivers are the lead's job AFTER return, never asked
  // in-workflow.
  if (fixRounds >= MAX_FIX_ROUNDS) {
    status = 'cap_reached'
    residuals = gating.map((g) => ({ lane: g.lane, ...g.finding }))
    log(`phase-7: CAP REACHED — ${gating.length} finding(s) still gating after ${MAX_FIX_ROUNDS} fix round(s); surfacing as residuals, not shipping silently`)
    break
  }

  fixRounds += 1
  phase('Fix')
  await parallel(gating.map((g) => () => agent(fixPrompt(g, fixRounds), {
    label: `fix:${g.lane}:${g.finding.id}:r${fixRounds}`,
    phase: 'Fix',
    schema: FIX,
  })))
  // Loop: the next iteration regenerates the diff, then re-runs the fleet
  // over the NEW patch. Fix returns do not gate — only a clean fleet does.
}

const result = {
  status,
  rounds: fixRounds,
  residuals,
  artifacts: [...artifacts, `${ART}/diff-sprint.patch`],
  regression,
}
if (missingLane != null) result.missing_lane = missingLane
return result

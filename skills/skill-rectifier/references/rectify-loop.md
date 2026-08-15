# Rectify Loop (shared by skill-rectifier and agent-rectifier)

Target-neutral fix-and-revalidate loop. "The target" is the skill or agent under
repair; "the validator" is the paired validator skill; "the fix catalog" is the
per-type catalog. The invoking SKILL.md defines all three plus report naming.

## Step 0: Identify inputs

Two inputs: a validation report (in `./docs/agent_reports/`) and the target path.
If the user just ran the validator, both are in recent context. Otherwise, with a
live user available, ask which report (list recent files) and confirm the target
path from the report header. Running autonomously (forked context, no user to ask):
do not ask — take the most recent matching validation report whose header names the
target; if none exists, run the validator in report-only mode first to produce one.
Record which report you resolved in the rectification report.

## Step 1: Parse the validation report

Extract every finding: category, severity (FAIL | WARN), check_name, detail,
location, suggested_fix (from the Recommendations section if present). Sort FAILs
first (by category order), then WARNs — later fixes sometimes depend on earlier
structural repairs.

## Steps 2-5: Apply fixes by category

Work category by category in the invoking skill's stated order (structural first,
instruction compliance last). Mechanical fixes are applied without asking. Load the
fix catalog when starting Step 2 and keep it in context through Step 5 — it holds
every per-finding recipe.

## Step 6: Verify fixes

1. Run the validator's structural script (command in the invoking SKILL.md).
2. If you modified any scripts, syntax-check them: `bash -n <script>` for shell,
   `python3 -c "import ast; ast.parse(open('<script>').read())"` for Python.
3. Read the fixed target end-to-end — fixes applied in isolation sometimes create
   awkward transitions, duplicate sections, or contradictions.

## Step 7: Generate rectification report

Write to `./docs/agent_reports/` (`mkdir -p` first) using the invoking skill's
filename pattern and its `references/report-template.md`.

## Step 8: Self-healing loop — validate, rectify, repeat until grade A

Mandatory and automatic. Do not skip it; do not ask whether to proceed. **The
rectifier — not the validator — owns the loop.** Keep a running tally across rounds:
round number, fixes applied, and the report's FAIL and WARN counts.

1. Invoke the validator on the target, stating this is a **"report-only
   re-validation, round {N}"**. Those words stop the validator from re-invoking the
   rectifier and nesting a second loop. Let it run all its phases — do not shortcut
   to just the structural script. Simulation-style phases may be skipped in
   intermediate rounds, but the final round confirming grade A must run every phase
   the original validation ran.

   Both validators set `disable-model-invocation: true`, so the `Skill` tool cannot
   reach them. Resolve the one this rectifier pairs with — `agent-validator` or
   `skill-validator`, named in the invoking SKILL.md:

   ```bash
   bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode <validator>
   ```

   It answers `MODE=agent`, so spawn the validator through the `Agent` tool with the
   type it names. Never read its body inline: it forks so a whole validation run
   stays out of this window, and this loop runs up to five rounds.
2. Read the new report's Overall Grade and FAIL/WARN counts; add them to the tally.
3. **Grade A** (0 failures, 0-2 warnings): loop complete — go to Step 9.
4. **Below A** (B, C, D, F): parse the new report (Step 1), apply fixes (Steps 2-5),
   write an updated report (Step 7, filename suffixed `-round{N}`), return to 1.
5. **Exit conditions — stop on the first of these:**
   - **Grade A reached** (success).
   - **5 rounds completed** without reaching A — escalate: the target resists
     mechanical repair and needs human judgment.
   - **A round applies zero fixes** (all remaining issues deferred/unfixable) —
     escalate.
   - **No progress for two consecutive rounds** (FAIL+WARN total did not decrease)
     — escalate. This catches oscillation, where fixing one finding re-creates
     another.

Escalation means: stop fixing and hand the user a clear list of what remains, why
each item couldn't be auto-fixed, and the round history. With no live user
(autonomous/forked context), put the escalation in the final rectification report
and summary instead of asking.

The loop is bounded because an unbounded loop that isn't converging burns tokens
without adding safety — a precise list of what remains is the productive outcome.

## Step 9: Present final results

Show: starting grade and final grade, rounds performed, total fixes applied across
all rounds, any items deferred to human judgment (if escalated), and the path to the
final validation report confirming grade A.

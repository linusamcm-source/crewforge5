# Phase 0 — Pre-flight (fail loud)

**Goal.** Verify the environment, the plan path, and the resume state are sound before any code, agent, or worktree is touched. Any failure STOPs the sprint with a clear, actionable report.

## Entry condition

The user invoked `team-sprint <plan_path>` (or the skill autoloaded from a planning artifact). `$plan_path` is set. No prior phase has run for this invocation.

## Gate

All checks below pass (including 10a language-crew resolution under `crew: auto`). Any failure → STOP, surface the offending check's reason, do not advance.

## Steps

Run sequentially. Each check is short-circuiting.

0. **External tooling present.** `source $SCRIPTS/lib.sh && require_all`. Probes `jq`, `bats`, `shellcheck`, `repomix`, `python3`. Concatenated install hints on failure.
1. **In a git repo.** `git rev-parse --is-inside-work-tree` returns `true`.
2. **Working tree clean.** `git status --porcelain` empty. Dirty tree blocks the sprint per pre-edit-hygiene rule — surface and ask.
3. **Target branch exists.** `git rev-parse --verify <target_branch>` succeeds. Default `develop`.
4. **Required sub-skills loadable.** `use-repo-code`, `sprint-watchdog`, `ui-validation-loop`, `pre-commit-review-fleet`. Missing any → STOP. `adversarial-review` is additionally required whenever `scheduling: graph` — the Phase 2 graph-hardening review is hard-wired in graph mode, so check loadability here and STOP if absent; under `scheduling: sequential` it is not used (plan-level review runs planner-side and needs nothing from this skill).

4a. **Deferred transport tools present (self-inspection).** The transport surface is **not** always present — `SendMessage`, `TaskOutput`, and `Monitor` are deferred tools, and a call against one that was never loaded fails `Invalid tool parameters` at delivery time (past every later gate). The lead inspects its **own** tool list — an agent natively sees the tools available to it; do **not** assume any `ToolSearch "select:<name>"` probe syntax (it is not universal) — for exactly the deferred transport tools the chosen `scheduling` mode will actually call:
    - `scheduling: graph` needs the node executor's single `SendMessage` **and** the spawner's block-collect path (`TaskOutput` and/or `Monitor`).
    - `scheduling: sequential` needs **no** `SendMessage` at all (`$REF/sendmessage-protocol.md` — the node-executor layer collapses into the lead and every child, reviewers included, is collected by final return); it needs only the block-collect path (`TaskOutput`/`Monitor`).

    A required tool absent from the lead's own tool list → **STOP** loud under `scheduling: graph` (the `SendMessage` hop is unavoidable there). If only `SendMessage` is missing, **WARN** and fall back to `scheduling: sequential` rather than letting delivery fail silently at Phase 7. This is parallel to the step-4 sub-skill loadability gate: a transport tool the run depends on is verified here, "before any code, agent, or worktree is touched", not discovered missing at the moment of delivery. **Every spawned node executor's first action** is to verify the same required tools appear in its **own** tool set (again by self-inspection, no probe syntax assumed); a missing tool is returned immediately as a final-return failure — which needs no `SendMessage` — and the lead treats that as a preflight failure for the node.
5. **Commands resolve.** Detect or load from config via `bash $SCRIPTS/detect_commands.sh`; `command -v <bin>` for each. Missing test runner → STOP — **except when `crew: auto`**: defer the stop, because step 10a backfills commands from the verified crew profile. Re-run this check at the end of 10a and STOP only if the test runner is still unresolved.
6. **Plan file exists and is non-empty.** `[ -s "$plan_path" ]`.
7. **Plan-path uniqueness validation.** `bash $SCRIPTS/validate_plan_path.sh "$plan_path"`. On `STATUS=FAIL` the filename lacks a story-id slug or `.team-sprint/sprints/sprint-<slug>/` already belongs to a different or finalised plan — STOP and surface the script's stderr reason. On `STATUS=RESUME`, an earlier sprint for this exact plan is being continued. See `$REF/plan-path-convention.md` for the full naming contract.
8. **Sprint-watchdog Phase -1 audit.** Invoke sprint-watchdog with `audit-only`. Surfaces stale state, dangling worktrees from prior failed sprints.

8a. **Arm the watchdog guard.** `bash ${CREWFORGE_ROOT}/hooks/sprint-watchdog-guard.sh --activate` (run from the repo root). Creates `.claude/scripts/sprint-watchdog/.sprint-active.json`, which is the sole activation gate for the `PostToolUse(TaskUpdate)` guard — with no file the hook is a no-op, so it never fires outside a sprint. The guard mechanically records `impl_no_source_files`, `impl_missing_source_files`, and `review_no_artifact` violations for sprint-watchdog Step A to drain. It **fails open by design**: a guard error is never a sprint stop condition, which is exactly why Step B re-verifies independently. Absence of the hook (unregistered in `settings.json`) is a WARN, not a STOP — the sprint proceeds with the watchdog as the only check.
9. **Refresh repomix pack.** `bash $SCRIPTS/repomix_refresh.sh --max-age-minutes "$repomix_max_age_minutes"` regenerates `.repomix-output.xml` when missing or older than `repomix_max_age_minutes` (config, default 240). Stale pack = false-clean reviews in Phase 4 / 7.

9a. **Ensure + build + verify graphify** (when `graphify != off`; skip entirely when `graphify: off`). graphify is the knowledge-graph layer that **augments** repomix for the recon/review phases — it is installed once per project and the graph is built/refreshed here so Phases 1/2/4 can query it. Three sub-steps, in order. Under `graphify: on` any failure STOPs Phase 0; under `graphify: auto` a failure logs a WARN and sets `state.json.graphify_degraded=true` (the sprint continues without the graph — reviewers fall back to repomix only).

    1. **Ensure installed + verified-running.** Installs the `graphifyy` package if `import graphify` fails, persists `graphify-out/.graphify_python`, and smoke-tests that graphify runs (this is the "is graphify installed correctly for *this* project" check):
       ```bash
       bash "$SCRIPTS/graphify_ensure.sh" --ensure
       ```
       `STATUS=OK` → installed and runnable. `STATUS=FAIL` → install/import broke; STOP under `graphify: on`, else WARN + degrade.

    2. **Build or refresh the project graph.** Check freshness, then (re)build only when needed — the build is the one graphify step a bash script can't own (semantic extraction needs subagents), so the lead invokes the `/graphify` skill:
       ```bash
       bash "$SCRIPTS/graphify_ensure.sh" --graph-status --max-age-minutes "$graphify_max_age_minutes"
       ```
       - `STATUS=FRESH` → reuse the existing `graphify-out/graph.json`, skip the build.
       - `STATUS=MISSING` or `STATUS=STALE` → invoke the **`/graphify`** skill (via the Skill tool) on the repo root to build/refresh `graphify-out/graph.json`. A pre-built graph from a prior session is reused; otherwise `/graphify` runs its full pipeline.

    3. **Retest graphify in the sprint (smoke query).** Re-verify after the build so the graph is confirmed queryable before any reviewer relies on it — this is the explicit "newly installed graphify runs correctly in the team skill" gate:
       ```bash
       bash "$SCRIPTS/graphify_ensure.sh" --verify
       ```
       With a graph present `--verify` runs a real `graphify query` (falling back to a NetworkX load of `graph.json`) and returns `STATUS=OK` only if it answers. `STATUS=FAIL` → STOP under `graphify: on`, else WARN + degrade. Hold the OK/degraded verdict; it is persisted to `state.json.graphify_degraded` in step 10 once state is initialised (state.json does not exist yet here).

9b. **Probe the recon router** (when `recon != off`; skip entirely when `recon: off`). `$SCRIPTS/recon.sh` is tiers 1–2 of the escalation ladder: it normalises structural intents across codegraph/graphify/repomix and names the provider and freshness behind every answer, so a provider that cannot parse the language degrades visibly instead of returning an empty "no callers". Two sub-steps, in order.

    1. **Index CodeGraph when it is present but unindexed.** `codegraph status` exits 0 whether or not the project is initialised, so the verdict is parsed from its **stdout**, never from its exit code. A present-but-unindexed CodeGraph is indexed here, or the router reports it `no-index` for the whole sprint:
       ```bash
       if command -v codegraph >/dev/null 2>&1 \
          && codegraph status | grep -qi 'not initialized'; then
         codegraph init
       fi
       ```
       The `if` is load-bearing. As a trailing `&&` chain this exits 1 on BOTH
       healthy states — codegraph absent, and codegraph present-but-already-indexed
       — and this phase's Gate ("Any failure → STOP") would abort Phase 0 before
       the probe below ever runs, inverting the fail-soft intent of `recon: auto`.

    2. **Probe provider health.**
       ```bash
       bash "$SCRIPTS/recon.sh" --probe
       ```
       - `STATUS=OK` → every bash-probeable provider BINARY resolved. Indexes are not graded here, so a resolved provider can still answer `REASON=no-index` on a structural intent.
       - `STATUS=DEGRADED` → some providers absent; STOP under `recon: on`, else WARN + set `recon_degraded=true` and continue (the router still serves `text` via repomix).
       - `STATUS=SKIP` → the router is disabled; callers go straight to the instruments and `recon_degraded` stays false.

       Hold the verdict; it is persisted to `state.json.recon_degraded` in step 10 once state is initialised.

10. **Persist sprint metadata.** Runs BEFORE the subskill preflight so subsequent `state.sh update` calls have an initialised `state.json` to write into.
    ```bash
    bash "$SCRIPTS/state.sh" init "$plan_path" "$target_branch" "$worktree_name"
    # record the step-9a graphify verdict (omit when graphify: off)
    bash "$SCRIPTS/state.sh" update "$plan_path" graphify_degraded='<true|false>'
    # record the step-9b recon verdict (omit when recon: off)
    bash "$SCRIPTS/state.sh" update "$plan_path" recon_degraded='<true|false>'
    ```
    `$ART/state.json` is now the resume contract. See `$REF/state-schema.md` for the schema.

10a. **Language-crew resolution** (when `crew: auto`; skip entirely when `crew: off`). Assigns stack-matched agents instead of the static RN defaults. STOP on failure — the sprint must not run a wrong-stack fleet.

    1. **Detect language**: `bash $SCRIPTS/detect_language.sh` — the canonical marker table lives in that script's header (crew-factory calls the same script; no prose copy anywhere). `STATUS=OK` → use `LANG`. `STATUS=AMBIGUOUS` → pick the primary from `CANDIDATES` by source volume; ask the user if genuinely ambiguous. `STATUS=UNKNOWN` → ask the user.
    2. **Resolve the manifest.** `bash $SCRIPTS/crew_check.sh check <lang>` — `STATUS=CACHED` → load `.claude/crews/<lang>.json` (schema-valid, every role resolved to a real agent file). Otherwise invoke the `crew-factory` agent (subagent_type `crew-factory`) — a one-off worker, the same single-agent invocation style as the step-8 sprint-watchdog audit (Phase 0 spawns no fleet yet; the sprint's role teammates start in Phase 2). Pass the detected language; it surveys the stack, builds + validates the senior-developer to grade A, seeds and validates the rest, and writes `.claude/crews/<lang>.json`. Wait for it. If it cannot bring every generated agent to grade A, it stops and escalates — surface that and STOP Phase 0.
    3. **Persist** the role map + verified commands into state. `state.json.crew` is the channel phases 3–4 read at spawn time; `crew_commands` is provenance/resume only (the gate scripts do NOT read state — see step 4):
       ```bash
       bash "$SCRIPTS/state.sh" update "$plan_path" crew='<manifest.crew>' crew_commands='<manifest.commands>'
       ```
    4. **Make manifest commands reach the gates** (state.json is NOT read by `detect_commands.sh` or `coverage_check.sh` — they read config + env). For any `commands.*` unresolved at step 5, the lead uses the manifest's command strings directly for its own test/typecheck/lint runs (Phase 3 VERIFY). For the Phase 3 coverage gate, the lead passes the manifest coverage command inline as `TS_COMMANDS_COVERAGE=<cmd>` (and `TS_COVERAGE_THRESHOLD` if from the manifest) on the `coverage_check.sh` invocation — shell env does not persist between Bash calls, so set it per-call. Agent-type resolution is NOT done here: phases 3–4 resolve `subagent_type` from `state.json.crew` at spawn (config explicit > crew > default), so nothing to resolve into `*_agent` now.
    5. **Re-check the deferred command gate** (step 5): if a test runner is still unresolved after this backfill, STOP now.

11. **Subagent skill preflight + auto-resolution + state transformation.** This is a LOCKED 5-step sequence — the resolved hook list in `state.json.subskill_hooks` must be reproducible. Run these sub-steps in this exact order:

    **11.1. Read `team-sprint.config.yaml`.** Load the user config into memory (the raw map `subskill_hooks.phase-N → [entries]` plus the top-level `integration_diagram` field).

    **11.2. Resolve `integration_diagram: auto`.** If `integration_diagram == auto`, invoke:
    ```bash
    bash "$SCRIPTS/preflight_subskills.sh" --probe-only integration-diagram
    ```
    - On success: prepend the diagram skill's hook spec into the in-memory map under `subskill_hooks.phase-{0,2,3,4,6,7}` with `source: "auto"` and `required: false` (auto-prepended entries default to non-required).
    - On failure: log `integration-diagram: not found, auto → off` at INFO; do NOT prepend; do NOT abort Phase 0 (graceful degrade — auto-mode failure is never gating).

    **11.3. Probe the merged hook list.** Invoke:
    ```bash
    bash "$SCRIPTS/preflight_subskills.sh" --probe-all "$plan_path"
    ```
    Probe-failure handling is governed by the per-entry `required` flag (not by user-declared vs auto-prepended):
    - `required: true` + probe fail → Phase 0 ABORT, surface the failing skill name in the error.
    - `required: false` (default) + probe fail → log WARN line `subskill <name> probe failed; hook will still attempt to run (command is authoritative)` and continue. The `command` is always authoritative — see `$REF/subskill-hooks.md`.

    **11.4. Config-to-state transformation (explicit).** For each map key `phase-N` in `team-sprint.config.yaml.subskill_hooks`, iterate the entries:
    - **If `N ∈ {1, 5}` (reserved phases per mech-9 + mech-15 ADR):** emit INFO log line `subskill_hooks.phase-N unsupported in v1.0; block ignored` and SKIP (do NOT persist).
    - **Else (N ∈ {0, 2, 3, 4, 6, 7}):** emit one object per entry into the merged hook list with:
      - `skill` — copied from the entry
      - `command` — copied from the entry
      - `required` — `entry.required ?? false`
      - `phase` — literal map key (`"phase-0"`, `"phase-2"`, …)
      - `source` — `"user"` for entries from YAML; `"auto"` for entries auto-prepended in step 11.2.

    **Array order:** for each active phase in ascending order (0, 2, 3, 4, 6, 7), emit all auto-prepended entries first (in declaration order from the diagram skill's hook spec), then all user-declared entries (in YAML declaration order). Persist the resulting flat array:
    ```bash
    bash "$SCRIPTS/state.sh" update "$plan_path" subskill_hooks='[...]'
    ```

    **11.5. Audit log line.** Emit a single INFO log line prefixed `subskill_hooks resolved:` listing every resolved hook with its `skill`, `phase`, `required`, and `source`.

    **Privacy (deny-list, not allow-list):** the log line includes `command` verbatim UNLESS `command` contains any of the shell-injection-enabling characters `| ; & \` $( > <` (pipe, semicolon, ampersand, backtick, command-substitution, redirection). When any of those characters is present, the line reads `<command redacted — contains shell metachars>`. Safe characters (`~`, `=`, `:`, `@`, `+`, `-`, `,`, `'`, `"`) are NOT redaction triggers. The full unredacted command is still committed to `state.json.subskill_hooks` regardless — redaction applies only to the audit log line.

12. **Run sub-skill hooks for this phase, fail-soft.** Final step before advancing.
    ```bash
    bash "$SCRIPTS/run_subskill_hooks.sh" 0 "$plan_path"
    ```

## Exit condition

`$ART/state.json` exists with `current_phase: 0` and all required fields populated; repomix pack is fresh; resume state (if any) acknowledged. Advance:
```bash
bash "$SCRIPTS/state.sh" advance-phase "$plan_path" 1
```

## Artifacts produced

- `$ART/state.json`
- `.repomix-output.xml` (worktree root, refreshed if stale)

## Scripts referenced

- `$SCRIPTS/validate_plan_path.sh`
- `$SCRIPTS/state.sh`
- `$SCRIPTS/detect_commands.sh`
- `$SCRIPTS/repomix_refresh.sh`
- `$SCRIPTS/graphify_ensure.sh` (when `graphify != off`)
- `$SCRIPTS/recon.sh` (when `recon != off`)
- `$SCRIPTS/preflight_subskills.sh`
- `$SCRIPTS/run_subskill_hooks.sh`

## References

- `$REF/plan-path-convention.md` — naming rules + validator semantics.
- `$REF/state-schema.md` — `$ART/state.json` field-by-field schema and resume contract.

## Extensions

<!-- subskill-hooks:phase-0 -->
Sub-skills declared in `team-sprint.config.yaml` under `subskill_hooks.phase-0` run here, fail-soft. See `$REF/subskill-hooks.md` for the contract.

**WHO READS THIS / WHEN:** Phase 0 reads this before step 10a (language-crew resolution); Phases 3–4 read it when resolving a `subagent_type` at spawn time. The executable mechanics live in `phases/phase-0.md` step 10a — this file is the contract behind them.

### Stack-matched agent crew (`crew: auto`)

The fleet is stack-specific by construction: a React-Native crew is the wrong tool for a Python repo. `crew: auto` resolves agents from the repo's detected language:

- Phase 0 detects the language and looks for `.claude/crews/<lang>.json` (the crew manifest).
- **Hit** → load it. **Miss** → spawn the `crew-factory` agent: it surveys the stack, builds and `agent-validator`-grades the **senior-developer agent to A first**, seeds every other role (architect, tester, profiler, security, code-reviewer, simplifier, docs-writer, dependency-auditor) from that base, validates each to A, writes the manifest. Cached — re-run only by deleting the manifest or `--refresh`. The factory reuses good existing registry specialists and generates only the gaps.
- Phase 0 persists the role map to `state.json.crew`. Phases 3–4 resolve each `subagent_type` at spawn by precedence: explicit config agent name > `state.json.crew.<key>` > static default. Unset `commands.*` come from the manifest — the lead runs the test/typecheck/lint trio via `scripts/run_gate.sh` (tees each gate to `<log-dir>/<gate>.log`, emits pass/fail JSON, exit 1 on failure) and passes the coverage command to `coverage_check.sh` via `TS_COMMANDS_COVERAGE` (gate scripts read config/env, not `state.json`).

`crew: off` uses the static `*_agent` fields verbatim; any non-`auto` `*_agent` value overrides the manifest.

# Phase 2: per-dimension detail

Cite `path/to/file.ext:LINE` for every finding. The instrument notes below say where evidence for each dimension usually comes from; verify every citation live per the evidence rules.

1. **Architectural decay** — circular deps, layering violations, god files (>500 LOC) and god functions, duplicated logic across 3+ sites where an abstraction should exist, abstractions that exist but nobody uses, dead code (unused exports, unreachable branches, stale commented-out blocks). *Recommended instrument: graphify when available* — `query` for coupling and cycles, zero-caller queries for dead code; else grep the pack for the same signals (oversized files, blocks duplicated across 3+ sites, exports with no importers). Confirm hits in source.

2. **Consistency rot** — multiple ways of doing the same thing (HTTP clients, error handling, logging, config loading, validation, date handling). Naming drift. Folder structure that no longer reflects what the code actually does. *Primary instrument: pack greps.*

3. **Type & contract debt** — `any` / `unknown` / `as any` / `# type: ignore` / loose dicts. Untyped API boundaries. Missing schema validation at trust boundaries. *Primary instrument: pack greps.*

4. **Test debt** — run coverage if the project has a working coverage command (check the justfile / Makefile / package scripts); identify gaps on critical paths. Tests that assert implementation rather than behavior. Skipped or flaky tests. High-churn files with no tests.

5. **Dependency & config debt** — CVE scan via the stack tooling below. Unused deps. Duplicate deps doing the same job. Env var sprawl (referenced but not documented; defaults inconsistent across envs).

6. **Performance & resource hygiene** — N+1 queries, sync work in async paths, blocking I/O on hot paths, uncleaned listeners or handles, unnecessary serialization.

7. **Error handling & observability** — swallowed exceptions, blanket catches, errors logged but not handled, inconsistent error shapes across modules, missing structured logs on critical paths. *Primary instrument: pack greps.*

8. **Security hygiene** — hardcoded secrets, string-concat SQL, missing input validation at trust boundaries, permissive auth or CORS, weak crypto. *Primary instrument: pack greps, then live-read every hit — security findings must never cite unverified snapshot lines.*

9. **Documentation drift** — README claims that don't match reality, comments that contradict adjacent code, public APIs without docstrings.

# Recon Harness — capability router for code-knowledge instruments

**Status:** specification, not yet built.
**Source:** `$HOME/.claude/union.md` (Graphify vs GitNexus vs CodeGraph comparison), reviewed
2026-07-27 against the live tooling on this machine.

## Context and problem

`team-sprint`, `team-sprint-planner`, `adversarial-review`, `tech-debt-audit` and ~40 agent
definitions all perform codebase recon. Today they choose instruments by prose instruction
(`CLAUDE.md` → "Codebase recon instruments", three layers) and by model judgment at call
time. Three problems with that:

1. **Selection collapse.** `tokensave` alone exposes ~140 MCP tools (verified: the deferred
   tool roster in-session lists `mcp__tokensave__tokensave_*` ×140). Adding graphify's MCP
   surface and CodeGraph's 20 read-only tools puts ~167 tools in front of one selection
   decision. `union.md:204-208` states the failure directly: *"When agents see a long list of
   tools, they often ignore most of them."*
2. **No capability map.** graphify, CodeGraph and repomix have genuinely disjoint strengths
   (`union.md:16-21`). Nothing in the current setup encodes *which instrument answers which
   question*, so agents default to whichever they were last told about.
3. **No cost floor.** `union.md:329-330` notes graphs add pure overhead under ~20 files.
   Nothing enforces that; recon runs at full cost on a 6-file repo.

### Verified constraints

| Fact | Evidence |
| --- | --- |
| No graph tool ships on Homebrew | `brew search codegraph` → `codesnap, codex-app`; `brew search gitnexus` → `nexus`; `brew search graphify` → `graphviz, grafx` |
| CodeGraph's brew tap is empty | `GET api.github.com/repos/colbymchenry/homebrew-codegraph/contents/` → `"This repository is empty."` (repo itself: 200, size 0) |
| No graphify/gitnexus taps exist | `homebrew-graphify`, `homebrew-tap` under `Graphify-Labs` and `abhigyanpatwari` → all 404 |
| graphify ships on PyPI as `graphifyy` | `uv tool list` → `graphifyy v0.9.27`, binaries `graphify`, `graphify-mcp` |
| CodeGraph ships on npm, MIT | `npm view @colbymchenry/codegraph` → `v1.5.0`, `license = MIT`, `bin = { codegraph: 'npm-shim.js' }` |
| GitNexus is noncommercial-licensed | `npm view gitnexus license` → `PolyForm-Noncommercial-1.0.0` |
| `codegraph install` mutates `CLAUDE.md` | Vendor docs: installer "adds a small marker-fenced CodeGraph section in the agent's instructions file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`)" |

**Decision (user, 2026-07-27):** GitNexus is **excluded entirely** — PolyForm-Noncommercial is
incompatible with commercial repos on this machine. The harness is graphify + CodeGraph +
repomix + tokensave. Homebrew manages **runtimes only**; tool installs use native channels.
**Installation is out of scope for this sprint** — the router degrades cleanly when a provider
is absent (`STATUS=DEGRADED`/`UNAVAILABLE`), so no story depends on a tool being installed.
Provisioning is machine maintenance, tracked separately.

## Design

### Core claim: route in bash, not in the model

The router collapses ~167 tools to **10 intents**. Routing is a deterministic bash lookup —
zero tokens, no model judgment, testable under `bats` like every other script in
`skills/team-sprint/scripts/`. Agents declare *what they want to know*; the router picks the
access path from a probed capability catalogue.

This is a query planner, not a tool menu. An application does not hand-pick indexes; it
declares SQL and the planner chooses the access path from statistics. Hand-picking works
until the schema changes, then every caller is wrong — which is exactly what happens when
40 agent definitions hardcode `graphify query` and graphify's CLI shifts.

### Intent vocabulary

Ten intents. Each has an ordered provider chain; the router executes the first available
provider **that indexed the repo's primary language** and reports which one answered. The chain
is a preference, not a constant: resolution is per-intent *and* per-language, and a provider
that did not index the language is skipped exactly as if it were absent.

| Intent | Question it answers | Provider chain (preference order, language-filtered) | Native invocation (first link) |
| --- | --- | --- | --- |
| `text` | "where does this string occur" | repomix(rtk grep) | `rtk grep <pat> $REPOMIX_PACK` |
| `callers` | "what calls X" | codegraph → tokensave → graphify | `codegraph callers <sym>` |
| `callees` | "what does X call" | codegraph → tokensave → graphify | `codegraph callees <sym>` |
| `impact` | "what breaks if I change X" | codegraph → tokensave → graphify | `codegraph impact <sym>` |
| `tests` | "which tests cover this change" | codegraph → tokensave (delegate) | `codegraph affected <files...>` |
| `path` | "how does A reach B" | graphify → codegraph | `graphify path A B` |
| `dynamic` | "who handles this callback/event/route" | codegraph → tokensave (delegate) | `codegraph explore <query>` |
| `coupling` | "are A and B coupled" | tokensave → graphify | `tokensave_coupling` (delegate) |
| `docs` | "what do the PDFs/design docs say about X" | graphify → repomix | `graphify query <q>` |
| `spans` | "what files does feature W span" | graphify → repomix | `graphify explain <mod>` |

Provider CLIs verified on this machine at CodeGraph 1.5.0 (`codegraph --help`):
`init`, `index`, `sync`, `status`, `query`, `explore`, `node`, `files`, `callers`, `callees`,
`impact`, `affected`. CodeGraph is a **bash-invocable provider**, not MCP-only — no delegation
needed for any of its intents.

**Language capability is probed, never assumed.** Phase 0 step 10a already resolves the repo's
primary language from manifest markers (`skills/team-sprint/phases/phase-0.md:65`); RH1's probe
adds the second half, recording in `.recon/capabilities.json` *which languages each provider
actually indexed*. The sources are mechanical: `codegraph status` prints a `Files by Language:`
breakdown (verified in the 1.5.0 dist at `lib/dist/bin/codegraph.js:970`), and graphify's
`graphify-out/graph.json` tags every node with `metadata.language`. Chain resolution then filters
the table above by that catalogue. When no provider in an intent's chain indexed the primary
language the router returns `STATUS=UNAVAILABLE REASON=language-unsupported` — never `EMPTY`,
which reads as "asked and found nothing" and is a different, false claim.

**tokensave is exempt from the language filter, by necessity.** It is MCP-only and unreachable
from bash, so the probe can never enumerate the languages it indexed and therefore can never
prove it did *not* index one. A filter that cannot read a provider's catalogue must not silently
drop that provider: an unknown catalogue is treated as "may answer", so a tokensave link always
survives filtering and the delegation decision is handed to the calling agent, which can see its
own roster. Consequently `REASON=language-unsupported` can only fire on an intent whose chain is
entirely bash-probeable (codegraph, graphify, repomix); any chain containing tokensave resolves
to `STATUS=DELEGATE` instead. This is the single rule reconciling the filter with the delegate
link — without it the two produce opposite statuses for the same input.

**On `$HOME/.claude` itself the CodeGraph half of this harness is inert, and the plan assumes it.**
Verified this session: `codegraph status` in `$HOME/.claude` prints `⚠ Not initialized`, and
CodeGraph's grammar registry (`lib/dist/extraction/grammars.js`) enumerates 40-odd languages —
`c cpp csharp go java javascript python ruby rust swift typescript vue yaml …` — with **no
`bash`/`shell`/`sh` entry at all**, so initialising it here would not help. graphify's live
`graphify-out/graph.json` by contrast holds 184 nodes whose `source_file` is `.sh` and whose
metadata reads `{'language': 'bash', ...}`. On this repo every codegraph-first intent therefore
resolves past codegraph, and `callers`/`callees`/`impact` are answered by graphify. RH1 carries
the AC: in a repo whose indexed languages include `.sh` for graphify and not for codegraph,
`recon.sh callers <sym>` is answered by graphify and the output reports `PROVIDER=graphify`.

**Phase 0 precondition — flip `graphify: auto`.** The sprint config sets `graphify: off`
(`$HOME/.claude/team-sprint.config.yaml:32`), which skips phase-0 step 9a entirely and
would leave every graphify-served intent fixture-only with no live verification at all. That is
needless here: verified 2026-07-28, graphify is installed at `$HOME/.local/bin/graphify`
and `graphify-out/graph.json` is present and fresh — 2,763,824 bytes, 3453 nodes, rebuilt
2026-07-28 05:58 — so live verification is free. Set `graphify: auto`
before Phase 0 — under `auto` a graphify failure WARNs and sets `state.json.graphify_degraded=true`
rather than stopping the sprint (`skills/team-sprint/phases/phase-0.md:36`), so the precondition
costs nothing if the tool later breaks. RH5 owns the key and carries the `docs` chain ACs; RH3 owns
the graphify freshness assertions this precondition gives a live producer.

The `tests` intent is the highest-value single addition and was not anticipated from
`union.md`. `codegraph affected <changed-files>` returns the test files reachable from a
change, which is precisely the input the per-story test-scoping work
(`skills/team-sprint/SKILL.md`, Phase 3/4 story-scoped gates) currently approximates by
convention. Wiring it turns "run the tests we think relate to this story" into "run the tests
the graph proves relate to this story".

**`tests` is unusable on a bats suite, including this repo's.** CodeGraph parses no shell, so a
`.bats`-only test suite is invisible to `codegraph affected`; the intent is scoped to repos whose
test files are in a CodeGraph-indexed language. On a shell suite `tests` must return
`STATUS=UNAVAILABLE REASON=language-unsupported` rather than an empty answer, so that the
convention-based test scoping in `SKILL.md` Phase 3/4 is **knowingly retained** for this sprint
rather than silently believed replaced. RH3 carries the AC.

**`dynamic` and `docs` are preferences, not exclusivities.** An earlier draft made both hard
single-provider on the strength of `union.md:164-176` and `union.md:139-141,151-152` — vendor
comparison prose, not a probe. The probes this session only partly landed, so both are downgraded
to ordered chains. `codegraph explore` could not be run at all (CodeGraph is not initialised here
and parses no shell if it were), so CodeGraph's callback-tracing exclusivity stays **UNVERIFIED**
and `dynamic` falls back to tokensave instead of becoming a permanent `UNAVAILABLE`. graphify's
non-code indexing *is* confirmed — 3015 of the 3453 nodes in the live `graph.json` carry
`file_type: document` — but "graphify is the *only* one indexing non-code" is not, so `docs`
prefers graphify and falls back to repomix. A vendor claim must never be able to harden into a
permanent `UNAVAILABLE`. Where a chain genuinely has one link (`text`), an absent provider still
returns `STATUS=UNAVAILABLE REASON=not-installed` and never falls through to a provider that
cannot answer.

**Decision (2026-07-28) — `docs` is chained, never single-provider-terminal.** An earlier draft
carried both readings at once: the intent table gives `docs | graphify → repomix` while a Design
sentence made a missing `graphify-out/graph.json` a terminal `STATUS=UNAVAILABLE REASON=no-index`.
Chained wins, and for the reason directly above — graphify's *exclusivity* on non-code indexing is
UNVERIFIED, so a missing graphify index must never be allowed to refuse a question repomix can
still answer. This is just the plan's general rule applied: a non-terminal link that cannot answer,
for any reason (absent binary, no index, wrong language, MCP-only under `--no-delegate`), is
skipped exactly as if the provider were absent and the chain advances. `no-index` therefore names a
*link skip* on `docs` and becomes the emitted terminal status only when the link lacking an index
is the last one. For repomix the pack IS the index: an absent
`${REPOMIX_PACK:-.repomix-output.xml}` is `no-index`, an absent `rtk`/`repomix` binary is
`not-installed`. Terminality on a single provider survives only where the chain genuinely has one
link (`text`).

**Delegation targets are unverified tool names.** The `tokensave` links above (`tests`, `dynamic`,
`coupling`) are MCP-only: bash emits `STATUS=DELEGATE PROVIDER=tokensave TOOL=<name> ARGS=<json>`
and the calling agent makes the call. The specific names — `tokensave_affected`,
`tokensave_call_chain`, `tokensave_runtime`, `tokensave_coupling` — are **UNVERIFIED**: no
`tools/list` probe is runnable from bash, so none of them is cited from a live roster — and the
only names this machine's tokensave server publishes in its own instructions are
`tokensave_context` and `tokensave_search`, neither of which appears in that list. RH1 therefore
hardcodes no MCP tool name at all: it emits `STATUS=DELEGATE PROVIDER=tokensave INTENT=<intent>
ARGS=<json>` and the calling agent, which *can* see its roster, selects the tool. `TOOL=` is
emitted only when a live roster supplied the name. An unconfirmed name must never become either a
hardcoded guess or a silently dropped chain link.

### The router answers *where*, never *what*

Router output carries `file:line symbol` and never source code. This is deliberate and
load-bearing: a confident, fully-formed answer invites citation without verification, which
directly contradicts the evidence rules in `CLAUDE.md` ("Snapshots are recon; the live tree
is evidence… Line-number citations require a Read of the cited range"). Withholding the body
forces the `Read`. The router is a locator, and locators do not get to be believed.

Two provider subcommands actively fight this and their adapters must strip them: `codegraph
explore` ("relevant symbols' **source** + call paths in one shot") and `codegraph node` ("one
symbol's **source** + caller/callee trail"), both per `codegraph --help` at 1.5.0. RH1 carries the
AC — given a fixture `codegraph explore` / `codegraph node` output containing source bodies, the
adapter emits only `<path>:<line>\t<symbol>\t<relation>` lines and no body text, with the fixture
under `scripts/fixtures/recon/` per RH1's existing DoD — and names both source-bearing
subcommands explicitly in its contract-coverage loop rather than testing "an adapter".

### Escalation ladder — when to use which instrument

| Tier | Instrument | Use when | Cost |
| --- | --- | --- | --- |
| 0 | Live `Read` | target file known, ≤3 files | 1 call |
| 1 | `recon.sh text` | text/occurrence, location unknown | 1 call, output-capped |
| 2 | `recon.sh <structural intent>` | relationship question | 1 call, normalised |
| 3 | full index rebuild | index missing or stale | 1–5 min, once |

**Rule: never escalate a tier you can answer at a lower one.** The router enforces the floor
mechanically — see RH3's small-repo guard.

### Output grammar

One shape regardless of provider, so callers parse once. **This block is the single source of
truth for the status set** — RH1's contract-coverage loop reads its status list from here rather
than restating it, so a new status cannot be added in one place and go untested in the other.

```
PROVIDER=<name> INTENT=<intent> FRESHNESS=<live|fresh|stale:<n>m|none> QUERY=<arg>
<path>:<line>\t<symbol>\t<relation>
...
STATUS=<OK|EMPTY|UNAVAILABLE|SKIP|DEGRADED|NO_INTENT_MATCH|DELEGATE> [COUNT=<n>] [REASON=<r>] [FILES=<n>] [PROVIDER=<name>] [TOOL=<name>] [ARGS=<json>]
```

- `STATUS=` is mandatory, is always the last line, and takes exactly one of those seven values — there is no eighth, and a value not on this list is a bug, not an extension.
- The leading `PROVIDER= INTENT= FRESHNESS= QUERY=` header line is emitted on the two answer statuses (`OK`, `EMPTY`) only; every other status is a single `STATUS=` line with no header and no body.
- `COUNT=<n>` is mandatory on `OK` and `EMPTY` and omitted on the five non-answer statuses, where there is no result set to count.
- `REASON=<r>` is mandatory on `SKIP`, `UNAVAILABLE` and `DEGRADED`, and omitted elsewhere. Closed vocabulary: `disabled`, `small-repo`, `not-a-repo`, `not-installed`, `no-index`, `language-unsupported`, `provider-error`.
- `FILES=<n>` appears only on `STATUS=SKIP REASON=small-repo`, reporting the file count RH3's guard actually measured, and on `STATUS=SKIP REASON=not-a-repo FILES=0`, where there is no repo to count.
- `PROVIDER=` appears in the header line on `OK`/`EMPTY`, and again on the `STATUS=DELEGATE` line to name the provider being delegated to; `ARGS=` appears on `STATUS=DELEGATE` only, as does `INTENT=`, which the delegating agent needs to pick the tool. `TOOL=` appears there only when the probe read that name off a live MCP roster — bash cannot enumerate an MCP roster, so a hardcoded tool name is forbidden and a nameless `DELEGATE` line is well-formed.
- `STATUS=DELEGATE` is terminal only for a caller that can make MCP calls. Under `--no-delegate` / `RECON_NO_MCP=1` an MCP-only link is skipped exactly as an absent provider is, and the chain advances.
- Result lines are capped at `RECON_MAX_LINES` (default 50); a truncated body ends with one `TRUNCATED=<emitted>/<total>` line, the only body line exempt from the `<path>:<line>` shape, and `COUNT=` still reports the pre-truncation total.

`FRESHNESS=` is mandatory on `OK` and `EMPTY` and takes one of `live|fresh|stale:<n>m|none`.
`none` is the no-index-consulted value, deliberately matching the condition `graphify_ensure.sh`
reports as `STATUS=MISSING` (`graphify_ensure.sh:34`). It is **omitted entirely**, not set to
`none`, on `SKIP`/`DEGRADED`/`UNAVAILABLE`/`NO_INTENT_MATCH`/`DELEGATE`, consistent with the
optional-key rule above — those statuses emit no header line at all; RH4's call log, which is
fixed-arity JSON rather than a line grammar, records the field as `null` in exactly those cases.
The three providers have different staleness models — CodeGraph auto-syncs (`union.md:128-133`,
~2s debounce via FSEvents), graphify and repomix are manual and age-gated — and a caller cannot
honour the evidence rules without knowing which it got. RH3 adds `none` to its contract-coverage
`FRESHNESS=` loop so the value has a test, and — since RH1 builds no `SKIP` branch and so cannot
emit one — RH3 also carries the AC that a small-repo `SKIP` line is well-formed under this
grammar: one line, `REASON=small-repo`, `FILES=<n>`, no `FRESHNESS=`, no `COUNT=`.

---

## Coverage gate — resolution for this sprint

No bash coverage instrument is installed (`kcov`, `bashcov` both absent; `kcov` is available
on Homebrew). Set **`coverage_threshold: 0`** in the sprint config. `coverage_check.sh:148-160`
emits `{mode:"skipped", gate_status:"disabled", pass:null}` and exits 0; `disabled` is a
first-class state honoured at `phase-3.md:52`, `phase-5.md:71` and the `SKILL.md:180` gate, so
the sprint proceeds without a bypass. Prefer `coverage_threshold: 0` over
`commands.coverage: "true"` — the latter asserts a coverage command that does not exist.

**Do not install kcov for this sprint.** `recon.sh` is a dispatch table over 10 intents; line
coverage of a `case` statement measures whether code ran, not whether the contract holds. The
sprint substitutes a **contract-coverage** gate instead, which is mechanical, needs no new
tooling, and measures the thing that actually matters for a router. It applies to every story:

- Every intent in the 10-intent table is named in at least one `bats` test.
- Every `STATUS=` value in the Output grammar block — that block, not a per-script restatement of it — has a test asserting it is emitted, and every value a script's header documents appears in that block.
- Every `REASON=` value in the output grammar's closed vocabulary — all seven of `disabled small-repo not-a-repo not-installed no-index language-unsupported provider-error`, the list read from that block rather than trimmed here — has a test asserting it is emitted with its status, and no value may sit outside every story's loop.
- Every provider in a story's chain has a fixture, including the absent-provider case and the indexed-the-language-but-not-this-one case.
- Every source-bearing provider subcommand (`codegraph explore`, `codegraph node`) has a fixture carrying real source bodies and a test asserting the adapter emits none of it.

Each is a loop over a list compared against `grep -l` on the test files — assert it in the
story's DoD, not by eye. **Every count-style assertion in these loops must be `|| true`-guarded**
(`n="$(... | grep -c PATTERN || true)"`), because `grep -c`/`grep -l` exit 1 on zero matches and
the bats helpers run under `set -euo pipefail` — the unguarded form aborts the test exactly in
the zero case it is meant to detect. `lint_skill.sh:111` is the in-repo precedent.

## Story RH1: `recon.sh` router core and provider adapters

### Depends On: none

### Touches:
- `skills/team-sprint/scripts/recon.sh`
- `skills/team-sprint/scripts/tests/recon.bats`
- `skills/team-sprint/scripts/recon_providers.sh`
- `skills/team-sprint/scripts/tests/recon_providers.bats`

### Boundaries:
- `skills/team-sprint/scripts/lib.sh` (produces `fail`/`warn`/`require_*` and the sourcing contract this script depends on)
- `skills/team-sprint/scripts/graphify_ensure.sh:1-38` (produces the header-comment / `STATUS=` / exit-code convention RH1 must match *exactly* — the AC says "in the style of", so this file is the spec)
- CodeGraph CLI, external, installed via npm `@colbymchenry/codegraph` (produces the capability surface the probe reads; **not in this repo**, its tool roster is not documented at a stable URL)
- tokensave MCP roster (~140 `mcp__tokensave__*` tools; produces the delegate targets — **MCP-only, unreachable from bash**, so the probe can never shell it)
- `skills/team-sprint/scripts/graphify_ensure.sh:93-125` (produces the interpreter resolution + `graphify-out/.graphify_python` cache the adapter MUST reuse rather than reimplement; note it now calls `uv tool run --from graphifyy` — a bare `uv tool run graphifyy python` resolves to nothing)
- `$HOME/.claude/CLAUDE.md:118-119` (produces the `rtk grep`-not-bare-grep rule the repomix adapter is asserted against — verified 2026-07-28 that `RTK.md` contains neither the string `rtk grep` nor `bare grep`, so it is not the producer; worse, `RTK.md:24-26` "Hook-Based Usage" claims all commands are automatically rewritten by the hook, which contradicts the rule this adapter is asserted against)
- `${REPOMIX_PACK:-.repomix-output.xml}` (produces the XML pack whose `<file path=…>` tags are the ONLY source of a hit's real path and line offset; `-B 2` does not reach the owning tag and never did — verified 2026-07-27 on the live pack: the tag for `agents/boundary-reviewer.md` sits at pack line 472 and its content runs to line 568, so the adapter indexes tag offsets rather than using context lines)
- `rtk grep` output shape, external (produces pack-line-numbered hits and, when its result cap trips, a trailing `  +<n> more in <file>` line — verified 2026-07-27: a broad sweep of the live pack ended `+6245 more in .repomix-output.xml`; that trailer is RH1's only source of a pre-truncation `COUNT=` for the `text` intent)
- CodeGraph CLI 1.5.0, external (produces `callers`/`callees`/`impact`/`affected`/`explore` output shapes the adapter normalises)
- tokensave MCP tool names, external and **MCP-only** (produce the optional `TOOL=` value on the `STATUS=DELEGATE` line — bash can emit the delegation but can never execute it, and can never enumerate the roster either, so `TOOL=` is omitted unless a live roster supplied the name)

One adapter function per provider, each translating an intent + argument into that provider's
native invocation and normalising its output into the RH1 grammar.

- **repomix** — `rtk grep <pattern> "${REPOMIX_PACK:-.repomix-output.xml}"`. Explicit `rtk`,
  never bare grep, never relying on the PreToolUse hook (per `CLAUDE.md:118-119` and the existing
  `recon-instruments.md:19-31` rationale: bare grep on a pack returns full-width XML lines
  and floods context). The pack is a concatenation, so a raw `rtk grep` line number is a pack
  offset, not a source coordinate. The adapter builds a one-pass index of `<file path=` tag
  offsets (`grep -n '<file path=' "$PACK"`) and maps each hit to (owning path, pack line −
  tag line) before emitting it, so `text` obeys the same `<path>:<line>` grammar as every
  other intent rather than getting an exemption.
- **graphify** — `graphify query|path|explain`. Interpreter resolution is not reimplemented:
  the adapter reads `graphify-out/.graphify_python` and validates it exactly as
  `graphify_ensure.sh:96-101` does (`-x` on the cached path plus `"$cached" -c 'import
  graphify'`); when the cache is absent or invalid it shells `graphify_ensure.sh --check`
  once and re-reads it. `graphify_ensure.sh` gains no new mode — it exposes
  `--ensure|--check|--verify|--graph-status` only (verified at `graphify_ensure.sh:47`), so
  it stays out of RH1's Touches.
- **codegraph** — CLI where one exists, else the MCP surface discovered by RH1's probe.
- **tokensave** — MCP-only, so the adapter never calls it and never hardcodes a tool name.
  The delegate tool names an earlier draft carried (`tokensave_callers`, `tokensave_impact`,
  `tokensave_coupling`) are **unverified guesses** and are dropped: no `tools/list` probe is
  runnable from bash, and the only names this machine's tokensave server documents in its own
  instructions are `tokensave_context` and `tokensave_search` — neither of which the draft
  named. The adapter emits `STATUS=DELEGATE PROVIDER=tokensave INTENT=<intent> ARGS=<json>`
  and the calling agent picks the tool from its own roster; `TOOL=` is emitted only when the
  probe resolved that name from a live roster.

Build the entrypoint: argument parsing, the 10-intent table, provider-chain resolution, the
capability probe, and the output grammar. Sources `lib.sh` and follows the header-comment,
`STATUS=`-line and exit-code conventions of `graphify_ensure.sh` exactly.

**One evaluation order, declared here and documented in the header comment.** Every status is
decided in this sequence and the first match wins, so two live conditions can never race:
(1) `recon: off` → `STATUS=SKIP REASON=disabled` (branch added by RH5); (2) intent match →
`STATUS=NO_INTENT_MATCH`; (3) small-repo guard → `STATUS=SKIP REASON=small-repo` (branch added
by RH3); (4) provider resolution → `OK`/`EMPTY`/`DEGRADED`/`UNAVAILABLE`/`DELEGATE`. RH1 builds
steps 2 and 4 and leaves the two `SKIP` branches to their owning stories; the order itself is
asserted in RH1 and re-asserted in RH3 once the guard exists.

**Line cap.** Result lines are capped at `RECON_MAX_LINES` (default 50). When the cap trips the
adapter emits exactly that many result lines followed by one trailing body line
`TRUNCATED=<emitted>/<total>`, and `COUNT=` on the `STATUS=` line reports the pre-truncation
total. That marker is the only body line exempt from the `<path>:<line>` result grammar. RH5
owns the matching `recon_max_lines: 50` config key and its contract-coverage entry; with no
config present RH1 supplies the 50 default itself.

**MCP capability is the caller's to declare.** `STATUS=DELEGATE` is terminal only when the
caller can actually make an MCP call. `recon.sh --no-delegate` (equivalently `RECON_NO_MCP=1`)
declares that it cannot: every MCP-only link is then skipped exactly as if the provider were
absent and the chain advances to the next link, so a bash-only caller can never be handed a
delegation it has no way to execute. RH4's `--explain` reports `no-delegate` among its skip
reasons.

Capability probe runs once and caches to `.recon/capabilities.json`. **Providers are bound by
capability, not by hardcoded tool name** — CodeGraph's MCP tool roster is not documented
publicly at a stable URL (verified: the vendor docs page does not enumerate tool names), so
names are discovered at probe time and cached. A probe that cannot resolve a provider marks it
unavailable; it never guesses a name. Two properties of the cache are load-bearing:

- **The cache key is (binary path, mtime, size), not the version string.** Version strings cost
  a provider exec to read, which defeats the point of caching; the triple is readable with one
  `stat` and detects a reinstall or an upgrade just as well. RH5 owns the TTL key
  `recon_probe_max_age_minutes` (default 1440), documented in the same `type: / default:`
  comment format as `graphify_max_age_minutes`; RH1 hardcodes the same default for the
  no-config case.
- **The probe records index state, not just binary presence.** A present binary over an
  un-indexed repo answers nothing, and reporting that as `EMPTY` is the false claim this plan
  exists to prevent. The probe parses `codegraph status` **stdout** for the initialised state —
  never its exit code, which is 0 even when the project is not initialised (verified 2026-07-27
  in `$HOME/.claude`: prints `⚠ Not initialized`, exits 0) — and stores the result as `indexed`
  alongside `available`. RH6 owns adding `codegraph init` to the Phase 0 probe step.

### Acceptance Criteria
- `recon.sh --help` exits 1 and prints a usage block naming all 10 intents and every mode (`--help`, `--probe`, `--no-delegate`, and the bare `<intent> <arg…>` form).
- The router evaluates in exactly one order — disabled, then intent match, then small-repo guard, then provider resolution — asserted by a case that trips two conditions at once: an unrecognised intent invoked against a stubbed-absent provider set yields `STATUS=NO_INTENT_MATCH`, never `STATUS=DEGRADED`.
- With `recon` unset or `auto`, `recon.sh callers <symbol>` in a repo with no providers installed prints exactly one `STATUS=DEGRADED REASON=not-installed` line and exits 0; the `recon: on` hard-fail branch is NOT built here — RH5 adds it, mirroring the `graphify: on` HARD-gate wording.
- The DEGRADED fixture repo sets `recon_min_files: 0` (or holds more than 20 tracked files) so the test still passes once RH3 inserts the small-repo guard ahead of provider resolution.
- An unrecognised intent (`recon.sh frobnicate x`) prints `STATUS=NO_INTENT_MATCH` and exits 0 — callers fall back to free-form exploration, this is an answer not an error.
- `recon.sh --probe` prints exactly one STATUS line to stdout — `STATUS=OK` (every requested provider resolved), `STATUS=DEGRADED REASON=not-installed` (some absent) or `STATUS=SKIP REASON=disabled` — and exits 0.
- `recon.sh --probe` writes `.recon/capabilities.json` containing, per provider, `available` (bool), `indexed` (bool), `languages` (array of the language names that provider actually indexed, read from `codegraph status`'s `Files by Language:` block and from `metadata.language` across `graphify-out/graph.json`), `version` (string), `binary` (path), `binary_mtime` (epoch int), `binary_size` (int) and `resolved_at` (epoch int).
- A second `--probe` inside `recon_probe_max_age_minutes` (default 1440) whose cached (binary path, mtime, size) triple is unchanged does not exec any provider — assert via a stub provider that appends to a counter file; a changed mtime or size re-probes that provider alone.
- With the codegraph binary present but `codegraph status` reporting not-initialized (parsed from stdout — it exits 0 either way), the codegraph link is skipped as `no-index` exactly as an absent binary is and the chain advances, so `tests` and `dynamic` emit `STATUS=DELEGATE PROVIDER=tokensave`; under `--no-delegate` the MCP-only link is skipped too, codegraph is then the terminal link, and both emit `STATUS=UNAVAILABLE REASON=no-index`, never `EMPTY` — this is the present-but-un-indexed input, distinct from the absent-binary input below.
- In a repo whose indexed languages include `.sh` for graphify and not for codegraph, `recon.sh callers <sym>` is answered by graphify and the output reports `PROVIDER=graphify` — chain resolution filters each link by the `languages` catalogue, so a codegraph-first intent skips codegraph exactly as if the binary were absent.
- When no provider in an intent's chain recorded the repo's primary language in its `languages` catalogue, that intent returns `STATUS=UNAVAILABLE REASON=language-unsupported` and never `EMPTY` — assert against a stubbed capabilities cache whose every provider indexed some other language.
- `dynamic` with the codegraph binary absent entirely — not merely present-and-un-indexed — falls through to its one remaining link and emits `STATUS=DELEGATE PROVIDER=tokensave`; under `--no-delegate`, or with tokensave also absent, it emits `STATUS=UNAVAILABLE REASON=not-installed`, the terminal link's own reason and deliberately distinct from the un-indexed case's `REASON=no-index`, and reaches graphify not at all — graphify is not on the `dynamic` chain.
- `recon.sh coupling A B --no-delegate` (or `RECON_NO_MCP=1`) with tokensave present skips the MCP-only link and answers `PROVIDER=graphify`, not `STATUS=DELEGATE`.
- Every emitted result line matches `^[^\t]+:[0-9]+\t[^\t]*\t[^\t]*$`, the sole exception being the optional trailing `TRUNCATED=<emitted>/<total>` marker line.
- No emitted line contains source-code bodies — assert against `codegraph explore` and `codegraph node` fixtures specifically (the two subcommands that actually emit bodies; a `codegraph callers` fixture never contained one, so it would pass for the wrong reason), each asserting the output carries the symbol's declaring `file:line` and none of its body text.
- Each adapter, given a fixture provider output, emits lines matching the RH1 grammar.
- The repomix adapter's generated command contains `rtk grep` and never a bare `grep`/`rg` (assert by capturing the command string, not by running it).
- The `text` adapter converts every pack offset into a source-relative coordinate — it indexes `<file path=` tag offsets once per invocation and emits `<owning path>:<pack line − tag line>` — asserted on a fixture pack where a known symbol resolves to its true source line (the live pack puts the `agents/boundary-reviewer.md` tag at line 472 and that file's line 2 at pack line 474).
- `COUNT=` for the `text` intent is the pre-truncation hit total taken from `rtk grep`'s `+<n> more in <file>` trailer (emitted hits + n); with no trailer present it is the emitted hit count.
- The graphify adapter reads `graphify-out/.graphify_python` and validates it as `graphify_ensure.sh:96-101` does (`-x` on the cached path plus `import graphify`), and only a VALID cache skips interpreter detection — assert with two stubs, one valid cache (detection does not re-run) and one stale cache pointing at a deleted path (detection re-runs).
- With no `.graphify_python` cache the adapter shells `graphify_ensure.sh --check` once and re-reads the cache; if that still yields no interpreter it emits `STATUS=UNAVAILABLE REASON=not-installed` and never crashes.
- An adapter whose provider exits non-zero returns the documented failure sentinel and never aborts the shell.
- A provider adapter returning the failure sentinel causes the router to try the next link in the chain; only the terminal link's status is emitted — assert with two stub providers, the first failing and the second answering.
- A zero-exit provider that produced no result lines is terminal: it emits `STATUS=EMPTY COUNT=0` and does NOT advance the chain, while a non-zero provider exit emits no status of its own and yields `STATUS=UNAVAILABLE REASON=provider-error` only when it was the last link.
- Exactly one `STATUS=` line is printed per invocation regardless of chain depth — assert with a three-link chain whose first two links fail.
- The tokensave adapter emits `STATUS=DELEGATE PROVIDER=tokensave INTENT=<intent> ARGS=<json>` whose `ARGS=` value parses as JSON, and emits `TOOL=` only when the probe resolved that name from a live MCP roster — no MCP tool name is ever hardcoded in bash.
- Provider output exceeding `RECON_MAX_LINES` (default 50) is truncated to that many result lines followed by one `TRUNCATED=<emitted>/<total>` line, and `COUNT=` reports the pre-truncation total.

### Definition of Done
- [ ] `shellcheck scripts/recon.sh` clean.
- [ ] `recon.bats` green — `run-all.sh:54` collects `("$TESTS_DIR"/*.bats)`, so a new suite is discovered by that glob; there is no registry to edit and no registration step to perform.
- [ ] `commands.typecheck` names no file a later story creates: `$HOME/.claude/team-sprint.config.yaml:44` reads `bash skills/team-sprint/scripts/tests/run-all.sh` before Phase 0 (as originally written it named `recon.sh` and `recon_providers.sh`, neither of which exists until this story lands, so every typecheck run before RH1 failed on a missing file). `lint_skill.sh:125` check 7 and `run-all.sh:42-47` already shellcheck every `$SCRIPTS/*.sh` that exists, with no missing-file failure mode.
- [ ] Header comment block documents every mode (`--help`, `--probe`, `--no-delegate`, bare intent), the single evaluation order, every `STATUS=` value including the three `--probe` statuses, and exit codes, in the style of `graphify_ensure.sh:1-38`.
- [ ] **Contract coverage** (substitutes for the disabled line-coverage gate — see "Coverage gate" above). Both loops pass, asserted in `recon.bats`, not by eye: all 10 intents (`text callers callees impact tests path dynamic coupling docs spans`) are each named in at least one test; and every `STATUS=` value RH1 itself produces (`OK EMPTY UNAVAILABLE DEGRADED NO_INTENT_MATCH DELEGATE`, read from the Output grammar block rather than restated) has a test asserting it is emitted.
- [ ] **Contract coverage, `REASON=`.** Every `REASON=` value RH1 itself produces (`not-installed no-index language-unsupported provider-error`) has a test asserting it is emitted with its status, looped against `grep -l` on `recon.bats` — `provider-error` included, since RH1's last-link-failed branch is its only producer anywhere in the sprint and the sprint-wide `REASON=` loop lists it.
- [ ] The two `SKIP` branches are deliberately out of RH1's loop because RH1 cannot emit them: `SKIP REASON=small-repo` is added to RH3's loop with RH3's guard, `SKIP REASON=disabled` to RH5's with RH5's config gate. A `STATUS=` value that is documented but never asserted is an untested branch regardless of what a line-coverage number would say, so no value may sit outside all three loops.

---
- [ ] `shellcheck scripts/recon_providers.sh` clean.
- [ ] Fixtures for all four providers under `scripts/fixtures/recon/`, including the stale-`.graphify_python` cache (a cached path that no longer exists) and a fixture repomix pack carrying at least two `<file path=…>` tags so the offset mapping is exercised across a tag boundary.
- [ ] `recon_providers.bats` green — discovered by the same `run-all.sh:54` glob, with no registration step.
- [ ] **Contract coverage.** Every provider in `recon_providers` (`repomix graphify codegraph tokensave`) has both a present-fixture and an absent-provider test — the graphify absent case includes the stale-cache fixture — asserted by looping the provider list against `grep -l` on the bats file, not by eye. The absent case is the one that regresses silently.

---

---

## Story RH3: small-repo guard and freshness reporting

### Depends On: RH1

### Touches:
- `skills/team-sprint/scripts/recon.sh`
- `skills/team-sprint/scripts/tests/recon_guard.bats`
- `skills/team-sprint/scripts/lib.sh`
- `skills/team-sprint/scripts/tests/lib.bats`

### Boundaries:
- `skills/team-sprint/scripts/lib.sh` `mtime_epoch()` (produces the index age; handles the BSD/GNU `stat` split for files that exist, but aborts under `set -e` when the file is absent — the caller must test first, so every call site is guarded by `[[ -f "$idx" ]] || { <absent-index branch>; }` rather than leaning on the helper)
- `skills/team-sprint/scripts/lib.sh` `repo_root()` at `lib.sh:71` (git-common-dir based, so it returns the MAIN tree root from inside any worktree; produces the base path for both the config lookup and the guard's file count — and, unhardened, returns `/` outside a repo, which is why RH3 hardens it)
- `TEAM_SPRINT_CONFIG` (produces the config path override; the full resolution is `CONFIG_FILE="${TEAM_SPRINT_CONFIG:-$(repo_root)/team-sprint.config.yaml}"`)
- `skills/team-sprint/team-sprint.config.yaml.example:173-178` `graphify_max_age_minutes` (produces the *documented* default of 240 for graphify's `fresh` vs `stale:<n>m` split — verified 2026-07-27 that `skills/team-sprint/team-sprint.config.yaml` does not exist and the live `$HOME/.claude/team-sprint.config.yaml` sets no `graphify_max_age_minutes` at all, so no config file is a producer of defaults and `recon.sh` supplies 240 itself)
- `skills/team-sprint/team-sprint.config.yaml.example:141-146` and `$HOME/.claude/team-sprint.config.yaml:30` `repomix_max_age_minutes` (produces the threshold for the repomix-served `text` intent; documented default and live value are both 240, and `recon.sh` hardcodes 240 for the empty return)
- `$HOME/.claude/CLAUDE.md` "Never run `find` from `/` or `~`" (produces the constraint on the file-count fallback)
- CodeGraph's FSEvents daemon, external (produces the `FRESHNESS=live` claim — see Open Question 2: auto-sync is daemon-backed, so `live` is only true while a daemon is actually running, which is why the label is gated on a probe rather than on the provider's identity)

Enforce the cost floor and the freshness contract.

**Config resolution.** `recon.sh` reads its keys from
`CONFIG_FILE="${TEAM_SPRINT_CONFIG:-$(repo_root)/team-sprint.config.yaml}"`. It deliberately does
NOT copy `coverage_check.sh:121`'s `${PWD}/team-sprint.config.yaml`: the config is untracked and
matched by `.gitignore`'s `/*` whitelist rule (verified 2026-07-27 — `git ls-files
team-sprint.config.yaml` is empty, `git check-ignore -v` reports `.gitignore:8:/*`), and
`phase-2.md:52-60` copies only the repomix pack and `graphify-out/` into a node worktree, so a
`$PWD`-relative lookup from a worktree CWD finds nothing and every recon key silently falls back to
its default. `repo_root()` is git-common-dir based (`lib.sh:61-75`) and resolves the main tree from
inside any worktree, so one rule serves both call sites. Every key still carries a hardcoded default
inside `recon.sh` for the empty string `read_config_scalar` returns when the file, or the key, is
absent.

**Small-repo guard.** Below `recon_min_files` (default 20) every structural intent returns
`STATUS=SKIP REASON=small-repo FILES=<n>` without touching a provider. The threshold's rationale is
quoted inline rather than cited: under about 20 files an agent can just read everything directly,
and the graph adds overhead with no payoff. It is inlined because its source (`union.md`) is
untracked and matched by the same `/*` whitelist rule (verified 2026-07-27: `git ls-files union.md`
empty, `git check-ignore -v union.md` → `.gitignore:8:/*`), so it never reaches a worktree and
cannot be read in the environment where this story's DoD is checked. File count comes from `git
ls-files`, captured as `n="$(git ls-files 2>/dev/null | wc -l)" || n=0` so a failing `git` cannot
abort the script under `pipefail`, falling back to a `find` scoped to the validated repo root —
never an unscoped `find` (`CLAUDE.md`: "Never run `find` from `/` or `~`").

**Root resolution precedes any `find`.** `repo_root()` shells `git rev-parse --git-common-dir`
(`lib.sh:71-75`); outside a repo that yields an empty string and `cd "$common/.."` lands on `/`, so
an unvalidated root would hand `/` straight to `find`. The guard therefore gates on `git rev-parse
--is-inside-work-tree >/dev/null 2>&1` BEFORE resolving a root, and on failure emits
`STATUS=SKIP REASON=not-a-repo FILES=0` and exits 0 — an answer, not an error, with no `find` run at
all. `not-a-repo` is a new value in the Output grammar's closed `REASON=` vocabulary and RH3 owns
adding it there. RH3 also hardens `repo_root()` itself so an empty `--git-common-dir` fails loud
instead of returning `/`, since `art_dir`, RH4's `.recon/` and RH1's capability cache all inherit
the same hazard — hence `lib.sh` and `lib.bats` in Touches.

**Freshness is computed per provider, against that provider's own max-age key.** Every answer
carries `FRESHNESS=`: codegraph against a daemon-liveness probe, graphify against
`graphify_max_age_minutes`, repomix against `repomix_max_age_minutes`, each with its own hardcoded
240 fallback inside `recon.sh`, so changing one key never moves another provider's label. `fresh`
when that provider's index mtime is within its own max age, `stale:<n>m` otherwise. Staleness is
reported, never silently corrected — a stale answer with an honest label is usable; a
silently-rebuilt index mid-review is not.

**`live` is a probe result, not a provider property.** CodeGraph's auto-sync is FSEvents-daemon
backed, so `live` is claimed only when a daemon-liveness probe succeeds — `codegraph status`
reporting an initialised, daemon-backed project, parsed from its **stdout** and never from its exit
code, which is 0 even when the project is not initialised (verified 2026-07-27 in `$HOME/.claude`:
prints `⚠ Not initialized`, exits 0). RH1's probe stores that parsed `indexed` bool in
`.recon/capabilities.json` and RH3 gates `FRESHNESS=live` on it; when the probe fails or reports
uninitialised, codegraph falls back to the same `mtime_epoch`-based `fresh`/`stale:<n>m` computation
graphify and repomix use.

**graphify freshness has a live producer; only `live` is stub-bound.** Verified 2026-07-28:
graphify is installed at `$HOME/.local/bin/graphify` and this repo's
`graphify-out/graph.json` is present and fresh — 2,763,824 bytes, 3453 nodes, rebuilt 2026-07-28
05:58 — so `fresh` and `stale:<n>m` are asserted against a real index, once the Design's Phase 0
precondition flips the live config's `graphify: off`
(`$HOME/.claude/team-sprint.config.yaml:32`, verified 2026-07-28) to `graphify: auto`.
Fixtures with a forced mtime remain only for what a live index cannot produce on demand — the
300-minute `stale:300m` case and the absent-index case — and `FRESHNESS=live` stays stub-only,
being CodeGraph-daemon-backed on a repo where CodeGraph is not initialised and parses no shell if
it were. RH6 owns the matching Phase 0 step, gated on `recon != off`: verify or rebuild that index
(plus `codegraph init` where CodeGraph can index the repo) so the freshness labels keep a real
producer before RH4's call log starts collecting the data Open Question 3 depends on.

### Acceptance Criteria
- In a repo with 19 tracked files, `recon.sh callers foo` prints `STATUS=SKIP REASON=small-repo FILES=19` and invokes no provider (assert via stub counter).
- At 20 files the same call proceeds to provider resolution.
- `recon.sh text foo` is **not** subject to the guard — text search is Tier 1 and stays cheap at any repo size.
- `recon_min_files: 0` disables the guard entirely.
- With the small-repo guard in place the declared evaluation order still holds — disabled, then intent match, then small-repo guard, then provider resolution — asserted by a case that trips two conditions at once: an unrecognised intent (`recon.sh frobnicate x`) in a 5-file repo yields `STATUS=NO_INTENT_MATCH`, never `STATUS=SKIP REASON=small-repo`.
- In a repo whose test files are all `.bats`, `recon.sh tests <changed-files…>` never emits `EMPTY` — CodeGraph parses no shell, so an empty answer would falsely read as "asked and found nothing" and would silently retire the convention-based test scoping in `SKILL.md` Phase 3/4; the codegraph link is skipped by the language filter and, because `tests` chains to tokensave and tokensave is exempt from that filter, the terminal status is `STATUS=DELEGATE PROVIDER=tokensave` — assert `REASON=language-unsupported` only on an intent whose chain is entirely bash-probeable.
- Invoked from a directory that is not a git repository, `recon.sh callers foo` emits exactly one `STATUS=SKIP REASON=not-a-repo FILES=0` line and exits 0, having shelled no `find` at all — assert the generated command string is empty and in particular is not rooted at `/` or `$HOME`.
- The file count is captured as `n="$(git ls-files 2>/dev/null | wc -l)" || n=0`, so a `git` failure never aborts the script under `set -euo pipefail` — assert with `git` stubbed to exit 128 from inside a real repo.
- The guard's file count never shells an unscoped `find`; assert the generated command is rooted at the validated repo path.
- `repo_root()` fails loud (non-zero, `fail`-style stderr message) when `git rev-parse --git-common-dir` returns empty, instead of resolving to `/` — asserted in `lib.bats` from a non-git temp dir.
- With no config file present at the resolved path, `recon_min_files` falls back to the hardcoded 20, `graphify_max_age_minutes` to 240 and `repomix_max_age_minutes` to 240 — assert by running `recon.sh` from a temp repo holding no `team-sprint.config.yaml`.
- With CWD inside a git worktree that carries no `team-sprint.config.yaml` of its own, `recon.sh` still reads `recon_min_files` from the main-tree config — assert in a worktree-shaped temp repo whose main tree sets `recon_min_files: 0` and whose worktree CWD is config-free.
- With `graphify-out/graph.json` mtime 300 minutes old and `graphify_max_age_minutes: 240`, output carries `FRESHNESS=stale:300m` and `STATUS=OK` (an answer, downgraded — not an error).
- graphify freshness is asserted against a real `graphify-out/graph.json` and not by forced-mtime fixture alone: with a genuine index present, `recon.sh spans <mod>` reports `FRESHNESS=fresh` or `FRESHNESS=stale:<n>m` and never `FRESHNESS=none` — this repo's index is verified present (3453 nodes, rebuilt 2026-07-28) and the Design's `graphify: auto` precondition is what makes it reachable.
- With `graphify-out/graph.json` absent, `recon.sh spans foo` emits exactly one STATUS line and exits 0 — assert in a temp repo with no `graphify-out` directory, so the absent-index branch is taken before any `mtime_epoch` call rather than letting the helper abort the script.
- A repomix-served `text` answer whose pack is older than `repomix_max_age_minutes` carries `FRESHNESS=stale:<n>m`, and changing `graphify_max_age_minutes` alone does not alter that label.
- A CodeGraph-served answer carries `FRESHNESS=live` only when the daemon-liveness probe succeeds — assert with `codegraph status` stubbed to report an initialised, daemon-backed project.
- With `codegraph status` stubbed to print `Not initialized` and exit 0, a CodeGraph-served answer is NOT labelled `live` and falls back to the `mtime_epoch`-based `fresh`/`stale:<n>m` computation — the branch reads stdout, never the exit code.

### Definition of Done
- [ ] `recon_guard.bats` green, covering the 19/20 boundary in both directions.
- [ ] Guard threshold and its rationale documented in the header comment, with the rationale quoted inline (under ~20 files an agent can read everything directly; the graph adds overhead with no payoff) and attributed to this plan — `union.md` is untracked and `.gitignore`-matched, so it is absent from the worktree where this DoD is checked and must not be the citation.
- [ ] The Output grammar block's closed `REASON=` vocabulary gains `not-a-repo`, its `FILES=` rule widens from "only on `STATUS=SKIP REASON=small-repo`" to also cover `REASON=not-a-repo FILES=0`, and the coverage-gate section's `REASON=` list gains the same value so the two cannot drift.
- [ ] `lib.bats` green on the hardened `repo_root()`, and `shellcheck` clean on `lib.sh` and `recon.sh`.
- [ ] **Contract coverage.** Every `FRESHNESS=` value (`live fresh stale:<n>m none`) has a test asserting it is emitted — including the absent-index case, which emits no `FRESHNESS=` at all and is asserted as such; every `REASON=` value RH3 emits (`small-repo not-a-repo language-unsupported`) has one; and the guard boundary is covered on BOTH sides (19 skips, 20 proceeds). Assert by looping the value lists against `grep -l`, not by eye.

---

## Story RH4: call log and `--explain`

### Depends On: RH1

### Touches:
- `skills/team-sprint/scripts/recon.sh`
- `skills/team-sprint/scripts/tests/recon_log.bats`
- `skills/team-sprint/scripts/lib.sh`
- `skills/team-sprint/scripts/tests/lib.bats`

### Boundaries:
- the target repo's `.gitignore` (RH4 appends `.recon/` to it — a file this story does not own and which may be a whitelist, as `$HOME/.claude/.gitignore` is: there `/*` ignores everything, `git check-ignore -v .recon/` already answers `.gitignore:8:/*` (verified 2026-07-27), and an appended `.recon/` line would be redundant, not effective)
- `union.md:43-44` (produces the unverified 58%-fewer-tool-calls vendor claim this log exists to test with local data)
- `skills/team-sprint/scripts/lib.sh` `repo_root()` at `lib.sh:61-75` (produces the `.recon/` location: git-common-dir based, so it returns the MAIN tree root from inside any worktree — the header comment documents exactly that intent for artifact dirs, and it is why the log is never resolved against CWD)
- `jq` (produces the encoding of every log line — `jq -c -n --arg`, `--argjson` for the numeric fields, as at `state.sh:165-172` and `state.sh:302`; `lib.sh:30` `require_jq` is the guard `recon.sh`'s preflight calls as `require_jq || exit 1`)
- `python3` (produces the millisecond clock behind `elapsed_ms`: `/bin/bash` is 3.2.57 (verified 2026-07-27) and has no `EPOCHREALTIME`, so `lib.sh` gains `now_ms()` shelling `python3 -c 'import time;print(int(time.time()*1000))'`, mirroring the python3-shellout convention `read_config_scalar` already uses at `lib.sh:195`)

**Call log.** Append one JSON object per invocation to `<main-repo-root>/.recon/calls.jsonl`.
The directory is resolved once through `lib.sh` `repo_root()` and never against `$PWD`, so every
node worktree appends to the single log the main tree holds — the same resolution RH1's
`.recon/capabilities.json` needs if the Phase 0 probe is to be reused by every node instead of
re-shelled N times. The object is fixed-arity — `{intent, provider, query, count, status,
freshness, elapsed_ms, ts}` — and is emitted with `jq -c -n --arg` (`--argjson` for `count` and
`elapsed_ms`), matching the JSON-emission convention at `state.sh:302`, never a hand-built string:
a query carrying a quote, a backslash or a tab must not be able to produce an unparseable line.
`provider`, `count` and `freshness` are explicit JSON `null` on every status that emits no header
line (`SKIP`, `DEGRADED`, `UNAVAILABLE`, `NO_INTENT_MATCH`, `DELEGATE`) — absent from the line
grammar, `null` in the fixed-arity JSON, exactly as the Output grammar block already fixes it.

**`elapsed_ms` has a producer.** `/bin/bash` here is 3.2.57, which has no `EPOCHREALTIME`, and
`date +%s%3N` is GNU-only, so RH4 adds `now_ms()` to `lib.sh` as a `python3` shell-out — the same
pattern `read_config_scalar` uses for the work bash cannot do. Hence `lib.sh` and `lib.bats` in
Touches.

The 58%-fewer-tool-calls figure in `union.md:43-44` is vendor-published and not
independently reproduced. The log is how this setup answers the question with its own data
after a few sprints, rather than adopting the claim on faith. It is also the evidence base
for retiring a provider that never wins a chain.

**`--explain`.** `recon.sh --explain <intent> <arg>` prints the provider it *would* use, the
full chain with each link's availability and why it was skipped, and the resolved command —
then exits without executing. Falls straight out of the query-planner model, and is the
debugging surface when an agent gets an answer it did not expect.

**`--explain` is a mode, and every mode ends in a status line.** It follows `--probe` exactly
(`graphify_ensure.sh:32`: every mode prints exactly one `STATUS=` line): after the chain report it
prints one terminal `STATUS=OK PROVIDER=<would-be-provider> INTENT=<intent>` when a link resolves,
or `STATUS=UNAVAILABLE REASON=not-installed` when none does. Both values are already in the closed
seven-value set, so the grammar gains nothing new. Like `--probe`, a mode status carries no
`PROVIDER= INTENT= FRESHNESS= QUERY=` header line and no `COUNT=`, and the chain report is mode
output rather than a result set, so its lines are exempt from the `<path>:<line>` result grammar.

**The `.gitignore` append is conditional.** `.recon/` is added only when
`git check-ignore -q .recon/` does not already match; against a `/*`-whitelist `.gitignore` the
line would be redundant and the file is left byte-identical.

### Acceptance Criteria
- Every invocation appends exactly one line to `<main-repo-root>/.recon/calls.jsonl`; each line parses as JSON under `jq -e .`.
- Invoked with CWD inside a git worktree, the log line is appended to `<main-repo-root>/.recon/calls.jsonl` — assert in a worktree-shaped temp repo that the main tree's log grew by one line and the worktree CWD holds no `.recon/` at all.
- A query containing a double quote, a backslash and a tab is logged and the resulting line still parses under `jq -e .`, with `.query` round-tripping byte-identical — assert via `jq -r .query`.
- `elapsed_ms` is a non-negative integer, and is strictly greater than 0 for a stubbed provider that sleeps.
- `now_ms()` in `lib.sh` echoes an integer millisecond epoch and two successive calls separated by a sleep differ — asserted in `lib.bats`.
- A small-repo `SKIP` invocation appends one line whose `provider`, `count` and `freshness` are JSON `null` (present-and-null, not absent) and which still parses under `jq -e .`.
- With `recon_log: off`, an invocation appends nothing to `.recon/calls.jsonl` and still prints its normal `STATUS=` line.
- `--explain callers foo` prints the chain, prints the resolved command, appends **nothing** to `calls.jsonl`, invokes no provider, prints exactly one `STATUS=` line, and exits 0.
- `--explain` ends in `STATUS=OK PROVIDER=<would-be-provider> INTENT=<intent>` when a link resolves and `STATUS=UNAVAILABLE REASON=not-installed` when none does — assert both against stubbed provider sets, and assert neither emits a `PROVIDER= INTENT= FRESHNESS= QUERY=` header line.
- `--explain` output names each unavailable provider with a reason (`not-installed`, `no-index`, `capability-mismatch`, `no-delegate`).
- A read-only `.recon/` directory degrades to `STATUS=OK` with a stderr WARN — logging never fails a query.
- `.recon/` is appended to the repo's `.gitignore` only when `git check-ignore -q .recon/` does not already match it; against a `/*`-whitelist `.gitignore` the file is left byte-identical — assert both fixtures.

### Definition of Done
- [ ] `recon_log.bats` green.
- [ ] Two `.gitignore` fixtures under `scripts/fixtures/recon/`: a conventional one with no matching rule, and a `/*`-whitelist one that `git check-ignore` already matches.
- [ ] Log schema documented in the header comment, split by status class: on `STATUS=OK|EMPTY` all eight fields carry values; on `SKIP|DEGRADED|UNAVAILABLE|NO_INTENT_MATCH|DELEGATE` only `intent status ts elapsed_ms` carry values and `provider`/`count`/`freshness` are explicit JSON `null`, never absent — the fixed-arity choice the Output grammar block already commits the log to.
- [ ] The header-comment mode list gains `--explain`, and `recon_log.bats` asserts `--explain` emits exactly one `STATUS=` line — mirroring `graphify_ensure.sh:32`.
- [ ] **Contract coverage.** Every field in the logged JSON object (`intent provider query count status freshness elapsed_ms ts`) is asserted by a test in BOTH status classes — carrying a value on `OK`/`EMPTY`, explicit `null` on the five non-answer statuses; the hostile-input query (quote, backslash, tab) has a test; both `.gitignore` fixtures have one; and every `--explain` skip reason (`not-installed no-index capability-mismatch no-delegate`) has one.

---

## Story RH5: config keys and degradation

### Depends On: RH1, RH3

### Touches:
- `skills/team-sprint/scripts/recon.sh`
- `skills/team-sprint/team-sprint.config.yaml.example`
- `$HOME/.claude/team-sprint.config.yaml`
- `skills/team-sprint/scripts/state.schema.json`
- `skills/team-sprint/scripts/tests/recon_config.bats`

### Boundaries:
- `skills/team-sprint/scripts/state.schema.json` (the DoD adds `recon_degraded` to it; `additionalProperties` is `true`, so an unknown key passes validation silently — the schema must be edited or the flag is unenforced)
- `$HOME/.claude/team-sprint.config.yaml` (the live sprint config, where the `recon` block must actually land or every key resolves to its hardcoded default for the whole sprint; it is **untracked** and matched by `.gitignore:8:/*` — verified 2026-07-28, `git ls-files team-sprint.config.yaml` empty and `git check-ignore -v` reports that rule — so the edit appears in no `git diff` and its DoD is asserted by reading the file, never by diff)
- `skills/team-sprint/scripts/lib.sh` `read_config_scalar` / `read_config_commands` (produce the config values; the parser handles only a top-level key or a `commands:` block, so a nested `recon:` map would need parser work this story does not scope — and a YAML **flow sequence** is not parsed either: verified 2026-07-28, `read_config_scalar` on `recon_providers: [codegraph, graphify]` returns the literal string `[codegraph, graphify]`, brackets and comma included, which is why `recon_providers` is a space-separated scalar)
- `skills/team-sprint/team-sprint.config.yaml.example:152-178` (produces the `off|auto|on` comment format the new keys must mirror)

Extend the config with a `recon` block, mirroring the `off|auto|on` enum vocabulary and
comment style the existing `graphify:` key already uses
(`team-sprint.config.yaml.example:152-178`).

```yaml
recon: auto                  # off | auto | on
recon_min_files: 20          # small-repo guard threshold; 0 disables
recon_providers: codegraph graphify repomix tokensave   # space-separated allow-list
recon_log: on                # off | on
recon_max_lines: 50          # type: int             default: 50    result-line cap
recon_probe_max_age_minutes: 1440   # type: int (minutes)   default: 1440   capability-cache TTL
```

**`recon_providers` is a space-separated scalar, not a YAML sequence, and it is the single
source of truth for provider opt-out.** `read_config_scalar` parses a top-level scalar and
nothing else — verified 2026-07-28, a flow sequence comes back as the literal string
`[codegraph, graphify]`, brackets and comma included — so the scalar form works with the
existing parser unmodified and RH5 needs no `lib.sh` change and no `read_config_list` helper.
There is deliberately no per-provider `<provider>_enabled` key: dropping a name from
`recon_providers` already expresses exactly that, and a second surface expressing the same
thing is a precedence question with no right answer. One consequence is load-bearing and
documented in the comment block: an empty value (`recon_providers:`) is indistinguishable
from an absent key — `read_config_scalar` returns the empty string for both (verified
2026-07-28) — so it resolves to the default chain, and the way to run no providers at all is
`recon: off`.

`auto` = probe, use what is present, WARN and continue on absence. `on` = Phase 0 gate.
`off` = the router is never invoked and callers go straight to the instruments themselves:
`rtk grep` over the repomix pack at `${REPOMIX_PACK:-.repomix-output.xml}` for text,
`graphify query` / `graphify path` / `graphify explain` for structure, and live `Read` for
verification. Naming the instruments here rather than pointing at a prose convention keeps
this branch true after RH6 rewrites `CLAUDE.md`.

**Degradation is total and silent-to-the-sprint.** All providers absent → the router still
serves `text` via repomix, sets `state.json.recon_degraded=true`, and the sprint proceeds.
This mirrors the existing `graphify_degraded` fail-soft. No recon tool ever blocks a sprint
under `auto`. The flag has a writer as well as a schema entry: Phase 0 step 10 records the
verdict with `bash "$SCRIPTS/state.sh" update "$plan_path" recon_degraded='<true|false>'`,
omitted entirely when `recon: off`, exactly mirroring the `graphify_degraded` line at
`phase-0.md:61`. RH5 owns the `state.schema.json` edit; RH6 owns the `phase-0.md` edit and
carries the AC for it.

`gitnexus` is **not** a valid `recon_providers` value. Supplying it is a config error with a
message naming the PolyForm-Noncommercial licence as the reason — a future reader must not
have to rediscover why the obvious third tool is missing.

### Acceptance Criteria
- `recon: off` → `recon.sh` any-intent returns `STATUS=SKIP REASON=disabled`, exits 0.
- `recon: on` with zero providers available → exit non-zero (Phase 0 gate fails loud).
- `recon: auto` with zero providers → `STATUS=DEGRADED`, exit 0.
- `recon.sh docs <q>` in a repo with no `graphify-out/graph.json` does not terminate: the graphify link is skipped as `no-index` and the chain advances to repomix, so the answer reports `PROVIDER=repomix` — assert both fixtures, an installed graphify over an unindexed repo and an absent graphify binary, each still answered by repomix.
- `recon.sh docs <q>` emits a terminal `STATUS=UNAVAILABLE` only when both links are unavailable, carrying the last link's own reason: `REASON=no-index` when the repomix pack `${REPOMIX_PACK:-.repomix-output.xml}` is missing (the pack is repomix's index) and `REASON=not-installed` when `rtk`/`repomix` is absent — assert both.
- `recon_providers: gitnexus` (in any position of the space-separated list) → exit non-zero with a message containing `PolyForm-Noncommercial`.
- `recon_providers:` with an empty value resolves to the default chain `codegraph graphify repomix tokensave`, not to zero providers — the empty and absent cases are indistinguishable to `read_config_scalar` and both take the default.
- Every new key has a comment block naming its type and default, matching the `type: / default:` column format at `team-sprint.config.yaml.example:152-178`.
- Every recon key carries a hardcoded default inside `recon.sh` for the empty string `read_config_scalar` returns when the config file, or the key, is absent — assert by running each key's behaviour from a temp repo holding no `team-sprint.config.yaml` at all, and again from one whose config omits just that key.
- No recon key is read from a nested map or a YAML sequence — every one is a top-level scalar `read_config_scalar` can parse unmodified, asserted by reading each key back out of the example file.

### Definition of Done
- [ ] `recon_config.bats` green.
- [ ] `recon_degraded` added to `scripts/state.schema.json`.
- [ ] The `recon` block is present in the live `$HOME/.claude/team-sprint.config.yaml`, asserted by reading the file (it is untracked and `.gitignore`-matched, so it appears in no `git diff`) — otherwise every key resolves to its hardcoded default for the whole sprint.
- [ ] **Contract coverage, split per key kind** — each list looped against `grep -l` on `recon_config.bats`, not checked by eye. `recon` exercises all three enum values (`off auto on`). `recon_log` exercises both (`off on`). `recon_providers` exercises three cases: a valid list, an empty value, and one containing `gitnexus`. `recon_min_files` exercises 0 / below-threshold / at-threshold — already covered by RH3's 19/20 boundary ACs, so RH5 cross-references those tests rather than duplicating them. `recon_max_lines` exercises below-cap and over-cap, the over-cap case asserting both the single `TRUNCATED=<emitted>/<total>` line and the pre-truncation `COUNT=`. `recon_probe_max_age_minutes` exercises within-TTL (no provider exec) and expired (re-probe), reusing RH1's stub-counter fixture. An unexercised enum branch is an untested branch.

---

## Story RH6: distribution to skills and agents

### Depends On: RH1, RH5

### Touches:
- `CLAUDE.md`
- `skills/team-sprint-planner/references/recon-instruments.md`
- `skills/team-sprint/SKILL.md`
- `skills/team-sprint/phases/phase-0.md`
- `skills/team-sprint/scripts/tests/recon_distribution.bats`

### Boundaries:
- `agents/*.md` — **explicitly not edited** (their correctness depends on the inheritance fact, not on their contents: every custom subagent inherits `$HOME/.claude/CLAUDE.md` automatically, so editing the CLAUDE.md section reaches all of them. Verified at Claude Code 2.1.220, `code.claude.com/docs/en/sub-agents` → "What loads at startup"). No file count is stated on purpose — the cardinality is decorative and rots; the load-bearing claim is inheritance. Verified 2026-07-28: `agents/` is 51 files, all tracked, working tree clean, so nothing there blocks Phase 0.
- built-in `Explore` and `Plan` agents (the **only** subagents that skip CLAUDE.md and git status, and it is not configurable — they will never see the recon ladder, so any rule they need belongs in the delegation prompt)
- `$HOME/.claude/CLAUDE.md` git history (produces the ≤8-net-line budget's rationale: the file was deliberately consolidated 8628→7019 bytes on 2026-07-27 and has since grown back to 7910 at HEAD. Verified 2026-07-28 that HEAD and the working tree agree at 7910 bytes with `git status --porcelain CLAUDE.md` empty, so the assertion is `git diff --numstat BASE...HEAD -- CLAUDE.md` and no pre-sprint commit or stash of `CLAUDE.md` is needed)
- `skills/team-sprint/scripts/lint_skill.sh` check 6 (produces the dangling-anchor failure if the new SKILL.md text adds an internal anchor link)
- `skills/tech-debt-audit/SKILL.md` and `skills/adversarial-review/SKILL.md` — **deliberately left stale, not updated by this story.** Verified 2026-07-28 that neither restates the three-layer list (no "three layers" string in either file), so neither contradicts the new ladder; both describe repomix/graphify in their own words, and copying the ladder into them is precisely the duplication-drift the CLAUDE.md-only mechanism exists to avoid. One **pre-existing defect** is inherited rather than introduced or fixed here: `tech-debt-audit/SKILL.md:51` says to grep the pack with bash `grep`/`rg` because "the RTK `PreToolUse` hook rewrites these", which contradicts `CLAUDE.md:118-119`'s "explicit `rtk grep` … never trust the RTK hook to rewrite it". Reconciling the two is out of RH6's scope; it is filed as an open question, not silently absorbed.

Make the harness reachable without editing every agent definition.

**The distribution mechanism is `CLAUDE.md`'s "Codebase recon instruments" section** — every
agent already inherits it. Replace the three-layer list with the four-tier ladder plus one
line pointing at `recon.sh`. Budget: **≤8 net added lines.** This file is loaded every turn
and was deliberately consolidated on 2026-07-27; the harness does not get to undo that.

Editing individual `agents/*.md` files is explicitly out of scope — `CLAUDE.md` already
states custom subagents inherit it and that duplicating rules into agent files causes drift.

Phase 0 gains a `recon.sh --probe` step alongside the existing `graphify_ensure.sh` calls at
`phase-0.md:40-53`, following the same STATUS-branch structure.

### Acceptance Criteria
- `CLAUDE.md`'s recon section documents all four tiers and the "never escalate a tier you can answer at a lower one" rule.
- The `CLAUDE.md` diff adds ≤8 net lines, anchored to the sprint base ref exactly as `per_story_diff.sh:81` and `coverage_check.sh --mode new` do: `git diff --numstat BASE...HEAD -- CLAUDE.md`, never a bare working-tree `git diff`.
- The rewritten recon section retains, verbatim, the explicit-`rtk grep` / never-trust-the-hook rule and the delete-the-pack-to-refresh instruction, folded into the Tier 1 row so the ≤8-net-line budget still holds — asserted by grepping the post-edit `CLAUDE.md` for `never trust the RTK hook`.
- Nothing under `skills/` or in `CLAUDE.md` still describes the recon convention as "three layers" — asserted by `grep -rn 'Three layers — the convention' CLAUDE.md skills/ --exclude-dir=plans` returning no hit, the `--exclude-dir=plans` being load-bearing because this plan file quotes the phrase itself and would otherwise match forever; `skills/humanise/SKILL.md:8` uses `Three layers:` for an unrelated subject (Australian English) and does not match the full phrase, while `skills/officecli` does not use it at all (verified 2026-07-28: `grep -rni 'three layer' skills/officecli/` returns nothing) — both are out of scope.
- No file under `agents/` is modified by this story — asserted with both `git status --porcelain agents/` (catches untracked additions, which a diff misses) and `git diff --name-only BASE...HEAD -- agents/`, each expected empty.
- `recon-instruments.md` routes structural questions through `recon.sh` and retains the existing `rtk grep`-on-pack instruction verbatim.
- The `recon.sh` block added to `recon-instruments.md` is guarded by the same executable test the graphify block at `recon-instruments.md:42-43` uses — `RS=$HOME/.claude/skills/team-sprint/scripts/recon.sh; if [ -x "$RS" ]; then ...; fi` — and the surrounding text states the fallback when it is absent, asserted by grepping the post-edit file for `-x "$RS"`.
- `phase-0.md` invokes `recon.sh --probe` under `recon != off` and branches on `STATUS=OK|DEGRADED|SKIP`, with the disposition worded as at `phase-0.md:42`: STOP under `recon: on`, else WARN + set `recon_degraded=true` and continue — the same step both branches and persists the flag.
- The `phase-0.md` probe step runs `codegraph init` before `recon.sh --probe` whenever the codegraph binary is present and `codegraph status` reports the project uninitialised (parsed from stdout, which exits 0 either way), so a present-but-unindexed CodeGraph is indexed rather than permanently reported `no-index` — asserted by grepping the post-edit `phase-0.md` for `codegraph init`.
- That same `phase-0.md` step is gated on `recon != off` and builds or probes at least one real index (a graphify build or `codegraph init`), so `FRESHNESS=fresh` and `FRESHNESS=live` have a live producer this sprint instead of fixtures alone — asserted by grepping the post-edit `phase-0.md` for the `recon != off` gate and the index-building call.
- `team-sprint/SKILL.md`'s optional-sub-skills section describes the router in one paragraph, matching the existing `graphify` bullet's format.
- `team-sprint/SKILL.md`'s config block gains one line per new recon key in the same `key: value  # comment` column format as the adjacent `graphify:` / `graphify_max_age_minutes:` lines at `SKILL.md:57-58` — asserted by grepping the post-edit SKILL.md for each of `recon:`, `recon_min_files:`, `recon_providers:` and `recon_log:`. This is additional to, and separate from, the optional-sub-skills paragraph, and both count against SKILL.md's own budget, never the `CLAUDE.md` ≤8-net-line budget.

### Definition of Done
- [ ] `bash skills/team-sprint/scripts/lint_skill.sh` clean — **team-sprint only**; the script hardcodes its own skill dir at `lint_skill.sh:16` (`SKILL_DIR="$(cd "$HERE/.." && pwd)"`), so no invocation of it lints `team-sprint-planner`. Adding a `--skill-dir` argument is a separate change with its own `lint_skill.bats` AC, deliberately out of RH6's scope; the planner-side edit is covered by `recon_distribution.bats` instead.
- [ ] `recon_distribution.bats` green — discovered by the same `run-all.sh:54` glob (`bats_files=("$TESTS_DIR"/*.bats)`); there is no registry to edit and no registration step to perform. Both mechanical assertions below live in it.
- [ ] The `CLAUDE.md` ≤8-net-line budget is met, asserted as `git diff --numstat BASE...HEAD -- CLAUDE.md`.
- [ ] **Contract coverage.** All four escalation tiers appear in the CLAUDE.md text, and the "no file under `agents/` is modified" AC is asserted mechanically — `n="$(git diff --name-only BASE...HEAD | grep -c '^agents/' || true)"; [ "$n" -eq 0 ]` plus `[ -z "$(git status --porcelain agents/)" ]` — not by inspection. The `|| true` is load-bearing: `grep -c` exits 1 on zero matches and the bats helpers run under `set -euo pipefail`, so the unguarded form fails exactly in the passing case; this matches `lint_skill.sh:111`.
- [ ] The `-B 2` comment at `skills/team-sprint-planner/references/recon-instruments.md:25` is corrected in the same pass that adds the `recon.sh` block to that file: `-B 2` cannot reach the owning `<file path=…>` tag, which routinely sits hundreds of lines above the hit. (Moved here from RH1's DoD — the file is in RH6's Touches and not RH1's, so RH1 could never satisfy it.)

---

## Open questions

1. ~~**CodeGraph CLI query surface.**~~ **Resolved 2026-07-27.** Installed 1.5.0 via
   `npm install -g @colbymchenry/codegraph`; `codegraph --help` confirms a full bash CLI
   (`callers`, `callees`, `impact`, `affected`, `explore`, `node`, `query`, `files`, `sync`,
   `status`). CodeGraph is a bash provider. Its `install` subcommand — the one that writes
   into `CLAUDE.md` — is never invoked by this harness. The `npm install -g` itself was
   verified not to mutate `CLAUDE.md` (SHA-256 identical before and after).
2. **Daemon lifecycle.** `codegraph daemon` manages background indexers and `codegraph unlock`
   clears stale locks — so the auto-sync in `union.md:128-133` is daemon-backed, not free. On
   a machine with many indexed repos this is N background processes. Index pruning and orphaned-
   daemon cleanup are NOT in this sprint (RH7 was cut); they belong with provisioning. Measure
   real daemon count after ~2 weeks before deciding whether auto-sync stays on by default.
3. **tokensave overlap.** tokensave already answers `callers`, `impact` and `coupling`. If its
   answers prove as good as CodeGraph's on this machine's repos, CodeGraph's marginal value
   collapses to `dynamic` alone — which may still justify it, since nothing else traces
   callbacks. RH4's call log is the instrument that decides this; revisit after ~3 sprints.
4. **Intent vocabulary growth.** Ten intents is deliberately small. An eleventh should require
   evidence from `calls.jsonl` that the gap is real and recurring, not a one-off.
5. **RTK-hook contradiction (pre-existing, not introduced by this sprint).** `CLAUDE.md:118-119`
   says to grep the pack with **explicit `rtk grep`** and never trust the hook to rewrite it;
   `skills/tech-debt-audit/SKILL.md:51` says the opposite — use bash `grep`/`rg` because the RTK
   `PreToolUse` hook rewrites them — and `RTK.md` backs the hook reading. Verified 2026-07-28.
   RH6 preserves the CLAUDE.md rule verbatim and does not touch tech-debt-audit, so the drift
   survives this sprint. Decide which reading is correct and fix the loser in a separate change.

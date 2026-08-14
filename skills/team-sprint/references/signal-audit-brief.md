# Signal audit brief — hand this to an auditing agent

**WHO READS THIS / WHEN:** an agent asked to audit a repo and produce a defect-signal report.
Pair it with `signal-ledger.md`, which defines the schema you emit against.

You are hunting **silent wrongness**: things that look fine and are not. Crashes announce
themselves and need no ledger. What this brief exists to catch is the class of defect where a
document and its implementation drift apart while both read plausibly, and nobody notices until
something is built on the gap.

Read `signal-ledger.md` §2 (schema), §3 (categories and severity), §5 (emission contract) before
starting. §5 is binding: unevidenced signals are capped at `UNVERIFIED` and are never actioned.

---

## The stance

**Assume the thing you are auditing is broken and try to prove it.** An audit that sets out to
confirm health finds health. Every check below is phrased as a refutation attempt on purpose.

**Run the command. Do not read the code and reason about it.** The single highest-yield finding
in the sprint that produced this brief came from running `graphify affected mtime_epoch` and
getting `No affected nodes found` while `rtk grep` found six real references. Reading either
tool's source would never have surfaced it. Two other findings that session were nearly reported
backwards because a five-row sample was unrepresentative — widen the sample, then check.

**Report what you cannot verify as `UNVERIFIED` and downgrade it.** A fabricated signal is worse
than a missed one, because this ledger is drained automatically by agents that will not
second-guess you.

---

## The seven sweeps

Run all seven. Each names the category it feeds.

### 1. Doc-vs-code drift → `CONTRACT_DRIFT`

For every script with a header comment block, and every doc that describes a script's behaviour:
read the description, then read the implementation, then **run it** and compare all three.

- Does the header enumerate modes/statuses/exit codes the code no longer emits, or omit ones it does?
- Does a phase/skill doc describe a script doing something it does not do?
- Where two docs describe the same mechanism, do they agree?

> *Real hit:* `phase-1.md:124` claimed a script *"rewrites the plan paragraph-by-paragraph"*.
> The script's own line 2 says it **annotates**. The loop that depended on rewriting could never
> terminate — and both documents had been reviewed repeatedly without anyone reading them together.

### 2. Gate integrity → `GATE_DEFECT`

For every gate (anything that can block progress), ask three questions:

- **Is it reachable?** Can the thing it gates ever satisfy it? A gate whose fix-step cannot
  change what the gate measures is decorative.
- **Does it measure the thing it claims?** Find a way to pass it while violating its intent. If
  you find one, that is at least HIGH, usually CRITICAL.
- **Does it fail open or closed?** What happens when its measuring tool is missing, unreadable,
  or errors? A guard that degrades to a pass is not a guard.

> *Real hit:* a gate counted marker comments to prove review findings had been applied. Deleting
> a marker without applying it passed the gate — 10 findings were destroyed while it reported
> clean. It could not distinguish resolution from erasure.

### 3. Citation truth → `PROVENANCE`

Extract every `file:line` reference in docs, plans and comments. **Read each cited range.** Does
it say what the citing text claims?

Cheap, mechanical, and consistently productive — line numbers rot every time a file is edited,
and nothing checks them. Sample at least 10; report the sample size so the reader can calibrate.

### 4. Scope and reachability → `SCOPE`

- Does anything declare a target outside the repo root? `git ls-files <path>` — empty means it
  can never appear in a diff, be reviewed, be merged, or be rolled back.
- Does any run depend on a file `git check-ignore` rejects? Then it cannot be materialised in a
  worktree or on a fresh clone.
- Does a reviewed artifact differ from the executed one? Compare hashes, not names.

> *Real hit:* a story declared `Touches: justfile` while its line citations resolved against a
> different file in `$HOME`. Untracked, so every sprint guarantee — isolation, diff, review,
> merge, rollback — silently did not apply to it.

### 5. Lifecycle and automation → `LIFECYCLE`

- **Ordering:** in any update/install recipe, does step N invalidate step M? Run it, then
  re-check the versions it claims to have synced.
- **Interrupt safety:** any `mktemp` → write → `mv` sequence — is the temp file trap-cleaned? Is
  a lock released on signal?
- **Silent overwrite:** can two processes write the same generated path with no guard?
- **Mutation vectors:** does any third-party installer write into config you care about?
  Checksum before and after; assert absence of files it might create.

> *Real hit:* an update recipe upgraded a package but never re-synced its dependent skill, so
> every upgrade silently reopened a version drift — visible only by running the recipe and
> re-checking the version.

### 6. Answer honesty → `SEMANTIC` (highest value; do not skip)

For anything that answers questions — a query tool, an index, a router:

**Establish ground truth independently, then compare.** Pick a fact you can verify by direct
search, ask the tool, and diff the answers.

- Does it ever return "nothing found" when something exists? That is a **false negative** and is
  always CRITICAL. Silence reads as "safe to proceed", so it is more dangerous than an error.
- Does it distinguish *"I looked and found nothing"* from *"I cannot look"*? Collapsing those two
  into one empty answer is the defect underneath most false negatives.
- Where a tool covers only some inputs (languages, file types), is that coverage *checked*, or
  assumed?

> *Real hit:* a graph tool indexed 106 bash functions but 12 of one file's 23 had zero inbound
> call edges — it answered "no callers" for functions with six real call sites. Its fixtures all
> passed. Only ground-truth comparison exposed it.

### 7. Internal consistency → `SEMANTIC`

- Do any two requirements demand opposite outcomes for the same input?
- Is every closed vocabulary (status values, reason codes, enums) the same everywhere it is
  enumerated? Extract each list and diff them.
- Is every requirement satisfiable *within the scope of whoever owns it*? A requirement needing a
  deliverable from a component that depends on it is unsatisfiable in either order.
- Is every requirement written where its consumer actually reads? A rule in prose that the
  consumer parses from a structured field does not exist.

> *Real hit:* an instruction to add a criterion to story B was written as prose in section A
> reading *"B carries the criterion…"*. The parser exposed only structured criteria arrays, so
> implementers never saw it. It passed every check and reached nobody.

---

## Output

Emit one row per defect, per `signal-ledger.md` §2. Deliver as JSONL — one object per line, ready
for import:

```json
{"category":"GATE_DEFECT","severity":"CRITICAL","component":"skills/team-sprint/scripts/findings_gate.sh",
 "locus":"findings_gate.sh:1-20","issue":"The gate counts marker comments, so it cannot distinguish a folded finding from a deleted one.",
 "consequence":"A fold that deletes markers without applying them reports STATUS=OK COUNT=0; 10 of 64 findings were destroyed while the gate read clean.",
 "fix":"Require an adversarial coherence pass diffing the folded plan against the pre-fold copy, asserting each recommendation appears in PARSED output.",
 "evidence_cmd":"bash findings_gate.sh plan.md","evidence_out":"STATUS=OK COUNT=0",
 "verified":1,"blocking":1,"emitted_by":"bash-code-reviewer","emitted_at":"2026-07-28T04:00:00Z"}
```

Then a short prose summary: how many signals by category and severity, **which sweeps found
nothing** (a silent sweep is data — either the area is clean or your check was too narrow, and
saying which you believe is part of the job), and the single finding you would fix first.

**Do not fix anything.** Auditing and repairing in one pass means the auditor grades its own
work — the ledger's separation of `attempt.verify_cmd` from `signal.evidence_cmd` exists
precisely to keep those two agents apart.

---

## Calibration

A thorough audit of a mature ~20-script repo yields roughly 15–30 signals, most `MEDIUM`, with
1–3 `CRITICAL`. Wildly outside that range is itself a signal:

- **Zero, or 2–3 findings** — your sweeps were too narrow, or you audited what was easy to check
  rather than what was load-bearing. Sweeps 6 and 7 are the usual omissions.
- **100+** — you are reporting style preferences. Every row must have a real `consequence`;
  if you cannot state what breaks, it is not a signal.

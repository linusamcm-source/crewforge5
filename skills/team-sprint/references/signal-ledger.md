# Signal Ledger — schema and emission contract

**WHO READS THIS / WHEN:** any agent asked to report defect signals; the reaper that drains the
ledger; anyone wiring a self-repair loop.

A **signal** is one evidenced defect observation. Agents emit signals; the ledger accumulates
them across sessions; a periodic reaper resolves them. The loop terminates when a full sweep
emits nothing new — that is the definition of done, not a count.

The ledger is SQLite. It is deliberately not JSONL: the loop needs `UPDATE`, dedupe by key,
recurrence counting, and "show me every open CRITICAL not seen in 30 days" — all of which are
one query and none of which are cheap over append-only text.

---

## 1. Why this exists

`$HOME/.claude` is ~20 shell scripts, ~50 agents and ~40 skills that reason about each other. The
failure mode is never a crash. It is a **document and its implementation drifting apart while
both look fine** — and the drift is only visible to whoever happens to read both in one sitting.

One sprint (`sprint-recon-harness-1`, 2026-07-27/28) produced 24 such observations. Every one
was found by accident, in prose, in a chat transcript that will be garbage-collected. This
schema exists so the next one is a row instead.

The taxonomy in §3 is **derived from those 24**, not imagined. Each category earned its place by
having been hit at least once.

---

## 2. Schema

```sql
-- One evidenced defect observation.
CREATE TABLE IF NOT EXISTS signal (
  id              INTEGER PRIMARY KEY,
  dedupe_key      TEXT    NOT NULL,          -- see §4. THE load-bearing column.
  category        TEXT    NOT NULL,          -- §3 enum
  severity        TEXT    NOT NULL,          -- CRITICAL|HIGH|MEDIUM|LOW|UNVERIFIED
  status          TEXT    NOT NULL DEFAULT 'open',
                                             -- open|fixed|wontfix|duplicate|superseded|stale
  component       TEXT    NOT NULL,          -- repo-relative path, or external:<name>
  locus           TEXT,                      -- 'file.sh:120-125' when narrower than component

  issue           TEXT    NOT NULL,          -- ONE sentence. What is wrong.
  consequence     TEXT    NOT NULL,          -- what breaks BECAUSE of it. Not a restatement.
  fix             TEXT,                      -- concrete, actionable. NULL only if unknown.

  -- Provenance. An unevidenced signal is worthless; these two columns are the whole point.
  evidence_cmd    TEXT    NOT NULL,          -- the exact command run
  evidence_out    TEXT    NOT NULL,          -- its LITERAL output, truncated not paraphrased
  verified        INTEGER NOT NULL DEFAULT 0,-- 1 = evidence_cmd was run THIS session

  emitted_by      TEXT    NOT NULL,          -- agent type or 'human'
  emitted_at      TEXT    NOT NULL,          -- ISO8601 UTC
  run_id          TEXT,                      -- workflow/session id, for blast-radius queries

  -- Lifecycle
  seen_count      INTEGER NOT NULL DEFAULT 1,-- incremented on recurrence, NOT a new row
  last_seen_at    TEXT    NOT NULL,
  resolved_at     TEXT,
  resolved_by     TEXT,
  resolution_note TEXT,
  duplicate_of    INTEGER REFERENCES signal(id),
  blocking        INTEGER NOT NULL DEFAULT 0,-- 1 = must not ship with this open

  CHECK (severity IN ('CRITICAL','HIGH','MEDIUM','LOW','UNVERIFIED')),
  CHECK (status   IN ('open','fixed','wontfix','duplicate','superseded','stale')),
  CHECK (verified IN (0,1)),
  -- A CRITICAL or HIGH must be verified. Unevidenced severity is how a ledger rots.
  CHECK (verified = 1 OR severity IN ('MEDIUM','LOW','UNVERIFIED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS signal_dedupe ON signal(dedupe_key) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS signal_triage ON signal(status, severity, category);
CREATE INDEX IF NOT EXISTS signal_component ON signal(component);

-- Every attempt to resolve a signal, successful or not. Append-only.
-- Without this the loop cannot tell "not tried yet" from "tried 4 times and cannot".
CREATE TABLE IF NOT EXISTS attempt (
  id           INTEGER PRIMARY KEY,
  signal_id    INTEGER NOT NULL REFERENCES signal(id),
  attempted_at TEXT    NOT NULL,
  attempted_by TEXT    NOT NULL,
  outcome      TEXT    NOT NULL,             -- fixed|failed|deferred|rejected
  verify_cmd   TEXT,                         -- how the fix was PROVEN, not asserted
  verify_out   TEXT,
  note         TEXT,
  CHECK (outcome IN ('fixed','failed','deferred','rejected'))
);
CREATE INDEX IF NOT EXISTS attempt_signal ON attempt(signal_id);

-- One row per sweep. Convergence is measured here, not felt.
CREATE TABLE IF NOT EXISTS sweep (
  id             INTEGER PRIMARY KEY,
  started_at     TEXT NOT NULL,
  finished_at    TEXT,
  scope          TEXT NOT NULL,              -- what was swept
  signals_new    INTEGER NOT NULL DEFAULT 0,
  signals_recur  INTEGER NOT NULL DEFAULT 0,
  signals_fixed  INTEGER NOT NULL DEFAULT 0,
  dry            INTEGER NOT NULL DEFAULT 1  -- 1 = found nothing new. Two in a row = converged.
);
```

---

## 3. Categories

Each is a real failure this setup has hit. The example is the actual incident.

| category | definition | worked example |
| --- | --- | --- |
| `CONTRACT_DRIFT` | a document states X, the code does Y | `phase-1.md:124` said `apply_findings.sh` *"rewrites the plan paragraph-by-paragraph"*; the script's own header says it **annotates**. Phase 1 could never converge. |
| `GATE_DEFECT` | a gate is unreachable, measures the wrong thing, or fails open | `findings_gate.sh` counts markers, so it cannot distinguish folding from **deleting** — it returned `COUNT=0` on a plan where 10 findings had been destroyed. |
| `PROVENANCE` | a `file:line` citation does not say what cites it | a plan cited `state.sh:163` for a jq convention; `sed -n '163p'` prints `  local tmp`. |
| `SCOPE` | a target outside the repo, or an untracked file a run depends on | a story declared `Touches: justfile`, but `git ls-files justfile` is empty and the real target was `~/justfile` — outside version control, so it could never appear in a diff, review, or merge. |
| `LIFECYCLE` | version drift, ordering bug, resource leak, silent overwrite | `just update` upgrades the graphify *package* but never re-runs `graphify install`, so every upgrade leaves the skill stale. Observed live: 0.9.27 → 0.9.28, drift warning immediately back. |
| `SEMANTIC` | false negative, vocabulary drift, unsatisfiable requirement, self-contradiction | two acceptance criteria demanded opposite terminal statuses for the same input, because tokensave's exemption from the language filter was never declared. |

### Severity

Severity is about **consequence**, never about how annoying it is.

- `CRITICAL` — silently produces a wrong answer that will be acted on, or makes a gate
  unreachable/meaningless. **A false negative is always CRITICAL**: silence reads as "safe",
  and that is worse than an error, which at least gets noticed.
- `HIGH` — breaks a contract another component relies on; wrong but detectable.
- `MEDIUM` — real defect, bounded blast radius, no silent wrongness.
- `LOW` — cosmetic, or a latent trap with no current trigger.
- `UNVERIFIED` — believed but not evidenced. **Never actioned automatically.**

---

## 4. `dedupe_key` — the column the loop lives or dies on

Recurrence must be *counted*, not re-inserted. A loop that files a fresh row each sweep can
never tell progress from churn, and will never report convergence.

```
dedupe_key = sha256(category + '|' + component + '|' + normalized_issue)[:16]
```

`normalized_issue`: lowercase, collapse whitespace, strip line numbers and digits. Line numbers
move when a file is edited; the defect does not.

On emit: `INSERT … ON CONFLICT(dedupe_key) DO UPDATE SET seen_count = seen_count + 1,
last_seen_at = excluded.last_seen_at`.

A signal recurring after being marked `fixed` is the single most valuable row in the ledger — it
means a fix did not hold. Re-open it, do not insert a twin:

```sql
UPDATE signal SET status='open', seen_count=seen_count+1, last_seen_at=:now
WHERE dedupe_key=:k AND status='fixed';
```

---

## 5. Emission contract

Every emitting agent must satisfy all five:

1. **Evidence is a command you ran this session.** Not memory, not training data, not a prior
   transcript. `evidence_cmd` + `evidence_out` are mandatory and `evidence_out` is literal —
   truncated if huge, never paraphrased.
2. **`verified=0` caps severity at `UNVERIFIED`.** The schema enforces it. A fabricated signal is
   worse than no signal, because this ledger is drained automatically.
3. **`consequence` must not restate `issue`.** "The header is wrong" is an issue; "so RH6 writes a
   `phase-0.md` branch on a status `recon.sh` can never emit, silently swallowing the real
   failure" is a consequence. Rows without a real consequence are noise and get deprioritised.
4. **Negative claims need triple verification** — exact grep, case-insensitive grep, and a glob
   for filename patterns. All three zero, or it is not a negative finding.
5. **One defect per row.** If the fix has two independent halves, that is two signals. The
   sprint that motivated this file lost 10 findings to exactly this: a recommendation with two
   halves had one half applied and the other silently dropped.

---

## 6. The self-repair loop

```
sweep:
  1. OPEN SWEEP        insert a `sweep` row, dry=1
  2. HARVEST           fan out read-only auditors over scope; each emits signals
                       (INSERT … ON CONFLICT → seen_count++). Any new row → dry=0
  3. TRIAGE            select open signals, ordered:
                         blocking DESC, severity, seen_count DESC, last_seen_at
                       skip any with >= 3 failed attempts → status='wontfix', escalate to human
  4. REPAIR            one agent per signal. It MUST record an `attempt` row whether it
                       succeeds or not, with verify_cmd/verify_out proving the fix — an
                       assertion of success is not success
  5. VERIFY            re-run each signal's own evidence_cmd. Still reproduces → outcome
                       'failed', signal stays open. This is what stops a repair agent
                       marking its own homework
  6. CLOSE SWEEP       finished_at, counts, dry
converged when two consecutive sweeps have dry=1; hard cap 5 sweeps —
still producing new signals at sweep 5 -> stop and hand the open set to the user
```

**Rules the loop must not break:**

- **Never auto-repair `UNVERIFIED`.** Escalate instead.
- **Never let the repairing agent be the verifying agent.** Step 5 re-runs the original
  `evidence_cmd`, which the repairer did not write.
- **Cap attempts at 3.** A signal that resists three repairs is a design decision wearing a bug
  costume; it needs a human, not a fourth agent.
- **Escalate any signal whose `seen_count` grows while `status='fixed'`.** The fix is not holding
  and the loop is burning tokens re-fixing it.
- **A sweep that reports `dry=1` on its first ever run is a broken harvester, not a clean repo.**
  Treat it as suspicious and verify the auditors actually ran.

### Useful queries

```sql
-- triage queue
SELECT id, severity, component, issue, seen_count FROM signal
WHERE status='open' ORDER BY blocking DESC,
  CASE severity WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
  seen_count DESC;

-- fixes that did not hold — highest-value rows in the ledger
SELECT s.id, s.component, s.issue, s.seen_count, COUNT(a.id) AS attempts
FROM signal s JOIN attempt a ON a.signal_id = s.id
WHERE s.seen_count > 1 GROUP BY s.id HAVING attempts > 0 ORDER BY s.seen_count DESC;

-- convergence
SELECT id, started_at, signals_new, signals_recur, signals_fixed, dry
FROM sweep ORDER BY id DESC LIMIT 10;

-- where the rot concentrates
SELECT component, COUNT(*) n, SUM(status='open') open_now
FROM signal GROUP BY component ORDER BY n DESC LIMIT 20;
```

---

## 7. Seed data

`sprint-recon-harness-1` produced 24 signals in
`.team-sprint/sprints/sprint-recon-harness-1/handoff.jsonl`. Its fields map directly:
`kind`→`category` (remap `skill_defect`→ the §3 taxonomy), `what`→`issue`,
`evidence`→`evidence_cmd`+`evidence_out`, `workaround`→`fix`, `blocking`→`blocking`.

Backfilling it is the correct first sweep: it gives the ledger real rows, and it immediately
tests the dedupe key against observations that genuinely recurred across rounds.

---

## 8. Known limits

- SQLite has no concurrent-writer story worth relying on. Agents emit to per-run JSONL; a
  single-threaded importer loads them. Do not have 16 agents open the same `.db`.
- `dedupe_key` normalisation is a heuristic. Two genuinely different defects in one file with
  similar wording will collide. Prefer a false merge to a false split: a merged pair is visible
  as a high `seen_count` with contradictory attempts, whereas a split pair is invisible forever.
- Nothing here detects a defect no auditor was told to look for. The taxonomy is a floor, not a
  ceiling — §3 grew from 0 to 6 categories in a single sprint, and should be expected to grow
  again. Add a category when a signal genuinely does not fit; never force it into `SEMANTIC`.

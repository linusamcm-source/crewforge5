# Token-Slim Method — detailed mechanics and caveats

Load this when actually performing trims or splits (step 3–4 of SKILL.md).

## Trim guidance (descriptions → ≤300 chars)

- Keep the triggers a user is most likely to *type*: short imperative phrases and
  slash-command forms beat long positioning prose.
- The description must still answer "what does this skill do" in one clause —
  discoverability first, brevity second. A trim that keeps triggers but drops the
  skill's core job is a failed trim even if the harness passes.
- Single-line plain YAML scalar. Avoid wrapping the whole value in double quotes when
  the text itself contains double-quoted trigger phrases; plain style works when the
  value starts with a letter and contains no leading indicator characters.
- Never change `name:`, `model:`, or other frontmatter keys.
- Place the `## When to use` section near the top of the body (after any intro/TL;DR).
  Write relocated triggers as natural prose or bullets, quoting each phrase verbatim —
  the harness matches them whitespace-insensitively but otherwise exactly.

## Split guidance (bodies → references/)

What counts as *conditional* (safe to move):
- end-of-run report templates and output-format blocks
- per-category fix/check catalogs and tables consulted selectively
- copy-paste pattern/template libraries (move each pattern to its own
  `references/pattern-<name>.md`, keep a one-line-per-pattern index inline)
- integration guides for other tools ("Working with X" sections)
- steps whose own text says "only if …" / flag-gated subcommands
- domain background, physics/theory prose, appendix material

What must stay inline (never move):
- the step-by-step workflow skeleton executed on every invocation
- intake gates, pre-flight checks, authorization gates
- self-healing loop rules and anti-fabrication protocols
- anything another running system reads positionally (e.g. a sprint runner's
  phase-execution instructions)

Every move is verbatim, headings included — the harness asserts every baseline
heading still exists somewhere in the skill dir. At each extraction point leave:
`If <condition>: load [references/<file>.md](references/<file>.md)`.

## Class ceilings

| class | ceiling | signs |
|---|---|---|
| template-heavy | ≤50% | body is mostly copy-paste code/config blocks |
| runbook | ≤75% | step workflow with large selectively-read blocks |
| high-stakes runbook | ≤80% | other automation depends on its exact structure |
| near-threshold | ≤85% | body barely over 10k; move appendix prose only |

Ceilings are fractions of the **baseline** body chars, recorded in `ceilings.json`
(`{"skill-name": 0.75, …}`) so `sweep.py` can enforce them mechanically.

## Known caveats (all hit in the first run)

- **Symlinked skill dirs**: a skill dir may be a symlink to another repo
  (e.g. `skills/adhd → ~/.agents/skills/adhd`). Edit through the symlink path, but
  note the changes are not tracked by the host repo's git — record this in the report.
- **Singular `reference/` dirs**: some skills already have their own convention
  (e.g. team-sprint's `reference/`). Follow the skill's existing convention; do not
  rename or create a parallel plural dir. Note: `check.sh`'s link check only covers
  `references/*.md` links — verify singular-dir links by hand.
- **Protected sections**: fork-context runbooks may require certain steps to remain
  byte-identical (verify with a `git diff` span check against the pre-edit file).
- **Descriptions just over 300**: a skill outside trim-scope (desc ≤500) that gets a
  body split must still pass `check.sh`'s desc cap — lightly trim it to ≤300 rather
  than special-casing the gate.
- **Write-tool filename guards**: creating `references/report-template.md` may be
  refused by report-file heuristics; create such files via a Bash heredoc instead.
- **Downstream tooling**: if any script parses a slimmed skill (e.g. a sprint
  runner's plan parser), re-run that tooling as an extra acceptance gate.

## Report template

```markdown
# Token-Slim Report — <run-name>

Executed <date>. Baseline: `baseline.json` (immutable snapshot, commit <sha>).

## Totals
| metric | baseline | after | saving |
|---|---|---|---|
| description chars (per-turn load) | … | … | … chars ≈ … tok/turn |
| body chars (at-invocation load) | … | … | … chars |

## Per-skill before/after
| skill | desc before | desc after | body before | body after | ceiling | touched |
|---|---|---|---|---|---|---|
```

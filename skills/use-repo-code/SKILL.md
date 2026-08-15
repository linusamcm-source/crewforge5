---
name: use-repo-code
model: haiku
context: fork
agent: Explore
description: Use when you need to grep a repomix snapshot of the repo across many files at once — "where is X in this repo", "find usages of Z", "does this already exist", "check codebase before implementing". Not for editing live code or in-session changes; complements direct source reads.
disable-model-invocation: true
---

# Use Repo Code

Authoritative grep target for repo-wide questions. Pairs with whatever per-project
navigation index exists (`ARCHITECTURE.md`, etc.) and a compressed
[repomix](https://github.com/yamadashy/repomix) pack of the codebase.

## When to use

Triggers on requests like "where is X in this repo", "how does Y work", "find usages
of Z", "what files handle feature W", "show me the implementation of...", "does this
already exist", "check codebase before implementing", or any question requiring
reading source without running Glob/Grep against the live working tree. Do NOT use
when editing live code, when code was recently changed in-session, or when a
navigation index already answers the question — prefer live Read/Grep in those
cases. Complements, does not replace, direct source reads.

## Purpose

**Prevent drift. Prevent overwrites.** Most stories say "implement X". Without
checking the repo first, agents re-implement logic that already exists, violate
architecture rules, or overwrite working handlers. This skill makes that check a
single grep away.

## When this skill MUST run

| Trigger | Why |
|---|---|
| Pre-implementation safety check | Confirm the symbol/handler/component doesn't already exist |
| Code review (file-list verification) | Trace every claimed file against the pack to verify additive vs destructive change |
| Drift audit | Compare planning artifacts against actual source |
| Multi-agent roundtable | Ground each agent's opinion in real code — they grep the pack to cite actual files instead of improvising |
| Cross-language schema check | Verify a shared contract change (Zod / OpenAPI / Protobuf) propagates everywhere it should |

## Inputs (preconditions)

Skill expects, at repo root:

- A repomix pack file. Default name: `.repomix-output.xml`. Common alternatives: `.repomix/pack.xml`. If a per-project convention is set in `CLAUDE.md`, follow that.
- Optional: a project navigation index (`ARCHITECTURE.md`, `docs/architecture.md`) — the cheapest first read.

If the pack is missing or older than 2 hours, regenerate (Step 1).

## Workflow

### Step 1 — Ensure fresh pack

Check the pack age. If missing or older than 2 hours, regenerate — one call does all
of it (age check, canonical flags and ignore list, repomix → npx → bunx fallback):

```bash
bash ~/.claude/skills/use-repo-code/scripts/pack.sh          # prints pack= age_s= regenerated=
```

Flags and ignore list live in the script; per-size tuning in `references/repomix-flags.md`.

**Never `Read` the XML whole** — it's huge. Grep only.

**Search the pack with `rtk grep` (primary) — call it explicitly.** Run `rtk grep '<pattern>' "$PACK"` (add `-B 2` to catch the owning `<file path="...">` tag). It truncates lines, caps results, and groups hits by file — bare grep against a pack returns full-width XML lines and floods context. Do **not** rely on the RTK `PreToolUse` hook to rewrite bare `grep`/`rg` for you — the hook may not be installed, and the rewrite is a bonus, not the mechanism. The fallback chain is mechanised: `bash ~/.claude/skills/use-repo-code/scripts/pack-grep.sh '<pattern>' [flags]` uses rtk when present, else bounded `grep -nE -m 40`, always with `-B 2`. The built-in `Grep`-tool examples in Steps 3–4 remain the no-Bash fallback.

### Step 2 — Navigate with the index, not file reads

For "where does X live?" / "what does file Y do?":

```
Read <project-index>   # e.g. ARCHITECTURE.md, docs/architecture.md
```

Index entries usually have 2-3 line summaries. Use those to budget `-A` values when you grep the pack — don't re-read source files listed in the index unless a drift check demands it.

### Step 3 — Check existing code BEFORE implementing (the core safety step)

For every symbol/file/handler a task plans to create, grep the pack first. If it exists, **extend — never overwrite**. The four checks below are mechanised — one call each, `found=yes|no` plus sample hits:

```bash
E=~/.claude/skills/use-repo-code/scripts/exists.sh
bash $E file   path/to/expected.ext    # a) file already exists?
bash $E symbol CreateThing             # b) symbol already exists?
bash $E test   CreateThing             # c) test already covers this?
bash $E import '@scope/pkg'            # d) import already wired?
```

The repomix pack uses **XML style** by default. Each file block begins with `<file path="...">` and ends with `</file>`. That tag is the jump target — not `## File:`. The Grep-tool equivalents below are the fallback when Bash isn't available:

**a) File already exists?**

```
Grep(
  pattern: "^<file path=\"path/to/expected.ext\">$",
  path: "<pack file>",
  output_mode: "content",
  -A: 200
)
```

**b) Symbol already exists?**

```
Grep(
  pattern: "func .* CreateThing|function CreateThing|class CreateThing",
  path: "<pack file>",
  output_mode: "content",
  -B: 2, -A: 30
)
```

`-B 2` picks up the owning `<file path="...">` tag so you know where the match lives.

**c) Test already covers this?**

```
Grep(
  pattern: "TestCreateThing|describe\\(['\"]CreateThing|it\\(['\"].*creates a thing",
  path: "<pack file>",
  output_mode: "content",
  -B: 2, -A: 10
)
```

**d) Is the import path I'm about to add already wired?** Grep for the canonical import string before adding a new one.

### Step 4 — Architecture / layer check

Before writing or editing in any layered codebase (clean arch, hex, n-tier, BFF +
service split), check:

1. What layer is the target file in? (UI / hook / store / coordinator / service / domain / handler / repository)
2. What does it want to import? Grep the pack for that import path.
3. Does the import direction respect the architecture rules in `CLAUDE.md` / `ARCHITECTURE.md`? If not, STOP — that is a layer violation.

Quick pattern:

```
Grep(pattern: "import .* from '@/services", path: "<pack file>", -B: 2)
```

Any match inside a store/UI file = layer violation in most architectures.

### Step 5 — Language / package boundary check (multi-language repos)

If the repo splits responsibilities across languages or packages (e.g. TS frontend +
Go API + Python ML), check the project's stated boundary rules in `CLAUDE.md` /
`ARCHITECTURE.md` before adding code in the wrong place. Grep the target path prefix
to confirm the package.

### Step 6 — Report or implement

- **Pre-implementation** (before writing tests/code): report existing symbols, matching tests, layer pass/fail. Hand control back to the caller.
- **Information request**: return file paths + relevant snippets with `<file path="...">` tags intact so the caller can navigate.

If a question is about relationships ("what calls X"), past decisions, or which recon tool fits: load [references/codebase-intelligence.md](references/codebase-intelligence.md).

For worked end-to-end scenarios (pre-implementation check, file-list verification, schema drift, multi-agent grounding): load [references/common-workflows.md](references/common-workflows.md).

## Inter-agent communication

If invoked as part of a multi-agent flow that produces a report, the structured final
return is the delivery; persist any artifact the flow requires. Use `SendMessage` only
when the recipient is not the spawner (per CLAUDE.md and the team-sprint protocol).

## Tips

- `<file path="...">` tags are the cheapest jump target.
- `-B 2` on every content grep — picks up the file path tag so you know where the hit came from.
- If your project index has token estimates per file, use them to budget `-A` sizes.
- `--compress` keeps Tree-sitter structure + signatures only — plenty for existence checks, not full implementations. For full implementations, open the file directly.
- For large files (>1000 tokens), grep narrow symbols rather than pulling the whole header.

## Don'ts

- Don't `Read` the pack whole. Grep only.
- Don't repack mid-session unless a major refactor just happened.
- Don't trust `CLAUDE.md` blindly if a drift audit flagged it — prefer the index + source.
- Don't write code before confirming the symbol doesn't already exist.
- Don't skip the layer check for layered codebases. Lint may catch it, but only after the commit.

## References

- `references/repomix-flags.md` — recommended pack-generation flags per project size
- `references/grep-patterns.md` — common grep patterns by language
- `references/codebase-intelligence.md` — repomix vs graphify vs claude-mem, evidence rules
- `references/common-workflows.md` — worked scenarios A–D

## Configuration

The pack location can be overridden via the `REPOMIX_PACK` env var or by setting it
in the project's `CLAUDE.md`. Default is `.repomix-output.xml` at repo root.

---
name: humanise
model: sonnet
description: Rewrite a draft in the user's voice plus Australian English. Trigger on "humanise", "rewrite in my voice", "make this sound like me", "de-LLM-ify", or "Australianise" a piece of writing.
---
# Humanise My Draft

Rewrites a draft to sound like the user wrote it, in Australian English, at the register the destination calls for. Three layers: **voice transfer**, **LLM-tell removal**, **AU English** — routed through per-scenario register packs and gated by mechanical scripts. The model does one job (the rewrite); scripts in `scripts/` do routing, verification, and logging with exit codes.

## When to use

Use whenever the user asks to humanise (or "humanize") a draft, hands over an email/report/proposal/README/PR description to polish, personalise, or tighten, or pastes corporate-sounding prose to make it more natural. Works on raw text and .docx files. This is voice transfer plus AU English, not generic copyediting.

## Operating principle: voice vs. register

**Voice** is what makes the user sound like themselves — it transfers across every document. **Register** is the formality dial — set by the *destination*, not the person. The voice profile is mined mostly from casual chat, so it over-indexes casual register; never carbon-copy casual markers into formal documents. Each register pack names a `voice_tier` — the named survive/die tiers live in [references/voice-tiers.md](references/voice-tiers.md).

## When this skill runs

Check for a voice profile at `~/Documents/claude-voice-profile.md` (or `voice-profile.md` in the workspace). If absent, offer to build one first: load [references/building-voice-profile.md](references/building-voice-profile.md), which fills `assets/voice-profile-template.md` and, when `session_info` is unavailable or a refresh is requested, defers to [references/voice-profile-edge-cases.md](references/voice-profile-edge-cases.md).

## Humanising a draft

`S=~/.claude/skills/humanise/scripts` throughout. All key=value outputs are for you to read; nonzero exits are gates. `lib.sh` holds shared helpers sourced by the other scripts; `au-check.sh` and `tells.sh` read their wordlists from `assets/au-words.tsv` and `assets/tell-patterns.tsv`.

### Step 0: Sniff and route

```bash
$S/sniff.sh [--path <destination>] [--hint "<user's framing>"] <draft-file>
$S/packs.sh <scenario>     # pack files to read + merged manifest (voice_tier, au_intensity, invariants)
```

Act on confidence: **high** → proceed, put the routing receipt in the output note; **medium** → proceed but flag the guess before the rewrite; **low** → intake gate below. Contract, signal table, and sibling house-style recipes: [references/destination-sniffing.md](references/destination-sniffing.md). An explicit user register ("as casual") skips sniffing entirely.

#### Intake gate — ask before rewriting

Only when confidence is low or rewrite depth is unclear, call **AskUserQuestion**, pre-filled with the sniffer's best guess as the recommended option:

- **Register** — `casual message` / `email` / `report / formal doc` / `code doc (README, PR, docstring)`.
- **Rewrite depth** — `Light — voice-match + AU English, keep structure (Recommended)` / `Full rewrite — restructure freely`.

### Step 1: Read everything

1. The voice profile.
2. Every file from `packs.sh` `files=` (base pack first).
3. [references/llm-tells.md](references/llm-tells.md) and [references/australian-english.md](references/australian-english.md).
4. `$S/feedback.sh corrections <scenario>` — apply every line it prints (learned corrections, see [references/feedback-loop.md](references/feedback-loop.md)).

### Step 2: Diagnose the draft

```bash
$S/tells.sh <draft>              # baseline density + rhythm flags — your hit list
$S/invariants.sh extract <draft> > /tmp/humanise.lock   # protected tokens
```

Then judge what scripts can't: what's the actual argument? Which profile signatures fit this pack's voice_tier? **Cross-dock rule**: casual drafts under ~50 words skip Steps 2 and 7 — one-pass rewrite, deliver.

### Step 3: Rewrite, don't edit

Token-swapping ("utilise"→"use") leaves LLM sentence structure intact. Rewrite at sentence/paragraph level: break uniform paragraph shapes, front-load buried claims, cut tricolons to the one specific adjective, delete generic closing sentences, commit where over-hedged — and hedge the user's way where they'd hedge. The pack's conventions and voice_tier bound every choice.

### Step 4: Apply Aussie English

At the pack's `au_intensity` (`spelling` / `spelling+vocab` / `idiom`), per [references/australian-english.md](references/australian-english.md) (start with its quick summary). Professional, not bogan.

### Step 5: Check against register exemplars

Compare against the pack's named exemplars ([references/business-register-exemplars.md](references/business-register-exemplars.md) for prose registers; vetted siblings for repo-bound scenarios). Slid below the register floor → pull back. Still LLM-stiff → push further.

### Step 6: Final pass — does it sound like the user?

Read it aloud mentally. Any line the user wouldn't say in any register gets reworked.

### Step 7: Verify (mechanical gates)

```bash
$S/invariants.sh verify /tmp/humanise.lock <rewrite>   # BLOCKING when manifest says invariants: strict
$S/tells.sh <rewrite>                                  # density must drop vs Step 2 baseline
$S/au-check.sh <rewrite>                               # US spellings outside code; findings=0 or justified
```

Any gate fails → fix and re-run. au-check findings are advisory only for deliberately-kept API names and proper nouns; everything else gets fixed.

### Step 8: Deliver and log

```bash
$S/deliver.sh <scenario> <rewrite-file>
```

If the user later edits or ships a changed version, capture it (`$S/feedback.sh capture`) and distil per [references/feedback-loop.md](references/feedback-loop.md).

## Register packs

One markdown file per scenario in `references/registers/` (casual-message.md, email.md, report.md, formal-doc.md, code-doc.md, readme.md, pr-description.md, docstring.md, commit-message.md). Manifest keys between the leading `---` markers: `voice_tier`, `au_intensity`, `invariants`, optional `extends:` for inheritance (child overrides parent). Adding a scenario = dropping a new pack file; no changes here.

## File handling and pitfalls

.docx input/output or unclear return format: load [references/file-handling.md](references/file-handling.md). Before finalising, check the anti-patterns (AI-detection framing, over-Australianising, deleting substance, faking typos, ignoring register): load [references/what-not-to-do.md](references/what-not-to-do.md).

## Output format

1. The rewrite (inline if text, file link if .docx).
2. A tight receipt: routing line (scenario + evidence), tells density before → after from Step 2/7, the high-level shifts, and the `applied corrections:` footer when any fired.

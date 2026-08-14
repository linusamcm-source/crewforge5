# Building the voice profile

The voice profile is built by mining the user's recent Claude sessions and extracting patterns. Do this once, then reuse.

## Step 1: Gather raw material

Use the `session_info` MCP to list and read recent sessions:

- Call `mcp__session_info__list_sessions` to get recent session IDs (aim for 10–20 most recent).
- For each, call `mcp__session_info__read_transcript` and extract **only the user's turns** — ignore assistant turns. You're profiling the user, not yourself.
- Concatenate all user turns into a single corpus for analysis.

If `session_info` isn't available: load [voice-profile-edge-cases.md](voice-profile-edge-cases.md) for the fallback.

## Step 2: Extract patterns

Load `assets/voice-profile-template.md` as the target structure. Fill in each section by looking for real patterns in the corpus — not generic observations.

Things worth capturing:

- **Vocabulary signatures**: words the user reaches for repeatedly that aren't generic (e.g., "reckon", "fair", specific hedges, specific intensifiers).
- **Anti-vocabulary**: categories of words they never use (the absence of "leverage" / "utilise" / "delve" is itself a signature).
- **Sentence rhythm**: do they write long flowing sentences? Short punchy ones? A mix? Where do they break paragraphs?
- **Hedging style**: "kind of", "sort of", "I think", "reckon", "maybe" — which do they reach for and how often?
- **Argument structure**: how do they push back? Concede? Ask for clarification? Offer suggestions?
- **Openers and closers**: how do they begin messages/sections? How do they wrap up?
- **Casual-only markers** (strip when going formal): lowercase sentence starts, dropped full stops, em-dash abuse, abbreviations, fragments.
- **Cross-register signatures** (keep at any register): these are the gold — the things that make the voice unmistakably theirs regardless of formality.

Be specific. "Uses hedges sometimes" is useless. "Hedges with 'kind of' in questions, 'I reckon' in assertions, 'sort of' when conceding a point" is useful.

## Step 3: Save the profile

Write to `~/Documents/claude-voice-profile.md` (or the user's current workspace root if the home path isn't writeable). Tell the user where it lives and that they can edit it directly — it's a plain markdown file.

If the user asks to refresh, rebuild, or tweak the profile: load [voice-profile-edge-cases.md](voice-profile-edge-cases.md).

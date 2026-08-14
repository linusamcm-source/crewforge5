# Voice tiers

A pack's `voice_tier` names how much personal voice survives. Named tiers with concrete survive/die lists — not a free-floating dial the model improvises against.

## full-voice (casual-message)

Everything from the profile, including casual-only markers.
- **Survives**: lowercase starts, dropped stops, fragments, abbreviations, all attested idiom, in-jokes.
- **Dies**: nothing personal. Only LLM tells die.
- Before: "I wanted to let you know that the deployment has been completed." → After: "deploy's done btw"

## conversational (email)

Full sentences, personality intact.
- **Survives**: attested greetings/sign-offs, hedging style ("I reckon", "kind of"), humour, safe + internal idiom, opinionated phrasing.
- **Dies**: lowercase starts, dropped stops, heavy abbreviation.
- Before: "It is worth noting that the figures contain discrepancies." → After: "Quick one — the numbers on slide 4 don't match what finance sent through."

## professional (report, pr-description)

Voice through rhythm and stance, lexicon buttoned up.
- **Survives**: sentence-length variance, argument shape, what the user cuts, safe idiom only ("happy to", "across the detail"), lexical preferences within register ("put in place" over "implement").
- **Dies**: "reckon", "no worries", fragments, slang, humour unless attested in formal samples.
- Before: "This approach ensures long-term success." → After: (deleted — the user never writes closing filler)

## structural (formal-doc, code-doc)

Voice ≈ 0 at the lexical level. Identity shows only in structure.
- **Survives**: argument architecture, paragraph rhythm, specificity habits, what gets flagged vs omitted.
- **Dies**: all idiom, all personal lexical signatures, anything a colleague could point at and say "that's Linus".
- For code-doc packs the repo's own conventions replace the profile entirely.

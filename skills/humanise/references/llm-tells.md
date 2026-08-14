# LLM tells and how to rewrite them

This reference catalogues the patterns that make AI prose read as AI prose. Each tell includes what to watch for, why it's a tell, and how to rewrite it. These are the top candidates for attention during a humanising pass — but remember the aim is voice-driven rewriting, not mechanical substitution. If a user genuinely writes "comprehensive" in their natural voice, leave it. The point is to notice and break default LLM rhythms, not blacklist words.

## 1. Vocabulary defaults

Certain words appear in LLM output at wildly higher rates than in natural human writing. They're not wrong — they're just overused in a specific narrow sense that makes them conspicuous.

### The high-signal offenders
- **delve / delve into** — almost never appears in natural business prose. Replace with "look at", "go through", "work through", "get into", or often just delete the scaffolding: "Let's delve into X" → "X:"
- **leverage** (as verb) — "use", "draw on", "make use of", "put (X) to work". Avoid entirely when the verb is really just "use".
- **utilise** — "use".
- **robust** — usually means "works well" or "handles edge cases" or "tested". Be specific about what it actually means in context.
- **seamless / seamlessly** — almost always empty. Cut or replace with concrete description of what the integration actually does.
- **nuanced** — often means "complicated" or "depends". Say what it depends on.
- **comprehensive** — often means "covers the main things". Specify which things.
- **navigate** (figurative — "navigate challenges", "navigate the landscape") — "handle", "deal with", "work through", or be specific.
- **unlock / empower / elevate / streamline** — corporate verbs that rarely carry concrete meaning. Replace with what actually happens.
- **actionable** — redundant most places it appears. "Actionable insights" = "things you can do".
- **synergy / synergies** — almost always means "two things fitting together". Just say that.
- **paradigm / paradigm shift** — overreach for most business writing. Be more specific.
- **ecosystem** (figurative — "the ecosystem of tools") — usually means "set of tools". Say that.
- **holistic** — usually means "looking at the whole thing". Say that.
- **journey** (figurative — "the customer journey") — sometimes fine, often cliché. Check if a more specific word works.
- **cutting-edge / state-of-the-art / best-in-class / world-class** — marketing filler. Cut or be specific about what makes it so.

### Hedged scaffolding phrases
Phrases that buy time without adding content. Usually cuttable.
- "It's worth noting that..." → cut, state the claim directly
- "It's important to consider..." → cut
- "It's crucial to understand..." → cut
- "One thing to keep in mind..." → cut, or "one thing:"
- "As we can see..." → cut
- "At the end of the day..." → cut
- "In today's fast-paced world / rapidly evolving landscape..." → cut entirely; nobody writes openings like this
- "When it comes to X..." → cut; go straight to what you want to say about X

### Transitional crutches
LLMs over-transition. Humans often just put the next point on a new line.
- "Furthermore", "Moreover", "Additionally" — usually cuttable; if needed, "Also," is less stilted
- "In conclusion", "To summarise", "In summary" — rarely needed in short documents; let the final paragraph close itself
- "Notably", "Importantly" — often scaffolding rather than content; cut unless genuinely flagging a surprise

## 2. Structural tells

These are often more damaging than vocabulary because they're harder for a casual reader to articulate but make the prose feel "off" in aggregate.

### The rule of three, everywhere
LLMs love tricolons: "comprehensive, efficient, and scalable", "the people, the process, and the technology", "innovation, collaboration, and excellence". This is a real rhetorical device used by humans — but LLMs deploy it so reflexively it becomes a tell.

**Fix:** cut to one adjective, often the most specific. "Comprehensive, efficient, and scalable" → "fast" or "works at scale" or whatever the actual claim is.

### Uniform paragraph structure
Every paragraph: topic sentence → three supporting sentences → generic closing sentence. Repeated for six paragraphs.

**Fix:** vary. Some paragraphs should be one sentence. Some should run long. Let the argument shape dictate paragraph shape, not the reverse.

### Uniform sentence length
When you diagram the sentences in a paragraph, LLM output tends to show equal-ish lengths — often 15–25 words, all similar. Natural writing shows high variance: a 40-word sentence next to a 6-word one.

**Fix:** after drafting, count. If everything is within 5 words of the mean, introduce range deliberately. A fragment. A very long sentence with several clauses and specific detail. Then short again.

### Generic closing sentences
LLMs often end paragraphs with sentences like "This approach ensures long-term success", "These factors are crucial to consider", "Ultimately, this will drive value". These add nothing.

**Fix:** delete. Let paragraphs end on their last substantive sentence.

### The "X is not just Y, it's Z" construction
"This isn't just about efficiency — it's about transformation." "It's not merely a tool, it's a platform." This construction is everywhere in LLM writing.

**Fix:** pick one. Say what it is. The contrast is usually false.

### Parallelism overload
"We help teams collaborate better, communicate faster, and execute smarter." Three perfectly parallel verb+adverb pairs. Rare in natural writing.

**Fix:** break the parallelism. Let one element be different in shape.

## 3. Argument structure tells

### Overbalanced both-sidesing
LLMs tend to acknowledge every counterargument, hedge every claim, and end up saying nothing. Human business writing commits to positions.

**Fix:** if the piece is meant to be advisory, make a recommendation. If it's meant to persuade, actually argue. Hedges are fine where real uncertainty exists; delete hedges that exist only for performative balance.

### Burying the lede
LLMs often open with background, context, and scaffolding before getting to the actual point. Humans writing well lead with the point.

**Fix:** move the thesis/ask/finding to the first or second sentence. Context follows, if needed.

### Padding with definitions
"Before we proceed, let's define X." Most business readers don't need basic definitions; if they do, a short parenthetical beats a paragraph.

**Fix:** cut definitions unless the term is genuinely niche and central.

## 4. Formatting tells

### Over-reliance on bullet points
LLMs convert any loose list of ideas into a bullet list. In real business writing, bullets are for genuinely parallel items; prose is for connected argument.

**Fix:** if the bullets would flow as a paragraph, make them a paragraph. Keep bullets for: specifications, action items, genuinely parallel options.

### Bolded phrase density
Every third phrase bolded for "emphasis". A reader who sees twenty bolded phrases stops seeing any of them.

**Fix:** bold sparingly — headings, terms being defined, one key phrase per section at most.

### Em-dash rhythm
LLMs develop a characteristic em-dash tic — like this — used mid-sentence — for clause interruption — too often. Occasional em-dashes are fine; the tell is rhythmic overuse.

**Fix:** count em-dashes. If there's more than one per paragraph on average, replace most with commas, full stops, or parentheses. Keep them for genuine interruption or reveal.

### Title-case headers on everything
Every section header in Title Case, even for casual documents. Sentence case reads more natural for most internal and informal business writing.

**Fix:** match header case to document formality. Casual internal doc: sentence case. Formal report: title case.

## 5. Content tells

### Claims without specificity
"This will drive significant value." What value, to whom, how much? "Stakeholders will benefit." Which stakeholders, from what?

**Fix:** replace generic claims with specific ones, or delete if specifics aren't available.

### Over-explaining context the reader has
"As you know, our company has been pursuing..." The reader works there; they know.

**Fix:** cut the preamble. Start from where the new information begins.

### Symmetric pros/cons lists of equal length
LLMs often list three pros and three cons, neatly balanced. Real analysis often has a long pro list and one critical con, or vice versa.

**Fix:** list what's actually there. Uneven is fine.

## 6. Rewriting principles

When applying these fixes:

1. **Read the draft as a whole first.** Many tells show up only in aggregate (uniform structure, em-dash rhythm). Spot the patterns before fixing lines.
2. **Cut before substituting.** The easiest rewrite is often deletion. "It's worth noting that the market is growing" → "The market is growing" or often, if the point was already clear, just cut.
3. **Preserve the claim.** Substance stays; scaffolding goes.
4. **Voice over purity.** If the user's profile shows they naturally use a word on the "avoid" list, that's their voice — leave it. The list above is LLM defaults, not a blanket ban.
5. **Check rhythm after rewriting.** Read the output aloud mentally. If it still has the metronome beat of equal-length sentences, you're not done.

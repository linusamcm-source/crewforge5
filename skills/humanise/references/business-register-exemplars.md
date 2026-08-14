# Business register exemplars

These are examples of clean professional prose across common business writing registers. Use them as a reference for what "good" looks like at each register — the register floor when humanising, regardless of how casual the user's voice profile is.

Each example is annotated with what makes it work.

---

## Register 1: Internal email to a peer or small team

The most casual register that still counts as professional. Full stops, sentence case, conversational phrasing; personality welcome; AU idiom fine.

### Good example

> Hey team —
>
> Quick one on the Q2 planning doc. I went through it last night and there are a couple of spots where the numbers don't match what finance sent through on Wednesday. Specifically: slide 4 has FY25 ARR at $8.2M and the finance export has it at $7.9M. Not a huge gap but worth sorting before Tuesday.
>
> I've left comments in the doc. Happy to jump on a call if it's easier to talk through.
>
> Cheers,
> L

**Why it works:**
- Lead with the subject, not the preamble.
- Specific numbers, specific locations ("slide 4").
- One opinion ("not a huge gap but worth sorting") — commits to a position.
- Closing offers a next step without padding.
- AU idiom ("quick one", "jump on a call", "sort", "Cheers") is present but light. No fake formality.

### Bad version (LLM tells)

> Dear Team,
>
> I hope this email finds you well. I wanted to reach out regarding the Q2 planning document that was recently circulated. Upon reviewing the document in detail, I noticed some discrepancies that I believe warrant further discussion.
>
> Specifically, there appear to be inconsistencies between the figures presented in slide 4 and the financial data provided by the finance team earlier this week. I've identified that the FY25 ARR is listed as $8.2M in the planning document, whereas the finance export indicates $7.9M. While this discrepancy may not be substantial, I believe it's important to address it before our Tuesday meeting to ensure alignment across the team.
>
> I have taken the liberty of leaving comments within the document to highlight these points. Please do not hesitate to reach out if you would like to discuss this further over a call.
>
> Best regards,
> L

**What's wrong:** greeting padding, "upon reviewing", "I believe", "warrant further discussion", "ensure alignment", "taken the liberty", "please do not hesitate" — all scaffolding. Twice the words, less information.

---

## Register 2: Email to an external client or partner

Professional, warm, specific. Cuts to business efficiently. Idiom light and safe. Spelling and grammar clean.

### Good example

> Hi Amelia,
>
> Thanks for sending through the draft brief on Friday. I've read through it and had a chance to discuss with the team here.
>
> Two things stood out:
>
> First, the timelines on the discovery phase look tight given the research scope. We'd normally allow four weeks for the stakeholder interviews alone, and the brief has three. I can put together a revised schedule if that's useful.
>
> Second, the success metrics in section 4 are measuring outputs (number of workshops, hours consulted) rather than outcomes. Worth a conversation about what success looks like six months post-engagement — happy to run through how we've handled this on similar projects.
>
> I'm free Thursday afternoon or most of Friday if you'd like to talk either through. Otherwise I can send written notes by end of week.
>
> Kind regards,
> Linus

**Why it works:**
- Opens with what happened ("Thanks for sending... I've read through") not what the writer hopes ("I hope this finds you well").
- Numbered-but-not-bulleted structure: "Two things stood out: First... Second..." — clearer than bullets, less stiff than "Firstly/Secondly".
- Specific critiques with specific remedies offered.
- "Happy to run through", "if that's useful" — safe AU idiom, warm without being casual.
- Closes with concrete options, not "let me know your thoughts".

### Bad version

> Dear Amelia,
>
> I hope this email finds you well. Thank you for taking the time to share the comprehensive draft brief. We appreciate the thorough work that has gone into it.
>
> Upon reviewing the document, we have identified a few areas that we believe could benefit from further discussion. Firstly, the timelines outlined for the discovery phase may be somewhat ambitious given the scope of research required. Typically, we would allocate approximately four weeks for stakeholder interviews alone, which is slightly more than what has been proposed. We would be happy to collaborate on a revised timeline that better accommodates these requirements.
>
> Secondly, we noted that the success metrics detailed in section 4 primarily focus on output-based measures rather than outcome-based ones. We believe this presents a valuable opportunity to align on what success looks like in the longer term, and we would be delighted to share insights from similar engagements we have undertaken.
>
> Please let us know a time that works for you to discuss these points further. We look forward to your thoughts.
>
> Warm regards,
> Linus

**What's wrong:** "I hope this finds you well", "we appreciate", "upon reviewing", "we have identified", "we believe could benefit from further discussion", "slightly more than what has been proposed", "we would be happy", "we would be delighted", "we look forward to your thoughts". It's polite to the point of being empty. Triple the words to say the same thing.

---

## Register 3: Internal report or briefing document

Paragraph prose, formal but not stiff, short sentences where possible, specific throughout. Headers in sentence case. Minimal idiom.

### Good example

> **Summary**
>
> The March outage affected 14% of customers for an average of 42 minutes. Root cause was a misconfigured database failover policy introduced in the 5 March release. This document sets out what happened, why, and the three changes we've made since.
>
> **What happened**
>
> At 02:14 AEDT on 12 March, the primary database in our Sydney region began throttling connections. The replica was healthy and should have taken over automatically. The failover script had been modified a week earlier to handle a separate edge case, and the modification introduced a condition that prevented failover from triggering.
>
> Engineering noticed within eight minutes and manually promoted the replica. Full service returned at 02:56. 14% of customers saw either complete outages or degraded response times during this window.
>
> **Why it wasn't caught**
>
> The 5 March release passed all automated tests. Our failover test suite, however, tests against a known-good configuration; it didn't re-run after the edge-case modification because the modification was gated by a feature flag that was off during testing. When we enabled the flag in production, it exposed the untested path.

**Why it works:**
- Summary up top: what happened, magnitude, cause, purpose of doc. Readers who only read the summary get the essentials.
- Prose paragraphs rather than bullets where the argument is connected.
- Specific times, percentages, durations throughout — no "significant impact" handwaving.
- Short plain sentences. No "we identified that the modification introduced a condition" — just "the modification introduced a condition".
- No rhetorical scaffolding ("it's important to note that", "as can be seen"). The document just says what happened.

---

## Register 4: Formal proposal, tender, or client deliverable

Most buttoned-up register. Precise, evidence-backed, clean. No idiom. AU spelling; neutral professional phrasing. Voice signatures come through in structure and argument shape, not lexical idiom.

### Good example

> **1. Approach**
>
> Our approach to the engagement is structured in three phases: discovery, design, and delivery. Each phase has defined inputs, outputs, and review points. The design phase overlaps with discovery by two weeks to allow emerging findings to shape initial design decisions without waiting for discovery to fully conclude.
>
> The total engagement is twelve weeks. Week-by-week activities are detailed in Appendix B; the high-level structure is set out below.
>
> **1.1 Discovery (weeks 1–5)**
>
> Discovery is intended to establish a shared view of the current state, the operating context, and the specific constraints that will shape what the design phase can credibly propose. It involves three activities:
>
> - Stakeholder interviews (fifteen interviews across the six business units identified in the brief).
> - A documentation review covering policy, process, and prior engagement reports provided by the organisation.
> - A data request covering the operational metrics listed in Appendix A.
>
> We will not conduct primary customer research in this phase. Customer research is proposed as an optional addition in Section 5.

**Why it works:**
- Plain confident prose. No "we believe", "we will endeavour to", "our team is excited to".
- Specific numbers and references (weeks, appendices).
- Commits to scope clearly and flags what's excluded ("we will not conduct primary customer research").
- Minimal idiom: no "happy to", no "we'll run through". This register doesn't take it.
- Structure is regular but not mechanical; bulleted list only where items are genuinely parallel.

---

## Pulling voice through at each register

At every register, voice should come through in:

- **Rhythm** — sentence length variance, paragraph breaks
- **Argument shape** — how the user builds from claim to support, how they hedge, what they emphasise
- **Word choice within the register's permitted lexicon** — e.g. at formal register, "put in place" over "implement" still lands; "roll out" instead of "deploy" still reads professional
- **What gets cut** — what the user considers noise (filler adjectives, scaffolding sentences) is part of their voice

Voice should **not** come through at formal registers via:

- Casual idiom ("reckon", "no worries", "happy days")
- Fragments
- Dropped punctuation
- Slang vocabulary
- Lowercase starts

When in doubt, consult the user's profile for their **cross-register signatures** — the patterns marked as transferring across all registers. Those go in everywhere. Casual-only markers stay out of formal work.

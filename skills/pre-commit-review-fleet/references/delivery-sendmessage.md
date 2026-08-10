# Optional SendMessage belt-and-braces (reviewer delivery)

A reviewer that also carries `SendMessage` MAY
additionally send the stringified JSON to `team-lead` as belt-and-braces
(`{to: "team-lead", message: "<the JSON above, stringified>", summary:
"<role> review: N findings"}` — `message` must be a plain string;
passing the object raw fails schema validation with `Invalid tool
parameters`; there is no `recipient`/`content`/`metadata` field and
`summary` is required whenever `message` is a string), but its absence
is never a stop condition and never blocks the merge.

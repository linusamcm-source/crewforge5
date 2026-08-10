# Companion tooling and source spec

## Companion library and CLI

There is a Node/TS implementation that does the same loop with structured
JSON parsing, score weighting, and a CLI. Use it when running outside
Claude Code or in batch.

    npm install -g adhd-agent
    adhd "your problem here"

Code, paper, evals, and contributing guide at
https://github.com/UditAkhourii/adhd. The skill above gives you the same
loop inside Claude with no install required.

## Source spec

This skill operationalises a written spec on divergent ideation. The
original prose lives in the upstream repo linked above. The
implementation choices made here (parallel isolated Agent calls,
mechanical generator/critic split, frame-based branching) follow from
that spec.

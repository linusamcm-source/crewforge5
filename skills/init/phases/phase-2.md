# Phase 2 — Hygiene

Rightsize the instruction files themselves: `CLAUDE.md`, rules, hooks, MCP
config. This is `context-hygiene` passes 1–4 applied to the resolved config
root.

## Work

Load `context-hygiene` through the resolver (`MODE=inline`) and apply its passes
to each instruction file in `INIT_TARGET`.

**Propose, never overwrite.** For each file you would rewrite, write the pair
that the gate judges:

```
$INIT_STATE/proposals/<slug>.orig       a copy of the file as it stands
$INIT_STATE/proposals/<slug>.proposed   the rewrite you are proposing
```

Only after the gate passes do you copy each `.proposed` over its real file.

A proposal with no `.orig` beside it fails: there is nothing to compare it
against, so "everything survived" would be an unearned verdict.

Fan out one agent per file when there are several — the files are disjoint, so
the work parallelises cleanly.

## Gate

`init_gate.sh hygiene` — `retention_gate.sh` over every pair. It fails on a lost
`never`/`always`/`must` directive, a lost exact command, path, version, or error
string. Those are the lines a reader cannot reconstruct, and they are also the
lines a length-driven trim removes first.

On a breach the flow does not advance. Re-propose keeping the reported line;
do not lower the bar.

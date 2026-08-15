# Phase 1 — Measure

Record what the config costs now. Nothing later may claim a saving that is not
a difference against this file.

## Work

Load `token-slim` through the resolver (`MODE=inline`) for the method, then
take the snapshot:

```bash
python3 "${CREWFORGE5_ROOT}/skills/token-slim/scripts/baseline.py" \
  --skills-dir "$INIT_TARGET/skills" \
  --out "$INIT_STATE/baseline.json"
```

`baseline.json` is **immutable for the rest of the run**. It holds, per skill,
the normalised description length, the body length, every quoted trigger phrase
and every heading. Phases 3 and 7 both read it: phase 3 to prove nothing
discoverable was lost, phase 7 to compute the delta it reports. Re-recording it
mid-run would make both of those checks compare a file against itself.

Also note the always-loaded total for context, which is the number this whole
flow is trying to move:

```bash
bash "${CREWFORGE5_ROOT}/scripts/budget_check.sh" --verbose
```

## Gate

`init_gate.sh measure` — `baseline.json` exists, parses as an object, and
records at least one skill.

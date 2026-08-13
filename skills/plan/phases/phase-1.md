# Phase 1 — Ground

**Goal of the phase:** replace recollection with citations. Every claim the plan
makes about the codebase has to trace to a file and a line read in this session.

## Steps

1. Refresh the pack. The staleness threshold is the repo's own
   `repomix_max_age_minutes` (`team-sprint.config.yaml`, default 240) — the same
   key `recon.sh` reads, so a repo that has tuned its pack freshness does not get
   a second, private number here:

   ```bash
   m="$(. "${CREWFORGE_ROOT:-.}/skills/team-sprint/scripts/lib.sh"
        read_config_scalar "${TEAM_SPRINT_CONFIG:-team-sprint.config.yaml}" repomix_max_age_minutes)"
   case "$m" in ''|*[!0-9]*) m=240;; esac
   bash "${CREWFORGE_ROOT:-.}/skills/team-sprint/scripts/repomix_refresh.sh" --max-age-minutes "$m"
   ```

2. Survey with `use-repo-code`. It declares `context: fork`, so it is **spawned
   through the `Agent` tool** with the type its frontmatter names — reading its
   body inline would pull the whole pack into this window and defeat the reason
   it forks. Ask the resolver rather than assuming:

   ```bash
   bash "${CREWFORGE_ROOT:-.}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code
   ```

3. Escalate only as far as the question needs: tier 1 (`recon.sh text`) for
   occurrences, tier 2 (`recon.sh callers|impact|coupling`) for structure. The
   router is at `${CREWFORGE_ROOT}/skills/team-sprint/scripts/recon.sh`.

## Degrading honestly

`repomix_refresh.sh` exits 1 when `repomix` is absent, and that is the common
case on a fresh machine. When it does, do **not** carry on quietly: fall back to
live `Grep`, tell the user the provider changed, and record the verdict —

```bash
bash "${CREWFORGE_ROOT:-.}/scripts/flow/flow_state.sh" plan set \
  ground_degraded "DEGRADED: no repomix on PATH; grounded with live Grep"
```

The verdict has a shape and the gate checks it: it must **start with `DEGRADED`**
and **name the provider you actually used** (`Grep`). A bare "ok" is rejected,
because a key that accepts anything is a key that lets you walk past this phase
ungrounded — which is the one thing it exists to stop.

## Gate

`repomix_refresh.sh --max-age-minutes "$repomix_max_age_minutes" || flow_state.sh
plan get ground_degraded | grep -E '^DEGRADED.*[Gg]rep'`.

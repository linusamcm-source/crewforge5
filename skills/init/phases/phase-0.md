# Phase 0 — Preflight

Establish that the flow can run, then where it is operating and on what, before
anything is measured or rewritten.

## Work

0. **Check dependencies first — before anything else, including the flow
   driver.** Run the check directly, not through `flow_gate.sh`:

   ```bash
   bash "${CREWFORGE5_ROOT}/skills/init/scripts/init_gate.sh" deps
   ```

   It is the only gate that answers on a machine without `jq`, which is the
   machine it exists for — `flow_gate.sh`, `flow_next.sh` and every other gate
   exit early when `jq` is absent, so reaching them first would report one
   missing tool and hide the rest.

   Stdout carries `REQUIRED_MISSING=` and `OPTIONAL_MISSING=` as comma-joined
   lists; stderr carries a ready-to-paste install block between its
   `----- copy-paste into another terminal -----` markers.

   Then, in this order:

   - **Nothing missing.** Say so in one line and go to step 1.
   - **Only optional tools missing.** Name them, say what degrades (see the
     bundle's `README.md` Dependencies section), and go to step 1. Optional
     tooling absent is a documented degradation, not a stop.
   - **Required tools missing, and you can install them without `sudo` and
     without a package manager that needs one** — a Homebrew formula on macOS,
     `npm install -g`, `uv tool install` — then **ask the user first**, naming
     the exact command, and run it only if they agree. Installing software is a
     change to their machine, and a gate that made it silently would be
     deciding on their behalf.
   - **Otherwise** — anything needing `sudo`, an unknown package manager, or a
     tool the gate reports no install command for — do not attempt it. Print
     the block from the gate's stderr verbatim, in a fenced `bash` block, and
     tell the user to run it in another terminal.

   **Never run a line that pipes a remote script into a shell**, whatever the
   user has already agreed to in this run. `curl … | sh` fetches code nobody
   in this conversation has read, from a URL that can answer differently the
   next time it is asked, and it needs no `sudo` — so the rule above would
   otherwise wave it through. Hand those lines over; the gate marks the
   alternative on the following comment line where one exists.

   **Then wait.** Do not advance, do not start step 1, and do not run any
   later gate. When the user says they are done, run `init_gate.sh deps` again
   and compare the new `REQUIRED_MISSING=` against the old one. **Loop:**
   re-emit the block for whatever is still missing, wait again, re-check. The
   loop ends only when `STATUS=OK` — or when the user asks to stop, which is
   their call to make and yours to record in the report.

   Report progress between rounds. "`jq` installed, `python3` still missing" is
   what makes a second round feel like progress rather than the same wall.

1. **Resolve the config root.** `INIT_TARGET` is the directory holding the
   `skills/` and `agents/` this run audits. Default is the repo root. Export it
   if the config lives elsewhere, then claim a subject for it **before**
   recording anything — flow state is keyed by subject, so two config roots
   audited from one repo need two of them:

   ```bash
   : "${INIT_TARGET:=$(git rev-parse --show-toplevel)}"
   export INIT_TARGET
   bash "${CREWFORGE5_ROOT}/scripts/flow/flow_state.sh" init use --from "$INIT_TARGET"
   bash "${CREWFORGE5_ROOT}/scripts/flow/flow_state.sh" init set target "$INIT_TARGET"
   ```

   Resolve the default before claiming anything. `INIT_TARGET` unset means the
   repo root, but leaving it unset here would slugify an empty string into the
   shared `default` subject and record an empty `target` — the subject would no
   longer name what is under audit.

   `flow_state.sh init list` shows the audits this repo already holds;
   `flow_state.sh init reset` discards the current one to start it over.
2. **Load the house rules.** `claude-config` is the standing statement of how
   this bundle wants skills, agents and hooks written, and every later phase
   proposes edits against it. Load it inline:

   ```bash
   RESOLVE="${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh"
   "$RESOLVE" --load-mode claude-config     # MODE=inline
   "$RESOLVE" claude-config                 # path to read
   ```

   Check `--load-mode` before reading any sub-skill body. A skill answering
   `MODE=agent AGENT=<type>` declares `context: fork` and must be spawned
   through the `Agent` tool with that type — reading such a body inline keeps
   its instructions and destroys the isolation it forks for.
3. **Require a clean tree.** Every later phase rewrites config files. An
   unrelated uncommitted edit makes the diff that proves what init changed
   unreadable, so this is a stop rather than a warning.

## Gate

`init_gate.sh preflight` — every required tool present, inside a git repo,
`INIT_TARGET` exists, and `git status --porcelain` is empty.

The gate re-runs the dependency scan itself, so a run that skipped step 0 still
fails here with `REASON=missing-deps` rather than proceeding half-equipped.
Step 0 exists because by the time the driver can call this gate, `jq` is
already required — the check has to happen before the machinery that needs it.

If the tree is dirty, stop and say so. Do not commit on the user's behalf: the
uncommitted work is theirs and they have not been asked about it.

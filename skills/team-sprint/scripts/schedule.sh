#!/usr/bin/env bash
#
# schedule.sh — graph-state engine for the team-sprint `execute` wave loop.
#
# The live scheduler is the LLM lead, which *reasons* through the wave loop and
# spawns teammates via Task/SendMessage. This script owns the deterministic,
# mechanical half: the node state machine over graph.json. Every mutation is a
# guarded, atomic, write-ahead update — so the lead never hand-edits JSON and a
# crash always leaves a valid resting checkpoint.
#
#   schedule.sh frontier <graph.json>            # ready node ids (deps all done)
#   schedule.sh next     <graph.json>            # ready minus running, capped by max_parallel_agents
#   schedule.sh status   <graph.json>            # verdict=<running|complete|blocked|deadlock> + counts
#   schedule.sh claim    <graph.json> <id> [<base-sha>]
#                                                # pending  -> in_progress (sets branch/worktree/base_commit/phase=3)
#   schedule.sh phase    <graph.json> <id> <3-6> # update a node's active sub-phase
#   schedule.sh commit   <graph.json> <id> <sha> # in_progress -> committed
#   schedule.sh integrate<graph.json> <id> <sha> # committed   -> done  (call AFTER the git merge succeeds)
#   schedule.sh fail     <graph.json> <id> [why] # -> failed; cascade-block transitive dependents
#   schedule.sh reset-orphans <graph.json>       # resume: in_progress->pending(+attempts)
#   schedule.sh simulate <graph.json> [--fail a,b] [--max-waves N] [--resume]
#                                                # dry-run: drive the graph to drain with STUB executors
#
# Node lifecycle: pending -> ready(derived) -> in_progress -> committed -> done, plus failed / blocked.
# Branch/worktree derive from graph.integration_branch and $TS_WORKTREE_PATH (the integration worktree).
# Node branch = <integration_branch>-<id> (a SIBLING ref: git forbids a
# slash-nested node ref under an existing integration-branch ref); a graph
# missing integration_branch falls back to sprint/unknown with a stderr WARN
# (exit code and stdout shape unchanged).
# base_commit = the integration HEAD sha the lead passes at claim (the node's
# diff base for per_story_diff.sh TS_DIFF_BASE / coverage_check.sh --diff-base);
# null when omitted. reset-orphans preserves it alongside branch/worktree.
#
# Exit codes: 0 ok | 1 usage/IO | 2 illegal transition / guard failure | 3 python3 unavailable
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: schedule.sh <cmd> <graph.json> [args]   (see header)" >&2; exit 1; }
CMD="$1"; GRAPH="$2"; shift 2
[ -f "$GRAPH" ] || { echo "schedule: graph not found: $GRAPH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "schedule: python3 required" >&2; exit 3; }

TS_WORKTREE_PATH="${TS_WORKTREE_PATH:-}" \
python3 - "$CMD" "$GRAPH" "$@" <<'PY'
import sys, os, json, datetime, tempfile

cmd, graph_path, *rest = sys.argv[1:]
WT_PATH = os.environ.get("TS_WORKTREE_PATH", "")

def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def die(msg, code=2):
    sys.stderr.write("schedule: " + msg + "\n"); sys.exit(code)

def load():
    with open(graph_path) as f:
        return json.load(f)

def save(g):
    d = os.path.dirname(os.path.abspath(graph_path))
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".graph.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(g, f, indent=2); f.write("\n")
    os.replace(tmp, graph_path)

def index(g):
    return {n["id"]: n for n in g["nodes"]}

def node(g, nid):
    by = index(g)
    if nid not in by:
        die(f"no such node: {nid}", 1)
    return by[nid]

def deps_done(by, n):
    return all(by[d]["status"] == "done" for d in n["depends_on"])

def ready_ids(g):
    # Build the node index ONCE per readiness scan rather than once per node
    # (deps_done used to rebuild it on every call -> O(n^2) per read command).
    by = index(g)
    return [n["id"] for n in g["nodes"]
            if n["status"] == "pending" and deps_done(by, n)]

def counts(g):
    c = {}
    for n in g["nodes"]:
        c[n["status"]] = c.get(n["status"], 0) + 1
    for k in ("pending", "in_progress", "committed", "done", "failed", "blocked"):
        c.setdefault(k, 0)
    c["ready"] = len(ready_ids(g))
    c["total"] = len(g["nodes"])
    return c

def verdict(g):
    c = counts(g)
    actionable = c["ready"] or c["in_progress"] or c["committed"]
    if actionable:                      return "running"
    if c["done"] == c["total"]:         return "complete"
    if c["failed"] or c["blocked"]:     return "blocked"
    if c["pending"]:                    return "deadlock"
    return "complete"

def node_branch(g, nid):
    # Single source for the node-branch scheme: <integration_branch>-<id>.
    # Must stay a SIBLING ref of the integration branch — a slash-nested node
    # ref cannot coexist with it (git ref vs ref-directory), so every
    # `git worktree add -b` would fail.
    ib = g.get("integration_branch")
    if not ib:
        # D5: surface the silent fallback — stderr only, exit code unchanged.
        sys.stderr.write("schedule: WARN: graph has no integration_branch — falling back to sprint/unknown\n")
        ib = "sprint/unknown"
    return f"{ib}-{nid}"

def transitive_dependents(g, root):
    children = {n["id"]: [] for n in g["nodes"]}
    for n in g["nodes"]:
        for d in n["depends_on"]:
            children.setdefault(d, []).append(n["id"])
    seen, stack = set(), list(children.get(root, []))
    while stack:
        x = stack.pop()
        if x in seen: continue
        seen.add(x); stack.extend(children.get(x, []))
    return seen

# ---- read-only commands ----------------------------------------------------
if cmd == "frontier":
    print(" ".join(ready_ids(load()))); sys.exit(0)

if cmd == "next":
    g = load(); c = counts(g)
    slots = max(0, g.get("max_parallel_agents", 4) - c["in_progress"])
    order = {nid: i for i, nid in enumerate(g.get("order", [n["id"] for n in g["nodes"]]))}
    batch = sorted(ready_ids(g), key=lambda x: order.get(x, 1 << 30))[:slots]
    print(" ".join(batch)); sys.exit(0)

if cmd == "status":
    g = load(); c = counts(g)
    print(f"verdict={verdict(g)} total={c['total']} pending={c['pending']} ready={c['ready']} "
          f"in_progress={c['in_progress']} committed={c['committed']} done={c['done']} "
          f"failed={c['failed']} blocked={c['blocked']}")
    sys.exit(0)

# ---- mutating commands -----------------------------------------------------
def need(args, k):
    if len(rest) < k:
        die(f"{cmd} needs {k} arg(s)", 1)

if cmd == "claim":
    need(rest, 1); g = load(); nid = rest[0]; n = node(g, nid)
    if n["status"] != "pending":
        die(f"claim: node {nid} is {n['status']}, not pending", 2)
    if not deps_done(index(g), n):
        die(f"claim: node {nid} has unmet dependencies", 2)
    n["status"] = "in_progress"; n["phase"] = 3; n["started_at"] = now()
    n["branch"] = node_branch(g, nid)
    n["worktree"] = f"{WT_PATH}-{nid}" if WT_PATH else None
    # Claim-time integration HEAD = the node's diff base (D8). Nullable for
    # back-compat with 2-arg claims.
    n["base_commit"] = rest[1] if len(rest) > 1 else None
    save(g); print(f"claimed {nid} -> in_progress (branch {n['branch']})"); sys.exit(0)

if cmd == "phase":
    need(rest, 2); g = load(); nid, p = rest[0], rest[1]; n = node(g, nid)
    if p not in ("3", "4", "5", "6"):
        die("phase must be 3-6", 1)
    if n["status"] != "in_progress":
        die(f"phase: node {nid} is {n['status']}, not in_progress", 2)
    n["phase"] = int(p); save(g); print(f"{nid} phase={p}"); sys.exit(0)

if cmd == "commit":
    need(rest, 2); g = load(); nid, sha = rest[0], rest[1]; n = node(g, nid)
    if n["status"] != "in_progress":
        die(f"commit: node {nid} is {n['status']}, not in_progress", 2)
    n["status"] = "committed"; n["commit"] = sha
    save(g); print(f"committed {nid} @ {sha}"); sys.exit(0)

if cmd == "integrate":
    need(rest, 2); g = load(); nid, sha = rest[0], rest[1]; n = node(g, nid)
    if n["status"] != "committed":
        die(f"integrate: node {nid} is {n['status']}, not committed", 2)
    n["status"] = "done"; n["integrated_commit"] = sha; n["done_at"] = now()
    n["phase"] = None; n["worktree"] = None
    save(g); print(f"integrated {nid} @ {sha} -> done"); sys.exit(0)

if cmd == "fail":
    need(rest, 1); g = load(); nid = rest[0]; n = node(g, nid)
    if n["status"] in ("done", "failed"):
        die(f"fail: node {nid} is already {n['status']}", 2)
    n["status"] = "failed"; n["done_at"] = now()
    # The header documents `fail <graph> <id> [why]`; persist it or the reason
    # is lost to the resume path, which reads graph.json and not the transcript.
    if len(rest) > 1 and rest[1]:
        n["failed_reason"] = " ".join(rest[1:])
    by = index(g)
    # Report what was ACTUALLY transitioned. Re-walking transitive_dependents()
    # for the summary ignored the done/failed guard three lines up, so `fail B`
    # then `fail A` claimed B was blocked when it was already failed — and paid
    # for a second O(V+E) traversal to get it wrong.
    blocked = []
    for dep in transitive_dependents(g, nid):
        m = by[dep]
        if m["status"] not in ("done", "failed"):
            m["status"] = "blocked"; m["blocked_by"] = nid
            blocked.append(dep)
    save(g)
    blocked.sort()
    print(f"failed {nid}; blocked {len(blocked)} dependent(s): {' '.join(blocked)}"); sys.exit(0)

if cmd == "reset-orphans":
    # attempts is the retry ledger this command both writes and enforces: a node
    # whose executor has died MAX_ATTEMPTS times fails deterministically here
    # instead of being reclaimed forever, and its dependents cascade-block just
    # as `fail` would block them.
    MAX_ATTEMPTS = int(os.environ.get("TS_MAX_NODE_ATTEMPTS", "3"))
    g = load(); by = index(g); reset = []; exhausted = []
    for n in g["nodes"]:
        if n["status"] == "in_progress":
            n["attempts"] = n.get("attempts", 0) + 1
            if n["attempts"] >= MAX_ATTEMPTS:
                n["status"] = "failed"; n["done_at"] = now()
                n["failed_reason"] = f"executor died {n['attempts']} times (TS_MAX_NODE_ATTEMPTS={MAX_ATTEMPTS})"
                for dep in transitive_dependents(g, n["id"]):
                    m = by[dep]
                    if m["status"] not in ("done", "failed"):
                        m["status"] = "blocked"; m["blocked_by"] = n["id"]
                exhausted.append(n["id"])
            else:
                n["status"] = "pending"; n["phase"] = None
                reset.append(n["id"])                  # branch + worktree + base_commit preserved for inspection
    save(g)
    msg = f"reset {len(reset)} orphan(s): {' '.join(reset)}"
    if exhausted:
        msg += f"; failed {len(exhausted)} exhausted node(s): {' '.join(sorted(exhausted))}"
    print(msg); sys.exit(0)

# ---- dry-run simulator -----------------------------------------------------
if cmd == "simulate":
    fail_set, max_waves, allow_resume = set(), 1000, False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--fail":      fail_set = set(x for x in rest[i+1].replace(",", " ").split() if x); i += 2
        elif a == "--max-waves": max_waves = int(rest[i+1]); i += 2
        elif a == "--resume":  allow_resume = True; i += 1
        else: die(f"simulate: unknown flag {a}", 1)

    g = load()
    if not allow_resume and any(n["status"] != "pending" for n in g["nodes"]):
        die("simulate: graph is not fresh (non-pending nodes present); pass --resume to drive it anyway", 2)

    mp = g.get("max_parallel_agents", 4)
    ordering = {nid: k for k, nid in enumerate(g.get("order", [n["id"] for n in g["nodes"]]))}
    wave = 0
    while wave < max_waves:
        v = verdict(g)
        if v in ("complete", "blocked", "deadlock"):
            break
        c = counts(g)
        slots = max(0, mp - c["in_progress"])
        batch = sorted(ready_ids(g), key=lambda x: ordering.get(x, 1 << 30))[:slots]
        if not batch:                                   # nothing to spawn but not terminal -> let merges settle
            break
        wave += 1
        by = index(g)
        for nid in batch:                               # claim the whole wave (stub: mark in_progress)
            n = by[nid]; n["status"] = "in_progress"; n["phase"] = 3; n["started_at"] = now()
            n["branch"] = node_branch(g, nid)
        done_ids, fail_ids = [], []
        for nid in batch:                               # stub executor resolves each node
            n = by[nid]
            if nid in fail_set:
                n["status"] = "failed"; n["done_at"] = now(); fail_ids.append(nid)
                for dep in transitive_dependents(g, nid):
                    m = by[dep]
                    if m["status"] not in ("done", "failed"):
                        m["status"] = "blocked"; m["blocked_by"] = nid
            else:
                n["status"] = "committed"; n["commit"] = f"sim{nid}"
                n["status"] = "done"; n["integrated_commit"] = f"mrg{nid}"  # serialized stub merge
                n["done_at"] = now(); n["phase"] = None; n["worktree"] = None
                done_ids.append(nid)
        save(g)
        print(f"wave {wave}: spawned [{' '.join(batch)}] "
              f"done [{' '.join(done_ids)}]" + (f" failed [{' '.join(fail_ids)}]" if fail_ids else ""))

    c = counts(g); v = verdict(g)
    print(f"-> {v} after {wave} wave(s): done={c['done']} failed={c['failed']} blocked={c['blocked']} "
          f"pending={c['pending']}")
    sys.exit(0 if v in ("complete", "blocked") else 2)

die(f"unknown command: {cmd}", 1)
PY

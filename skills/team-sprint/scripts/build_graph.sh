#!/usr/bin/env bash
#
# build_graph.sh — synthesise the work-graph (graph.json) for `scheduling: graph`.
#
#   build_graph.sh <stories.json> <graph.json>     # reads stories, writes graph
#
# Consumes `stories.json` (the array emitted by parse_stories.sh) plus config
# from the environment, and emits a schema-valid `graph.json` with every node at
# `status: "pending"`, `depends_on` = `declared_deps ∪ inferred_deps`, and a
# cached topological `order[]`. Schema: references/state-schema.md (graph.json).
#
# Edge sources (TS_DEPENDENCY_SOURCE, default `hybrid`):
#   declared  — edges from each story's `depends_on[]` only.
#   inferred  — edges only from `touches[]` glob overlap (declared recorded, not edged).
#   hybrid    — declared edges are authoritative; for any two nodes whose
#               `touches[]` globs overlap, skip the pair when it is already
#               transitively ordered (either direction) in the effective graph
#               so far (declared ∪ inferred edges added earlier) — no phantom
#               `inferred_deps[]` entry; only when incomparable, add a
#               conflict-ordering edge (lower story_id first) and record it in
#               the dependent's `inferred_deps[]`. Edging only incomparable
#               pairs keeps the graph acyclic by construction.
#
# Config via env (references/phases/phase-2.md step 4 wires all three):
#   TS_WORKTREE_NAME        -> integration_branch = "sprint/<name>"   (default sprint-unknown + stderr WARN)
#   TS_MAX_PARALLEL_AGENTS  -> max_parallel_agents                    (default 4)
#   TS_DEPENDENCY_SOURCE    -> declared | inferred | hybrid           (default hybrid)
#
# Validator: exits non-zero, naming the offending node(s), on a cycle (prints the
# cycle path), a dangling `depends_on` ref (id absent from stories.json), or a
# self-edge. Pure stdlib python3 — no jq, no pip deps.
#
# Exit codes: 0 ok | 1 usage/IO | 2 graph-validation failure | 3 python3 unavailable
set -euo pipefail

STORIES="${1:-}"
OUT="${2:-}"
{ [ -n "$STORIES" ] && [ -n "$OUT" ]; } || { echo "usage: build_graph.sh <stories.json> <graph.json>" >&2; exit 1; }
[ -f "$STORIES" ] || { echo "build_graph: file not found: $STORIES" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "build_graph: python3 required" >&2; exit 3; }
# D5: a bare invocation silently produced sprint-unknown branch labels — surface
# the fallback on stderr (warning only; exit code and stdout shape unchanged).
[ -n "${TS_WORKTREE_NAME:-}" ] || echo "build_graph: WARN: defaulting integration_branch to sprint/sprint-unknown — pass TS_WORKTREE_NAME" >&2

exec python3 - "$STORIES" "$OUT" <<'PY'
import sys, os, re, json, fnmatch, datetime, tempfile

stories_path, out_path = sys.argv[1], sys.argv[2]
with open(stories_path, encoding="utf-8") as f:
    stories = json.load(f)
if not isinstance(stories, list):
    sys.stderr.write("build_graph: stories.json must be a JSON array\n"); sys.exit(1)

wt_name = os.environ.get("TS_WORKTREE_NAME") or "sprint-unknown"
integration_branch = "sprint/" + wt_name
try:
    mp = int(os.environ.get("TS_MAX_PARALLEL_AGENTS") or "4")
except ValueError:
    mp = 4
if mp < 1:
    mp = 1
source = (os.environ.get("TS_DEPENDENCY_SOURCE") or "hybrid").lower()
if source not in ("declared", "inferred", "hybrid"):
    sys.stderr.write(f"build_graph: invalid TS_DEPENDENCY_SOURCE: {source}\n"); sys.exit(1)

# --- ingest -----------------------------------------------------------------
ids, meta = [], {}
for s in stories:
    sid = str(s.get("story_id") or s.get("id") or "").strip()
    if not sid:
        sys.stderr.write("build_graph: story with empty story_id\n"); sys.exit(1)
    if sid in meta:
        sys.stderr.write(f"build_graph: duplicate story_id: {sid}\n"); sys.exit(2)
    ids.append(sid)
    meta[sid] = {
        "title":    (s.get("title") or sid),
        "declared": list(dict.fromkeys(str(d).strip() for d in (s.get("depends_on") or []) if str(d).strip())),
        "touches":  [str(t).strip() for t in (s.get("touches") or []) if str(t).strip()],
    }
idset = set(ids)

# --- validate declared edges: self-edge + dangling refs ---------------------
for sid in ids:
    for d in meta[sid]["declared"]:
        if d == sid:
            sys.stderr.write(f"build_graph: self-edge on node {sid}\n"); sys.exit(2)
        if d not in idset:
            sys.stderr.write(f"build_graph: node {sid} depends on unknown node {d}\n"); sys.exit(2)

def natural_key(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]

# --- glob overlap (conflict detection for inferred edges) -------------------
WILD = set("*?[]{}")

def comp_prefix(g):
    keep = []
    for part in g.split("/"):
        if any(c in WILD for c in part):
            break
        keep.append(part)
    return keep

def globs_intersect(a, b):
    if a == b:
        return True
    if fnmatch.fnmatch(a, b) or fnmatch.fnmatch(b, a):
        return True
    ca, cb = comp_prefix(a), comp_prefix(b)
    n = min(len(ca), len(cb))
    return ca[:n] == cb[:n]            # shared path-component prefix -> same subtree

def touches_overlap(a, b):
    return any(globs_intersect(ga, gb) for ga in meta[a]["touches"] for gb in meta[b]["touches"])

# --- synthesise edges -------------------------------------------------------
declared = {sid: list(meta[sid]["declared"]) for sid in ids}
inferred = {sid: [] for sid in ids}

if source in ("inferred", "hybrid"):
    # hybrid: effective-so-far adjacency (declared ∪ inferred edges added below)
    # backing the transitive-ordering check; grows as inferred edges land.
    eff = {sid: set(declared[sid]) for sid in ids}

    def ordered(x, y):
        # True when x transitively precedes y (x reachable from y via deps).
        seen, stack = {y}, [y]
        while stack:
            for d in eff[stack.pop()]:
                if d == x:
                    return True
                if d not in seen:
                    seen.add(d); stack.append(d)
        return False

    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = ids[i], ids[j]
            if not (meta[a]["touches"] and meta[b]["touches"]):
                continue
            if not touches_overlap(a, b):
                continue
            if source == "hybrid" and (ordered(a, b) or ordered(b, a)):
                continue                # already transitively ordered — no edge, no phantom dep
            lo, hi = sorted([a, b], key=natural_key)     # lower story_id first
            if lo not in inferred[hi] and lo not in declared[hi]:
                inferred[hi].append(lo)
                eff[hi].add(lo)         # keep effective-so-far current for later pairs

if source == "declared":
    effective = {sid: list(declared[sid]) for sid in ids}
elif source == "inferred":
    effective = {sid: list(inferred[sid]) for sid in ids}
else:
    effective = {sid: list(dict.fromkeys(declared[sid] + inferred[sid])) for sid in ids}

# --- topological order + cycle detection ------------------------------------
indeg = {sid: 0 for sid in ids}
dependents = {sid: [] for sid in ids}
for sid in ids:
    for d in effective[sid]:
        indeg[sid] += 1
        dependents[d].append(sid)

order, queue = [], [sid for sid in ids if indeg[sid] == 0]
while queue:
    cur = queue.pop(0)
    order.append(cur)
    for dep in dependents[cur]:
        indeg[dep] -= 1
        if indeg[dep] == 0:
            queue.append(dep)

if len(order) != len(ids):
    placed = set(order)
    remaining = [sid for sid in ids if sid not in placed]

    def find_cycle(nodes):
        nodeset, color, stack, res = set(nodes), {}, [], []
        def dfs(u):
            color[u] = "gray"; stack.append(u)
            for v in effective[u]:
                if v not in nodeset:
                    continue
                if color.get(v) == "gray":
                    res.extend(stack[stack.index(v):] + [v]); return True
                if color.get(v) is None and dfs(v):
                    return True
            stack.pop(); color[u] = "black"; return False
        for x in nodes:
            if color.get(x) is None and dfs(x):
                break
        return res or nodes

    cyc = find_cycle(remaining)
    sys.stderr.write("build_graph: dependency cycle: " + " -> ".join(cyc) + "\n"); sys.exit(2)

# --- emit -------------------------------------------------------------------
generated_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
nodes = [{
    "id": sid,
    "title": meta[sid]["title"],
    "status": "pending",
    "phase": None,
    "depends_on": effective[sid],
    "declared_deps": declared[sid],
    "inferred_deps": inferred[sid],
    "touches": meta[sid]["touches"],
    "branch": None,
    "worktree": None,
    "base_commit": None,
    "commit": None,
    "integrated_commit": None,
    "iterations": {"coverage": 0, "review_fix": 0},
    "attempts": 0,
    "blocked_by": None,
    "started_at": None,
    "done_at": None,
} for sid in ids]

graph = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://anthropic.com/skills/team-sprint/graph.schema.json",
    "graph_version": 1,
    "scheduling": "graph",
    "generated_at": generated_at,
    "max_parallel_agents": mp,
    "integration_branch": integration_branch,
    "order": order,
    "nodes": nodes,
}

d = os.path.dirname(os.path.abspath(out_path))
fd, tmp = tempfile.mkstemp(dir=d, prefix=".graph.", suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(graph, f, indent=2); f.write("\n")
os.replace(tmp, out_path)

edge_count = sum(len(effective[s]) for s in ids)
print(f"build_graph: {len(ids)} node(s), {edge_count} edge(s), source={source} -> {out_path}")
PY

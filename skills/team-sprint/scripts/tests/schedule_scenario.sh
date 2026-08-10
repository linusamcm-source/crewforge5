#!/usr/bin/env bash
# schedule_scenario.sh — end-to-end wave-loop scenario for schedule.sh + build_graph.sh.
# Driven by scripts/tests/schedule.bats (which asserts exit 0). Standalone-runnable.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # scripts/ (this file lives in scripts/tests/)
SC="$HERE/schedule.sh"
BG="$HERE/build_graph.sh"
FIX="$HERE/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
no(){ echo "  FAIL: $1"; fail=$((fail+1)); }

# build a fresh happy graph to drive
TS_WORKTREE_NAME="sprint-demo" bash "$BG" "$FIX/happy.stories.json" "$TMP/g.json" 2>/dev/null

# 1. frontier of a fresh graph = the single root (9)
if [ "$(bash "$SC" frontier "$TMP/g.json")" = "9" ]; then
  ok "frontier = [9]"
else
  no "frontier ($(bash "$SC" frontier "$TMP/g.json"))"
fi

# 2. claim/commit/integrate transitions; completing 9 unblocks 11 and 13
TS_WORKTREE_PATH="/wt/repo-sprint-demo" bash "$SC" claim "$TMP/g.json" 9 >/dev/null
if [ "$(bash "$SC" frontier "$TMP/g.json")" = "" ]; then
  ok "9 claimed -> frontier empty"
else
  no "frontier after claim"
fi
bash "$SC" commit "$TMP/g.json" 9 sha9 >/dev/null
bash "$SC" integrate "$TMP/g.json" 9 mrg9 >/dev/null
front="$(bash "$SC" frontier "$TMP/g.json")"
if [ "$front" = "11 13" ]; then
  ok "9 done -> frontier = [11 13]"
else
  no "frontier after integrate ($front)"
fi
if python3 - "$TMP/g.json" <<'PY'
import json,sys
n={x["id"]:x for x in json.load(open(sys.argv[1]))["nodes"]}
assert n["9"]["status"]=="done" and n["9"]["integrated_commit"]=="mrg9" and n["9"]["worktree"] is None, n["9"]
assert n["9"]["branch"]=="sprint/sprint-demo-9", n["9"]["branch"]
print("  ok: node 9 record (done, integrated_commit, branch set, worktree cleared)")
PY
then pass=$((pass+1)); else no "node 9 record"; fi

# 3. illegal transition guard: committing a pending node fails (exit 2)
rc=0; bash "$SC" commit "$TMP/g.json" 12 nope >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  ok "commit on pending node -> exit 2"
else
  no "illegal-transition guard (rc=$rc)"
fi

# 4. fail cascade: failing 11 blocks 12 (12 depends on 11), not 13
cp "$TMP/g.json" "$TMP/f.json"
TS_WORKTREE_PATH="/wt/x" bash "$SC" claim "$TMP/f.json" 11 >/dev/null
bash "$SC" fail "$TMP/f.json" 11 "boom" >/dev/null
if python3 - "$TMP/f.json" <<'PY'
import json,sys
n={x["id"]:x for x in json.load(open(sys.argv[1]))["nodes"]}
assert n["11"]["status"]=="failed", n["11"]["status"]
assert n["12"]["status"]=="blocked" and n["12"]["blocked_by"]=="11", n["12"]
assert n["13"]["status"]=="ready" or n["13"]["status"]=="pending", n["13"]["status"]  # 13 dep is 9(done) -> not blocked
print("  ok: fail 11 -> 12 blocked(by 11), 13 unaffected")
PY
then pass=$((pass+1)); else no "fail cascade"; fi

# 5. reset-orphans: an in_progress node returns to pending with attempts++
cp "$TMP/g.json" "$TMP/r.json"
TS_WORKTREE_PATH="/wt/x" bash "$SC" claim "$TMP/r.json" 11 >/dev/null
bash "$SC" reset-orphans "$TMP/r.json" >/dev/null
if python3 - "$TMP/r.json" <<'PY'
import json,sys
n={x["id"]:x for x in json.load(open(sys.argv[1]))["nodes"]}
assert n["11"]["status"]=="pending" and n["11"]["attempts"]==1, n["11"]
print("  ok: reset-orphans: in_progress 11 -> pending, attempts=1")
PY
then pass=$((pass+1)); else no "reset-orphans"; fi

# 6. simulate drains the happy graph to complete, respecting dependency order
TS_WORKTREE_NAME="sprint-demo" bash "$BG" "$FIX/happy.stories.json" "$TMP/sim.json" 2>/dev/null
rc=0; out="$(bash "$SC" simulate "$TMP/sim.json")" || rc=$?
while IFS= read -r line; do printf '      | %s\n' "$line"; done <<<"$out"
if [ "$rc" -eq 0 ] && grep -q -- "-> complete" <<<"$out"; then
  ok "simulate happy -> complete"
else
  no "simulate happy ($rc)"
fi
if python3 - "$TMP/sim.json" <<'PY'
import json,sys
g=json.load(open(sys.argv[1])); n={x["id"]:x for x in g["nodes"]}
assert all(x["status"]=="done" for x in g["nodes"]), [x["status"] for x in g["nodes"]]
assert all(x["branch"]=="sprint/sprint-demo-"+x["id"] for x in g["nodes"]), [x["branch"] for x in g["nodes"]]
print("  ok: all nodes done after simulate, branches <integration_branch>-<id>")
PY
then pass=$((pass+1)); else no "simulate end-state"; fi

# 7. simulate --fail 11 -> verdict blocked (12 unreachable), 9/13 done, 11 failed
TS_WORKTREE_NAME="sprint-demo" bash "$BG" "$FIX/happy.stories.json" "$TMP/simf.json" 2>/dev/null
out="$(bash "$SC" simulate "$TMP/simf.json" --fail 11)"
if grep -q -- "-> blocked" <<<"$out"; then
  ok "simulate --fail 11 -> blocked"
else
  no "simulate fail verdict ($out)"
fi
if python3 - "$TMP/simf.json" <<'PY'
import json,sys
n={x["id"]:x for x in json.load(open(sys.argv[1]))["nodes"]}
assert n["9"]["status"]=="done" and n["13"]["status"]=="done", (n["9"]["status"],n["13"]["status"])
assert n["11"]["status"]=="failed" and n["12"]["status"]=="blocked", (n["11"]["status"],n["12"]["status"])
print("  ok: fail run end-state (9,13 done; 11 failed; 12 blocked)")
PY
then pass=$((pass+1)); else no "simulate fail end-state"; fi

# 8. concurrency cap: 6 disjoint roots, max_parallel=2 -> 3 waves of <=2
TS_MAX_PARALLEL_AGENTS=2 TS_WORKTREE_NAME="w" bash "$BG" "$FIX/wide.stories.json" "$TMP/wide.json" 2>/dev/null
out="$(bash "$SC" simulate "$TMP/wide.json")"
waves="$(grep -c '^wave ' <<<"$out")"
if [ "$waves" -eq 3 ]; then
  ok "wide(6)/max=2 -> 3 waves"
else
  no "wave count ($waves)"
fi
maxbatch="$(grep '^wave ' <<<"$out" | sed -E 's/.*spawned \[([^]]*)\].*/\1/' | awk '{print NF}' | sort -nr | head -1)"
if [ "$maxbatch" -le 2 ]; then
  ok "no wave exceeds the cap (max batch=$maxbatch)"
else
  no "cap exceeded ($maxbatch)"
fi

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]

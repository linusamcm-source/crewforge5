#!/usr/bin/env bash
#
# parse_stories.sh — parse a plan-final.md into stories.json for build_graph.sh.
#
#   parse_stories.sh <plan-final.md>     # writes a JSON array to stdout
#
# Story headings are shape-agnostic — any of:
#   `## Story <id>: <title>`      (canonical)
#   `## NEW Story <id>: <title>`  (mixed plans; treated identically to `## Story`)
#   `### <id> amendment ...`      (v2-style; <id> is the token before ` amendment`,
#                                  title is the full heading text)
# Per heading it extracts (`heading_line` = 1-based line of the heading):
#   acceptance_criteria[]  from `### Acceptance Criteria`     (bullet list, or one joined prose item)
#   definition_of_done[]   from `### Definition of Done`      (bullet list, or one joined prose item)
#   depends_on[]           from `### Depends On:`             (inline "9, 11" or bullets; "none" -> [])
#   touches[]              from `### Touches:`                (inline comma/space list, or one glob per bullet)
#
# With no story heading the whole file is one implicit story keyed by the
# filename stem (story_id = title = stem), depends_on: [] (a lone node has
# nothing to depend on), heading_line: null.
#
# Notes:
#   * Continuation join (AC/DoD bodies only): a non-blank line that is not a
#     bullet and follows a bullet is that bullet's wrapped continuation — it is
#     joined to the item with a single space. A blank line, a new bullet, or a
#     heading at any depth terminates the join. Touches/Depends bullets are
#     never joined — a bullet stays one verbatim glob/id.
#   * Comment skip: HTML comment spans (`<!-- ... -->`, including multi-line
#     comments) in section bodies are stripped — never items, continuations,
#     or prose for the un-bulleted fallback. Text sharing a line with a
#     delimiter survives outside the span. An unterminated `<!--` drops the
#     section remainder with a warning on stderr (never silently).
#   * Pure stdlib python3 — no jq, no pip deps. Fenced code blocks are skipped
#     everywhere — fenced lines are never headings, items, or continuations.
#   * Inline `### Touches:` is split on commas/whitespace; put brace-expansion
#     globs (e.g. `src/{a,b}/**`) on their own bullet line so the comma survives.
#
# Exit codes: 0 ok | 1 usage/IO | 3 python3 unavailable
set -euo pipefail

PLAN="${1:-}"
[ -n "$PLAN" ] || { echo "usage: parse_stories.sh <plan-final.md>" >&2; exit 1; }
[ -f "$PLAN" ] || { echo "parse_stories: file not found: $PLAN" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "parse_stories: python3 required" >&2; exit 3; }

exec python3 - "$PLAN" <<'PY'
import sys, os, re, json

plan = sys.argv[1]
with open(plan, encoding="utf-8") as f:
    text = f.read().replace("\r\n", "\n").replace("\r", "\n")
lines = text.split("\n")
n = len(lines)

# --- mark fenced code lines so headings/items inside them are ignored ---
fence = [False] * n
inf = False
for i, l in enumerate(lines):
    s = l.lstrip()
    if s.startswith("```") or s.startswith("~~~"):
        fence[i] = True            # the fence delimiter itself is never a heading
        inf = not inf
    else:
        fence[i] = inf

def live(i):
    return not fence[i]

STORY_RE = re.compile(r'^##\s+(?:NEW\s+)?Story\s+([^:\s]+)\s*:?\s*(.*?)\s*$', re.I)
AMEND_RE = re.compile(r'^###\s+(\S+)\s+amendment\b', re.I)
H2_RE    = re.compile(r'^##\s+')
H3_RE    = re.compile(r'^###\s+(.*?)\s*$')
ITEM_RE  = re.compile(r'^\s*(?:[-*+]|\d+[.)])\s+(.*?)\s*$')

def story_heading(i):
    # (story_id, title) if line i starts a story — canonical `## Story`,
    # `## NEW Story`, or v2-style `### <id> amendment` — else None.
    if not live(i):
        return None
    m = STORY_RE.match(lines[i])
    if m:
        sid = m.group(1).strip()
        return sid, (m.group(2).strip() or sid)
    a = AMEND_RE.match(lines[i])
    if a:
        return a.group(1).strip(), re.sub(r'^###\s+', '', lines[i]).strip()
    return None

def classify(heading_text):
    low = heading_text.lower()
    for kind, pat in (("ac", r'acceptance\s+criteria'),
                      ("dod", r'definition\s+of\s+done'),
                      ("deps", r'depends\s*on'),
                      ("touches", r'touches')):
        m = re.match(pat, low)
        if m:
            inline = heading_text[m.end():].lstrip()
            if inline.startswith(":"):
                inline = inline[1:]
            return kind, inline.strip()
    return None, ""

def split_ids(s):
    return [p for p in re.split(r'[,\s]+', s.strip()) if p and p.lower() != "none"]

def parse_body(lo, hi):
    ac, dod, deps, touches = [], [], [], []
    cur_kind, cur_inline, buf = None, "", []

    def strip_comments(raw):
        # Strip HTML comment spans (`<!-- ... -->`, incl. multi-line): comment
        # text is neither an item, a continuation, nor fallback prose, but
        # text sharing a line with a delimiter survives outside the span. A
        # line the strip leaves blank is dropped (a real blank would end the
        # join). An unterminated `<!--` warns on stderr — never silent.
        out, inc = [], False
        for bl in raw:
            started_in, s, r = inc, bl, ""
            while s:
                if inc:
                    e = s.find("-->")
                    if e < 0:
                        s = ""
                    else:
                        s, inc = s[e + 3:], False
                else:
                    b = s.find("<!--")
                    if b < 0:
                        r, s = r + s, ""
                    else:
                        r, s, inc = r + s[:b], s[b + 4:], True
            if not started_in and r == bl:
                out.append(bl)                             # untouched (incl. real blanks)
            elif r.strip():
                out.append(r)                              # residue outside the comment span
        if inc:
            print("parse_stories: warning: unterminated <!-- comment in "
                  f"{plan}; remaining section lines were dropped", file=sys.stderr)
        return out

    def flush():
        if cur_kind is None:
            return
        body = strip_comments(buf)
        items, joining = [], False
        for bl in body:
            mi = ITEM_RE.match(bl)
            if mi:
                items.append(mi.group(1).strip())
                joining = True
            elif not bl.strip():
                joining = False                            # blank line ends the join
            elif re.match(r'^#{1,6}\s', bl):
                joining = False                            # heading (H4+ reach buf) ends the join
            elif joining and cur_kind in ("ac", "dod"):
                items[-1] += " " + bl.strip()              # wrapped-bullet continuation (AC/DoD only)
        if cur_kind in ("ac", "dod") and not items:        # un-bulleted prose -> one joined item
            prose = [bl.strip() for bl in body if bl.strip()]
            items = [" ".join(prose)] if prose else []
        if cur_kind == "ac":
            ac.extend(items)
        elif cur_kind == "dod":
            dod.extend(items)
        elif cur_kind == "deps":
            for v in split_ids(cur_inline) + [v for it in items for v in split_ids(it)]:
                if v not in deps:
                    deps.append(v)
        elif cur_kind == "touches":
            vals = []
            if cur_inline:
                vals += [t.strip() for t in re.split(r'[,\s]+', cur_inline) if t.strip()]
            vals += [it.strip() for it in items]           # bullet = verbatim glob (brace-safe)
            for v in vals:
                if v and v not in touches:
                    touches.append(v)

    i = lo
    while i < hi:
        # A section heading is any H2/H3 that is not itself a story start.
        if live(i) and story_heading(i) is None:
            htext = None
            m3 = H3_RE.match(lines[i])
            if m3:
                htext = m3.group(1).strip()
            elif H2_RE.match(lines[i]):
                htext = re.sub(r'^##\s+', '', lines[i]).strip()
            if htext is not None:
                flush()
                cur_kind, cur_inline = classify(htext)
                buf = []
                i += 1
                continue
        if cur_kind is not None and live(i):               # fenced lines never reach flush()
            buf.append(lines[i])
        i += 1
    flush()
    return ac, dod, deps, touches

story_starts = [i for i in range(n) if story_heading(i)]
boundaries   = sorted(set(story_starts) |
                      {i for i in range(n) if live(i) and H2_RE.match(lines[i])})

stories = []
if story_starts:
    for s in story_starts:
        sid, title = story_heading(s)
        end = next((b for b in boundaries if b > s), n)    # body runs to the next story/H2 boundary
        ac, dod, deps, touches = parse_body(s + 1, end)
        stories.append({
            "story_id": sid, "title": title, "heading_line": s + 1,
            "acceptance_criteria": ac, "definition_of_done": dod,
            "depends_on": deps, "touches": touches,
        })
else:
    sid = os.path.splitext(os.path.basename(plan))[0]
    ac, dod, _deps, touches = parse_body(0, n)
    stories.append({
        "story_id": sid, "title": sid, "heading_line": None,
        "acceptance_criteria": ac, "definition_of_done": dod,
        "depends_on": [],                                  # lone implicit node
        "touches": touches,
    })

json.dump(stories, sys.stdout, indent=2)
sys.stdout.write("\n")
PY

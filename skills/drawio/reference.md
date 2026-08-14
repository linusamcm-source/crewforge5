# draw.io XML Reference

Detailed reference for styles, edge routing, containers, layers, tags, metadata, and dark mode. Consult this when generating draw.io XML diagrams.

**Two runtimes — read before trusting the "automatic layout" advice below.** The skill's default path (see SKILL.md) writes a `.drawio` file and exports via the draw.io **desktop CLI**. That path has **no live viewer and no automatic layout/edge-routing pass** — the exported PNG/SVG/PDF renders your raw XML verbatim, so place vertices deliberately using the rigid grid below. The `search_shapes` / `create_diagram` / `postLayout` tools and the automatic ELK edge-routing pass described in later sections apply **only when a `drawio-mcp` server is connected** and a live viewer renders the diagram. If those MCP tools are not available in your environment, ignore the tool calls and rely on your own placement.

## Reasoning budget (read this first)

Your job is to declare the **logical structure** of the diagram — what nodes exist, what edges connect them, what labels they carry, what lane/container groups them. draw.io's edge router and (when available) a post-layout pass handle routing and placement; you do **not** need to do layout math.

**Do NOT** in your reasoning:

- Do NOT debate the topic. The user asked for a flowchart / architecture / sequence / etc. — pick one concrete scenario on your first impulse and commit. Never write "Actually, let me think of something else…" or pitch alternatives.
- Do NOT debate flat-lanes vs nested-pools, horizontal vs vertical orientation, one vs multiple variations. Pick the first reasonable option (almost always: flat swimlanes, top-down or left-right based on what fits the content). Do not flip-flop.
- Do NOT compute x/y coordinates in prose. No "column spacings of 160px totaling 1840px width — that's too wide, let me tighten to 1700…" loops. Use the rigid grid below; do the arithmetic in your head and write the XML.
- Do NOT re-derive drawio mechanics (`horizontal=0`, `startSize=110`, nested-lane coordinates). Use the templates below as-is.
- Do NOT enumerate columns ("customer lane columns 0-10, web app 1-7"). Place a node, move on.
- Do NOT add `<Array as="points">` waypoints. Edges are routed automatically. (Exception: keeping an edge from crossing a node in the no-viewer path — see Edges.)
- Do NOT set `exitX` / `exitY` / `entryX` / `entryY` connection-point overrides unless you have specific geometric intent. Steering an edge around a node it would otherwise cross IS specific geometric intent.
- Do NOT verify, re-check, or adjust coordinates after placing a node — with one exception: the edge-clearance sweep (see Edges) is required, and any collision it finds gets fixed.
- Do NOT narrate "building the diagram / finalizing the XML / now let me…". Just emit XML.
- Do NOT write out lists of node positions as planning text. Emit them as `<mxCell>` elements directly.

**Do** in your reasoning:

- Identify the diagram type + actors/stages (1-2 short sentences).
- Identify any grouping (swimlanes? containers? none?).
- Go straight to XML.

**Rigid grid — use for every XML diagram:**

- Column x = `col_index * 220 + 40`  (col 0 = 40, col 1 = 260, col 2 = 480, …)
- Row y = `row_index * 160 + 40`     (row 0 = 40, row 1 = 200, row 2 = 360, …)
- Node size: rectangles `140×60`, diamonds `140×80`, circles `60×60`, documents `120×80`, cylinders `100×70`, platform icons `78×78`

The pitch exceeds the node size on purpose: the leftover strip between two grid slots (80px horizontal, 100px vertical) is a **routing channel**. Edges travel in channels; nodes never sit in them.

Pick a `(col, row)` for each node.

**The grid pitch is a minimum, not a target.** When a gap between two nodes must carry a labeled edge, more than one edge, or a node whose text needs a bigger box, skip a grid lane (leave a column/row empty) or double the pitch for that region. Every connection and every label must sit fully in empty space — readable at a glance, touching nothing.

## Mandatory style contract

Every vertex and every edge in every diagram carries `rounded=1;shadow=1;strokeWidth=2;` in its style, and the `mxGraphModel` element carries `shadow="1"`. The examples throughout this file show these tokens; when copying a style string from a shape library (AWS/Azure/GCP sidebars, `search_shapes` output), append `shadow=1;strokeWidth=2;` to it. Shapes with no corners to round still take shadow and stroke width.

The only cells exempt are ones that draw nothing: invisible `group;` containers, `shape=tableRow`, transparent table cells (`fillColor=none`), and bare `text;` labels. A shadow on an invisible box renders as a floating smudge.

```xml
<mxGraphModel dx="800" dy="600" grid="1" gridSize="10" page="1" shadow="1" adaptiveColors="auto">
```

## General principles

- **Use proper draw.io shapes and connectors** — choose the semantically correct shape for each element (e.g., `shape=cylinder3` for databases and tanks, `rhombus` for decisions, `shape=mxgraph.pid2valves.*` for valves in P&IDs). draw.io has extensive shape libraries; prefer domain-appropriate shapes over generic rectangles.
- **Decide whether to search for shapes** — before generating a diagram, decide if it needs domain-specific shapes from draw.io's extended libraries. **Skip `search_shapes`** for standard diagram types that use basic geometric shapes: flowcharts, UML (class, sequence, state, activity), ERD, org charts, mind maps, Venn diagrams, timelines, wireframes, and any diagram using only rectangles, diamonds, circles, cylinders, and arrows. Also skip if the user explicitly asks to use basic/simple shapes or says not to search. **Use `search_shapes`** when the diagram requires industry-specific or branded icons: cloud architecture (AWS, Azure, GCP), network topology (Cisco, rack equipment), P&ID (valves, instruments, vessels), electrical/circuit diagrams, Kubernetes, BPMN with specific task types, or any domain where the user expects realistic/standardized symbols rather than labeled boxes.
- **Platform components always get the platform's icon** — a diagram naming AWS, Azure, GCP, Kubernetes, or Cisco components uses that library's shapes, never a labelled rectangle. When `search_shapes` is unavailable (the default CLI path), use the verified style strings in "Platform icon sets" below.
- **Match the language of labels to the user's language** — if the user writes in German, French, Japanese, etc., all diagram labels, titles, and annotations should be in that same language.

## Common styles

**Rounded rectangle:**
```xml
<mxCell id="2" value="Label" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
</mxCell>
```

**Diamond (decision):**

```xml
<mxCell id="3" value="Condition?" style="rhombus;rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
  <mxGeometry x="100" y="200" width="120" height="80" as="geometry"/>
</mxCell>
```

**Arrow (edge):**

```xml
<mxCell id="4" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;" edge="1" source="2" target="3" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

**Labeled arrow:**

```xml
<mxCell id="5" value="Yes" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;" edge="1" source="3" target="6" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

## Style properties

| Property                                                  | Values        | Use for                                                                            |
| --------------------------------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| `rounded=1`                                             | 0 or 1        | Rounded corners — mandatory on every vertex and edge                              |
| `shadow=1`                                              | 0 or 1        | Drop shadow — mandatory on every vertex and edge                                  |
| `strokeWidth=2`                                         | number        | Line width — mandatory 2 on every vertex and edge                                 |
| `whiteSpace=wrap`                                       | wrap          | Text wrapping                                                                      |
| `fillColor=#dae8fc`                                     | Hex color     | Background color                                                                   |
| `strokeColor=#6c8ebf`                                   | Hex color     | Border color                                                                       |
| `fontColor=#333333`                                     | Hex color     | Text color                                                                         |
| `shape=cylinder3`                                       | shape name    | Database cylinders                                                                 |
| `shape=mxgraph.flowchart.document`                      | shape name    | Document shapes                                                                    |
| `ellipse`                                               | style keyword | Circles/ovals                                                                      |
| `rhombus`                                               | style keyword | Diamonds                                                                           |
| `edgeStyle=orthogonalEdgeStyle`                         | style keyword | Right-angle connectors                                                             |
| `edgeStyle=elbowEdgeStyle`                              | style keyword | Elbow connectors                                                                   |
| `dashed=1`                                              | 0 or 1        | Dashed lines                                                                       |
| `swimlane`                                              | style keyword | Swimlane containers                                                                |
| `group`                                                 | style keyword | Invisible container (pointerEvents=0)                                              |
| `container=1`                                           | 0 or 1        | Enable container behavior on any shape                                             |
| `pointerEvents=0`                                       | 0 or 1        | Prevent container from capturing child connections                                 |
| `html=1`                                                | 0 or 1        | Enable HTML rendering in labels (required for `<b>`, `<br>`, `<font>`, etc.) |
| `shape=umlLifeline;perimeter=lifelinePerimeter;size=16` | shape         | UML sequence diagram lifeline (size = header height)                               |

## HTML labels

**Always include `html=1` in the style** when the `value` attribute contains any HTML tags (`<b>`, `<br>`, `<font>`, `<i>`, `<u>`, `<hr>`, `<p>`, `<table>`, etc.). Without `html=1`, HTML tags are displayed as literal text instead of being rendered.

HTML in attribute values must be **XML-escaped**: `<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`

```xml
<mxCell value="<b>Title</b><br>Description"
        style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
</mxCell>
```

**Line breaks:** Use `&#xa;` (works with both `html=1` and `html=0`) or `&lt;br&gt;` (requires `html=1`) for line breaks — never use `\n`, which renders as literal backslash-n text instead of a newline.

**Best practice:** Always include `html=1` in every cell style. This ensures labels render correctly whether they contain HTML or plain text — plain text is unaffected by the flag.

**Bold/italic/underline:** Use `fontStyle` in the style string when the entire label should be bold (`fontStyle=1`), italic (`fontStyle=2`), or underline (`fontStyle=4`). Values can be combined via bitwise OR (e.g., `fontStyle=3` = bold+italic). Use HTML tags (`<b>`, `<i>`, `<u>`) only when formatting part of the label (e.g., bold title with normal description). Never combine `fontStyle` with HTML tags for the same effect — this is redundant and causes visible raw tags if `html=1` is missing.

## Edges

**CRITICAL: Every edge `mxCell` must contain a `<mxGeometry relative="1" as="geometry" />` child element.** Self-closing edge cells (e.g. `<mxCell ... edge="1" ... />`) are invalid and will not render correctly. Always use the expanded form:

```xml
<mxCell id="e1" edge="1" parent="1" source="a" target="b" style="...">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
```

**Edge routing is automatic.** After the diagram renders, the viewer runs an ELK edge-routing pass that pins vertices and recomputes bend points + connection points. You do **not** need to:

- Add `<mxPoint>` waypoints
- Set `exitX` / `exitY` / `entryX` / `entryY`
- Route around obstacles
- Worry about edge-vertex collisions or parallel edge spacing

Just declare `source` and `target` and let ELK do the routing. The ELK pass also reverts itself if it made routing worse — so your edges are at worst unchanged, never worse.

**No-viewer path (default): you are the router — no edge may ever pass over a node.** When exporting via the desktop CLI (no `drawio-mcp`, no ELK pass — see the runtime note at the top), the raw XML is exactly what renders, and nothing will fix a collision for you.

**The one exception — parent containment.** An edge whose source or target sits inside a container may cross *that container's* boundary; that is the normal, correct way to connect into a group and needs no avoidance. Everything else is a defect: a line over a sibling node, over an unrelated container, or clipping the corner of a node it does not connect to. Edge-over-edge crossings are fine and are never a reason to add a bend.

Enforce clearance in this order:

1. **Placement first.** Put connected nodes in adjacent grid columns/rows so the default orthogonal path between them runs down an empty channel. Most collisions are placement problems, not routing problems. If two connected nodes are far apart with nodes in between, either move them adjacent or reserve an empty row/column as the through-channel before routing.
2. **Connection-point sides second.** If an edge would still clip a node, set `exitX`/`exitY`/`entryX`/`entryY` so it leaves and enters on sides facing an empty channel — e.g. a downstream node two columns right and one row down: exit right (`exitX=1;exitY=0.5;`), enter top (`entryX=0.5;entryY=0;`).
3. **Waypoints last.** If placement and sides can't avoid the collision, add an `<Array as="points">` waypoint steering the edge through an empty grid lane. Waypoints go at channel centres — halfway between two occupied columns/rows — never inside a node's bounding box.

```xml
<mxCell id="e9" value="retry" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;exitX=1;exitY=0.5;entryX=0.5;entryY=0;" edge="1" parent="1" source="n3" target="n7">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="420" y="230"/>
      <mxPoint x="420" y="400"/>
    </Array>
  </mxGeometry>
</mxCell>
```

**Long back-edges (loops, error paths, feedback) get their own lane.** They are the most common source of node collisions. Route them around the outside of the diagram — a channel below the bottom row or beside the last column — rather than back through the middle of the flow.

**Before emitting, sweep every edge once.** For each edge, take its source and target rectangles and the straight/orthogonal path between them, and check no third node's box lies on that path. Any hit: fix it with step 1, 2, or 3 above. This is the one check worth doing after placement — skip the general "verify coordinates" prohibition for it.

Every edge must read as a logical, easy-to-follow path from its source node to its target — no line through a box, no ambiguous mid-node crossings.

**Text clearance is part of the same contract.** Edge labels render at the edge midpoint by default — if that midpoint sits on or beside a node, the label collides with the node's text and both become unreadable. Prevent it the same way: spacing first (widen the gap the labeled edge travels through — see the grid-pitch note above), then shift the label along the edge (`x` offset in the label geometry, range -1 to 1) toward an empty stretch. Node text that doesn't fit gets a bigger node, never spillover. If two labels would touch, move one — a diagram where connections or text can't be read clearly has failed regardless of how correct its structure is.

**What you still choose: the edge style.** The style determines the overall look (orthogonal angles, curves, straight lines) — ELK honors the style family when routing.

| Style                     | Syntax                                       | Best for                                                                                                                                              |
| ------------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Orthogonal**      | `edgeStyle=orthogonalEdgeStyle`            | Flowcharts, architecture, network diagrams, BPMN — any diagram with right-angle connectors                                                           |
| **Straight**        | no `edgeStyle`                             | UML class/sequence diagrams, direct point-to-point connections. For sequence diagram messages use `endSize=6;startSize=6;` to keep arrowheads small |
| **Entity Relation** | `edgeStyle=entityRelationEdgeStyle`        | ER diagrams — creates perpendicular stubs at both ends                                                                                               |
| **Curved**          | `curved=1`                                 | Mind maps, informal diagrams                                                                                                                          |
| **Elbow**           | `edgeStyle=elbowEdgeStyle;elbow=vertical;` | Rarely needed —`orthogonalEdgeStyle` handles almost all cases; use this only for simple 1-bend linear flows                                        |

**Use a consistent edge style within each diagram.** Pick one based on diagram type and apply it to all edges: ER → `entityRelationEdgeStyle`; UML class → straight; mind maps → curved; flowcharts/architecture/network → `orthogonalEdgeStyle`.

**Useful edge style attributes** that apply regardless of routing:

- `rounded=1` — rounded corners at bend points (recommended for orthogonal)
- `endArrow=classic` / `endArrow=none` — arrow heads
- `dashed=1` — dashed line
- `strokeColor=#...`, `strokeWidth=2` — color/width
- Edge labels: set `value` directly on the edge cell

## Platform icon sets

When a diagram names a cloud platform or product that draw.io ships icons for, use the icon — never a rectangle labelled "S3" or "Cosmos DB". These libraries are bundled with the desktop app, so they render in CLI exports with no network access.

Rules for all three:

- Keep the library's own `fillColor` / `strokeColor` — those are the brand colours. Do not recolour.
- Append `shadow=1;strokeWidth=2;` to the library style string.
- Icons are square: `78×78` (or `50×50` for dense diagrams). `aspect=fixed` keeps them square — leave it in.
- Labels sit **below** the icon (`verticalLabelPosition=bottom;verticalAlign=top;`), so reserve vertical space in the grid: the label eats ~20px under the box and must not touch the row beneath.
- If `search_shapes` is available (drawio-mcp connected), use it to confirm the exact shape name. Without it, use a name you are confident of from the list below, or fall back to the platform's group/generic icon rather than inventing a name — an unknown shape name renders as an empty box.

### AWS (`mxgraph.aws4`)

**Service icon** — the plain glyph, brand colour by service category:

```xml
<mxCell id="s3" value="S3 Bucket" style="sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=#7AA116;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shadow=1;strokeWidth=2;shape=mxgraph.aws4.s3;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="78" height="78" as="geometry"/>
</mxCell>
```

**Resource icon** — the rounded coloured tile with the glyph inside (the standard AWS architecture-diagram element):

```xml
<mxCell id="lam" value="Lambda" style="sketch=0;outlineConnect=0;fontColor=#232F3E;fillColor=#ED7100;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shadow=1;strokeWidth=2;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;" vertex="1" parent="1">
  <mxGeometry x="260" y="40" width="78" height="78" as="geometry"/>
</mxCell>
```

Category fill colours: compute `#ED7100`, storage `#7AA116`, database `#C925D1`, networking `#8C4FFF`, security `#DD344C`, analytics `#8C4FFF`, management `#E7157B`, general `#232F3E`.

**Group container** — VPC, region, account, subnet, security group. This is a real container (`container=1;pointerEvents=0;`), so children set `parent="<group_id>"`:

```xml
<mxCell id="vpc" value="VPC" style="sketch=0;outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0;shadow=1;strokeWidth=2;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc2;strokeColor=#8C4FFF;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="640" height="360" as="geometry"/>
</mxCell>
```

Group icon names: `group_aws_cloud`, `group_aws_cloud_alt`, `group_region`, `group_vpc2`, `group_security_group`, `group_auto_scaling_group`, `group_account`.

### Azure (`img/lib/azure2`)

Azure icons are **image shapes**, not stencils — the style points at a bundled SVG:

```xml
<mxCell id="func" value="Function App" style="image;aspect=fixed;html=1;points=[];align=center;fontSize=12;shadow=1;strokeWidth=2;image=img/lib/azure2/compute/Function_Apps.svg;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="68" height="68" as="geometry"/>
</mxCell>
```

The path is `img/lib/azure2/<category>/<Name>.svg` — category folders include `compute`, `storage`, `databases`, `networking`, `identity`, `security`, `ai_machine_learning`, `analytics`, `integration`, `containers`, `devops`, `management_governance`, `web`, `iot`, `general`. Names are Title_Case with underscores (`Azure_Machine_Learning.svg`, `Function_Apps.svg`). Confirm names with `search_shapes` when it is available; if unsure, prefer a generic rounded rectangle in Azure blue (`fillColor=#0078D4;fontColor=#ffffff;strokeColor=#005A9E;`) over a guessed filename, because a missing image renders blank.

For Azure grouping (subscription, resource group, VNet), use a plain swimlane container in the platform's colour — Azure has no group-stencil equivalent to AWS.

### GCP (`mxgraph.gcp2`)

```xml
<mxCell id="run" value="Cloud Run" style="sketch=0;html=1;aspect=fixed;strokeColor=none;fillColor=#3B8DF1;verticalAlign=top;labelPosition=center;verticalLabelPosition=bottom;align=center;fontSize=12;shadow=1;strokeWidth=2;shape=mxgraph.gcp2.cloud_run;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="66" height="58" as="geometry"/>
</mxCell>
```

Shape names are lowercase with underscores (`compute_engine`, `cloud_storage`, `cloud_run`, `bigquery`, `pubsub`, `cloud_sql`, `cloud_monitoring`). GCP product icons are blue `#3B8DF1`; category icons live under `mxgraph.gcp3.*` in grey `#9aa0a6`.

GCP grouping cards (project, zone) use a rounded card container:

```xml
<mxCell id="proj" value="Project" style="sketch=0;rounded=1;absoluteArcSize=1;arcSize=2;html=1;strokeColor=#dddddd;fillColor=#ffffff;gradientColor=none;dashed=0;fontSize=12;fontColor=#9E9E9E;align=left;verticalAlign=top;spacing=10;spacingTop=-4;whiteSpace=wrap;container=1;pointerEvents=0;shadow=1;strokeWidth=2;" vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="560" height="320" as="geometry"/>
</mxCell>
```

### Other platforms

Same pattern applies to Kubernetes (`mxgraph.kubernetes.*`), Cisco (`mxgraph.cisco19.*`), and the other bundled libraries. Reach for `search_shapes` to get the exact style string when the MCP server is connected; otherwise use a generic shape rather than a guessed stencil name.

## Containers and groups

For architecture diagrams or any diagram with nested elements, use draw.io's proper parent-child containment — do **not** just place shapes on top of larger shapes.

### How containment works

Set `parent="containerId"` on child cells. Children use **relative coordinates** within the container.

### Container types

| Type                        | Style                                                   | When to use                                                                                                               |
| --------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **Group** (invisible) | `group;`                                              | No visual border needed, container has no connections. Includes `pointerEvents=0` so child connections are not captured |
| **Swimlane** (titled) | `swimlane;startSize=30;`                              | Container needs a visible title bar/header, or the container itself has connections                                       |
| **Custom container**  | Add `container=1;pointerEvents=0;` to any shape style | Any shape acting as a container without its own connections                                                               |

### Key rules

- **Edges to children inside containers naturally cross the container boundary** — this is correct and expected, and it is the *only* sanctioned exception to the no-edge-over-a-node rule. Do not add extra waypoints or complex routing to avoid a parent container when connecting to shapes inside it. It does not license crossing any *other* container: an edge that must pass a container it is not entering routes around it.
- **Always add `pointerEvents=0;`** to container styles that should not capture connections being rewired between children
- Only omit `pointerEvents=0` when the container itself needs to be connectable — in that case, use `swimlane` style which handles this correctly (the client area is transparent for mouse events while the header remains connectable)
- Children must set `parent="containerId"` and use coordinates **relative to the container**

### Example: Architecture container with swimlane

```xml
<mxCell id="svc1" value="User Service" style="swimlane;rounded=1;shadow=1;strokeWidth=2;startSize=30;fillColor=#dae8fc;strokeColor=#6c8ebf;html=1;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="api1" value="REST API" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="svc1">
  <mxGeometry x="20" y="40" width="120" height="60" as="geometry"/>
</mxCell>
<mxCell id="db1" value="Database" style="shape=cylinder3;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="svc1">
  <mxGeometry x="160" y="40" width="120" height="60" as="geometry"/>
</mxCell>
```

### Example: Invisible group container

```xml
<mxCell id="grp1" value="" style="group;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="c1" value="Component A" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="grp1">
  <mxGeometry x="10" y="10" width="120" height="60" as="geometry"/>
</mxCell>
```

### Swimlanes for grouped actors (BPMN-style flowcharts)

Use **flat swimlanes** at `parent="1"`, stacked vertically. One row of nodes per lane.

**Fixed values — do not compute or debate:**

- Lane size: `x=0, y=lane_index*150, width=CANVAS_W, height=150`
- Lane style: `swimlane;horizontal=0;startSize=110;fillColor=<pastel>;html=1;`
- Child nodes inside a lane: `parent="<lane_id>"`, `x = 120 + col*220`, `y = 45` (always 45), size 140×60 (or 140×80 for diamonds)
- Cross-lane edges: `parent="1"` (not inside a lane)

Pick `CANVAS_W = max_col * 220 + 300`. Choose lane colors from `#f5f5f5, #e8f4f8, #fff0e6, #e8f5e9, #fff9e6, #fce4ec` in that order.

```xml
<mxCell id="lane1" value="Customer" style="swimlane;rounded=1;shadow=1;strokeWidth=2;horizontal=0;startSize=110;fillColor=#f5f5f5;html=1;" vertex="1" parent="1">
  <mxGeometry x="0" y="0" width="1800" height="150" as="geometry"/>
</mxCell>
<mxCell id="n1" value="Place Order" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="lane1">
  <mxGeometry x="120" y="45" width="140" height="60" as="geometry"/>
</mxCell>
<mxCell id="lane2" value="System" style="swimlane;rounded=1;shadow=1;strokeWidth=2;horizontal=0;startSize=110;fillColor=#e8f4f8;html=1;" vertex="1" parent="1">
  <mxGeometry x="0" y="150" width="1800" height="150" as="geometry"/>
</mxCell>
<mxCell id="n2" value="Validate" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="lane2">
  <mxGeometry x="340" y="45" width="140" height="60" as="geometry"/>
</mxCell>
<mxCell id="e1" edge="1" parent="1" source="n1" target="n2" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

Do NOT nest lanes inside a pool. Do NOT vary lane heights. Do NOT compute title-area offset — it is always 110, children start at x=120 to clear it.

### Nested architecture containers (cloud, infra, network topologies)

For diagrams with **nested groupings** — VPC → Availability Zone → EC2 instance, Datacenter → Rack → Server, Region → Environment → Service — use nested swimlanes. This is where the AI most often flattens hierarchy that should be nested. Treat each level as a swimlane container.

**Rules:**

- Every container is a `swimlane` with `startSize=24` (title area at the top).
- Child cells set `parent="<container_id>"` and use coordinates **relative to their parent** (origin 0,0 is the parent's top-left, below the title).
- Edges between cells in **different** containers must have `parent="1"` (not a container) — otherwise they render inside the container and get clipped.
- For industry-specific icons (AWS/Azure/GCP logos, Cisco equipment, etc.), call `search_shapes` to get the exact `style` string and substitute it into a regular vertex — the container structure stays the same.

```xml
<mxCell id="vpc" value="VPC" style="swimlane;rounded=1;shadow=1;strokeWidth=2;startSize=24;fillColor=#dae8fc;strokeColor=#6c8ebf;html=1;" vertex="1" parent="1">
  <mxGeometry x="0" y="0" width="720" height="360" as="geometry"/>
</mxCell>
<mxCell id="az1" value="AZ us-east-1a" style="swimlane;rounded=1;shadow=1;strokeWidth=2;startSize=24;fillColor=#fff2cc;strokeColor=#d6b656;html=1;" vertex="1" parent="vpc">
  <mxGeometry x="20" y="36" width="320" height="300" as="geometry"/>
</mxCell>
<mxCell id="web1" value="web-1" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="az1">
  <mxGeometry x="30" y="40" width="120" height="60" as="geometry"/>
</mxCell>
<mxCell id="db1" value="db-1" style="shape=cylinder3;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="az1">
  <mxGeometry x="180" y="40" width="100" height="70" as="geometry"/>
</mxCell>
<mxCell id="az2" value="AZ us-east-1b" style="swimlane;rounded=1;shadow=1;strokeWidth=2;startSize=24;fillColor=#fff2cc;strokeColor=#d6b656;html=1;" vertex="1" parent="vpc">
  <mxGeometry x="360" y="36" width="340" height="300" as="geometry"/>
</mxCell>
<mxCell id="web2" value="web-2" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="az2">
  <mxGeometry x="30" y="40" width="120" height="60" as="geometry"/>
</mxCell>
<mxCell id="e1" edge="1" parent="1" source="web1" target="web2" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

### Cross-functional flowcharts (actor × phase grid, as a table)

Cross-functional flowcharts show a process across **two axes at once** — actors (rows) and phases (columns). Use drawio's `table` shape, which auto-arranges cells into a grid via `childLayout=tableLayout`. This is the canonical draw.io pattern and is distinct from plain swimlanes (which only group on one axis).

**Structure:**

- Outer container: `shape=table;childLayout=tableLayout;startSize=0;collapsible=0;fillColor=none;`
- Rows are children of the table: `shape=tableRow;horizontal=0;startSize=0;collapsible=0;`
- Cells are children of rows — regular vertices, one per (actor, phase) intersection
- Row heights and cell widths are set via `mxGeometry`; they tile automatically
- First row = phase headers; first cell of every other row = actor label
- Process nodes go INSIDE the appropriate cell (parent = cell id) at coordinates relative to the cell
- Cross-cell edges must use `parent="1"` (same rule as containers)

```xml
<mxCell id="tbl" style="shape=table;childLayout=tableLayout;startSize=0;collapsible=0;fillColor=none;" vertex="1" parent="1">
  <mxGeometry x="0" y="0" width="900" height="320" as="geometry"/>
</mxCell>
<mxCell id="r0" style="shape=tableRow;horizontal=0;startSize=0;collapsible=0;" vertex="1" parent="tbl">
  <mxGeometry width="900" height="40" as="geometry"/>
</mxCell>
<mxCell id="h0" style="text;html=1;" vertex="1" parent="r0">
  <mxGeometry width="140" height="40" as="geometry"/>
</mxCell>
<mxCell id="h1" value="Order" style="text;align=center;fontStyle=1;fillColor=#e8e8e8;" vertex="1" parent="r0">
  <mxGeometry x="140" width="380" height="40" as="geometry"/>
</mxCell>
<mxCell id="h2" value="Fulfill" style="text;align=center;fontStyle=1;fillColor=#e8e8e8;" vertex="1" parent="r0">
  <mxGeometry x="520" width="380" height="40" as="geometry"/>
</mxCell>
<mxCell id="r1" style="shape=tableRow;horizontal=0;startSize=0;collapsible=0;" vertex="1" parent="tbl">
  <mxGeometry y="40" width="900" height="140" as="geometry"/>
</mxCell>
<mxCell id="a1" value="Customer" style="rounded=1;shadow=1;strokeWidth=2;fillColor=#dae8fc;fontStyle=1;" vertex="1" parent="r1">
  <mxGeometry width="140" height="140" as="geometry"/>
</mxCell>
<mxCell id="c_cust_order" style="fillColor=none;" vertex="1" parent="r1">
  <mxGeometry x="140" width="380" height="140" as="geometry"/>
</mxCell>
<mxCell id="t_place" value="Place Order" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="c_cust_order">
  <mxGeometry x="120" y="40" width="140" height="60" as="geometry"/>
</mxCell>
<mxCell id="c_cust_fulfill" style="fillColor=none;" vertex="1" parent="r1">
  <mxGeometry x="520" width="380" height="140" as="geometry"/>
</mxCell>
<mxCell id="r2" style="shape=tableRow;horizontal=0;startSize=0;collapsible=0;" vertex="1" parent="tbl">
  <mxGeometry y="180" width="900" height="140" as="geometry"/>
</mxCell>
<mxCell id="a2" value="System" style="rounded=1;shadow=1;strokeWidth=2;fillColor=#d5e8d4;fontStyle=1;" vertex="1" parent="r2">
  <mxGeometry width="140" height="140" as="geometry"/>
</mxCell>
<mxCell id="c_sys_order" style="fillColor=none;" vertex="1" parent="r2">
  <mxGeometry x="140" width="380" height="140" as="geometry"/>
</mxCell>
<mxCell id="t_validate" value="Validate" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="c_sys_order">
  <mxGeometry x="120" y="40" width="140" height="60" as="geometry"/>
</mxCell>
<mxCell id="c_sys_fulfill" style="fillColor=none;" vertex="1" parent="r2">
  <mxGeometry x="520" width="380" height="140" as="geometry"/>
</mxCell>
<mxCell id="t_ship" value="Ship" style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="c_sys_fulfill">
  <mxGeometry x="120" y="40" width="140" height="60" as="geometry"/>
</mxCell>
<mxCell id="e1" edge="1" parent="1" source="t_place" target="t_validate" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
<mxCell id="e2" edge="1" parent="1" source="t_validate" target="t_ship" style="edgeStyle=orthogonalEdgeStyle;rounded=1;shadow=1;strokeWidth=2;html=1;">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

**When to use cross-functional tables vs flat swimlanes:**

- Flat swimlanes — one-dimensional (actors only, or phases only). Simpler. Use this when you just need to show who does what in sequence.
- Cross-functional table — two-dimensional (actors AND phases). Use this when **both** the actor and the process stage matter, and every step belongs to a specific (actor, phase) cell.

**Do NOT** nest swimlanes inside a table row, do NOT set `startSize` on rows or cells (columns tile from `x=0`), and do NOT rely on the AI to produce exact widths that sum to the table width — close-enough totals are fine, the `tableLayout` normalizes them.

## Layers

Layers control visibility and z-order. Every cell belongs to exactly one layer. Use layers to manage diagram complexity — viewers can toggle layer visibility to show or hide groups of elements (e.g., "Physical Infrastructure" vs "Logical Network" vs "Security Zones").

Cell `id="0"` is the root and cell `id="1"` is the default layer — both always exist. Additional layers are `mxCell` elements with `parent="0"`:

```xml
<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="2" value="Annotations" parent="0"/>
    <mxCell id="10" value="Server" style="rounded=1;shadow=1;strokeWidth=2;html=1;" vertex="1" parent="1">
      <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="20" value="Note: deprecated" style="text;" vertex="1" parent="2">
      <mxGeometry x="100" y="170" width="120" height="30" as="geometry"/>
    </mxCell>
  </root>
</mxGraphModel>
```

- A layer is an `mxCell` with `parent="0"` and no `vertex` or `edge` attribute
- Assign shapes to a layer by setting `parent` to the layer's id
- Later layers render on top of earlier layers (higher z-order)
- Add `visible="0"` as an attribute on the layer cell to hide it by default
- Use layers when the diagram has distinct conceptual groupings that viewers may want to toggle independently

## Tags

Tags are visual filters that let viewers show or hide elements by category. Unlike layers, a single element can have multiple tags, making tags ideal for cross-cutting concerns (e.g., tagging shapes as "critical", "v2", or "backend").

Tags require wrapping `mxCell` in an `<object>` element. Tags are assigned via the `tags` attribute as a space-separated string:

```xml
<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <object id="2" label="Auth Service" tags="critical v2">
      <mxCell style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
        <mxGeometry x="100" y="100" width="120" height="60" as="geometry"/>
      </mxCell>
    </object>
    <object id="3" label="Legacy API" tags="critical deprecated">
      <mxCell style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
        <mxGeometry x="300" y="100" width="120" height="60" as="geometry"/>
      </mxCell>
    </object>
  </root>
</mxGraphModel>
```

- Tags require the `<object>` wrapper — a plain `mxCell` cannot have tags
- The `label` attribute on `<object>` replaces `value` on `mxCell`
- Tags are space-separated in the `tags` attribute
- Viewers filter the diagram by selecting tags in the draw.io UI (Edit > Tags)
- Tags do not affect z-order or structural grouping — they are purely a visibility filter

## Metadata and placeholders

Metadata stores custom key-value properties on shapes as additional attributes on the `<object>` wrapper element. Combined with placeholders, metadata values can be displayed in labels — useful for data-driven diagrams showing status, owner, IP addresses, or versions on each shape.

Set `placeholders="1"` on the `<object>` to enable `%propertyName%` substitution in the `label`:

```xml
<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <object id="2" label="<b>%component%</b><br>Owner: %owner%<br>Status: %status%"
            placeholders="1" component="Auth Service" owner="Team Backend" status="Active">
      <mxCell style="rounded=1;shadow=1;strokeWidth=2;whiteSpace=wrap;html=1;" vertex="1" parent="1">
        <mxGeometry x="100" y="100" width="160" height="80" as="geometry"/>
      </mxCell>
    </object>
  </root>
</mxGraphModel>
```

- Custom properties are plain XML attributes on `<object>` (e.g., `component="Auth Service"`)
- Set `placeholders="1"` to enable `%key%` substitution in the label and tooltip
- The label must use `html=1` style when using HTML formatting with placeholders
- Placeholders resolve by walking up the containment hierarchy: shape attributes first, then parent container, then layer, then root — first match wins
- Predefined placeholders work without custom properties: `%id%`, `%width%`, `%height%`, `%date%`, `%time%`, `%timestamp%`, `%page%`, `%pagenumber%`, `%pagecount%`, `%filename%`
- Use `%%` for a literal percent sign in labels
- Tags, metadata, and placeholders can all be combined on the same `<object>` element
- Use metadata when shapes represent data records (servers, services, components) and you want to attach structured information beyond the visible label

## Dark mode colors

Diagrams may be viewed in dark mode. Prefer `adaptiveColors="auto"` and let draw.io invert explicit colours automatically; when you set explicit light colours, choose ones that stay legible after inversion, or use `light-dark(light,dark)` to control both themes so contrast stays high in either mode.

draw.io supports automatic dark mode rendering. How colors behave depends on the property:

- **`strokeColor`, `fillColor`, `fontColor`** default to `"default"`, which renders as black in light theme and white in dark theme. When no explicit color is set, colors adapt automatically.
- **Explicit colors** (e.g. `fillColor=#DAE8FC`) specify the light-mode color. The dark-mode color is computed automatically by inverting the RGB values (blending toward the inverse at 93%) and rotating the hue by 180° (via `mxUtils.getInverseColor`).
- **`light-dark()` function** — To specify both colors explicitly, use `light-dark(lightColor,darkColor)` in the style string, e.g. `fontColor=light-dark(#7EA6E0,#FF0000)`. The first argument is used in light mode, the second in dark mode.

To enable dark mode color adaptation, the `mxGraphModel` element must include `adaptiveColors="auto"`.

When generating diagrams, you generally do not need to specify dark-mode colors — the automatic inversion handles most cases. Use `light-dark()` only when the automatic inverse color is unsatisfactory.

## Automatic edge routing

Every XML diagram rendered in the viewer automatically runs an ELK (Eclipse Layout Kernel) edge-routing pass **after** the initial render:

1. Vertex positions are pinned (the AI's placement is respected — no vertex moves).
2. ELK recomputes bend points + connection points for every edge (orthogonal routing).
3. A metric (edge-vertex intersections) compares before vs. after. If ELK made collisions worse, the edge routing is reverted to your original.
4. The exported XML (copy/clipboard, "Open in draw.io") reflects whatever is finally shown — so downstream consumers also get the cleaned-up edges.

You do not need to request this. Place vertices where they belong and write edges naively — the viewer handles connector cleanup.

This also means: there is no server-side post-processing pass. What you generate is what the viewer starts with; the ELK pass is the only correction.

## Post-layout (optional, overrides vertex positions)

For cases where you want a **full** re-layout — moving vertices to canonical positions — set the optional `postLayout` parameter on `create_diagram`. Vertices animate (morph) from their original positions to the algorithm's layout.

| Value              | ELK algorithm       | Best for                                                 |
| ------------------ | ------------------- | -------------------------------------------------------- |
| `verticalFlow`   | `layered` (DOWN)  | Flowcharts, process diagrams                             |
| `horizontalFlow` | `layered` (RIGHT) | Pipelines, swim lanes                                    |
| `tree`           | `mrtree`          | Org charts, decision trees, hierarchies                  |
| `force`          | `force`           | Networks without clear hierarchy                         |
| `stress`         | `stress`          | Small-to-mid general graphs (usually tighter than force) |
| `radial`         | `radial`          | Concentric layers around a root                          |

**For XML diagrams: usually omit `postLayout`.** You authored the coordinates yourself, so the layout is already deliberate — the automatic edge-routing pass handles the rest. Set `postLayout` only when the user explicitly wants a canonical layout, or when you know vertex placement is significantly off.

**For Mermaid diagrams: see the `postLayout` parameter description for when to set it.** Complex Mermaid flowcharts (≥ ~20 nodes, ≥ 3 decision diamonds, feedback edges, or ≥ 3 endpoints) need `postLayout: "verticalFlow"` (for `flowchart TD/TB`) or `"horizontalFlow"` (for `flowchart LR/RL`) — along with `startNodeIds` and `endNodeIds` — because the native parser's layout goes cramped or unbalanced past that threshold. Simple flowcharts and all non-flowchart Mermaid types (sequence, class, ER, sankey, …) need no `postLayout`.

**When NOT to use (XML):**

- The user has asked for specific positions (swim lanes with exact lanes, architecture diagrams with meaningful spatial arrangement).
- The diagram relies on containers/grouping where spatial layout encodes information.

## Style reference

Complete style reference (all shape types, style properties, color palettes, HTML labels, and more): reference.md

XML Schema (XSD): https://github.com/jgraph/drawio-mcp/blob/main/shared/mxfile.xsd

## CRITICAL: XML well-formedness

When generating draw.io XML, the output **must** be well-formed XML:

- **NEVER include ANY XML comments (`<!-- -->`) in the output.** XML comments are strictly forbidden — they waste tokens, can cause parse errors, and serve no purpose in diagram XML.
- Escape special characters in attribute values: `&amp;`, `&lt;`, `&gt;`, `&quot;`
- Always use unique `id` values for each `mxCell`

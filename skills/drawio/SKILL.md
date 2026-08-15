---
name: drawio
model: sonnet
description: Create any diagram — flowchart, architecture, ER, sequence, class, network, mockup, wireframe, UI sketch — or when the user mentions draw.io, drawio, drawoi, .drawio, or export to PNG/SVG/PDF
disable-model-invocation: true
---
# Draw.io Diagram Skill

Generate draw.io diagrams as native `.drawio` files. Optionally export to PNG, SVG, or PDF with the diagram XML embedded (so the exported file remains editable in draw.io).

## Diagramming a codebase

When the diagram describes real code — architecture, ER, class, sequence, call-flow, dependency, or module diagrams of the current repo — **ground it in the actual code first. Do not guess structure from memory.**

1. **If `graphify-out/` exists**, treat the request as a graphify query first. `graphify` is hidden from the catalogue, so the `Skill` tool cannot reach it — `bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode graphify` answers `MODE=inline`, so read the body it names and run the queries from here, pulling god nodes, communities, file relationships, and paths. Use its output as the source of truth for nodes and edges.
2. **Otherwise, ground it with `use-repo-code`** — grep the repomix snapshot for the components, callers, symbols, and relationships the diagram needs, instead of reading files one by one or assuming layout. It is hidden from the catalogue, so resolve it rather than reaching for the `Skill` tool:

   ```bash
   bash "${CREWFORGE5_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code
   ```

   It answers `MODE=agent` — spawn it through the `Agent` tool with the type its frontmatter names, and take back only the nodes and edges. Reading its body inline would drag the whole pack in behind it.
3. Build the draw.io XML from what those return. Every box and arrow should trace to a real file/symbol/edge, not an assumption.

For diagrams unrelated to the current codebase (generic flowcharts, mockups, wireframes, conceptual diagrams), skip this — go straight to generation below.

## Intake gate — ask before generating

If the diagram type or export format isn't stated in the request, call **AskUserQuestion** before building the XML. Ask only the open questions.

- **Type** — What kind of diagram? Options: `Flowchart` / `Architecture` / `ER / class` / `Sequence`. Skip if the request already names one.
- **Export** — What output do you want? Options: `.drawio only (Recommended)` / `+ PNG` / `+ SVG` / `+ PDF`.

Use the export answer to drive the "Choosing the output format" step below.

## House rules — apply to every diagram, always

These four rules are not optional and are not overridden by any template, example, or shape-library default elsewhere in this skill. If a copied style string contradicts them, edit the string.

### 1. Edge clearance — no edge crosses a node

No edge may pass over, under, or through any node. The single exception: an edge connecting to a node **inside** a container may cross that container's own boundary (a parent it is entering or leaving). Crossing any *other* node, including any other container, is a defect.

Enforce in this order — placement, then connection-point sides, then waypoints (full procedure in the Edges section of reference.md). Edge-over-edge crossings are acceptable; edge-over-node is not.

### 2. Spacing — every connection and every character readable

Leave enough empty space that no edge label overlaps a node, another edge, or another label, and all node text fits inside its node. When a gap must carry a labeled edge or several edges, widen it — skip a grid lane rather than tighten. Whitespace is free; an unreadable diagram is worthless.

### 3. Visual style — rounded, shadowed, 2px, on everything

Every vertex and every edge carries all three:

```
rounded=1;shadow=1;strokeWidth=2;
```

Also set `shadow="1"` on the `mxGraphModel` element for the page-level shadow. Shapes whose geometry has no corners to round (ellipses, cylinders, platform icons) still take `shadow=1;strokeWidth=2;`.

### 4. Platform icons — use the real icon set

When a diagram names a platform or product with a shipped draw.io icon library — AWS, Azure, GCP, Kubernetes, Cisco, and others — use that library's shapes, not labeled rectangles. Verified style strings for AWS / Azure / GCP are in the "Platform icon sets" section of reference.md. Platform icons keep their library fill/stroke colours; add `shadow=1;strokeWidth=2;` and leave the rest alone. Fall back to a generic shape only when no icon exists for that component.

## How to create a diagram

1. **Generate draw.io XML** in mxGraphModel format for the requested diagram, obeying the House rules below
2. **Write the XML** to a `.drawio` file in the current working directory using the Write tool
3. **If the user requested an export format** (png, svg, pdf), locate the draw.io CLI (see below), export with `--embed-diagram`, then delete the source `.drawio` file **only after confirming the export file was actually created**. If the CLI is not found **or the export produces no output file** (e.g. headless session — see the GUI-session caveat below), keep the `.drawio` file and tell the user they can install/open the draw.io desktop app to export, or open the `.drawio` file directly
4. **Open the result** — the exported file if exported, or the `.drawio` file otherwise. If the open command fails, print the file path so the user can open it manually

## Choosing the output format

Check the user's request for a format preference. Examples:

- `/drawio create a flowchart` → `flowchart.drawio`
- `/drawio png flowchart for login` → `login-flow.drawio.png`
- `/drawio svg: ER diagram` → `er-diagram.drawio.svg`
- `/drawio pdf architecture overview` → `architecture-overview.drawio.pdf`

If no format is mentioned, just write the `.drawio` file and open it in draw.io. The user can always ask to export later.

### Supported export formats

| Format  | Embed XML    | Notes                                    |
| ------- | ------------ | ---------------------------------------- |
| `png` | Yes (`-e`) | Viewable everywhere, editable in draw.io |
| `svg` | Yes (`-e`) | Scalable, editable in draw.io            |
| `pdf` | Yes (`-e`) | Printable, editable in draw.io           |
| `jpg` | No           | Lossy, no embedded XML support           |

PNG, SVG, and PDF all support `--embed-diagram` — the exported file contains the full diagram XML, so opening it in draw.io recovers the editable diagram.

## draw.io CLI

The draw.io desktop app includes a command-line interface for exporting.

### Locating the CLI

First, detect the environment, then locate the CLI accordingly:

#### macOS

```bash
/Applications/draw.io.app/Contents/MacOS/draw.io
```

#### Linux

```bash
drawio            # PATH install; or /opt/drawio/drawio, or the AppImage path
```

#### Windows

```bash
"C:\Program Files\draw.io\draw.io.exe"
```

### Exporting

Run the located binary in export mode:

```bash
<drawio-binary> -x -f <format> --embed-diagram -o <output-path> <input.drawio>
```

- `-x` / `--export` — export mode
- `-f` / `--format` — `png`, `svg`, or `pdf` (the embed-capable formats; `jpg` cannot embed XML)
- `--embed-diagram` — embed the source XML so the export stays editable in draw.io
- `-o` / `--output` — output file path
- final positional arg — the input `.drawio` file

Examples:

```bash
"/Applications/draw.io.app/Contents/MacOS/draw.io" -x -f png --embed-diagram -o login-flow.drawio.png login-flow.drawio
"/Applications/draw.io.app/Contents/MacOS/draw.io" -x -f svg --embed-diagram -o er-diagram.drawio.svg er-diagram.drawio
"/Applications/draw.io.app/Contents/MacOS/draw.io" -x -f pdf --embed-diagram -o architecture.drawio.pdf architecture.drawio
```

The CLI is an Electron desktop app — export must run in the user's GUI session. A headless or SSH shell cannot render and the command will hang or produce nothing. If export yields no output file, fall back: keep the `.drawio` file and tell the user to open it in the draw.io desktop app.

### Opening the result

After writing (or exporting), open the file for the user with the platform's open command:

- macOS: `open -a "draw.io" <file>` (opens in the draw.io desktop app explicitly; the app name is `draw.io` with the dot — `drawio` will not resolve). If that fails, retry with bare `open <file>` to use the default associated app.
- Linux: `xdg-open <file>`
- Windows: `start "" <file>`

If the open command fails (headless, no GUI), print the absolute file path so the user can open it manually.

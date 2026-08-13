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

1. **If `graphify-out/` exists**, treat the request as a graphify query first — invoke the `/graphify` skill (`skill: "graphify"`) to pull god nodes, communities, file relationships, and paths. Use its output as the source of truth for nodes and edges.
2. **Otherwise, ground it with `use-repo-code`** — grep the repomix snapshot for the components, callers, symbols, and relationships the diagram needs, instead of reading files one by one or assuming layout. It is hidden from the catalogue, so resolve it rather than reaching for the `Skill` tool:

   ```bash
   bash "${CREWFORGE_ROOT}/scripts/flow/subskill_resolve.sh" --load-mode use-repo-code
   ```

   It answers `MODE=agent` — spawn it through the `Agent` tool with the type its frontmatter names, and take back only the nodes and edges. Reading its body inline would drag the whole pack in behind it.
3. Build the draw.io XML from what those return. Every box and arrow should trace to a real file/symbol/edge, not an assumption.

For diagrams unrelated to the current codebase (generic flowcharts, mockups, wireframes, conceptual diagrams), skip this — go straight to generation below.

## Intake gate — ask before generating

If the diagram type or export format isn't stated in the request, call **AskUserQuestion** before building the XML. Ask only the open questions.

- **Type** — What kind of diagram? Options: `Flowchart` / `Architecture` / `ER / class` / `Sequence`. Skip if the request already names one.
- **Export** — What output do you want? Options: `.drawio only (Recommended)` / `+ PNG` / `+ SVG` / `+ PDF`.

Use the export answer to drive the "Choosing the output format" step below.

## How to create a diagram

1. **Generate draw.io XML** in mxGraphModel format for the requested diagram. **Edge-clearance rule (always): no edge may ever pass over a node.** Every edge must take a logical, easy-to-read path from its source node to its target. Achieve this first through placement — position nodes on the grid so each edge has a clear channel — and, where an edge would otherwise cross an intermediate node, route it around via connection-point sides or waypoints (see the Edges section of reference.md). **Spacing rule (always): leave enough space that every connection and every piece of text is clearly readable.** No edge label may overlap a node, another edge, or another label; node text must fit inside its node. If a channel must carry edges with labels, widen the gap between nodes — whitespace is free, an unreadable diagram is worthless
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

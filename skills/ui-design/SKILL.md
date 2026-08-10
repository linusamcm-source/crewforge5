---
name: ui-design
model: opus
description: Design methodology — 7-dimension scoring, briefs, refinement. Use on "audit the UI", "design critique", "score the interface", "UI polish pass", "design review"
---

# UI Design — Methodology for Sophisticated Interfaces

A structured design methodology for evaluating, critiquing, and improving application
interfaces. Works for information-dense developer tools, consumer mobile apps, web
dashboards, and marketing pages alike. The methodology stays constant; the project's
design system (tokens, type scale, accent palette) is the variable.

## When to use

Design audits, visual critique, component design briefs, aesthetic refinement, and
systematic UI improvement — also trigger on "design brief for X", "improve the
aesthetics", "make it look better", "visual hierarchy check". This skill provides the
methodology — pair it with a UI-focused agent (e.g. `frontend-design`, `rn-ui-designer`,
or `ui-architect`) for the taste decisions.

---

## Quick Reference: When to Use What

| Task | Workflow |
|------|----------|
| "This view looks off" | → **Critique** (score 7 dimensions, produce fix list) |
| "Design a new panel" | → **Design Brief** (intent → composition → specs) |
| "Full UI polish pass" | → **Audit** (inventory → score → remediate) |
| "Is this component good?" | → **Component Review** (focused 7-dimension score) |
| "Make it more sophisticated" | → **Refinement** (identify generic, make distinctive) |

> Component Review (Workflow 4) is Critique scoped to a single component. Use Critique
> for full views, Component Review for individual components.

---

## Workflow 1: Design Critique

Score the target view/component across 7 dimensions, 0-10 each.

### Step 1 — Read Before Judging

Read ALL files involved in the target view:

1. The view file itself
2. Every component it imports
3. The project's global stylesheet / theme tokens
4. The project's design system file (`DESIGN.md`, `design-system.md`, Figma export, etc.)

**Do not critique from memory.** Read the actual values, not what you remember from a similar project.

### Step 2 — Score 7 Dimensions

| # | Dimension | What It Measures |
|---|-----------|-----------------|
| 1 | **Visual Hierarchy** | Does the eye land on the right thing first? Clear primary → secondary → tertiary? |
| 2 | **Spatial Composition** | Consistent rhythm, clean alignment, negative space creating structure? |
| 3 | **Typographic Quality** | Type scale hierarchy, explicit line-heights, correct mono/proportional usage? |
| 4 | **Color & Contrast** | Accent discipline, luminance depth, semantic consistency, WCAG AA? |
| 5 | **Motion & Interaction** | State transitions, hover/focus quality, consistent timing, signature moment? |
| 6 | **Information Density** | Efficient pixel usage, scannable layout, appropriate grouping? |
| 7 | **Identity & Distinction** | Recognizable as *this product*? Avoids generic AI slop? |

### Step 3 — Produce Fix List

For every dimension below 8/10:

```
[DIM-N] dimension_name: current_score/10 → target_score/10
  Problem: specific description of what's wrong
  Fix: file:line — exact change (old value → new value)
  Impact: which other dimensions this fix also improves
```

Priority: hierarchy > density > typography > color > composition > motion > identity.
Hierarchy and density affect usability most; identity is layered on last.

> **Critical-score override**: when a dimension scores below 5, fix it first regardless of priority order.

### Step 4 — Implement (if requested)

Work fixes in priority order. After each file:
- Verify the build/typecheck/lint
- Re-score the changed dimension to confirm improvement

---

## Workflow 2: Design Brief

If designing a new view/component before implementation: load [references/design-brief.md](references/design-brief.md) (intent → composition → typography → color → interaction → motion → signature elements).

---

## Workflow 3: Design Audit (Full App)

For a comprehensive evaluation of the entire application.

### Phase 1 — Inventory

1. Read the project's design system file and global stylesheet
2. List every view from the project's view directory
3. List every component
4. Note: purpose, approximate complexity, last modified

### Phase 2 — Systematic Scoring

Score each major view across all 7 dimensions:

```markdown
## View: <name>
| Dimension          | Score | Notes |
|--------------------|-------|-------|
| Visual Hierarchy   | 7/10  | ... |
| Spatial Composition| 6/10  | ... |
| Typographic Quality| 8/10  | ... |
| Color & Contrast   | 7/10  | ... |
| Motion & Interaction| 5/10 | ... |
| Information Density| 8/10  | ... |
| Identity           | 6/10  | ... |
| **Overall**        | **6.7** | |
```

### Phase 3 — Cross-Cutting Analysis

After scoring all views, identify:

1. **Weakest dimensions across the app** (e.g., motion is consistently low)
2. **Consistency gaps** (e.g., spacing varies between views)
3. **Token violations** (hardcoded values that should use design tokens)
4. **Identity opportunities** (where can we inject more personality?)

### Phase 4 — Remediation Plan

```markdown
### Priority 1: Critical (score < 5)
- [FIX-01] file:NN — description — improves dimension X from N to N

### Priority 2: High (score 5-7)
- [FIX-02] ...

### Priority 3: Polish (score 7-8)
- [FIX-03] ...
```

### Phase 5 — Implementation

Execute fixes in priority order. Build, re-score, move on.

---

## Workflow 4: Component Review

For evaluating a single component in isolation.

1. Read the component file
2. Read its parent view to understand context
3. Score across the 7 dimensions (adapted for component scope)
4. Token compliance: grep for hardcoded hex/px/font values
5. Interaction states: hover, focus-visible, active, disabled
6. Responsiveness: handles varying widths/content lengths?
7. Produce a fix list if any dimension scores below 8

---

## Workflow 5: Refinement (Generic → Distinctive)

If something "works but looks generic": load [references/refinement.md](references/refinement.md) (identify the generic → inject personality → verify still functional).

---

## Design System (Source of Truth)

Always read these files before any design work:

- `DESIGN.md` (or equivalent — `design-system.md`, `design-tokens.md`, etc.)
- The project's global stylesheet / theme module (CSS custom properties, Tailwind config, RN theme constants, etc.)

If the design system file doesn't exist, treat the implemented stylesheet as the
sole source of truth and surface the gap. If they disagree, the implemented
stylesheet is the runtime truth — flag the discrepancy for the user to resolve.

---

## Reference Documents

`references/design-brief.md` — Workflow 2 detail (intent → composition → specs)
`references/refinement.md` — Workflow 5 detail (generic → distinctive)

---

## Integration with Other Skills/Agents

| Tool | When |
|------|------|
| `frontend-design` agent / skill | Web component implementation, CSS debugging, animation coding |
| `rn-ui-designer` agent | React Native screens — motion, cross-platform precision |
| `ui-architect` agent | High-level direction, taste decisions, system-level design |
| `/simplify` skill | After any code changes, review for quality |
| `/ui-autopilot` skill | Bounded visual targets — autonomous parallel variants |
| `/ui-polish-loop` skill | Interactive single-screen polish in the simulator |

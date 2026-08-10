# Design Brief Workflow

## Workflow 2: Design Brief

For designing a new view/component before implementation.

### Section 1 — Intent

- **Problem**: what does the user need to accomplish?
- **Emotion**: what should it feel like? (focused, calm, urgent, analytical)
- **Primary action**: the ONE thing the user does most → maximum visual weight
- **Entry point**: how does the user arrive? (navigation, shortcut, notification)
- **Exit point**: where do they go after? (back, next step, dismiss)

### Section 2 — Composition

Specify the layout model:

```
┌─────────────────────────────────────────┐
│ [Header: title + actions]       48px    │
├──────────┬──────────────────────────────┤
│ Sidebar  │ Main Content                 │
│ 240px    │ fluid                        │
│ fixed    │                              │
├──────────┴──────────────────────────────┤
│ [Footer/Status bar]            32px     │
└─────────────────────────────────────────┘
```

Include:
- Column widths (fixed vs fluid)
- Row heights (fixed headers/footers, scrollable content)
- Overflow behavior (which regions scroll independently?)
- Minimum viewport / window size

### Section 3 — Typography Plan

Map content types to the project's type scale. Pick from the project's tokens — don't invent. Example shape:

```
Page title:     <font> 20px/600
Section head:   <font> 16px/600
Body text:      <font> 13px/400
Data values:    <mono> 14px/500
Labels:         <font> 11px/500 uppercase tracking +0.05em
```

### Section 4 — Color Strategy

For this view:
- Primary surface (which background layer?)
- Accent usage (where, why)
- Text contrast (primary / dim / muted mapping)
- Status mapping (how the view's states map to semantic colors)

### Section 5 — Interaction Model

- **Keyboard navigation**: Tab order, arrow keys, Enter, Escape
- **Hover states**: what changes on hover?
- **Focus indicators**: focus-visible style
- **State machine**: idle → loading → content → empty → error
- **Shortcuts**: any view-specific shortcuts

### Section 6 — Motion Choreography

- **Mount sequence**: what appears first? Stagger between siblings?
- **Transitions**: fade, slide, scale?
- **Micro-interactions**: hover, press, toggle
- **Exit**: how does it dismiss?

Pick durations from the project's motion tokens, typically: 50ms (micro), 100ms (short), 150ms (medium).

### Section 7 — Signature Elements

What makes this unmistakably *this product*? Inject project-specific personality:
visual language, accent pattern, density, signature components. The product's
`DESIGN.md` should define these — if absent, surface the gap and propose them.

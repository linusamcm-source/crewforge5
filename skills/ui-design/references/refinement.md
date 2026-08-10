# Refinement Workflow

## Workflow 5: Refinement (Generic → Distinctive)

When something "works but looks generic":

### Step 1 — Identify the Generic

List everything that could be in *any* app of this kind:

- Standard cards with equal border-radius
- Uniform padding with no spatial variation
- Buttons that look like a CSS framework default
- No typographic variation (everything same size/weight)
- No signature color usage (accent everywhere or nowhere)
- Symmetric, centered layouts with no visual tension

### Step 2 — Inject Personality

For each generic element, apply the project's design language. Pull from the project's
`DESIGN.md` if it exists; if not, ask what aesthetic direction this product wants and
propose options. Common moves:

- Replace uniform cards with varied treatments (some with left accent stripes, some borderless, some with luminance variation)
- Create typographic tension — one heading dramatically larger, uppercase labels, mix mono and proportional
- Use the accent with confidence — primary action gets it, everything else doesn't
- Add data density where appropriate — sparklines, timestamps, counts
- Break symmetry intentionally — sidebar wider than expected, asymmetric padding

### Step 3 — Verify It's Still Functional

Personality must not compromise:
- Readability (WCAG AA contrast)
- Scannability (users find what they need in <2 seconds)
- Keyboard navigation (Tab order still logical)
- Information hierarchy (most important thing still most prominent)

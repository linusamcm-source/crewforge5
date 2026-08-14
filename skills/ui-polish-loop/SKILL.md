---
name: ui-polish-loop
model: sonnet
description: Interactive UI polish loop for a running app — iOS simulator (via mobile MCP) or web (via rustwright MCP). Screenshot, apply the user's tweak, refresh, re-screenshot, repeat until stop. Use when the user says "clean up this screen", "polish this", "fix the spacing", or "make this nicer".
---

# UI Polish Loop

A tight visual feedback loop for polishing a running UI — the iOS simulator or a web page.
The user describes visual cleanups; you screenshot, locate the source, edit, refresh, and
repeat. No formal debugging, no test runs — just vibes and pixels until the user is happy.

## When to use

Use whenever the user wants to clean up, polish, tweak, refine, or iterate on the visual
appearance of a screen or page in the running app. Beyond the phrases in the description,
also trigger on "clean up this page", "this looks ugly", "tighten this up", "iterate on the
UI", "adjust the layout", "the colors are off", or any request that implies visual refinement
against what's currently on the simulator or in the browser. Trigger even if the user doesn't
explicitly mention screenshots, the simulator, or the browser — if they're describing visual
tweaks to the running app, use this skill.

Each cycle: screenshot the current screen/page, accept a natural-language cleanup request
from the user, infer which screen it is from the image, locate the source, apply the edit,
refresh, re-screenshot, show it back, and wait for the next request. Loops until the user
says stop.

## Why this shape

Polish is iterative and subjective. The user knows what they want when they see it. Every
moment summarising or explaining slows the loop. So the rhythm is: one screenshot, one
request, one edit, one refresh, repeat. Keep tempo fast.

This skill is distinct from:

- **`ac-validate`** — acceptance-criteria / autonomous validation,
  not free-form interactive polish.

## Pick the target first

On invocation, determine what's running:

- **iOS simulator** — the app is a React Native / Expo project, or the user says "the app",
  "the simulator", "on device", or names a mobile screen/tab. Drive it with the **mobile
  MCP** (`mcp__mobile-mcp__*`).
- **Web** — the app runs in a browser, or the user gives a URL / says "the page", "the site".
  Drive it with the **rustwright browser MCP** (`mcp__rustwright__*`). If no URL is given,
  infer it (dev servers are usually `http://localhost:<port>` — check running processes or
  the project's dev-server config) or ask once.

If it's genuinely ambiguous, ask once — then commit to that target for the session.

## The loop

```
[screenshot] → [user request(s)] → [infer screen] → [locate source] → [apply all edits] → [refresh + screenshot] → [show user] → ...
```

**On invocation, capture immediately.** Don't ask what to work on — capture whatever is on
screen, show it, and let the user describe what they want changed.

Every cycle:

1. **Capture** — target-specific:
   - *Simulator:* `mcp__mobile-mcp__mobile_take_screenshot`. If no device is booted, list
     devices with `mcp__mobile-mcp__mobile_list_available_devices` and launch the app with
     `mcp__mobile-mcp__mobile_launch_app` first. The image returns inline.
   - *Web:* `mcp__rustwright__browser_take_screenshot`. It saves a PNG and returns the file
     path — it does NOT return the image inline. Pass an explicit `path` in a project-local
     capture dir (`.tmp/ui-polish/` or the session scratchpad) with timestamped names like
     `2026-07-18T11-02-home.png`, then `Read` the path to see it and `SendUserFile` (display:
     render) to show the user.
2. **Present & listen** — show the image, wait for the request. The user may give one cleanup
   or several.
3. **Infer the screen/page** — read the image, match to a source file (see below).
4. **Locate the source** — find the markup/JSX and the styles.
5. **Apply all edits in the batch** — if the user asked for three changes, make all three
   before screenshotting. Don't screenshot between edits in the same request.
6. **Refresh** — take a single new screenshot after the whole batch lands:
   - *Simulator:* Expo Fast Refresh / Metro HMR updates within 1-2s. Screenshot immediately.
   - *Web:* HMR dev servers (Vite, webpack-dev-server, Next.js, SvelteKit) update themselves —
     `browser_wait_for` load state, then screenshot. Non-HMR setups (static files, server-
     rendered templates) need `mcp__rustwright__browser_reload` first; server-side changes
     without auto-reload need a dev-server restart before reloading.
7. **Show & loop** — present the new screenshot, wait for the next request.

**Exit** when the user says "stop", "done", "that's enough", "looks good", or equivalent.
When they do, ask once if they want you to run the project's validate / typecheck / lint
command to catch any issues the polish loop introduced.

## Navigation

Assume you're working on whatever's currently on screen. If mid-loop the user asks to move
elsewhere ("now fix the sessions tab", "open the settings page", "go back to the canvas"):

- *Simulator:* `mcp__mobile-mcp__mobile_click_on_screen_at_coordinates` or
  `mcp__mobile-mcp__mobile_list_elements_on_screen` to tap there.
- *Web:* `mcp__rustwright__browser_click` / `browser_type` / `browser_press_key` with refs
  from `mcp__rustwright__browser_snapshot`, or `browser_navigate` straight to the route.

Then take a fresh screenshot and continue. Navigation is a tool for the loop, not a
precondition.

## Inferring the screen/page from the image

The user explicitly wants you to read the image — lead with vision (layout, colour, spacing,
hierarchy). The element/accessibility tree is the backup, not the primary: it's noisy against
styled components; vision handles layout far better than a flat node list.

What to look for:

- **Visible text** — titles, button labels, section headers. Strongest signal. Grep the
  codebase for the exact string. If the project uses i18n (`react-i18next`, `i18next`,
  `expo-localization`), grep the locale files for the matching key first.
- **Route / navigation** —
  - *Simulator:* bottom tabs map to the project's convention. Expo Router: `app/(tabs)/<name>.tsx`.
    React Navigation: the tab navigator's screen options. A back arrow + content tells you the route.
  - *Web:* the current URL usually maps directly to a file — Next.js `app/`/`pages/`, SvelteKit
    `src/routes/`, file-based routers generally. Check the address via navigate/snapshot output.
- **Unique visual elements** — known custom components (canvas, map, chart, data grid) point
  at specific source dirs.
- **CSS class names / utility strings** (web) — Tailwind or BEM names greppable straight into
  the source.

If two screens look similar and you're not sure, **ask the user before editing**. Guessing
wrong costs a whole cycle.

## Finding the styling code

Check which idiom the project uses:

- *React Native:* `react-native-unistyles` (`createStyleSheet`, colocated), `StyleSheet.create`
  (colocated, sometimes a `.styles.ts` sibling), `tamagui`/`nativewind`/`restyle` (token-based,
  theme files), `styled-components` (colocated).
- *Web:* Tailwind / utility classes (edits in the markup; systemic values in `tailwind.config.*`
  or CSS `@theme`), CSS modules / plain CSS / SCSS (sibling `.module.css`; globals in
  `src/styles/`, `app/globals.css`), styled-components / emotion / vanilla-extract (colocated),
  component libraries (shadcn, MUI, DaisyUI — variant props first, then the theme/tokens file),
  server-rendered templates (Jinja, ERB, Blade — styles beside the template or a framework sheet).

Ask yourself: is the change local or systemic? Theme values (colours, spacing scale, font
sizes) usually live in a `constants/`, `theme/`, `tokens/`, or config directory. If the same
visual bug would appear on five other screens, update the theme value — don't patch one screen
and leave the rest broken.

## Editing rules

Respect project standards while making visual changes, but don't let them slow the loop:

- **No hardcoded user-facing text** if the project uses i18n. Add a key to the matching locale
  file and reference it via the project's `t(...)` helper. Mirror the key to other locales with
  the English value as a placeholder if needed — translation can be fixed later.
- **TypeScript strict mode** if enabled — no `any`, no `// @ts-ignore`.
- **Prefer the project's styling idiom** for new styles. Inline `style` is acceptable only for
  one-off dynamic values.
- **Honour design constraints from `DESIGN.md`/CLAUDE.md.** If the project forbids blur/glass
  effects, drop shadows, gradients, etc., do not introduce them in polish edits.
- **Don't break responsive layouts** (web). If the edit touches widths/flex/grid, sanity-check
  nothing overflows at the current viewport before presenting.
- **Do not run validate / `tsc` / `eslint` inside the loop.** It breaks tempo. Save it for the
  end, when the user exits.

## When a change doesn't land

Don't loop retrying blindly. Diagnose once, fix, continue. Likely causes, in order:

- The screen/route on screen isn't the file you edited — *simulator:* ask or use
  `mobile_list_elements_on_screen`; *web:* check the URL via `browser_snapshot`.
- A syntax / type / build error is blocking HMR — check the dev server output or the on-screen
  error overlay (red screen on RN; overlay in the browser — both are visible in a screenshot).
- You edited a source file that isn't the one rendering (duplicate component, wrong package in
  a monorepo) — grep again with a more specific string.
- Native-only changes (new modules, Metro config, asset additions) or static-site cache need a
  full reload / dev-server restart — rare for polish work.

## Comparing before and after

- *Simulator:* screenshots return inline and are transient. If the user asks "does this look
  different?" or you need to compare subtle changes, save the relevant pair to a project-local
  capture dir (`.captures/`, `.tmp/ui-polish/`) with timestamped names, and `Read` both back.
- *Web:* screenshots persist as files already — reuse that. Keep timestamped naming so pairs
  sort adjacently, `Read` both back to compare, and delete the capture dir when the loop exits
  unless the user wants the trail kept.

Otherwise, don't clutter the filesystem.

## Staying in the loop

Between iterations, don't summarise what you just did. The user can see the new screenshot —
that's the whole point. Just present the image and wait, or ask a single short question like
"anything else?" if they've gone quiet. When they say stop, wrap up by offering to run the
project's validate/lint command, then exit cleanly.

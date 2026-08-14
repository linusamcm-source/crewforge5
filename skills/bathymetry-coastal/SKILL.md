---
name: bathymetry-coastal
model: sonnet
description: Use when building React Native TypeScript components for bathymetric data display, coastal hazard mapping, depth contours, or surf zone rendering. Trigger on bathymetry, depth, sea floor, coastal erosion, storm surge, inundation mapping, reef structure, or harbour charts.
project: surf-seer, surfseer
---

# Bathymetry & Coastal Skill — React Native TypeScript

## When to use

Use this skill when building React Native TypeScript components for bathymetric data display, coastal hazard mapping, depth contours, surf zone rendering, morphodynamic change detection, or any spatial ocean-floor visualisation. Trigger when user mentions bathymetry, depth, sea floor, coastal erosion, storm surge, inundation mapping, reef structure, or harbour charts.

## Purpose

Build components that render seabed topography, coastal hazard zones, and nearshore spatial data on mobile devices. Handle the unique challenges of underwater terrain: sparse survey data, multiple vertical datums, and the need to convey depth intuitively to diverse audiences (scientists, mariners, surfers, coastal managers).

---

When you need the shared type contracts (grids, contours, hazard zones, surf breaks, profiles): load [references/types.md](references/types.md)

---

## Component Patterns

### Bathymetric Map Overlay

Render depth as a colour-fill overlay on a base map:

**Requirements:**
- Colour scale: deep blue → light blue → white → green → brown (standard hydrographic convention)
- Alternatively, use `cmocean.deep` for scientific audiences
- Depth labels at standard contours: 5m, 10m, 20m, 50m, 100m, 200m (shelf break), 500m, 1000m, 2000m
- Safety contours highlighted in bold (user-configurable threshold, e.g., 5m for vessel draft)
- Transparency control so underlying chart/satellite imagery is visible
- Show data source and datum clearly in legend
- Handle land/sea boundary carefully — use GSHHG or OpenStreetMap coastline as mask

**Performance:**
- Pre-render depth tiles at zoom levels for smooth pan/zoom
- Use WebGL (react-native-skia or Mapbox GL custom layer) for large grids
- Level-of-detail: coarse grid at wide zoom, full resolution when zoomed in

### Depth Profile Cross-Section

Interactive transect showing the seabed profile:

**Requirements:**
- X-axis: distance along transect (m or km)
- Y-axis: depth (m), inverted (0 at top, increasing downward)
- Show water surface line at current tide level
- Highlight depth zones: surf zone, inner shelf, outer shelf, slope, abyss
- Overlay wave ray paths if available (from SWAN refraction output)
- Mark reef crests, channels, bars, and other features
- Interactive: drag transect endpoints on map to update profile

### Storm Surge Inundation Map

Display modelled or historical inundation extents:

**Requirements:**
- Show inundation depth as graduated colour fill over land areas
- Animate temporal evolution (surge arrival → peak → recession) with time slider
- Overlay evacuation routes and critical infrastructure
- Display the combined water level: tide + surge + wave setup
- Mark the "bathtub" (static) vs dynamic (includes wave runup) inundation boundaries
- Include return period label prominently

### Surf Spot Detail View

For surf forecasting applications:

**Requirements:**
- Bathymetric map of the break area (50-500m scale)
- Annotated: reef/sandbar position, channel, takeoff zone, impact zone
- Overlay real-time or forecast wave direction arrows
- Show optimal swell window (direction/period) as a polar sector diagram
- Tide dependency indicator (bar chart showing quality vs tide height)
- Current hazard indicators: rip currents, rocks, urchins, marine life

---

For wave-physics utilities (breaking criterion, shoaling, group velocity, refraction, contour generation): load [references/wave-physics.md](references/wave-physics.md)

---

For vertical datum conversion detail and approximate offset constants: load [references/datums.md](references/datums.md)

---

## Validation & Testing

- **Sign convention**: Depths below datum are **negative** in raw data (GEBCO convention) but often displayed as **positive** numbers labelled "depth". Document which convention each type uses.
- **Land masking**: Grid cells above sea level (positive elevation) must be masked, not rendered as zero depth
- **Datum labelling**: Every depth display MUST show the vertical datum used
- **Resolution disclosure**: Show the source data resolution — don't imply sub-metre precision from a 15-arc-second grid
- **Contour sanity**: Contours should never cross each other and should form closed loops or terminate at domain boundaries

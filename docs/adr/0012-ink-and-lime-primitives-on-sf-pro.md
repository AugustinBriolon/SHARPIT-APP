# 0012. Ink & Lime primitives on SF Pro

Date: 2026-10-16

## Status

Accepted

## Context

The web repository replaced its brand with Ink & Lime (SHARPIT-WEBAPP ADR-085). The values reach this app through the generated `SharpitTokens.generated.swift`, but the app's own components were drawn for the old look:

- round tinted badges and uppercase eyebrow headers;
- a dot-grid canvas with halos, and specular card borders;
- a 180° tick dial;
- three bundled typefaces registered at launch.

The references also bring shapes the app did not have: a goal track with a "now" bubble, an inset group of white rows, numbered chips, check boxes and a dashed add button. ADR 0008 still holds: Apple's guidelines outrank the web where they conflict, so system lists, Dynamic Type and 44 pt targets stay.

## Decision

We will draw every shared surface with Ink & Lime primitives on SF Pro.

- **Type.** `SharpitTypography` keeps its style names but resolves them to SF Pro through `UIFontMetrics`, so Dynamic Type still scales. Figures use tabular digits at heavy weight. The bundled fonts, `SharpitFonts` and `scripts/fetch-brand-fonts.sh` are removed.
- **Geometry.** Radii, padding and sizes come from the exported geometry tokens (`SharpitTokens.cardRadius`, `cardPadding`, `controlHeight`, …) through `SharpitRadius` and `SharpitSpacing`.
- **Restyled in place, same API:**
  - `sharpitSurface`: card, inset group, chip, row, ink.
  - `SharpitCanvasBackground`: flat.
  - `SharpitCardHeader`: icon tile + title + subtitle.
  - `SharpitRowIcon`, `SharpitInlineTag`.
  - `SharpitPrimaryButton`: primary, accent and secondary styles, 52 pt.
  - `SharpitSegmentedControl`: ink selection on a chip track.
  - `SharpitTickGauge`: 270°, ink ticks, lime band and knob.
  - `SharpitScoreRing`: lime on track.
  - `SharpitStatTile`, `SharpitHeroScore`.
- **New, for shapes the references add:**
  - `SharpitIconTile`, `SharpitNumberChip`, `SharpitCheckBox`, `SharpitPill`.
  - `SharpitProgressBar`, `SharpitGoalTrack`, with `SharpitProgressMath`, which is tested.
  - `SharpitInsetGroup` / `SharpitInsetRow`, `SharpitHeroFigure`, `SharpitDashedAddButton`, `SharpitChartStyle`.
- **Sport tone.** `SharpitSportTone` is monochrome and theme-aware: foreground for lines, an ink or graphite tile with a lime glyph for marks.
- **Widgets** draw the card surface, with no texture or halo.
- **Reference.** A Debug-only gallery (`SharpitDesignGallery` default) rebuilds the seven reference cards from these components, so they can be compared in the simulator without an account.

## Options considered

### Option A — Keep the Syne / Plex / Mono faces with the new colours

- Pros: no typography churn.
- Cons: the references are set in a neutral grotesque with heavy figures; Syne headings would not read as the references. The fonts also cost bundle size and launch-time registration in both targets.

### Option B — Embed Inter to match the web exactly

- Pros: pixel parity with the web.
- Cons: adds a bundled family back, and loses SF Pro's optical sizes and native Dynamic Type behaviour (ADR 0008).

### Option C — SF Pro and restyle existing components in place (chosen)

- Pros: call sites keep compiling and take the new look automatically; no fonts to ship.
- Cons: the web and iOS faces differ slightly. Inter and SF Pro are close at these sizes.

## Consequences

### Positive

- About 2,000 colour and 1,300 typography call sites take the new look with no edits.
- Two font-loading code paths and nine font files are gone from the app and the widget extension.
- The new pure logic is covered by tests: the goal-track fraction (both directions, clamped), the dial's 270° geometry, and lit versus unlit ticks.

### Negative

- Feature screens that hand-roll layout (uppercase eyebrows, local paddings) still need a sweep onto the new primitives. Until then they mix old spacing with new colours.
- `sharpitCardSpecularBorder`, `SharpitCardHeader.tint` and `WidgetCanvas.stateTone` stay only as compatibility shims (marked `shortcut:`) until that sweep.

### Neutral

- `SharpitThemeTests` and the gauge tests in `TodayFoldTests` assert the new values.

## References

- SHARPIT-WEBAPP `docs/adr/ADR-085-ink-and-lime-brand-replaces-botanical-clinical.md`
- `docs/adr/0008-the-human-interface-guidelines-outrank-the-web-design-system.md`

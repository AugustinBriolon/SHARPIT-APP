# 2. Soft shadow elevation instead of hairline borders

Date: 2026-09-21

## Status

Superseded by [ADR-0008](0008-the-human-interface-guidelines-outrank-the-web-design-system.md)

## Context

The web design law (`../SHARPIT/design.md`, `DESIGN_LANGUAGE.md`) and SHARPIT ADR-041 ask
for flat surfaces with a 1px hairline border and elevation expressed through luminosity,
with no drop shadows. The native app followed it literally through `sharpitSurface(_:)`.

On iPhone this produced two problems reported by the product owner:

- Every journal row, plate and chip carried an outline. Stacked vertically on a phone, the
  outlines read as a form grid and felt heavy next to the system chrome, whose grouped
  surfaces lift rather than outline.
- In dark mode, sheets and the activity detail drawer fell back to the system background,
  which is pure black (`systemBackground` in `ActivityDetailView`, and no
  `presentationBackground` on any sheet). Next to the Forest Night canvas the black read as
  a hole in the page.

The web has no sheets, so it exports no token for a raised layer.

## Decision

The native app diverges from the web on elevation only:

- Content surfaces (`panel`, `chip`, `ink`) drop the hairline border. On light they are
  lifted by a soft, neutral, two-layer shadow (a tight contact shadow plus a wide ambient
  one, black at 4–8% opacity). `panelAlt` stays flat so a selected block reads as set into
  the page.
- On dark there are no shadows. Layers separate by luminosity, as the web already does.
- Every sheet goes through `.sharpitSheet()`, which sets a raised background and an
  elevation environment value. The raised tone is the canvas on light and the `card` token
  on dark — never system black. Surfaces inside a raised layer lift once more (on dark,
  `card` mixed with 6% of `foreground`). The activity detail drawer uses the same raised
  layer.
- Raised colors are derived from generated tokens in `SharpitElevation.swift`; the
  generated token file is not edited.

Colored glow shadows remain forbidden, as on the web.

## Options considered

### Option A — Keep flat surfaces with hairline borders
Follows the web law exactly and keeps the two platforms visually identical.
Cons: keeps the heavy outlined-grid feel on phone, and does not by itself fix black sheets.

### Option B — Soft neutral shadows on light, luminosity on dark (chosen)
Matches how iOS itself separates grouped content, removes the outline noise, and keeps dark
mode clean where black shadows would be invisible or muddy.
Cons: the app no longer matches the web's surface treatment; shadows cost an offscreen
render pass per surface.

### Option C — Shadows in both modes
One rule for both modes.
Cons: black shadows on a near-black green canvas are invisible at best and dirty at worst;
dark mode would gain render cost with no visual gain.

### Option D — Ask the web to add shadow and sheet tokens first
Keeps a single source of truth.
Cons: blocks a native-only problem (sheets do not exist on the web) on a web change.

## Consequences

### Positive
- No sheet or drawer renders pure black in dark mode: `SharpitThemeTests` assert the raised
  tone equals `card` and is brighter than the canvas.
- Surface treatment is defined once, in `SharpitSurface.swift` and `SharpitElevation.swift`;
  feature views keep calling `sharpitSurface(_:)` and `.sharpitSheet()`.
- A panel inside a sheet stays distinguishable from the sheet on dark.

### Negative
- The native app visibly differs from the web on surfaces. Anyone comparing screenshots
  across platforms must know this ADR exists.
- The shadow is applied to the background shape only, but each surface still adds a shadow
  pass on light; long lists should keep using `LazyVStack`.
- A new sheet that forgets `.sharpitSheet()` falls back to system black again.

### Neutral
- Data marks that use a stroke on purpose (sport tag outline, consistency strip days,
  gauges) keep it; this decision is about surfaces, not marks.
- `SharpitStroke.hairline` stays for those marks.

## References
- SHARPIT ADR-041 — iOS design tokens generated from web
- `../SHARPIT/design.md`
- `SHARPIT-APP/DesignSystem/SharpitElevation.swift`

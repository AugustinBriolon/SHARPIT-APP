# 35. The shared components turn Clinique in place

Date: 2026-11-14

## Status

Accepted. Supersedes [ADR 0034](0034-clinique-primitives-sit-beside-ink-and-lime.md). Client side of SHARPIT-WEBAPP ADR-130 and ADR-131.

## Context

ADR 0034 added the Clinique primitives beside the Ink & Lime components and planned to move screens one feature at a time. Three screens were swept that way: Résumé, Plan's week and the Coach thread.

That sweep showed two things:

- **The app does not hold two looks.** A swept screen still borrows shared pieces — a card header, a week strip, a session drawer opened from it. Each borrowed piece needed a bridge (an environment flag that swapped a shadow for a hairline, or lime for ink), and the bridge left Ink & Lime content inside a Clinique outline.
- **Most of the difference is in a few shared values.** Secondary text, the surface of a card, the icon tile, the pill and the primary button account for nearly every pixel that differs. About 900 call sites read them.

The athlete then asked for the whole app to move, without a screen-by-screen review.

## Decision

We will restyle the shared components in place, as ADR 0012 did for Ink & Lime, and keep the Clinique primitives for what is new.

- **Neutrals by substitution.** In the app target, secondary text reads `slate`; chips, inset groups and placeholders read `tile`; borders, grids and tracks read `divider`; the page and its cards read `card`. The Ink & Lime neutral tokens stay in the generated file for the widgets and the web.
- **A card is a hairline.** `sharpitSurface(.panel)` fills with the sheet's colour inside a 1 pt `divider` stroke, at the 20 pt Clinique corner. A card casts no shadow; `sharpitShadow` remains for what floats over the sheet — a toast, the activity sheet over its map, a slider's knob.
- **The page is the sheet.** `SharpitCanvasBackground` is the card colour. A screen adds its one wash with `cliniqueSheet(wash:)`. A grouped list sits on `tile` so its rows still read.
- **Ink runs the controls.** A selected day, a check box, a chosen step, a progress bar and the chart line are ink (`primary` with `primaryForeground`). `SharpitPrimaryButton` is a capsule and its accent style is ink.
- **Tiles are neutral.** `SharpitIconTile` and `SharpitSportBadge` draw an ink glyph on a round `tile`.
- **Lime becomes the good status.** `SharpitPill`'s lime styles take the good status set; a data mark that was lime takes `statusGoodMark`, and `statusGoodForeground` where it is text. `SharpitInlineTag` (« Clé », « Brick ») takes the Pro set, the coach's mark.
- **Labels are sentence case.** `SharpitEyebrow` is a slate caption, and no label is set in capitals.
- **Ink cards read the dark values.** `sharpitSurface(.ink)` puts its content in the dark colour scheme, so slate, tiles and status marks stay legible on ink in light mode.
- **A dial takes its pillar's hue** on an app screen (`SharpitTickGauge(tone:)`); the widgets keep lime.
- **Type is plain SF Pro.** The mock-ups are set in a neutral grotesque; `SharpitTypography` drops the rounded design, in the widgets too.
- **Tab icons are outlines** (`SharpitTabLabel`): the selected tab is told by its pill.
- **Résumé and Plan are rebuilt on their mock-ups**: a backdrop band with the date and a rising sheet, four rings, a rail of days with week totals counted on the device (`PlanWeekTotals`).
- **Every screen with a mock-up is built from it, not adapted to it.** The mock-up is rendered to an image and laid beside a capture of the app; what differs is fixed in the app, and a part the data did not carry is added rather than dropped (Santé's « Tendances » and marker tables, Plan's phase and race countdown, Sommeil's course by stage and its fourteen nights, Activité's records and weeks). Where no datum exists the nearest true one stands in, never an invented figure: Santé's « Score santé » ring reads the markers in their norm.
- **Chrome follows the mock-ups**: a tab's name in the bar's row (`SharpitBarTitle`), separate glass circles (`SharpitBarGap`); a day screen carries the day as a capsule in the bar, hides the tab bar and floats a home button.
- **Left as they are:**
  - the sign-in screen, the launch mark and the app icon — the brand;
  - switches, which stay lime: an ink switch put a white knob on a white track in dark mode;
  - ink surfaces (`sharpitSurface(.ink)`) and what is drawn on them;
  - the widgets themselves.

## Options considered

### Option A — Keep sweeping feature by feature (ADR 0034)

- Pros: each screen is reviewed against its mock-up before it ships.
- Cons: every shared piece needs a bridge, the bridges leave mixed content, and the app shows two looks for as long as the sweep lasts.

### Option B — Restyle the shared components in place (chosen)

- Pros: the whole app changes together and stays coherent. No flag, no bridge, less code than before.
- Cons: screens that were never laid out for Clinique take its colours inside their old structure. Screens that cannot be opened without an account were not looked at.

## Consequences

### Positive

- One look across the app, in light and dark, checked on the Debug galleries and screen demos (reference cards, Résumé, Plan, Coach, session drawer).
- The transitional flag and its two call sites are removed.
- The design gallery now shows the reference cards in Clinique, so a regression in a shared component shows there first.

### Negative

- Ink hero cards (Santé's age, the weekly review) are not part of the Clinique mock-ups and still stand.
- Screens rebuilt on their mock-up so far: Résumé, Plan, Coach, Activité and a session, Santé, Sommeil, Récupération, Nutrition, Journal, Paramètres, Connexions, Séance prévue, the paywall, Zones sensibles, Effort, the morning check-in, the plan adapter, the food search, the consent wall and the coach's memory. Objectifs, the guided strength session, the generator, the weekly review, thresholds, equipment, the onboarding and the empty / error states have the colours, not yet the structure.
- Where a mock-up shows what the data does not carry (a session's intensity blocks, « mieux / pareil / pire » on a zone, caffeine's last time, a water goal), the part is left out or said from the nearest true datum; each feature note names it.
- Résumé no longer shows the day's timeline or the nutrition card; nutrition is a ring that opens the food log.
- A week's planned volume and load count a done session for what was recorded, since its prescription is not in the entries: the rings read slightly high against the original plan.
- The snapshot references were recorded again; each was looked at.

### Neutral

- `CLAUDE.md` describes Clinique as the app's look; the Ink & Lime description is removed.
- The web app and the landing are unchanged (SHARPIT-WEBAPP ADR-131, additive tokens).

## References

- `docs/adr/0034-clinique-primitives-sit-beside-ink-and-lime.md`
- `docs/adr/0012-ink-and-lime-primitives-on-sf-pro.md`
- SHARPIT-WEBAPP `docs/adr/ADR-130-data-hues-and-status-sets-join-ink-and-lime.md`
- SHARPIT-WEBAPP `docs/adr/ADR-131-clinique-neutrals-hairlines-and-capsule-geometry.md`

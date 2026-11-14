# 34. Clinique primitives sit beside Ink & Lime until each screen is swept

Date: 2026-11-14

## Status

Superseded by [ADR 0035](0035-the-shared-components-turn-clinique-in-place.md).

## Context

The redesign chose direction "Clinique": white sheets, thin rings with a pillar hue, status pills, hairlines instead of card shadows, capsule controls on system glass. SHARPIT-WEBAPP ADR-130 and ADR-131 added its tokens beside the Ink & Lime ones, without changing an existing value, and `SharpitTokens.generated.swift` now carries both sets.

ADR 0012 restyled the shared components in place, so about 2,000 call sites took Ink & Lime at once. Doing the same here would turn every screen over in one commit, before any of them had been laid out for the new look: the mock-ups change structure (a sheet with one wash, rows split by lines, a status pill beside each value), not only colours.

Several rules of this repository's `CLAUDE.md` describe Ink & Lime and contradict the new look: no hairline border on a surface, no wash in content, lime as the only hue, a 28 pt shadowed card.

## Decision

We will add Clinique as a separate set of primitives in `DesignSystem/Clinique.swift` and move screens to it one feature at a time.

- **New primitives, new names.** `CliniqueStatus` and `CliniqueStatusPill`, `CliniquePillar` and `CliniqueRing`, `CliniqueButtonStyle` (primary, outline, plain; 44 pt, 52 pt for a flow's main action), `CliniqueWash` with `cliniqueSheet(wash:)`, `cliniqueCard()`, `CliniqueDivider`. They read only the Clinique tokens.
- **Ink & Lime components are untouched.** An unswept screen keeps `SharpitPill`, `SharpitScoreRing`, `SharpitPrimaryButton` and `sharpitSurface`.
- **A screen is swept whole.** It uses one set or the other, never both. The Ink & Lime rules of `CLAUDE.md` stop applying to a screen once it is swept; the Clinique rules of ADR-130 apply instead.
- **Glass stays the system's.** Floating controls reuse `sharpitGlassCapsule`, `sharpitGlassCircle` and `SharpitGlassGroup`. Clinique adds no material of its own, and content still never takes glass.
- **Type is unchanged.** `SharpitTypography` (SF Pro Rounded, regular and semibold) serves both sets.
- **A no-data ring is not a zero.** `CliniqueRing` takes an optional fraction; `nil` draws the track and a greyed glyph.
- **Reference.** A Debug gallery (`-SharpitCliniqueGallery YES`) shows the primitives in light and dark, to compare with the design canvas.

## Options considered

### Option A — Restyle the Ink & Lime components in place, as ADR 0012 did

- Pros: no second set to maintain; every screen changes with no call-site edit.
- Cons: screens would take hairlines and washes inside layouts built for shadowed cards and inset groups. The whole app would ship half-redesigned in one release.

### Option B — Separate primitives, screens swept one at a time (chosen)

- Pros: each release ships finished screens. A swept screen can be compared to its mock-up alone. The web is unaffected.
- Cons: two component sets live side by side for the length of the sweep, and a tab can sit next to one in the other look.

## Consequences

### Positive

- The gallery on an iOS 27 simulator shows the primitives match the canvas in light and dark, with real system glass under the docked action.
- `CliniqueRingMath` is covered by tests: no arc without data, an arc held to the circle.

### Negative

- Until the sweep ends the app shows two looks. The order of the sweep has to keep each tab coherent: Résumé first, then Plan, Coach, Séance, Santé.
- Not built yet, to be added when a screen needs them: segmented control, filter chips, stepper, checklist row, result table, loading placeholder, the dark header band of Résumé.
- Three light hues (recovery lime, nutrition orange, zone 3 yellow) sit below 3:1 on white. A ring always carries its glyph and a figure, so the hue is never the only cue.

### Neutral

- `CLAUDE.md` gains a Clinique paragraph; the Ink & Lime paragraphs stay until the last screen is swept.
- Ring glyphs are filled symbols. That follows the existing rule: a filled symbol is a status mark.

## References

- SHARPIT-WEBAPP `docs/adr/ADR-130-data-hues-and-status-sets-join-ink-and-lime.md`
- SHARPIT-WEBAPP `docs/adr/ADR-131-clinique-neutrals-hairlines-and-capsule-geometry.md`
- `docs/adr/0012-ink-and-lime-primitives-on-sf-pro.md`

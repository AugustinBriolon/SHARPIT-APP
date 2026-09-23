# 8. The Human Interface Guidelines outrank the web design system

Date: 2026-09-21

## Status

Accepted

Supersedes [ADR-0002](0002-soft-shadow-elevation-instead-of-hairline-borders.md)

## Context

Until now the native app treated the web design system as its law
(`../SHARPIT/design.md`, `DESIGN_LANGUAGE.md`, SHARPIT ADR-041) and diverged from it only
where the phone forced a divergence. [ADR 0002](0002-soft-shadow-elevation-instead-of-hairline-borders.md)
is that pattern: it dropped the web's hairline borders and lifted every surface with a soft
shadow, because stacked outlines read as a form grid on a phone.

Reviewing the built screens, the product owner judged the result unnative and unconsidered —
"placed there as if it just had to be displayed, with no question asked about the UX" — and
ruled that the app must follow Apple's Human Interface Guidelines, to the letter, above the
design system.

That ruling resolves a conflict the repo could not resolve on its own. Three concrete
symptoms, all reported from use:

- **Elevation inside elevation.** `SharpitField` raises a chip surface inside `SharpitFieldGroup`'s
  panel, which itself sits on a page of raised plates. Seuils & repères shows a shadow inside
  a shadow inside a shadow. ADR 0002 produced this: once every surface lifts, nesting two is
  visual noise with no hierarchy left to express.
- **A spinner on almost every screen.** Plan, Activité, Coach, Profil, Seuils and Corps all
  replace their content with "Lecture…" on open. Native apps rarely show one, not because
  they load faster, but because they paint what they already know and refresh underneath.
  Today and the journal now do this; nothing else does.
- **Hand-rolled rows everywhere.** Every list in the app is a `VStack` of custom surfaces
  rather than a `List`, so it inherits none of the system's row metrics, separator insets,
  swipe affordances, selection behaviour, keyboard handling or Dynamic Type scaling.

Two further constraints:

- The HIG themselves are not fetchable as text (the pages are JavaScript-rendered), so this
  decision records principles and the repo's own rules, not quotations. Where a specific
  number matters — the 44×44pt minimum touch target, Dynamic Type support — it is stated as
  a rule the code must satisfy and a test must pin.
- The web has no sheets, no navigation stack and no Dynamic Type, so on those subjects it has
  nothing to say and never did.

## Decision

**Where Apple's guidelines and the web design system disagree, Apple wins.** The web remains
the source of truth for *what* is measured and *what it is called*; it stops being the source
of truth for *how a native screen is built*.

Concretely:

- **Structure and behaviour come from the system.** Settings-like and row-based screens use
  `List` with `.insetGrouped`, not `VStack`s of custom surfaces: Moi, Profil, Seuils &
  repères, the connections screen, the journal's preference drawer. A row keeps the system's
  metrics, separator insets and swipe behaviour.
- **Separators come back, shadows go away on grouped content.** This is the reversal of
  ADR 0002: an inset-grouped list separates its rows the way iOS does, and a row inside it
  carries no surface of its own. `sharpitSurface` survives only for content that is genuinely
  a raised card on a canvas — the Today fold's plates, a chart panel — and **never nests**.
- **Nothing is raised inside something already raised.** One elevation level per screen
  region, enforced by an environment value so a component can tell whether it is already on a
  raised layer.
- **A screen never replaces content with a progress indicator.** It paints the last data it
  holds and refreshes underneath, showing progress only in the refresh control. A screen with
  nothing cached shows a skeleton in the shape of its content, never a centred spinner with a
  label. This generalises what Today (`TodaySnapshotRepository`) and the journal
  (`JournalSnapshotRepository`, `docs/adr/0007`) already do.
- **Every text style scales with Dynamic Type**, and every tappable target is at least
  44×44pt. Fixed point sizes and fixed row heights on text-bearing rows are defects, not
  choices.
- **Typography and colour stay SHARPIT's.** The generated tokens keep their meaning: the
  brand lives in the palette, the typeface and the words, which is where a brand belongs on
  iOS. Apple's own apps are not beige.
- **The forbidden list stands** (`CLAUDE.md`): no streak counters, no radial gauge dominating
  a hero, no sparkle or chatbot chrome, no coloured glow shadows, no invented metrics, no
  motivational micro-copy. The HIG do not ask for any of them.

A native screen that cannot be built from system components without losing meaning may still
be custom — a chart, the Today fold, a gauge. The burden is on the custom version to justify
itself, which is the reverse of the burden until now.

## Options considered

### Option A — Keep the web design system as law
Screens stay pixel-comparable across platforms and no ADR is reversed. Cons: keeps every
symptom above. The app keeps reading as a web page rendered on a phone, which is the
judgement that triggered this decision.

### Option B — HIG for structure, SHARPIT for colour and type, no ADR reversed
Follow the system on layout, spacing, targets and accessibility while keeping surfaces as
ADR 0002 defined them. Pros: nothing to supersede; most brand-led apps live here. Cons:
keeps shadow-on-shadow, because that defect comes from the surface rule itself, not from its
application. The product owner asked for the guidelines "to the letter", and this option
keeps an explicit exception to them.

### Option C — HIG outrank the design system (chosen)
The system decides structure, behaviour and elevation; SHARPIT decides palette, typeface and
copy. Pros: removes the nesting defect by removing the nesting; rows inherit accessibility,
Dynamic Type and swipe behaviour for free; new screens have a default that needs no
deliberation. Cons: the app visibly diverges from the web, so screenshot comparison stops
being a parity check; `SharpitSurface`'s reach shrinks and several feature views are rewritten
rather than tweaked; a future web redesign will not propagate to native structure.

### Option D — Rebuild against the HIG from scratch
Start the UI layer over with no inherited system. Pros: no legacy to reconcile. Cons: throws
away working screens, tested stores and the generated token pipeline to solve a problem that
is addressable screen by screen. The tests that pin behaviour would go with it.

## Consequences

### Positive
- Seuils & repères, Profil and Moi lose the nested elevation entirely, because a grouped list
  has no surface to nest.
- Rows gain the system's swipe actions, separator insets, selection and Dynamic Type without
  the app implementing any of it.
- "Lecture…" disappears from the screens that have a cache, and becomes a content-shaped
  skeleton on the ones that do not.
- A new screen has a default shape, so the next one does not need a design decision to exist.

### Negative
- The app and the web now differ by design, not by accident. A screenshot diff is no longer a
  parity check, and anyone comparing them must know this ADR exists.
- Several feature views are rewritten, not adjusted: the diff is large and touches screens
  that currently work.
- `SharpitSurface` and `SharpitElevation` keep a narrower role than they were built for, and
  some of their cases will end up unused. Dead cases should be deleted rather than kept "in
  case".
- ADR 0002's dark-mode win must not be lost with it: sheets still need `.sharpitSheet()` or
  they fall back to system black. That part of 0002 survives as a rule even though the ADR is
  superseded.

### Neutral
- The generated token pipeline is untouched: `SharpitTokens.generated.swift` still comes from
  the web, and colour still means what the web says it means.
- ADR 0004's rule that anything opening something carries a chevron is unaffected — that is
  also what a grouped list row does.
- The web keeps deciding vocabulary: « charge » versus « TSS » (`docs/adr/0006`) is a naming
  decision, not a layout one.

## References
- [ADR 0002](0002-soft-shadow-elevation-instead-of-hairline-borders.md) — superseded by this decision
- [ADR 0004](0004-semantic-color-and-a-tinted-coach-pill.md) — semantic colour and affordances, still in force
- [ADR 0007](0007-icloud-replicates-the-read-cache-only.md) — the cache this decision generalises into a loading rule
- https://developer.apple.com/design/human-interface-guidelines — the guidelines this decision adopts
- `../SHARPIT/design.md` — still the source of truth for palette, typeface and vocabulary

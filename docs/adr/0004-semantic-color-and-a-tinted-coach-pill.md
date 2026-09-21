# 4. Semantic color and a tinted coach pill

Date: 2026-09-21

## Status

Accepted

Supersedes [ADR-0003](0003-semantic-color-and-a-filled-coach-call-to-action.md)

## Context

ADR 0003 extended semantic color across the app and made "Discuter avec le coach" a
filled ink band at the bottom of the activity detail. On device the band read as heavy and
still sat too low: below the coach's analysis, well under the fold. The product owner
wants the action to be noticed through placement and one accent, not through mass.

The same review found the effort / feeling and compliance tiles each spent a full row on a
short readout, leaving half of every row empty, and the weather chip took a row of its own.

## Decision

Everything in ADR 0003 about semantic color stands: numbers take tones from
`SessionFeedbackTone`, built from ramps the web defines; a recorded journal "Non" takes
`signal-risk`; anything that opens something is a raised tile with a chevron and
`.buttonStyle(.sharpitPressable)`; passive information stays flat.

What changes:

- `CoachDiscussButton` is a tinted pill — primary text and icon on a 10% primary capsule,
  with an outward arrow. No fill, no subtitle, no shadow.
- It sits with the title of what it discusses: under the activity title on the detail page,
  right under the header in the planned session drawer.
- On the activity detail, effort · feeling and compliance share one row as two half-width
  tiles of equal height, and the weather moves beside the coach pill as a meta line.
- The detail panel drops its 56 pt top inset when it sits under a map, since the floating
  back button is over the map, not over the panel.

## Options considered

### Option A — Keep the filled ink band (ADR 0003)
Impossible to miss. Cons: visually heavy, competes with the verdict, and its position at the
bottom defeated its purpose.

### Option B — Tinted pill near the title (chosen)
Noticed because it is the first action under the title and the only tinted control there.
Cons: less contrast than a filled band; relies on placement.

### Option C — Toolbar button
Always visible. Cons: the detail hides its navigation bar for the map hero, and an icon-only
toolbar button loses the words that say what the coach will be told about.

## Consequences

### Positive
- The coach action is on screen when the detail opens, without scrolling.
- The first screen of the activity detail carries title, coach action, weather, rating and
  compliance, where it used to stop at the rating.

### Negative
- A tinted pill is quieter than the band; if usage drops, placement is the first thing to
  revisit, not size.

### Neutral
- The subtitle the band carried ("Le coach voit déjà…") is gone; the accessibility hint
  keeps the meaning.

## References
- ADR 0002 — Soft shadow elevation instead of hairline borders
- ADR 0003 — Semantic color and a filled coach call to action

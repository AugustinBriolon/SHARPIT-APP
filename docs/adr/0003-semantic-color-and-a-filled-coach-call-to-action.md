# 3. Semantic color and a filled coach call to action

Date: 2026-09-21

## Status

Superseded by [ADR-0004](0004-semantic-color-and-a-tinted-coach-pill.md)

## Context

The web design law reserves color for semantic state and filled surfaces for the verdict,
and the native app applied both strictly. On iPhone the product owner found the result
colorless and inert:

- On the activity detail page, the controls that open a drawer (effort and feeling,
  compliance) were grey text on grey capsules — the same look as the weather chip, which
  opens nothing. They went unnoticed.
- The compliance drawer showed the raw verdict enum (`AS_PLANNED`) and no visual reading of
  the score.
- "Discuter avec le coach", the one action that hands a subject to the coach, was drawn as
  a row identical to every other row.
- Journal answers used a neutral pill for "Non", so a recorded "no" looked like an
  unanswered day at a glance.
- Tappable cards gave no feedback under the finger (`.buttonStyle(.plain)`).

## Decision

- Numbers the athlete gives or receives take a semantic tone, built only from ramps the web
  already defines: effort follows the intensity ramp (`signal-recovery` → `signal-vo2`),
  feeling runs from `signal-risk` to `signal-base`, compliance uses recovery / caution /
  risk bands (≥ 85, ≥ 60, below). Tones live in `SessionFeedbackTone`.
- A recorded "Non" in the journal takes `signal-risk`.
- Anything that opens something is a raised tile with a chevron and the
  `sharpitPressable` style (scale 0.97 on press). Passive information stays flat.
- `CoachDiscussButton` is a filled ink band (Forest on light, Lime on dark) with an icon,
  subtitle and arrow. It is the one filled call to action on a screen, besides the verdict.
- Changing values animate with `numericText` transitions; small score rings fill on appear.
  Rings stay compact readouts beside their number, never a hero.

Still forbidden: decorative gradients, colored glow shadows, sparkle or chatbot chrome,
streak counters, invented metrics.

## Options considered

### Option A — Keep the web's strict color and fill rules
Visual parity with the web. Cons: keeps drawer entry points invisible and the coach
action indistinguishable from informational rows.

### Option B — Semantic color from existing ramps, one filled CTA, press feedback (chosen)
Makes state and affordance readable without inventing a palette. Cons: the app is more
colorful than the web; a second filled surface competes with the verdict on screens that
show both.

### Option C — Brand accent on every interactive element
Simple rule. Cons: color stops meaning state, which is the one thing it must keep meaning.

## Consequences

### Positive
- Effort, feeling and compliance read at a glance, with the same color meaning everywhere.
- The coach action is findable on every screen that offers it, from one component.
- Every tappable card answers the finger the same way.

### Negative
- Further visual divergence from the web, on top of ADR 0002.
- Red on "Non" also marks answers that are good news ("Maux de tête : Non"); the color
  states the answer, not its value.

### Neutral
- Feeling is now written in the web's vocabulary (`Très mal` … `Très bien`); values earlier
  builds wrote (`Très mauvais`, `Mauvais`, `Moyen`) are still read.

## References
- ADR 0002 — Soft shadow elevation instead of hairline borders
- `../SHARPIT/src/lib/activity/feeling/activity-feeling-scale.ts`
- `../SHARPIT/src/lib/planned-session/display/session-analysis-display.ts`

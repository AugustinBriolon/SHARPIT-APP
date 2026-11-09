# 32. The body step asks where the athlete is

Date: 2026-11-09

## Status

Accepted. Amends 0031 for the week's days, the zone sheet and the health grounds.

## Context

On the simulator, the athlete found three things that 0031 left short:

- **Ta semaine:** the day bars read as a chart, and a day beyond the session count was refused without a sign. Painting with a finger fought the page's scroll.
- **The zone sheet:** it asked what the zone is, the side, then « Légère / Modérée / Forte ». That said nothing about where the athlete is with it.
- **« Un terrain à ménager ? »:** three chips covered too few cases, asked nothing, and wrote free-text notes the coach could only guess from.

## Decision

- **Ta semaine:**
  - Each session is a token, and each day is a key. A chosen day is a lime disc carrying its session's number. A free day is a ring, and it fades to 0.35 once every session has its day. A tap on a faded day explains how to change.
  - Until the athlete touches a day, the week is spread for recovery: 3 → Ma·Je·Sa, 4 → L·Me·V·D (`V1TrainingAvailability.spread`). After a touch, their days stay.
  - Taps only, with the pressable style. No haptic, since a tap is not a notch under the finger.
- **The zone sheet** asks in turn, each question appearing once the one above is answered:
  - What it is, as rich rows with a one-line meaning.
  - The side, only off the body.
  - Since when: < 2 weeks, 2 weeks to 3 months, or > 3 months. This becomes the note's `startDate`.
  - Pain from 0 to 10 (Santé's `ZoneSeverityScale`), with the pain-monitoring rule underneath: up to 5 the plan keeps loading, above it lightens.
  - What the athlete can still do (Santé's `ZoneImpactPicker`, `functionalImpact`).
  - At « arrêté » or above 7, the sheet says to see a professional. A fragile zone asks none of the pain questions.
- **Health grounds** are their own model (SHARPIT ADR-124):
  - Rows from `HealthGroundCatalog`, which mirrors the web's keys and stages. The cycle, pregnancy and postpartum rows are offered to a woman only.
  - Each row opens a sheet asking the stage. A stage that owes a medical go-ahead says the coach stays at a moderate intensity until then.
  - The set goes out whole through `PUT /api/v1/health-grounds`. Like the injuries, it waits for the health consent, and it counts among the answers the first week is planned from.

## Options considered

- **Keep the paint gesture with tap fallback:** it competes with the scroll and lost taps on the simulator. Taps alone are enough for seven keys.
- **A severity ruler (`SharpitRulerPicker`) for pain:** eleven units leave a 100 pt ruler. The two-row scale Santé already uses is easier to hit and keeps one way to report pain.

## Consequences

- `OnboardingInjuryDraft` loses `Level` and the `condition` kind. A draft saved before still decodes; its zones simply ask their questions again.
- `OnboardingDraft.healthGrounds` is optional, so an older draft on disk still loads.

# SHARPIT iOS emotional UX — Digital Twin

**Date:** 2026-09-16  
**Status:** Accepted  
**Repos:** `SHARPIT-APP`  
**Related:** [2026-09-16-ios-design-system-design.md](./2026-09-16-ios-design-system-design.md), SHARPIT `docs/design/DESIGN_LANGUAGE.md`

## 1. North star

> **The Twin has already thought; you open to confirm.**

The first impression must feel like reading a calm instrument readout that already resolved complexity — not like opening a dashboard to hunt for meaning.

## 2. Emotional contract

| Athlete should feel | Must not feel |
| --- | --- |
| Understood | Surveilled |
| Calm | Anxious from raw numbers |
| Certain | Confused / hedged |
| Respected | Patronized / gamified |

**Instrument-grade delight:** micro-interactions that *reveal* (count-up, confidence ring fill, precise check, soft haptic). Never self-celebrating UI (no confetti, permanent bounce, sparkle spam).

## 3. First two seconds (Today)

Causal order — never reverse:

1. Canvas posture wash fades in  
2. Loading instrument (structure-matched skeleton)  
3. Crossfade to loaded content  
4. `verdictReveal` — hero opacity + slight rise  
5. `signalSettle` — cells stagger in with count-up  
6. Session plate or rest plate (evidence after decision)

Within ~2s the athlete must read the **verdict** before treating the four scores as the hero.

## 4. Moment catalogue

| Moment ID | Trigger | Motion | Haptic |
| --- | --- | --- | --- |
| `arrival` | First paint of loaded Today for the day | Hero settle + canvas | `.soft` (once/day) |
| `verdictReveal` | Loaded content appears | Opacity 0→1, offset Y 12→0, 280–360 ms | none (covered by arrival) |
| `signalSettle` | After verdict | Stagger 48 ms/cell, number count-up | none |
| `sessionDone` | Session kind becomes `.done` | Checkmark morph | `.success` (once/day per session id) |
| `pullRefresh` | Refresh succeeds | Brief opacity pulse on scores | `.light` |
| `confidenceRise` | confidencePct increases vs last paint | Ring fill to new value | none |

Anti-spam: persist celebration keys in `UserDefaults` keyed by training day id.

## 5. Motion rules

- Durations: **180–420 ms**  
- Curve: snappy spring (`response ≈ 0.32`, `dampingFraction ≈ 0.86`) for reveals; ease-out for fades  
- All animations go through `SharpitMotion`  
- If `accessibilityReduceMotion`: crossfade / set final values — **no springs, no stagger delays, no count-up**

## 6. Anti-patterns (never)

- Confetti, fireworks, streak flames  
- Continuous pulsing on idle chrome  
- Celebrating every refresh  
- Equal visual weight for verdict and metric tiles  
- Empty white void on rest days without an intentional rest plate  
- Feature code calling `withAnimation` with ad-hoc curves

## 7. Implementation phases (summary)

0. This spec  
1. Primitives (`SharpitMotion`, `SharpitHaptics`, `AnimatedNumber`)  
2. Today arrival choreography + confidence ring  
3. Signal tracks + `RestDayPlate`  
4. Win moments + anti-spam store  
5. Shell tab light arrival  

## 8. Success criteria

- Cold open: verdict is readable before metric noise  
- Reduce Motion ON/OFF both usable  
- Rest day never looks like a broken layout  
- Wins feel like recognition, not arcade rewards  

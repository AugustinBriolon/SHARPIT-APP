# 29. Résumé shows a trip the plan no longer fits

Date: 2026-11-06

## Status

Accepted. Supersedes [ADR-0028](0028-a-saved-trip-opens-the-plan-adapter.md).

## Context

ADR-0028 opened « Ajuster le planning » by itself when the « Déplacements » sheet closed after a save that narrowed training over planned sessions. In use, the athlete found it intrusive: right after creating a trip, a sheet reshaping the week came up with no warning. They asked instead for Résumé to say that the trip and the plan disagree, and to choose when to adjust.

The server now reads that disagreement (SHARPIT ADR-120). `/api/v1/today` carries `travelConflict` for today. It names the earliest trip or constraint in the next 14 days whose sessions still to do do not fit it, and counts those sessions. It is recomputed on every read.

## Decision

We will show a card on Résumé and open the adapter only on the athlete's tap:

- `TravelConflictCard` sits under `PlanHorizonCard`, built the same way (`SharpitCardHeader`, a pressable panel). Title « Ton déplacement à Lyon bouscule ton plan » (« « Boulot » bouscule ton plan » for a constraint), subtitle « 2 séances ne collent pas, du sam. 7 au dim. 8 nov. » (`TravelConflictReadout`).
- A tap goes through `ShellRouter.openTravelConflict`, which selects Plan and sets `pendingTravelConflict`. Plan opens the adapter with the trip written into the focus (`PlanTripAdaptation.focus(for:)`) and starts it, through the same `startAdapter(focus:catchUp:)` as « Rattraper ma semaine ».
- The card is not Pro-gated: it tells the athlete about their own plan. A Free athlete's tap shows the adapter's `SharpitProTeaser`, as any other route into it does.
- The card leaves on its own once the sessions fit. The adapter's apply bumps `calendarRevision`, Résumé reads the day again, and the server finds no conflict.
- The save in « Déplacements » opens nothing. ADR-0028's `onSaved` plumbing and its client-side check (`PlanTripAdaptation.offer`) are removed.

## Options considered

### Option A — Keep ADR-0028, ask first with a dialog

Pros: smallest change. Cons: the question still interrupts the save. It is asked once, so a trip left unresolved is forgotten.

### Option B — A Résumé card from the server, adapter on tap (chosen)

Pros: the athlete chooses when to adjust. The card stays until the plan fits, whoever fixes it (the adapter, a hand edit, the coach in chat). One rule on the server, the one that already guards writes. Cons: no « Ignorer », so a conflict the athlete chooses to keep stays shown until the trip ends.

### Option C — A badge on the Plan tab or the week's trip chip

Pros: closer to the plan. Cons: Résumé is the page read every morning, and a badge cannot say what is wrong or how many sessions are affected.

## Consequences

### Positive

- Saving a trip no longer opens a sheet by itself.
- The athlete sees on Résumé which trip, which days and how many sessions are affected, with one tap to the coach's proposal.

### Negative

- There is no way to dismiss the card short of changing the plan or the trip.
- An older server sends no `travelConflict`. The field is optional, so the card is simply absent.

### Neutral

- The trip still reaches the coach's context on save. Only the prompt to adjust moved.

## References

- `SHARPIT-APP/Features/Today/TravelConflictCard.swift`, `Features/Plan/PlanTripAdaptation.swift`
- `PlanView.startAdapter(focus:catchUp:)`, `ShellRouter.openTravelConflict`
- SHARPIT ADR-120 (`packages/server/src/lib/travel-context/travel-conflict.ts`)

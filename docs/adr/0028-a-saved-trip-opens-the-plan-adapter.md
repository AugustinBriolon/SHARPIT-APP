# 28. A saved trip opens the plan adapter

Date: 2026-11-06

## Status

Superseded by [ADR-0029](0029-resume-shows-a-trip-the-plan-no-longer-fits.md)

## Context

A trip or a constraint (Plan → « … » → « Déplacements », `PlanTripsView` / `CoachMemoryEntryForm`) tells the coach that training changes on some days: lighter, paused, or narrowed to some sports. Saving one only stored it. The server's `POST /api/v1/coach-memory` tags the sessions it covers with the trip's place (`applyTravelContextToUpcomingSessions`), but it does not change them. So a run planned on a « Pause complète » day stayed in the plan until the athlete opened « Ajuster le planning » on their own. The athlete reported this as a bug: creating a trip did not lead to a proposed change of the plan.

The adapter already does this job. `/api/v1/coach/adapt` (Pro, SHARPIT ADR-097) reads the coach context, constraints included, plus a free-text `focus`. It proposes changes over 14 days (`PlanAdjustmentStore.horizonDays`). The athlete keeps some of them and they are applied through `/api/v1/coach/adapt/apply`. « Rattraper ma semaine » (`PlanCatchUp`) already opens it with a missed session written into the focus.

## Decision

We will open « Ajuster le planning » when the « Déplacements » sheet closes after a save, with the trip written into the focus (`PlanTripAdaptation.focus`: place or title, days, and what training becomes). It opens only when all of these hold (`PlanTripAdaptation.offer`):

- the entry is a trip or a constraint, and it narrows training: a constraint other than `FULL`, or a list of allowed sports;
- its days overlap the adapter's 14 days;
- at least one session not yet done falls on those days (`plannedSessions(from:to:)` over the trip's days);
- the athlete is not known to be Free (`ProStore.pro?.isPro == false` skips it, so a save never opens a paywall).

The adapter starts at once, as it does for a catch-up. Nothing is written until the athlete applies the changes they kept.

## Options considered

### Option A — Do nothing

The coach reads the trip the next time the athlete adjusts the plan by hand. Pros: no code, no coach cost. Cons: the plan stays wrong until the athlete thinks of it, which is exactly what they reported.

### Option B — Re-plan on the server when the trip is saved

`POST /coach-memory` calls the adapter and writes the changes. Pros: works from every client, including the coach's own tool. Cons: it writes the plan without the athlete's approval, against the rule that the coach's calendar changes wait for it. Every save, edits included, would cost a model call. Free athletes would need a separate path.

### Option C — Offer the adapter on the client after the save (chosen)

Pros: reuses the existing adapter, sheet, Gate and apply path. Changes still wait for approval. The gate on narrowed training, the 14 days and a session still to do avoids a coach call when nothing in the plan is affected. Cons: iOS only (the web form does not do it), and only from Plan's sheet. A trip written by the coach in chat does not trigger it.

### Option D — Ask first (« Adapter ton plan ? »), then open the adapter

Pros: the athlete chooses before any coach call. Cons: one more tap and one more dialog for a case already filtered down to « the plan is affected ». The adapter itself is the question, since it applies nothing on its own.

## Consequences

### Positive

- A trip that pauses or narrows training over planned sessions gets a proposed plan right after it is saved, in one sheet, with no extra tap.
- No new endpoint or server code: the focus string is the only new contract.

### Negative

- Each qualifying save costs one adapter run against the athlete's coach quota (ADR-077 on the web).
- Web parity is missing: saving a trip on the web still does not offer an adjustment.
- An edit that only moves dates opens the adapter again when it still qualifies, even if the plan was already adjusted for the trip.

### Neutral

- Free athletes are unchanged: the trip still reaches the coach context; no teaser is shown.
- A trip beyond 14 days is left for a later adjustment, since the adapter cannot reach it.

## References

- `SHARPIT-APP/Features/Plan/PlanTripAdaptation.swift`, `PlanView.offerTripAdaptation`
- `PlanCatchUp` (the same pattern for a missed session)
- SHARPIT ADR-097 (coaching is Pro), ADR-040 (native `/api/v1` contract)

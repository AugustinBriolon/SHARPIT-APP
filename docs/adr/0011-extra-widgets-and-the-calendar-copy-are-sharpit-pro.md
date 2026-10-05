# 11. Extra widgets and the calendar copy are SharpIt Pro

Date: 2026-10-05

## Status

Accepted

## Context

SharpIt Pro gated only what the coach adds: the weekly review, unlimited session analysis, the
journal and nutrition readings, the biological age, and pushing sessions to the watch. The athlete
asked for four more reasons to subscribe, applied at once:

- an automatic copy of the plan into the iPhone's own Calendar;
- extra widgets;
- early access;
- supporting SharpIt.

The widgets show data the athlete owns, which the Pro gating principle says never to lock. They
are, however, a second view of figures that stay free everywhere in the app; nothing is hidden
except the home-screen shortcut.

## Decision

**Widgets.** Séance du jour, Verdict du jour, Nutrition, Demander au coach and Scanner stay free.
Sommeil, Poids, Volume de la semaine, Régularité and Prochain objectif are Pro:

- `ProStore` writes the tier into the widget snapshot (`WidgetSnapshot.isPro`).
- A locked widget draws `WidgetProLocked`.
- A snapshot that does not carry the tier yet leaves the widgets open, so a Pro athlete is never
  locked out between an update and the next launch.

**Calendar.** `PlanCalendarSync` uses EventKit with full access, asked only when the athlete turns
it on in Paramètres › Calendrier de l'iPhone:

- It writes the next 21 days of the plan into a calendar of its own, « SharpIt ».
- Each event is keyed by `sharpit://plan/session/<id>`.
- It runs on the same beats as the session reminders (launch, foreground, `calendarRevision`) and
  makes the calendar equal to the plan: moved sessions move, removed ones go.
- It never reads or touches another calendar. Turning it off removes the « SharpIt » calendar.
- The phone does the copy, not the server: there is no CalDAV feed and no new server schedule
  (Vercel Hobby), and it works offline from the plan already read.

**Early access and support** are listed perks (`pro-perks.ts`, served by `/api/v1/pro`) with no
code gate.

## Options considered

### Option A — Copy on the phone through EventKit (chosen)
- **Pros:**
  - No server work, immediate.
  - Native Calendar integration.
- **Cons:**
  - Only the phone that ran the app last updates the calendar.
  - Needs full calendar access, because updating its own events requires reading them.

### Option B — A subscribed ICS feed served by the web
- **Pros:**
  - Every device and calendar app.
- **Cons:**
  - The feed needs a secret-token URL, reachable without Clerk.
  - iOS refreshes subscribed calendars on its own schedule (minutes to hours), so a session moved
    would lag.

## Consequences

### Positive
- Four concrete Pro reasons, two of them shipped as code today.
- The plan appears in the athlete's Calendar with nothing to maintain by hand.

### Negative
- The extra widgets lock data the athlete can still read in the app — a deliberate exception to the
  Pro gating principle, at the athlete's request.
- A calendar shared through iCloud carries the session titles to the athlete's other devices.

### Neutral
- `NSCalendarsFullAccessUsageDescription` is declared in `Config/Info-Extra.plist`.

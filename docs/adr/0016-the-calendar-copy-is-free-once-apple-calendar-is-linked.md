# 16. The calendar copy is free once Apple Calendar is linked

Date: 2026-10-17

## Status

Accepted — supersedes the calendar part of [0011](0011-extra-widgets-and-the-calendar-copy-are-sharpit-pro.md).
The widget part of 0011 stands.

## Context

ADR 0011 made the plan's copy into the iPhone Calendar a Pro perk, and `AppleCalendarSync` wrote
sessions only when the athlete was Pro **and** Apple Calendar was the primary calendar source. A new
athlete who linked Apple Calendar therefore saw nothing land in their calendar, with no hint why.

The planned sessions are the athlete's own data. The Pro gating principle says Pro gates what
SHARPIT adds, never that data; 0011 was a deliberate exception, and the athlete has now reversed it.

## Decision

As soon as Apple Calendar is linked (`apple-calendar` in the source-prefs `connected` list), the next
21 days of the plan are written to the chosen calendar for every athlete, free or Pro.

- `AppleCalendarSync.shouldWrite(connected:)` is the whole rule: linked. No Pro check, no primary
  check.
- The write runs on link (`AppleCalendarSource.linkRevision` bumps once the server took the link;
  `RootView` refreshes on it), on launch, on every return to the foreground and on
  `calendarRevision` (the session reminders' beats).
- Unchanged from 0011: events keyed by `sharpit://plan/session/<id>`, moved sessions move,
  removed ones go, unlinking removes the « SharpIt » calendar.
- The web drops `calendar-sync` from the Pro perks (`pro-perks.ts`, served by `/api/v1/pro`). The
  link and busy routes never carried a `pro_required`.

## Options considered

### Option A — Free once linked (chosen)
- **Pros:**
  - Linking does what the athlete expects, at once.
  - Matches the Pro gating principle.
- **Cons:**
  - One Pro reason fewer.

### Option B — Keep Pro, show a `SharpitProTeaser` under the link
- **Pros:**
  - Keeps the perk.
- **Cons:**
  - Locks the athlete's own plan behind Pro; rejected by the athlete.

## Consequences

### Positive
- New athletes see their plan in Calendar right after linking.

### Negative
- An athlete with both Google and Apple Calendar linked, whose Google calendar is also on the
  iPhone, can see each session twice (once from the Google write, once in « SharpIt »).

### Neutral
- Busy-slot upload is unchanged: it still follows the calendar class's `enabled` list.

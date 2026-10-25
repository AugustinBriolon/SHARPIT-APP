# 25. A planned session is sent to the watch from its drawer

Date: 2026-10-25

## Status

Accepted.

## Context

The server can now send a planned run, ride or pool session to the athlete's Garmin watch through
the Training API (SHARPIT-WEBAPP ADR-106). This is Pro-only, sent by hand, and a second send must
be asked for explicitly. The app needs a place to offer it and a way to show whether the session is
already on the watch.

## Decision

We will offer « Envoyer sur ma montre » as a row in `PlannedSessionDrawer` (`SessionWatchPushRow`),
after the link row. Plan shows it only for a session that is not done, of a sport the watch takes
(`WatchPushState.canSend`), when Garmin is linked (read from `/api/v1/sync-status` with the plan's
extras). A Free athlete sees `SharpitProTeaser` in its place.

The row reads the receipt the plan already carries (`garminWorkoutId`,
`garminWorkoutScheduledDate`):

- not sent: « Envoyer sur ma montre »;
- sent on the session's day: « Sur ta montre », and a tap asks before resending;
- sent, then moved to another day: « Renvoyer sur ma montre », which replaces it at once.

A Garmin refusal (no import permission, Garmin session lost, quota) arrives as a 403 or a 429 with
the server's words, and is shown as they are in the toast. It never signs the athlete out.

## Options considered

### Option A — A row in the drawer (chosen)
Pros: next to the steps it sends, same shape as the link row, no new screen.
Cons: one session at a time.

### Option B — « Envoyer la semaine » in Plan's menu
Pros: one tap for the week.
Cons: spends Garmin's 200 calls a day quickly and resends on every re-plan; rejected with web
ADR-106 for now.

## Consequences

### Positive
- A Pro athlete puts a session on the watch in one tap, and sees when it is there or out of date.

### Negative
- Strength sessions and brick legs are not offered yet.
- Editing the steps after a send is not detected: only a moved day reads as out of date.

### Neutral
- Plan reads the sync status once more with its extras, to know whether Garmin is linked.

## References
- SHARPIT-WEBAPP ADR-106
- `docs/adr/0024` (Garmin through the OAuth handoff)

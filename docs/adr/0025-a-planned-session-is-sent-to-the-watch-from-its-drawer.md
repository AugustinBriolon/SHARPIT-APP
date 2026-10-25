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

We will offer « Envoyer sur ma montre » in the drawer's « … » (`SessionActionsMenu`), beside
« Lier à une séance réalisée », which moves there too: rows in the drawer's body read as heavy as
the session itself (the athlete's call, 2026-10-25). Plan offers it only for a session that is not
done, of a sport the watch takes (`WatchPushState.canSend`), when Garmin is linked (read from
`/api/v1/sync-status` with the plan's extras). A Free athlete's tap opens the paywall.

The entry reads the receipt the plan already carries (`garminWorkoutId`,
`garminWorkoutScheduledDate`):

- not sent: « Envoyer sur ma montre »;
- sent on the session's day: « Renvoyer sur ma montre », which asks before replacing;
- sent, then moved to another day: « Renvoyer sur ma montre », which replaces it at once.

The « … » now shows wherever one of its actions exists (Résumé and a brick's leg link a session
without editing it), and nowhere else.

A Garmin refusal (no import permission, Garmin session lost, quota) arrives as a 403 or a 429 with
the server's words, and is shown as they are in the toast. It never signs the athlete out.

## Options considered

### Option A — An entry in the drawer's « … » (chosen)
Pros: the drawer's body stays the session; every action on it sits in one place.
Cons: less visible than a row; one session at a time.

### Option C — A row in the drawer's body
Pros: seen at once, can say « Sur ta montre ».
Cons: shipped first and judged too heavy beside the steps.

### Option B — « Envoyer la semaine » in Plan's menu
Pros: one tap for the week.
Cons: spends Garmin's 200 calls a day quickly and resends on every re-plan; rejected with web
ADR-106 for now.

## Consequences

### Positive
- A Pro athlete puts a session on the watch from the « … », which says when it is already there.

### Negative
- Strength sessions and brick legs are not offered yet.
- Editing the steps after a send is not detected: only a moved day reads as out of date.

### Neutral
- Plan reads the sync status once more with its extras, to know whether Garmin is linked.

## References
- SHARPIT-WEBAPP ADR-106
- `docs/adr/0024` (Garmin through the OAuth handoff)

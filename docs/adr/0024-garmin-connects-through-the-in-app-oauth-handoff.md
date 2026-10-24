# 24. Garmin connects through the in-app OAuth handoff

Date: 2026-10-24

## Status

Accepted. Supersedes [0023](0023-garmin-is-linked-by-a-personal-api-key-the-app-never-keeps.md).

## Context

Garmin approved SharpIt for its Connect Developer Program (SHARPIT-WEBAPP ADR-105). Garmin is now
an OAuth provider: the athlete signs in on Garmin's page and chooses what to share, and the server
exchanges the code with the client secret, which must never ship in the app. The personal key
sheet of 0023 has no purpose any more.

## Decision

We will connect Garmin exactly as Strava, Withings and Google: `DisconnectableSource.garmin`
joins `oauthConnectable`, and « + » → Garmin opens `/api/v1/garmin/handoff` in the
`ASWebAuthenticationSession`, which closes on `/connect/garmin/callback` (the apex AASA lists it).
The `GarminKeySheet`, `GarminKeyClient` and the masked-key row are removed. Disconnecting goes
through `/api/v1/garmin/disconnect`, which also ends the registration at Garmin.

## Options considered

### Option A — The shared OAuth handoff (chosen)
Pros: one connect path for every OAuth source, no secret on the device, same outcomes and toasts.
Cons: none specific to Garmin.

### Option B — Keep the key sheet beside OAuth
Pros: the developer's own history through the Personal API.
Cons: two Garmin paths, a stopgap the public never needed; rejected with web ADR-105.

## Consequences

### Positive
- Garmin connects in one step, like the other sources.

### Negative
- Garmin sends no history on the Starter tier: a fresh connection starts empty until the watch syncs.

### Neutral
- The App Store guard now asserts the OAuth handoff and forbids a personal key or a token import.

## References
- SHARPIT-WEBAPP ADR-105
- `docs/adr/0014` (Sources de données)

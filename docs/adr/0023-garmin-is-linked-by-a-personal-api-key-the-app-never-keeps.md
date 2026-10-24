# 23. Garmin is linked by a personal API key the app never keeps

Date: 2026-10-24

## Status

Accepted

## Context

Garmin now offers an official Personal API: each user creates a key on Garmin Connect, and the key
reads their own data (SHARPIT-WEBAPP ADR-103). The server stores it encrypted and write-only, and
opens the key form only to allowlisted athletes until Garmin approves SharpIt for the Startup tier,
which brings OAuth. The app needs a way to take the key and to show a linked Garmin, without
becoming a second place the key lives.

## Decision

We will add Garmin to Paramètres › Sources de données as its own source, linked through a
`GarminKeySheet`:

- The « + » sheet offers Garmin only when `GET /api/v1/garmin/connect` answers `available`.
  An older server without the route, or any failure, reads as unavailable.
- The sheet takes the key in a `SecureField` (`textContentType(.password)`, so it can come from
  the password manager) with a link to Garmin's key page. It sends the key once through
  `GarminKeyClient` and stays open with Garmin's reason when the key is refused.
- The app keeps no copy: no Keychain item, no cache. The field is cleared on success.
- A linked Garmin's row reads « Clé ••••1234 » (`ConnectionsReadout.garminKeyLine`). Disconnecting
  goes through `/api/v1/garmin/disconnect`, like the OAuth sources.
- The first pull runs right after linking, as an OAuth source's does.

## Options considered

### Option A — A key sheet in Sources de données (chosen)
Pros: one place for every source; the athlete pastes the key where they manage Strava and Withings;
the server stays the only holder of the key.
Cons: the key has to be copied from Garmin Connect by hand, and renewed when it expires.

### Option B — Keep the key in the Keychain and pull Garmin from the iPhone
Pros: the server never sees the key.
Cons: no Garmin data while the app is closed, and Garmin's parsing would have to be rewritten in
Swift; rejected with web ADR-103's alternative 1.

### Option C — Wait for Garmin's Startup OAuth
Pros: a one-tap « Connecter » like Strava.
Cons: no Garmin until Garmin reviews SharpIt, an unknown delay.

## Consequences

### Positive
- The developer and beta athletes get Garmin back in the app today. Everyone else sees no change.
- When Startup OAuth lands, `DisconnectableSource.garmin` joins `oauthConnectable` and the sheet goes
  away; the row, logo and disconnect stay.

### Negative
- The sheet is a stopgap the public never sees, maintained until Startup.

### Neutral
- `Provider/Garmin` joins the asset catalog, from the web's `garmin.png`.

## References
- SHARPIT-WEBAPP ADR-103
- `docs/adr/0014` (Sources de données)

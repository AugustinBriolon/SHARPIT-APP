# 5. The app starts provider syncs and reads Apple Health

Date: 2026-09-21

## Status

Accepted

## Context

The app read `/api/v1/*` and nothing else. The server pulls Garmin three times a day or when
the athlete presses sync on the web, so a night slept after the last scheduled pull did not
reach the app until the athlete went through the web: watch, Garmin Connect, web, app.

Apple Health is on the phone and Garmin Connect writes to it within seconds of a watch sync,
but it does not carry everything SHARPIT reads from Garmin: no HRV, HRV status, Body
Battery, stress, Garmin sleep score or Training Readiness, and workouts without routes or
streams. Apple Health stores HRV as SDNN where Garmin reports an overnight RMSSD.

The server side of this decision is SHARPIT ADR-043.

## Decision

- Today asks `POST /api/v1/sync` for a pull on launch and on return to the foreground when
  `GET /api/v1/sync-status` says the last pull is over fifteen minutes old, and on every
  pull-to-refresh. It keeps the current data on screen and reloads when the pull ends. A
  quiet line above the verdict says how fresh the data is.
- Apple Health becomes a second source, switched on in Moi. When on, each sync first reads
  the last week of Apple Health on the phone and sends day summaries to
  `POST /api/v1/health-samples`; the server fills only what no provider wrote.
- Before relying on it, Moi offers a diagnostic that reads fourteen days of Apple Health on
  the athlete's own phone and grades each signal SHARPIT uses: covered, partial, missing, or
  without an Apple Health equivalent, with the app that wrote it.
- Garmin stays a provider, connected on the web.

## Options considered

### Option A — Keep the server's schedule
No change. Cons: the app keeps depending on the web for fresh data.

### Option B — App-started sync only
Removes the web step. Cons: data still waits for Garmin's own cloud and the server's pull.

### Option C — App-started sync plus Apple Health as a gap-filling source (chosen)
Fresh data as soon as the watch syncs, for what Apple Health carries, and a path for
athletes without Garmin. Cons: two sources to reconcile; the reconciliation rules live on
the server (ADR-043) and must be kept conservative.

### Option D — Replace Garmin with Apple Health
Simplest pipeline. Cons: loses HRV, readiness, Body Battery, stress, routes and streams —
most of what the recovery and activity screens read.

## Consequences

### Positive
- Opening the app is enough to see last night.
- The diagnostic answers "does Garmin send everything to Apple Health" with the athlete's
  own data instead of forum posts.

### Negative
- HealthKit read access cannot be observed: a refused type reads as missing.
- Apple Health workouts are not sent yet; an Apple Watch–only athlete gets days, not
  sessions.
- A pull can take a minute; the freshness line is the only sign of it.

### Neutral
- The Apple Health switch is a per-device preference kept in `UserDefaults`.

## References
- SHARPIT ADR-043 — native sync and Apple Health
- ADR 0004 — semantic color and a tinted coach pill

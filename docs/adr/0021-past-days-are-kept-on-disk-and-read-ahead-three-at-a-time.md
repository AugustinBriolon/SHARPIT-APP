# 21. Past days are kept on disk and read ahead three at a time

Date: 2026-10-23

## Status

Accepted

## Context

`DayReadCache` keeps every day read (`/api/v1/today`, `sleep`, `recovery`, `effort`,
`adaptation`, `training-load`, `nutrition`) and answers a past day without the server while it
is fresh. It lived in memory only, so every launch started empty, and the first look at an older
day waited on the network again. That is the case the athlete called slow.

`DayResourceStore` also read days ahead of the athlete: the two neighbours of the day on screen,
and up to six recent days with data. It read them one after the other, so six days cost six
round trips in series.

The server side of the same problem (past days rebuilt on each read) is SHARPIT-WEBAPP ADR-101.

## Decision

We will keep past days' answers on disk and read days ahead in parallel.

- `DayReadCache.keep(_:day:data:)` writes the bytes the server sent for a day before today to
  `ActivityDiskCache` under a new `.dayRead` kind. It does not re-encode them: most wire types are
  decode-only, and the server's bytes are the truest copy (`docs/adr/0007`).
- `settled` and `lastKnown` fall back to the disk when memory has nothing, and bring the day back
  into memory.
- A copy on disk is fresh when it was written after the last `expireAll()`. That instant is a
  stamp in `UserDefaults` (`sharpit.dayReads.expiredAt`). Every write from the app still expires
  all days, as before. A stale copy still paints at once while the day is read again.
- Today is never written to disk: it still changes, and `TodaySnapshotRepository` already covers
  its offline paint.
- Only `DayReadCache.shared` has a disk. Instances built in tests stay in memory unless they are
  given one.
- `DayResourceStore` reads days ahead `prefetchWidth` (3) at a time through a task group.

## Options considered

### Option A — Raw bytes in `ActivityDiskCache` (chosen)

Pros: reuses the store that already has Application Support placement, file protection until
first unlock, backup exclusion (`docs/adr/0017`) and the sign-out wipe (`LocalAccountData`). It
needs no schema, and needs no `Encodable` conformance on the wire types.
Cons: the files are not indexed. Clearing old days needs a sweep if the folder ever grows large.

### Option B — A row per day in SwiftData (`CachedResponse`)

Pros: one model already exists for cached answers.
Cons: `DayReadCache` is `nonisolated` and is called from the `SharpitClient` actor, while a
`ModelContext` belongs to one actor, so every read would need to hop to it. It would also need
one key per payload type and day.

### Option C — `URLCache` with HTTP cache headers from the server

Pros: no client cache code.
Cons: it cannot mark everything stale on a write while still painting the stale copy. Its
eviction is opaque. The response carries the athlete's health data, and only part of it would be
wiped at sign-out.

## Consequences

### Positive
- After a relaunch, a past day opened before shows without a request until the app's next write.
- Reading six days ahead takes about two round trips instead of six.

### Negative
- One file per payload type and day stays in Application Support until sign-out. At a few KB
  per file, a year of browsing every screen is in the tens of MB.
- A Health upload or a sync makes every stored day stale. The next opening of each day still
  paints at once, then reads it again.

### Neutral
- The stores read ahead with the token they got once, instead of asking for a token per day.

## References
- SHARPIT-WEBAPP ADR-101 — settled days are read, not rebuilt
- `docs/adr/0007`, `docs/adr/0009`, `docs/adr/0017`

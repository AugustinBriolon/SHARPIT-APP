# 7. iCloud replicates the read cache only

Date: 2026-09-21

## Status

Accepted

## Context

The app keeps a local read cache so a screen paints before the network answers. It holds two
models: `TodayDaySnapshot`, the raw `V1TodayResponse` for a training day, and
`JournalDaySnapshot`, added alongside this decision, holding a day's journal entry, its
preferences and its derived checklist. Both are read on `load()` and overwritten by whatever
the server answers.

The domain itself is not local. The journal, the athlete profile, the thresholds and the plan
live server-side, scoped per athlete through the Clerk session, and every write from the phone
goes to `/api`. Two signed-in devices therefore already see the same data — the server is what
synchronises them, and has been since the first screen.

What the server does not do is make a *fresh* device instant. An athlete who installs the app
on a second phone, or reinstalls it, has an empty cache: every screen shows its skeleton until
the first round trip completes. The same is true of a device that has been offline since before
a day changed.

Three constraints shape what CloudKit can be used for here:

- **CloudKit refuses several SwiftData features.** No `#Unique` constraints, no non-optional
  attribute without a default, no non-optional relationship. `TodayDaySnapshot` currently
  declares `#Unique<TodayDaySnapshot>([\.trainingDayId])`, so it cannot replicate as written.
- **The cache holds health data.** Sleep durations, weight, resting heart rate and the
  athlete's own journal answers about medication, menstruation and alcohol.
- **A replicated cache can be stale.** Two devices can both hold a row for the same day,
  written at different times, and neither knows about the other's until CloudKit syncs.

The signing team (`6X5CP5SFAG`) is a paid Apple Developer account, so CloudKit is available:
its Xcode-managed provisioning profile carries `TimeToLive 365`, where a free account is capped
at 7 days. This was verified before choosing, because a free account would have made the
decision moot.

## Decision

- **CloudKit replicates the local read cache, and nothing else.** `SharpitPersistence`
  configures its `ModelContainer` with `cloudKitDatabase: .private(…)`, covering
  `TodayDaySnapshot` and `JournalDaySnapshot`.
- **The server remains the single source of truth.** A write goes to `/api` and only to
  `/api`. The cache is written from the server's echo, never merged with it, so a replicated
  row can be overwritten but never wins.
- **The private database, never the public one.** The cache holds the athlete's health data; it
  belongs in their own iCloud account and is readable by nobody else, including us.
- **`#Unique` is replaced by uniqueness on read.** `TodayDaySnapshot` drops its constraint and
  both repositories resolve a day the same way: fetch every row for that `trainingDayId` sorted
  by `fetchedAt` descending, return the newest, delete the rest. Deduplication happens on the
  read path because that is the only place both rows are visible at once.
- **Every cache attribute has a default and every payload is optional.** Required by CloudKit,
  and honest besides: a day whose preferences were cached but whose entry read failed is a real
  state.
- **Offline behaviour does not change.** The cache paints the screen and the app still refreshes
  from the network on every appearance.

## Options considered

### Option A — Do nothing; the server already synchronises
The journal, profile and thresholds are athlete-scoped server-side, so two devices agree
already. Pros: no entitlement, no schema change, no new failure mode. Cons: a fresh or
reinstalled device shows skeletons until its first round trip, which is exactly the delay the
journal's cache was added to remove — on a new phone the cache is empty and the work buys
nothing.

### Option B — CloudKit on SwiftData, for the cache only (chosen)
The two snapshot models replicate through the athlete's private database; the domain keeps
travelling over `/api`. Pros: a second device paints a real day on first open; one mechanism
covers both existing caches and any future one; the sync is Apple's, not ours to operate.
Cons: `TodayDaySnapshot` loses a constraint that works today, and the deduplication that
replaces it is code we now own; the schema becomes less expressive for every future model; a
migration, so it needs testing against an existing store rather than only in memory.

### Option C — `NSUbiquitousKeyValueStore` for local-only preferences
Replicate only what exists nowhere else: the Apple Health toggle, `SharpitWinStore` state,
future appearance settings. Pros: no schema impact at all, no entitlement beyond key-value
storage, nothing to deduplicate. Cons: it carries a handful of small values, not a day
snapshot, so it does not address the cold-start delay. Worth doing later for those values; it
is not an alternative to this decision.

### Option D — Make CloudKit the sync mechanism for journal answers
Let the athlete's answers live in CloudKit and reconcile with the server. Pros: answers would
survive with no server round trip. Cons: a second source of truth for data the server already
owns. A device offline since yesterday would hold answers the athlete has since changed on the
web, and on reconnection CloudKit would resurrect them — the athlete would watch a corrected
answer revert. Rejected.

## Consequences

### Positive
- A second signed-in device paints a real Today and a real journal on first open, instead of
  five empty plates.
- A reinstall no longer starts from nothing.
- One cache mechanism for both screens, and for whatever caches next.

### Negative
- `TodayDaySnapshot` loses `#Unique`, so duplicate rows become possible and the repositories
  must handle them. A bug in that deduplication shows up as a stale day, which is harder to
  notice than a constraint violation.
- Enabling CloudKit on an existing store is a schema migration: it has to be tested against a
  store written by the current build, not only against an in-memory one.
- Replication itself cannot be tested in CI. Only the deduplication and the schema build are
  verifiable there; the sync needs two signed devices and a manual check.
- The build now depends on a paid developer account. A contributor on a free account can run
  the tests but cannot run the app on a device.

### Neutral
- The cache stays what it was: a way to paint a screen early. Every screen must still render
  correctly from an empty cache, because the first launch has one.
- Apple Health remains gap-filling only, and Garmin remains the reference
  ([ADR 0005](0005-app-started-sync-and-apple-health.md)). This decision changes where the
  cache lives, not where a measurement comes from.

## References
- `SHARPIT-APP/Persistence/TodayDaySnapshot.swift` — the container, and the `#Unique` this removes
- `SHARPIT-APP/Persistence/JournalDaySnapshot.swift` — the journal's cache and its read-path deduplication
- [ADR 0005](0005-app-started-sync-and-apple-health.md) — app-started sync and Apple Health as a gap filler
- https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices — the CloudKit constraints on a SwiftData schema

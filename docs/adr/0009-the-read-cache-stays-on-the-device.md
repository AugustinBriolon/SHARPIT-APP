# 9. The read cache stays on the device

Date: 2026-10-01

## Status

Accepted

Supersedes [ADR-0007](0007-icloud-replicates-the-read-cache-only.md)

## Context

[ADR-0007](0007-icloud-replicates-the-read-cache-only.md) replicated the SwiftData read cache
through the athlete's private CloudKit database, so a second or reinstalled iPhone painted a
real day on first open.

Preparing the App Store submission showed what that cache holds. Every model carries
health-derived data:

- `TodayDaySnapshot` — the day's verdict, sleep and recovery gauges;
- `JournalDaySnapshot` — the athlete's own answers on medication, menstruation and alcohol;
- `CachedResponse` — the health overview, body composition, sleep and recovery answers.

Some of it is read from HealthKit (sleep, resting heart rate, HRV). App Review guideline 5.1.3
and the HealthKit terms forbid storing personal health information in iCloud. The private
database does not make it acceptable: the rule is about where the data lives, not who can read
it. A rejection on this point would block the launch.

The server is already the source of truth and already synchronises devices: every screen
refreshes from `/api` on appearance. What CloudKit added was only the first paint on a fresh
device.

## Decision

- **The SwiftData container is device-only:** `cloudKitDatabase: .none`, whether in memory or
  on disk.
- **The iCloud entitlements are removed** (`icloud-services`, `icloud-container-identifiers`),
  so turning replication back on takes a deliberate entitlement change, which a test guards.
- **Settings loses « Synchronisation iCloud »** and `CloudSyncMonitor`: there is nothing left
  to report.
- **The schema keeps its CloudKit shape** (no `#Unique`, defaults everywhere, optional
  payloads) and the read-path deduplication. Existing stores open without a migration, and the
  deduplication costs nothing.

## Options considered

### Option A — Keep CloudKit, and exclude health-derived models
Split the container into a replicated configuration and a local one. Pros: keeps the fresh
device paint for whatever is not health data. Cons: every cached model holds health data, so
the replicated configuration would be empty; a future model would have to be classified
correctly, or a breach of the guideline would ship silently.

### Option B — Keep CloudKit, encrypt the payloads with a key kept in the keychain
Pros: iCloud would only hold ciphertext. Cons: a keychain item that syncs puts the key in
iCloud too, and one that does not cannot decrypt on the second device, which defeats the
purpose. It also adds key management to a cache whose only job is speed.

### Option C — No iCloud at all (chosen)
Pros: complies by construction; removes an entitlement, a monitor, a settings page and a
failure mode; nothing to classify for future models. Cons: a fresh or reinstalled iPhone shows
skeletons until its first round trip, as before ADR-0007.

## Consequences

### Positive
- No health data leaves the iPhone except to SHARPIT's own server, which the privacy policy and
  App Privacy answers already describe.
- One fewer entitlement, background push and Settings page to explain at review.

### Negative
- A new or reinstalled device paints from the network only: skeletons for one round trip on
  first open.
- Athletes who updated keep their iCloud copy until they delete it from iCloud settings; the app
  no longer reads or writes it.

### Neutral
- `remote-notification` stays as a background mode: the morning-verdict push still needs it.
- The app no longer needs CloudKit on the App ID; it can stay enabled there harmlessly.

## References
- [ADR-0007](0007-icloud-replicates-the-read-cache-only.md) — the decision this supersedes
- `SHARPIT-APP/Persistence/TodayDaySnapshot.swift` — `SharpitPersistence.configuration`
- https://developer.apple.com/app-store/review/guidelines/#health-and-health-research — guideline 5.1.3

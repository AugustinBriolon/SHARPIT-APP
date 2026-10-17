# 17. Local health files stay out of device backups

Date: 2026-10-17

## Status

Accepted

Extends [ADR-0009](0009-the-read-cache-stays-on-the-device.md)

## Context

[ADR-0009](0009-the-read-cache-stays-on-the-device.md) took the SwiftData read cache off CloudKit
because it holds health-derived data — sleep, recovery, weight, the athlete's journal answers —
and App Review guideline 5.1.3 and the HealthKit terms forbid storing it in iCloud.

A privacy review found that the same data still reached iCloud by another road: an iCloud device
backup, or an unencrypted Finder backup, copies `Library/Application Support` — the app's own and
the App Group's. Three stores live there:

- the SwiftData store (`default.store` and its `-wal` / `-shm` companions, in the App Group
  container since the app has the `group.app.sharpit.ios` entitlement);
- `ActivityCache/`, the raw detail and streams of each session (GPS track, heart rate);
- `WellnessCheckInLocal.json`, the « Ressenti du jour » draft (feeling, energy, soreness, stress,
  free notes).

None of them is the truth: the server holds every value, and a restored iPhone repaints from `/api`
on first open.

## Decision

- Each of the three stores is flagged `isExcludedFromBackup` through one helper,
  `BackupExclusion` (`SHARPIT-APP/Persistence/BackupExclusion.swift`).
- **SwiftData store:** after the container opens on disk, the store file and its `-wal` / `-shm`
  files are flagged, at every launch, since SQLite may recreate the journal files.
- **Activity cache:** the `ActivityCache` directory is flagged, so files written atomically inside it
  inherit the exclusion.
- **Wellness draft:** the file is flagged after each write, since an atomic write replaces the file
  and drops the flag.
- Tests guard each store, including the real store the host app opened at launch
  (`BackupExclusionTests`).

## Options considered

### Option A — Flag each store (chosen)
Pros: only health-derived files are excluded; anything later added to Application Support that
should survive a restore is backed up by default. Cons: a new store must remember to call
`BackupExclusion`, and atomic writes force re-flagging single files.

### Option B — Flag the whole `Application Support` directory once
Pros: one line, covers future stores automatically. Cons: silently excludes anything else written
there later, including data a restore should keep; the reason for the exclusion is invisible at the
store that needs it.

### Option C — Move the stores to `Caches`
Pros: `Caches` is never backed up. Cons: iOS purges it under storage pressure, which defeats
`ActivityDiskCache`'s purpose (a session opened last week opens instantly, offline included), and
moving the SwiftData store orphans the existing one, which would still be backed up.

## Consequences

### Positive
- No health-derived file from the app reaches an iCloud or Finder backup; the only copy off the
  iPhone is SHARPIT's own server, as the privacy policy says.
- Backups shrink by the size of the activity cache (streams are the heaviest payloads in the app).

### Negative
- A restored or migrated iPhone shows skeletons for one round trip and re-downloads opened
  activities; an unsent « Ressenti du jour » draft is lost on restore.
- A future local store holding health data must call `BackupExclusion` itself.

### Neutral
- File protection stays `completeUntilFirstUserAuthentication`, so lock-screen widgets still read
  their snapshot.
- The widget snapshot in the App Group container is not covered here.

## References
- [ADR-0009](0009-the-read-cache-stays-on-the-device.md) — the read cache stays on the device
- https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup
- https://developer.apple.com/app-store/review/guidelines/#health-and-health-research — guideline 5.1.3

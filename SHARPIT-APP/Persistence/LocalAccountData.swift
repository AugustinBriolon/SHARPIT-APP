import Foundation
import SwiftData
import WidgetKit

/// What this iPhone keeps for the signed-in athlete — the day snapshots, cached answers and
/// activity files — belongs to the account that wrote it.
///
/// None of it is keyed by account, so another account signing in on the same iPhone would be
/// painted from the previous one's data. The owner is remembered; a different account wipes
/// everything first, and so does deleting the account or a hard session expiry.
@MainActor
enum LocalAccountData {
    static let ownerKey = "sharpit.localData.owner"
    /// One-shot wipe of full `V1TodayResponse` snapshots → reduced glossary-only cache.
    static let todaySnapshotSchemaKey = "sharpit.todaySnapshot.v2"

    /// Called with the signed-in account. The first account seen by a version that did not
    /// record owners keeps what is there.
    static func claim(
        userId: String?,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        disk: ActivityDiskCache = .shared
    ) {
        migrateTodaySnapshotsIfNeeded(context: context, defaults: defaults)
        guard let userId else { return }
        if let owner = defaults.string(forKey: ownerKey), owner != userId {
            erase(context: context, defaults: defaults, disk: disk)
        }
        defaults.set(userId, forKey: ownerKey)
    }

    /// Everything, now — SwiftData rows, disk caches, drafts, BLE preference, widgets.
    static func erase(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        disk: ActivityDiskCache = .shared
    ) {
        // A batch delete runs on the store: pending inserts would survive it unsaved.
        try? context.save()
        try? context.delete(model: TodayDaySnapshot.self)
        try? context.delete(model: JournalDaySnapshot.self)
        try? context.delete(model: CachedResponse.self)
        try? context.save()
        eraseWithoutSwiftData(defaults: defaults, disk: disk)
    }

    /// Disk / preference wipe when no `ModelContext` is bound yet (or after it was cleared).
    static func eraseWithoutSwiftData(
        defaults: UserDefaults = .standard,
        disk: ActivityDiskCache = .shared
    ) {
        disk.removeAll()
        WellnessCheckInLocalStore.shared.erase()
        GuidedHeartRatePreference.clear()
        defaults.removeObject(forKey: ownerKey)
        WidgetSnapshotPublisher.erase()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Drops legacy full-payload Today snapshots once; new rows store glossary codes only.
    static func migrateTodaySnapshotsIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: todaySnapshotSchemaKey) else { return }
        try? context.delete(model: TodayDaySnapshot.self)
        try? context.save()
        defaults.set(true, forKey: todaySnapshotSchemaKey)
    }
}

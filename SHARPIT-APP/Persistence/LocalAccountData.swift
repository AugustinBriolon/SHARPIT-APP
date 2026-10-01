import Foundation
import SwiftData

/// What this iPhone keeps for the signed-in athlete — the day snapshots, cached answers and
/// activity files — belongs to the account that wrote it.
///
/// None of it is keyed by account, so another account signing in on the same iPhone would be
/// painted from the previous one's data. The owner is remembered; a different account wipes
/// everything first, and so does deleting the account.
@MainActor
enum LocalAccountData {
    static let ownerKey = "sharpit.localData.owner"

    /// Called with the signed-in account. The first account seen by a version that did not
    /// record owners keeps what is there.
    static func claim(
        userId: String?,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        disk: ActivityDiskCache = .shared
    ) {
        guard let userId else { return }
        if let owner = defaults.string(forKey: ownerKey), owner != userId {
            erase(context: context, disk: disk)
        }
        defaults.set(userId, forKey: ownerKey)
    }

    /// Everything, now.
    static func erase(context: ModelContext, defaults: UserDefaults = .standard, disk: ActivityDiskCache = .shared) {
        // A batch delete runs on the store: pending inserts would survive it unsaved.
        try? context.save()
        try? context.delete(model: TodayDaySnapshot.self)
        try? context.delete(model: JournalDaySnapshot.self)
        try? context.delete(model: CachedResponse.self)
        try? context.save()
        disk.removeAll()
        defaults.removeObject(forKey: ownerKey)
        // The home screen too: another athlete's day never shows on it.
        WidgetSnapshotPublisher.erase()
    }
}

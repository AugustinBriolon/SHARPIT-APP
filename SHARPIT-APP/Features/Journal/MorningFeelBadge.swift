import UIKit

/// App-icon badge for the morning-feel / morning-verdict reminder.
///
/// Cleared the moment the athlete taps « Enregistrer » on Ressenti du jour; restored
/// if the server refuses so the reminder comes back with the sheet. Never logs counts
/// or athlete data.
@MainActor
final class MorningFeelBadge {
    static let shared = MorningFeelBadge()

    /// Count snapshotted before an optimistic clear — restored on failure.
    private var snapshot: Int?
    private let readCount: () -> Int
    private let writeCount: (Int) -> Void

    init(
        readCount: @escaping () -> Int = { UIApplication.shared.applicationIconBadgeNumber },
        writeCount: @escaping (Int) -> Void = { UIApplication.shared.applicationIconBadgeNumber = $0 }
    ) {
        self.readCount = readCount
        self.writeCount = writeCount
    }

    /// Whether a clear is waiting on server confirmation (tests / host coordination).
    var isAwaitingConfirmation: Bool { snapshot != nil }

    /// Hides the badge at once. Remembers the previous count for a possible restore.
    func clearOptimistically() {
        if snapshot == nil {
            snapshot = readCount()
        }
        writeCount(0)
    }

    /// Puts the badge back after a failed save. Uses at least 1 when none was snapshotted.
    func restore() {
        writeCount(max(snapshot ?? 1, 1))
        snapshot = nil
    }

    /// Server confirmed — leave the badge at 0.
    func confirmCleared() {
        snapshot = nil
    }
}

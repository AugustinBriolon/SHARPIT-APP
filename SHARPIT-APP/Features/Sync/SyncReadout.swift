import Foundation

/// The line that says how fresh the data is.
enum SyncReadout {
    static func caption(state: ProviderSyncStore.State, lastSyncAt: Date?, now: Date = .now) -> String? {
        switch state {
        case .syncing:
            return String(localized: "Synchronisation…")
        case .failed:
            return String(localized: "Synchronisation impossible")
        case .idle:
            guard let lastSyncAt else { return nil }
            return String(localized: "Synchronisé ") + age(of: lastSyncAt, now: now)
        }
    }

    static func age(of date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60:
            return String(localized: "à l'instant")
        case ..<3_600:
            return String(localized: "il y a \(Int(seconds / 60)) min")
        case ..<86_400:
            return String(localized: "il y a \(Int(seconds / 3_600)) h")
        default:
            return "le " + date.sharpitFormatted(.dateTime.day().month(.abbreviated))
        }
    }
}

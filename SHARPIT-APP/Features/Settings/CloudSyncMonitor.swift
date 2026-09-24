import CloudKit
import CoreData
import Foundation
import Observation

/// What the iCloud copy of the cache last did — set up, sent, received — and whether it worked.
///
/// SwiftData replicates through `NSPersistentCloudKitContainer`, which announces every
/// operation on `eventChangedNotification`. Nothing else in the app hears them, so this keeps
/// the last finished one of each kind, persisted so Synchronisation iCloud can say "il y a
/// 3 h" on the next launch rather than "jamais" until the next export (`docs/adr/0007`).
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor()

    nonisolated enum Kind: String, CaseIterable, Sendable {
        case setup
        case importing = "import"
        case exporting = "export"

        var label: String {
            switch self {
            case .setup: "Configuration"
            case .importing: "Dernière réception"
            case .exporting: "Dernier envoi"
            }
        }
    }

    nonisolated struct Event: Codable, Equatable, Sendable {
        let endedAt: Date
        let succeeded: Bool
        let errorDescription: String?
    }

    private(set) var events: [Kind: Event] = [:]
    private(set) var accountStatus: CKAccountStatus?

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for kind in Kind.allCases {
            if let data = defaults.data(forKey: Self.key(kind)),
               let event = try? JSONDecoder().decode(Event.self, from: data) {
                events[kind] = event
            }
        }
    }

    /// Starts listening. Called once at launch; a second call does nothing.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                let endedAt = event.endDate
            else { return }
            let kind: Kind = switch event.type {
            case .setup: .setup
            case .`import`: .importing
            case .export: .exporting
            @unknown default: .setup
            }
            let recorded = Event(
                endedAt: endedAt,
                succeeded: event.succeeded,
                errorDescription: event.error?.localizedDescription
            )
            MainActor.assumeIsolated { self?.record(recorded, as: kind) }
        }
    }

    func refreshAccountStatus() async {
        accountStatus = try? await CKContainer(identifier: SharpitPersistence.cloudKitContainerId).accountStatus()
    }

    /// The error of the latest operation, when it failed — an old failure since followed by a
    /// success is history, not a problem.
    var lastError: String? {
        guard let latest = events.values.max(by: { $0.endedAt < $1.endedAt }), !latest.succeeded else {
            return nil
        }
        return latest.errorDescription ?? "Erreur inconnue"
    }

    func record(_ event: Event, as kind: Kind) {
        events[kind] = event
        if let data = try? JSONEncoder().encode(event) {
            defaults.set(data, forKey: Self.key(kind))
        }
    }

    private static func key(_ kind: Kind) -> String { "sharpit.cloudSync.\(kind.rawValue)" }
}

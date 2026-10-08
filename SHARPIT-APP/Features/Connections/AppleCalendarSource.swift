import Foundation
import Observation

/// Apple Calendar as a SHARPIT source — linked from the phone like Apple Health (ADR-054).
/// EventKit access plus `POST /api/v1/apple-calendar/link`; write and busy upload follow source prefs.
@MainActor
@Observable
final class AppleCalendarSource {
    enum State: Equatable {
        case idle
        case failed(String)
    }

    private(set) var isLinked: Bool = false
    private(set) var state: State = .idle

    private let sync: AppleCalendarSync
    private let client: any AppleCalendarLinking
    private let defaults: UserDefaults
    private var userId: String?

    init(
        sync: AppleCalendarSync = .shared,
        client: any AppleCalendarLinking = SharpitClient(),
        defaults: UserDefaults = .standard
    ) {
        self.sync = sync
        self.client = client
        self.defaults = defaults
    }

    static func linkedKey(userId: String) -> String { "appleCalendarLinked.\(userId)" }

    func bind(userId: String?) {
        self.userId = userId
        guard let userId else {
            isLinked = false
            return
        }
        isLinked = defaults.bool(forKey: Self.linkedKey(userId: userId))
    }

    /// Calendrier permission, then tell the web the source is on.
    func enable(token: @escaping () async throws -> String) async {
        guard await sync.requestAccess() else {
            state = .failed("Accès refusé : autorise SharpIt dans Réglages › Confidentialité › Calendriers.")
            return
        }
        setLinked(true)
        state = .idle
        await link(true, token: token)
    }

    func disable(token: @escaping () async throws -> String) async {
        setLinked(false)
        state = .idle
        await link(false, token: token)
    }

    private func setLinked(_ linked: Bool) {
        isLinked = linked
        guard let userId else { return }
        defaults.set(linked, forKey: Self.linkedKey(userId: userId))
    }

    private func link(_ linked: Bool, token: @escaping () async throws -> String) async {
        _ = try? await SharpitRetry.run {
            try await client.linkAppleCalendar(linked, token: try await token())
        }
    }

    /// After one-time migration from Paramètres › Calendrier de l'iPhone.
    func adoptLegacyMigration() {
        setLinked(true)
    }
}

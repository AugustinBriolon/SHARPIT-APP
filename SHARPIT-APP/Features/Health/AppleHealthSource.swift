import Foundation
import Observation

/// Apple Health as a source of SHARPIT data, beside Garmin.
///
/// When the athlete turns it on, the app reads the last week of Apple Health on each sync
/// and sends day summaries to the server, which fills only what no provider wrote
/// (ADR-043 on the web). Garmin stays the reference; Apple Health closes the gap until
/// Garmin's next pull, and covers athletes who have no Garmin at all.
@MainActor
@Observable
final class AppleHealthSource {
    enum State: Equatable {
        case idle
        case sending
        case failed(String)
    }

    /// Before the switch was kept per account: one value for the whole iPhone.
    static let legacyEnabledKey = "appleHealthEnabled"
    /// A week: long enough to catch a night Garmin missed, short enough to send in one go.
    static let lookbackDays = 7

    private(set) var isEnabled: Bool
    private(set) var state: State = .idle
    private(set) var lastSentAt: Date?

    private let reader: any HealthReading
    private let client: any HealthUploadServing
    private let defaults: UserDefaults
    private let now: () -> Date
    /// The account the switch belongs to: a new account on this iPhone starts with it off, so
    /// no Health data reaches an account that never asked for it.
    private var userId: String?

    init(
        reader: any HealthReading,
        client: any HealthUploadServing,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.client = client
        self.defaults = defaults
        self.now = now
        isEnabled = false
    }

    static func enabledKey(userId: String) -> String { "appleHealthEnabled.\(userId)" }

    /// Reads the switch of the signed-in account. The iPhone-wide value of earlier versions goes
    /// to the first account read, and is then forgotten.
    func bind(userId: String?) {
        self.userId = userId
        guard let userId else {
            isEnabled = false
            return
        }
        let key = Self.enabledKey(userId: userId)
        if defaults.object(forKey: key) == nil, defaults.object(forKey: Self.legacyEnabledKey) != nil {
            defaults.set(defaults.bool(forKey: Self.legacyEnabledKey), forKey: key)
            defaults.removeObject(forKey: Self.legacyEnabledKey)
        }
        isEnabled = defaults.bool(forKey: key)
    }

    var isAvailable: Bool { reader.isAvailable }

    /// Asks for Health access, then sends the first week.
    func enable(token: @escaping () async throws -> String) async {
        guard reader.isAvailable else {
            state = .failed("Apple Santé n'est pas disponible sur cet appareil.")
            return
        }
        do {
            try await reader.requestAuthorization()
        } catch {
            state = .failed("Accès à Apple Santé refusé.")
            return
        }
        setEnabled(true)
        _ = await send(token: token)
    }

    func disable() {
        setEnabled(false)
        state = .idle
    }

    /// Sends the last week when the source is on. True when the server changed a day, so
    /// the caller reloads what it shows.
    func send(token: @escaping () async throws -> String) async -> Bool {
        guard isEnabled, state != .sending else { return false }
        state = .sending
        let since = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: now()) ?? now()
        let days = await reader.dailySummaries(since: since)
        guard !days.isEmpty else {
            state = .idle
            return false
        }
        do {
            let updated = try await client.uploadHealth(days, token: try await token())
            lastSentAt = now()
            state = .idle
            return updated > 0
        } catch let error as SharpitAPIError where error == .rateLimited {
            state = .idle
            return false
        } catch {
            state = .failed("Envoi Apple Santé impossible.")
            return false
        }
    }

    private func setEnabled(_ value: Bool) {
        isEnabled = value
        guard let userId else { return }
        defaults.set(value, forKey: Self.enabledKey(userId: userId))
    }
}

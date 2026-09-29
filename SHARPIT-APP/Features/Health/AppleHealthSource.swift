import Foundation
import Observation

/// Apple Health as a source of SHARPIT data, beside Garmin.
///
/// When the athlete turns it on, the app sends the last year of Apple Health, then on each sync
/// what came in since: day summaries, which the server writes only where no provider did, and
/// workouts, which become activities while no Garmin or Strava account is connected (ADR-043 on
/// the web). Garmin stays the reference; an athlete with an Apple Watch alone gets everything
/// from here.
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
    /// What switching the source on sends: a year, the history an athlete without Garmin has.
    static let historyDays = 365
    /// The server's limits per call: 31 days, 10 workouts — 5 keeps a call with long streams
    /// well under the request size the host accepts.
    static let dayBatch = 31
    static let workoutBatch = 5
    static let workoutWindowDays = 30

    private(set) var isEnabled: Bool
    private(set) var state: State = .idle
    private(set) var lastSentAt: Date?

    private let reader: any HealthReading
    private let client: any HealthUploadServing
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar = Calendar.current
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

    /// Asks for Health access, then sends the last year — the history an athlete without Garmin
    /// has nowhere else — and from then on what is new.
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
        if marker(.days) == nil { setMarker(.days, historyStart) }
        if marker(.workouts) == nil { setMarker(.workouts, historyStart) }
        _ = await send(token: token)
    }

    func disable() {
        setEnabled(false)
        state = .idle
    }

    /// Sends what Apple Health holds since the last send, when the source is on: the days (the
    /// last week at least, so a night filled late still arrives), then the workouts. True when
    /// the server changed something, so the caller reloads what it shows.
    ///
    /// Each batch moves its marker forward once the server has it, so a send cut short — the app
    /// closed, the server's limit reached — picks up where it stopped.
    func send(token: @escaping () async throws -> String) async -> Bool {
        guard isEnabled, state != .sending else { return false }
        state = .sending
        // Asks only for the types added since the athlete last answered; silent otherwise.
        try? await reader.requestAuthorization()
        do {
            let daysChanged = try await sendDays(token: token)
            let workoutsChanged = try await sendWorkouts(token: token)
            lastSentAt = now()
            state = .idle
            return daysChanged || workoutsChanged
        } catch let error as SharpitAPIError where error == .rateLimited {
            // The rest goes with the next send.
            state = .idle
            return false
        } catch {
            state = .failed("Envoi Apple Santé impossible.")
            return false
        }
    }

    private func sendDays(token: @escaping () async throws -> String) async throws -> Bool {
        let lastWeek = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now()) ?? now()
        let since = min(marker(.days) ?? lastWeek, lastWeek)
        let days = await reader.dailySummaries(since: since)
        var changed = false
        for batch in days.chunked(by: Self.dayBatch) {
            let updated = try await SharpitRetry.run {
                try await client.uploadHealth(batch, token: try await token())
            }
            changed = changed || updated > 0
            if let last = batch.last, let date = TrainingDayId.date(last.date) {
                setMarker(.days, max(marker(.days) ?? date, date))
            }
        }
        return changed
    }

    private func sendWorkouts(token: @escaping () async throws -> String) async throws -> Bool {
        let end = now()
        var windowStart = marker(.workouts) ?? calendar.date(byAdding: .day, value: -Self.lookbackDays, to: end) ?? end
        var changed = false
        // A month at a time: a year of workouts with their streams is too much to hold at once.
        while windowStart < end {
            let windowEnd = min(calendar.date(byAdding: .day, value: Self.workoutWindowDays, to: windowStart) ?? end, end)
            let workouts = await reader.workouts(endingIn: DateInterval(start: windowStart, end: windowEnd))
            for batch in workouts.chunked(by: Self.workoutBatch) {
                let result = try await SharpitRetry.run {
                    try await client.uploadWorkouts(batch, token: try await token())
                }
                guard result.acceptsWorkouts else {
                    // Garmin or Strava brings the sessions: what was read is not offered again,
                    // and the next workout asks once more, since the server may take it by then.
                    setMarker(.workouts, end)
                    return changed
                }
                changed = changed || result.imported > 0
                if let last = batch.last { setMarker(.workouts, last.end) }
            }
            setMarker(.workouts, windowEnd)
            windowStart = windowEnd
        }
        return changed
    }

    private func setEnabled(_ value: Bool) {
        isEnabled = value
        guard let userId else { return }
        defaults.set(value, forKey: Self.enabledKey(userId: userId))
    }

    // MARK: - How far each kind was sent, per account

    enum Kind: String {
        case days
        case workouts
    }

    static func markerKey(_ kind: Kind, userId: String) -> String {
        "appleHealthSentThrough.\(kind.rawValue).\(userId)"
    }

    private var historyStart: Date {
        calendar.date(byAdding: .day, value: -Self.historyDays, to: now()) ?? now()
    }

    private func marker(_ kind: Kind) -> Date? {
        guard let userId else { return nil }
        return defaults.object(forKey: Self.markerKey(kind, userId: userId)) as? Date
    }

    private func setMarker(_ kind: Kind, _ date: Date) {
        guard let userId else { return }
        defaults.set(date, forKey: Self.markerKey(kind, userId: userId))
    }
}

extension Array {
    /// The array in consecutive slices of at most `size`.
    nonisolated func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

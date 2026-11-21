import Foundation
import Observation

/// The athlete's training mode, read once and written on every pick.
///
/// There is no explicit save: the web commits the drawer's draft on each meaningful
/// change, and a mode the athlete set but did not confirm would be a lie to the coach.
@MainActor
@Observable
final class ActivityStatusStore {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var store = V1ActivityStatusStore()

    /// The athlete's current training mode — the live read of what the chip carries.
    /// Used by screens that need to warn the athlete about the mode's effect without
    /// offering a second control to change it.
    var current: ActivityStatusId { store.status }

    private let client: any ActivityStatusServing
    private let tokenProvider: () async throws -> String
    /// An in-flight read task; parallel callers wait on the first instead of firing redundant HTTP requests.
    private var inFlight: Task<Void, Never>?
    /// The last store the server answered, read or written: what a failed write goes back to.
    private var confirmed = V1ActivityStatusStore()
    /// Counts the writes, so an older one answering late does not paint over a newer one.
    private var writeGeneration = 0

    init(client: any ActivityStatusServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    /// Reads the mode unless it is already loaded or being loaded.
    func loadIfNeeded() async {
        guard phase != .ready else { return }
        await load()
    }

    func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performLoad() async {
        // A read that crosses a write is stale either way: the write's answer is the newer truth.
        let generation = writeGeneration
        if phase != .ready, phase != .saving { phase = .loading }
        do {
            let token = try await tokenProvider()
            let read = try await client.activityStatus(token: token)
            guard generation == writeGeneration else { return }
            confirmed = read
            store = read
            phase = .ready
        } catch is CancellationError {
        } catch {
            guard generation == writeGeneration else { return }
            phase = .failed(Self.message(for: error, fallback: String(localized: "Ton statut n'a pas pu être chargé.")))
        }
    }

    /// Writes the mode and keeps what the server answers, which may differ — a date
    /// already past comes back as `active`.
    ///
    /// Writes can overlap (a date dialled in the picker sends one per stop): only the newest
    /// one's answer is shown, and a failure falls back to the last store the server confirmed,
    /// never to another write's optimistic state.
    func apply(status: ActivityStatusId, retention: ActivityStatusRetention) async {
        let write = V1ActivityStatusWrite(
            status: status,
            retention: retention,
            travelId: store.travelId
        )
        store = V1ActivityStatusStore(
            status: status,
            retention: status == .active ? .untilModified : retention,
            travelId: status == .paused ? store.travelId : nil
        )
        phase = .saving
        writeGeneration += 1
        let generation = writeGeneration
        do {
            let answer = try await SharpitRetry.run {
                try await client.setActivityStatus(write, token: try await tokenProvider())
            }
            confirmed = answer
            guard generation == writeGeneration else { return }
            store = answer
            phase = .ready
        } catch {
            guard generation == writeGeneration else { return }
            store = confirmed
            phase = .failed(Self.message(for: error, fallback: String(localized: "Ton statut n'a pas pu être enregistré.")))
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return String(localized: "Session expirée. Reconnecte-toi.")
        }
        return fallback
    }
}

/// `yyyy-MM-dd` in the athlete's own calendar, which is what the API stores.
enum ActivityStatusDate {
    nonisolated static func string(from date: Date, calendar: Calendar = .current) -> String {
        APIDate.dayString(date, calendar: calendar)
    }

    nonisolated static func date(from string: String, calendar: Calendar = .current) -> Date? {
        APIDate.day(string, calendar: calendar)
    }

    /// The date a freshly picked deadline starts on. A week out, because a mode ending
    /// today would expire on the next read and read as an accident.
    nonisolated static func defaultUntil(from now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: now) ?? now
    }

    nonisolated static func label(for day: String, calendar: Calendar = .current) -> String {
        guard let date = date(from: day, calendar: calendar) else { return day }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = AppLanguage.locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter.string(from: date)
    }
}

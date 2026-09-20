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

    private let client: any ActivityStatusServing
    private let tokenProvider: () async throws -> String

    init(client: any ActivityStatusServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        if phase != .ready { phase = .loading }
        do {
            let token = try await tokenProvider()
            store = try await client.activityStatus(token: token)
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(Self.message(for: error, fallback: "Ton statut n'a pas pu être chargé."))
        }
    }

    /// Writes the mode and keeps what the server answers, which may differ — a date
    /// already past comes back as `active`.
    func apply(status: ActivityStatusId, retention: ActivityStatusRetention) async {
        let previous = store
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
        do {
            let token = try await tokenProvider()
            store = try await client.setActivityStatus(write, token: token)
            phase = .ready
        } catch {
            store = previous
            phase = .failed(Self.message(for: error, fallback: "Ton statut n'a pas pu être enregistré."))
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return fallback
    }
}

/// `yyyy-MM-dd` in the athlete's own calendar, which is what the API stores.
enum ActivityStatusDate {
    nonisolated static func string(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
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
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter.string(from: date)
    }
}

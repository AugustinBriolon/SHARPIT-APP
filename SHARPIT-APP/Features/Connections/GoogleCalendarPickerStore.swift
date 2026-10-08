import Foundation
import Observation

/// Google calendars the athlete can pick as the write target for créneaux (ADR-040).
@MainActor
@Observable
final class GoogleCalendarPickerStore {
    enum Phase: Equatable {
        case loading
        case ready
        case selecting
        case failed(Failure)
    }

    enum Failure: Equatable {
        case load(String)
        case needsReconnect(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var calendars: [V1GoogleCalendar] = []

    private let client: any GoogleCalendarsServing
    private let tokenProvider: () async throws -> String

    init(
        client: any GoogleCalendarsServing = GoogleCalendarsClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        let phaseBeforeLoad = phase
        phase = .loading
        do {
            let token = try await tokenProvider()
            calendars = try await client.googleCalendars(token: token)
            phase = .ready
        } catch is CancellationError {
            if !calendars.isEmpty {
                phase = .ready
            } else if phaseBeforeLoad != .loading {
                phase = phaseBeforeLoad
            } else {
                phase = .failed(.load("Chargement interrompu. Réessaie."))
            }
        } catch {
            phase = .failed(Self.failure(for: error))
        }
    }

    /// True when the choice is saved and the sheet can close.
    func select(_ calendar: V1GoogleCalendar) async -> Bool {
        guard phase != .selecting, phase != .loading else { return false }
        let phaseBeforeSelect = phase
        phase = .selecting
        do {
            try await SharpitRetry.run {
                try await client.selectGoogleCalendar(
                    calendarId: calendar.id,
                    calendarName: calendar.summary,
                    token: try await tokenProvider()
                )
            }
            calendars = calendars.map { item in
                V1GoogleCalendar(
                    id: item.id,
                    summary: item.summary,
                    primary: item.primary,
                    isTarget: item.id == calendar.id
                )
            }
            phase = .ready
            return true
        } catch is CancellationError {
            phase = phaseBeforeSelect
            return false
        } catch {
            phase = .failed(Self.failure(for: error))
            return false
        }
    }

    private static func failure(for error: Error) -> Failure {
        if case SharpitAPIError.googleNeedsReconnect(let text)? = error as? SharpitAPIError {
            return .needsReconnect(text)
        }
        return .load(SharpitErrorGuidance.message(for: error, subject: "Les calendriers Google"))
    }
}

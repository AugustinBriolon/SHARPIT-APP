import Foundation
import Observation

/// An activity the athlete could say a prescription was carried out by.
struct SessionLinkCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sport: String
    let symbolName: String
    /// "Même jour", "J−1", "J+1" — the gap to the prescription, the way the web says it.
    let dayLabel: String
    let durationLabel: String?

    /// The activities a prescription could be linked to.
    ///
    /// Only unlinked ones, and only within a day either side: the server's own matching stays
    /// on the same day because adjacent days produced false pairings, but the athlete who
    /// picks by hand knows better than a rule, and a session done late or early is common.
    /// Closest day first, then the most recent.
    static func candidates(
        from activities: [V1ActivityListItem],
        around reference: Date,
        calendar: Calendar = .current
    ) -> [SessionLinkCandidate] {
        let referenceDay = calendar.startOfDay(for: reference)

        return activities
            .filter { $0.plannedSession == nil }
            .compactMap { activity -> (SessionLinkCandidate, dayGap: Int, date: Date)? in
                let day = calendar.startOfDay(for: activity.date)
                guard let gap = calendar.dateComponents([.day], from: referenceDay, to: day).day,
                      abs(gap) <= 1
                else { return nil }

                let candidate = SessionLinkCandidate(
                    id: activity.id,
                    title: activity.title ?? activity.type.label,
                    sport: activity.type.label,
                    symbolName: activity.type.symbolName,
                    dayLabel: Self.dayLabel(forGap: gap),
                    durationLabel: activity.duration.map(ActivityFormat.duration)
                )
                return (candidate, abs(gap), activity.date)
            }
            .sorted { ($0.dayGap, $1.date) < ($1.dayGap, $0.date) }
            .map(\.0)
    }

    private static func dayLabel(forGap gap: Int) -> String {
        switch gap {
        case 0: "Même jour"
        case ..<0: "J−1"
        default: "J+1"
        }
    }
}

/// Links one prescription to an activity the athlete picks.
@MainActor
@Observable
final class SessionLinkStore {
    enum Phase: Equatable {
        case loading
        case ready
        case linking
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var candidates: [SessionLinkCandidate] = []

    private let sessionId: String
    private let referenceDate: Date
    private let activities: any ActivityServing
    private let linker: any PlannedSessionLinking
    private let tokenProvider: () async throws -> String
    private let calendar: Calendar

    init(
        sessionId: String,
        referenceDate: Date,
        activities: any ActivityServing,
        linker: any PlannedSessionLinking,
        tokenProvider: @escaping () async throws -> String,
        calendar: Calendar = .current
    ) {
        self.sessionId = sessionId
        self.referenceDate = referenceDate
        self.activities = activities
        self.linker = linker
        self.tokenProvider = tokenProvider
        self.calendar = calendar
    }

    func load() async {
        phase = .loading
        do {
            let token = try await tokenProvider()
            let all = try await activities.activities(token: token)
            candidates = SessionLinkCandidate.candidates(from: all, around: referenceDate, calendar: calendar)
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(Self.message(for: error, fallback: "Tes séances réalisées n'ont pas pu être chargées."))
        }
    }

    /// True when the link is made. On failure the phase says why and the list stays as it was.
    func link(_ candidate: SessionLinkCandidate) async -> Bool {
        // A failed attempt leaves the list on screen, so trying another candidate is allowed.
        guard phase != .linking, phase != .loading else { return false }
        phase = .linking
        do {
            let token = try await tokenProvider()
            try await linker.link(sessionId: sessionId, activityId: candidate.id, token: token)
            // Every list read after this would otherwise repeat the answer from before.
            await activities.invalidateActivities()
            phase = .ready
            return true
        } catch {
            phase = .failed(Self.message(for: error, fallback: "La liaison n'a pas abouti. Réessaie."))
            return false
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return fallback
    }
}

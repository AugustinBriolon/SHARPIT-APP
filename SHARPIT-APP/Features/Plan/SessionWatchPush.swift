import Foundation

/// Where a planned session stands on the athlete's Garmin watch.
enum WatchPushState: Equatable {
    case notSent
    case sent
    /// Sent, then moved to another day: the watch still offers the old one.
    case moved

    /// The day is read in the calendar the plan is shown in, as Plan places the session.
    static func of(
        garminWorkoutId: String?,
        scheduledDate: String?,
        sessionDate: Date,
        calendar: Calendar = .current
    ) -> WatchPushState {
        guard garminWorkoutId != nil else { return .notSent }
        let day = calendar.dateComponents([.year, .month, .day], from: sessionDate)
        let key = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return scheduledDate == key ? .sent : .moved
    }

    /// The sports the Training API takes for now (SHARPIT ADR-106): strength and bricks wait.
    static func canSend(type: String?) -> Bool {
        ["RUN", "BIKE", "SWIM"].contains(type?.uppercased() ?? "")
    }

    /// The « … » entry says where the session stands: a resend is what is offered once sent.
    var menuTitle: String {
        self == .notSent
            ? String(localized: "Envoyer sur ma montre")
            : String(localized: "Renvoyer sur ma montre")
    }

    var symbolName: String {
        self == .notSent ? "applewatch" : "applewatch.and.arrow.forward"
    }
}

/// What the drawer needs to send its session to the watch; nil where it cannot — Garmin not
/// linked, a sport the watch does not take yet.
struct SessionWatchContext {
    let session: V1PlannedSessionItem
    let client: any GarminWorkoutPushing
    let tokenProvider: () async throws -> String
    /// The session reached the watch; the screen reads its plan again.
    let onSent: () -> Void

    /// Sends the session, and says how it went in the toast's words. The receipt is nil on a
    /// failure.
    func send(replace: Bool) async -> (receipt: V1GarminWorkoutReceipt?, message: String) {
        do {
            let receipt = try await client.sendToWatch(
                plannedSessionId: session.id,
                replace: replace,
                token: try await tokenProvider()
            )
            onSent()
            return (receipt, Self.sentMessage(for: receipt))
        } catch {
            return (nil, Self.failureMessage(for: error))
        }
    }

    /// A target sent without guidance is worth saying: the watch will not hold the athlete to it.
    static func sentMessage(for receipt: V1GarminWorkoutReceipt) -> String {
        if let warning = receipt.warnings.first {
            return String(localized: "Séance envoyée sur ta montre. \(warning)")
        }
        return String(localized: "Séance envoyée sur ta montre")
    }

    /// A Garmin refusal comes in the server's words (no permission, quota): said as it is.
    static func failureMessage(for error: Error) -> String {
        if case .message(let text)? = error as? SharpitAPIError { return text }
        return SharpitErrorGuidance.message(for: error, subject: String(localized: "L’envoi sur la montre"))
    }
}

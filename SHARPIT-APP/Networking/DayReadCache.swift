import Foundation
import os

/// Every day read (`/api/v1/today`, `sleep`, `recovery`, …) the app made this launch, by payload
/// type and day, so a day seen once never opens on a loading state again.
///
/// A past day no longer changes: while fresh, `SharpitClient` answers it without the server.
/// Today still changes — its night, sessions and check-in arrive — so it is only `lastKnown`: the
/// screen shows it at once and reads the server behind it. New data makes days stale rather than
/// gone: every write from the app (a sync, a Health upload, a food entry, an activity, a check-in)
/// expires them all, pull-to-refresh the day it shows; a stale day still paints at once, then
/// is read again.
nonisolated final class DayReadCache: Sendable {
    static let shared = DayReadCache()

    private struct Entry {
        let payload: any Sendable
        var isFresh: Bool
    }

    private let entries = OSAllocatedUnfairLock(initialState: [String: Entry]())
    private let today: @Sendable () -> String

    init(today: @escaping @Sendable () -> String = { TrainingDayId.today() }) {
        self.today = today
    }

    /// A past day still fresh: no need to ask the server.
    func settled<Payload: Sendable>(_: Payload.Type, day: String) -> Payload? {
        guard day < today() else { return nil }
        return entries.withLock { state in
            state[Self.key(Payload.self, day)].flatMap { $0.isFresh ? $0.payload : nil }
        } as? Payload
    }

    /// The last answer for the day, fresh or not: what a screen paints while it reads again.
    func lastKnown<Payload: Sendable>(_: Payload.Type, day: String) -> Payload? {
        entries.withLock { $0[Self.key(Payload.self, day)]?.payload } as? Payload
    }

    func keep<Payload: Sendable>(_ payload: Payload, day: String) {
        entries.withLock { $0[Self.key(Payload.self, day)] = Entry(payload: payload, isFresh: true) }
    }

    func expire(day: String) {
        entries.withLock { state in
            for key in state.keys where key.hasSuffix("?\(day)") { state[key]?.isFresh = false }
        }
    }

    func expireAll() {
        entries.withLock { state in
            for key in state.keys { state[key]?.isFresh = false }
        }
    }

    private static func key(_ type: Any.Type, _ day: String) -> String { "\(type)?\(day)" }
}

import Foundation
import os

/// The day reads (`/api/v1/today`, `sleep`, `recovery`, …) of days before today, kept for the
/// session: a past day no longer changes, so going back to it never asks the server again.
///
/// Today is never kept — its night, sessions and check-in still arrive. A past day changes only
/// through new data, so every write from the app (a sync, a Health upload, a food entry, an
/// activity, a check-in) forgets them all, and pull-to-refresh forgets the day it shows.
nonisolated final class SettledDayCache: Sendable {
    static let shared = SettledDayCache()

    private let payloads = OSAllocatedUnfairLock(initialState: [String: any Sendable]())
    private let today: @Sendable () -> String

    init(today: @escaping @Sendable () -> String = { TrainingDayId.today() }) {
        self.today = today
    }

    func payload<Payload: Sendable>(_: Payload.Type, path: String, day: String) -> Payload? {
        guard day < today() else { return nil }
        return payloads.withLock { $0[Self.key(path, day)] } as? Payload
    }

    func keep(_ payload: some Sendable, path: String, day: String) {
        guard day < today() else { return }
        payloads.withLock { $0[Self.key(path, day)] = payload }
    }

    func forget(day: String) {
        payloads.withLock { $0 = $0.filter { !$0.key.hasSuffix("?\(day)") } }
    }

    func forgetAll() {
        payloads.withLock { $0.removeAll() }
    }

    private static func key(_ path: String, _ day: String) -> String { "\(path)?\(day)" }
}

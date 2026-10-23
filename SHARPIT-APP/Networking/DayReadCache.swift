import Foundation
import os

/// Every day read (`/api/v1/today`, `sleep`, `recovery`, …) the app made, by payload type and
/// day, so a day seen once never opens on a loading state again.
///
/// A past day no longer changes: while fresh, `SharpitClient` answers it without the server.
/// Today still changes — its night, sessions and check-in arrive — so it is only `lastKnown`: the
/// screen shows it at once and reads the server behind it. New data makes days stale rather than
/// gone: every write from the app (a sync, a Health upload, a food entry, an activity, a check-in)
/// expires them all, pull-to-refresh the day it shows; a stale day still paints at once, then
/// is read again.
///
/// Past days are also kept on disk as the server sent them, so a relaunch opens them without
/// the network too. A copy on disk is fresh when it was written after the last `expireAll`.
nonisolated final class DayReadCache: Sendable {
    static let shared = DayReadCache(disk: .shared)

    private struct Entry {
        let payload: any Sendable
        var isFresh: Bool
    }

    private let entries = OSAllocatedUnfairLock(initialState: [String: Entry]())
    private let today: @Sendable () -> String
    private let disk: ActivityDiskCache?
    private let expiredAtKey: String
    // UserDefaults is thread-safe; it is not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(
        today: @escaping @Sendable () -> String = { TrainingDayId.today() },
        disk: ActivityDiskCache? = nil,
        defaults: UserDefaults = .standard,
        expiredAtKey: String = "sharpit.dayReads.expiredAt"
    ) {
        self.today = today
        self.disk = disk
        self.defaults = defaults
        self.expiredAtKey = expiredAtKey
    }

    /// A past day still fresh: no need to ask the server.
    func settled<Payload: Decodable & Sendable>(_: Payload.Type, day: String) -> Payload? {
        guard day < today() else { return nil }
        let key = Self.key(Payload.self, day)
        if let fresh = entries.withLock({ state in state[key].flatMap { $0.isFresh ? $0.payload : nil } }) {
            return fresh as? Payload
        }
        guard let stored = fromDisk(Payload.self, key: key), stored.isFresh else { return nil }
        return stored.payload
    }

    /// The last answer for the day, fresh or not: what a screen paints while it reads again.
    func lastKnown<Payload: Decodable & Sendable>(_: Payload.Type, day: String) -> Payload? {
        let key = Self.key(Payload.self, day)
        if let known = entries.withLock({ $0[key]?.payload }) { return known as? Payload }
        return fromDisk(Payload.self, key: key)?.payload
    }

    /// Keeps the day's answer; with the bytes the server sent, a past day survives a relaunch.
    func keep<Payload: Sendable>(_ payload: Payload, day: String, data: Data? = nil) {
        let key = Self.key(Payload.self, day)
        entries.withLock { $0[key] = Entry(payload: payload, isFresh: true) }
        if let data, day < today() { disk?.write(data, .dayRead, id: key) }
    }

    /// Pull-to-refresh: the read that follows rewrites the day, in memory and on disk.
    func expire(day: String) {
        entries.withLock { state in
            for key in state.keys where key.hasSuffix("?\(day)") { state[key]?.isFresh = false }
        }
    }

    func expireAll() {
        entries.withLock { state in
            for key in state.keys { state[key]?.isFresh = false }
        }
        defaults.set(Date.now, forKey: expiredAtKey)
    }

    /// A day kept on disk, brought back into memory so the next read skips the file.
    private func fromDisk<Payload: Decodable & Sendable>(_: Payload.Type, key: String) -> (payload: Payload, isFresh: Bool)? {
        guard let stored = disk?.read(.dayRead, id: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: stored.data)
        else { return nil }
        let expiredAt = defaults.object(forKey: expiredAtKey) as? Date ?? .distantPast
        let isFresh = stored.savedAt > expiredAt
        entries.withLock { state in
            if state[key] == nil { state[key] = Entry(payload: payload, isFresh: isFresh) }
        }
        return (payload, isFresh)
    }

    private static func key(_ type: Any.Type, _ day: String) -> String { "\(type)?\(day)" }
}

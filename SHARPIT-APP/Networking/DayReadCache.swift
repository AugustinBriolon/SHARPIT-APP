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

    /// `generation` counts the wipes: a read that began before one must not refill the cache after it.
    private struct State {
        var entries: [String: Entry] = [:]
        var generation = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
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
        if let fresh = state.withLock({ $0.entries[key].flatMap { $0.isFresh ? $0.payload : nil } }) {
            return fresh as? Payload
        }
        guard let stored = fromDisk(Payload.self, key: key), stored.isFresh else { return nil }
        return stored.payload
    }

    /// The last answer for the day, fresh or not: what a screen paints while it reads again.
    func lastKnown<Payload: Decodable & Sendable>(_: Payload.Type, day: String) -> Payload? {
        let key = Self.key(Payload.self, day)
        if let known = state.withLock({ $0.entries[key]?.payload }) { return known as? Payload }
        return fromDisk(Payload.self, key: key)?.payload
    }

    /// The wipe count to read before a request, so `keep` can tell its answer belongs to a past session.
    var generation: Int { state.withLock { $0.generation } }

    /// Keeps the day's answer; with the bytes the server sent, a past day survives a relaunch.
    /// With the `generation` read before the request, an answer that outlived a `clear()` is dropped.
    func keep<Payload: Sendable>(_ payload: Payload, day: String, data: Data? = nil, generation: Int? = nil) {
        let key = Self.key(Payload.self, day)
        let accepted = state.withLock { state in
            guard generation == nil || generation == state.generation else { return false }
            state.entries[key] = Entry(payload: payload, isFresh: true)
            return true
        }
        if accepted, let data, day < today() { disk?.write(data, .dayRead, id: key) }
    }

    /// Another athlete may sign in next: nothing read for this one stays in memory.
    /// The files on disk go with `ActivityDiskCache.removeAll()`.
    func clear() {
        state.withLock {
            $0.entries.removeAll()
            $0.generation += 1
        }
    }

    /// Pull-to-refresh: the read that follows rewrites the day, in memory and on disk.
    func expire(day: String) {
        state.withLock { state in
            for key in state.entries.keys where key.hasSuffix("?\(day)") { state.entries[key]?.isFresh = false }
        }
    }

    func expireAll() {
        state.withLock { state in
            for key in state.entries.keys { state.entries[key]?.isFresh = false }
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
        state.withLock { state in
            if state.entries[key] == nil { state.entries[key] = Entry(payload: payload, isFresh: isFresh) }
        }
        return (payload, isFresh)
    }

    private static func key(_ type: Any.Type, _ day: String) -> String { "\(type)?\(day)" }
}

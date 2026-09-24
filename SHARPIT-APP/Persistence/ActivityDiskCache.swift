import Foundation

/// An activity's detail and streams, kept on disk as the server sent them.
///
/// An activity is read far more often than it changes, and its streams — GPS track, heart rate,
/// splits — are the heaviest read in the app. Opening one repainted a loader every time because
/// the only cache lived in a client rebuilt with each screen. The raw JSON is stored, not a
/// re-encoding: the wire types are decode-only, and the bytes the server answered are the
/// truest copy (`docs/adr/0007`: the cache is never the truth, it is the last answer).
///
/// Application Support rather than Caches: iOS may purge Caches under pressure, and the point
/// is that a session opened last week opens instantly today, offline included.
nonisolated struct ActivityDiskCache: Sendable {
    nonisolated enum Kind: String, Sendable {
        case detail
        case stream
        /// A planned session's breakdown, which Today's payload does not carry: shown at once
        /// from here while the plan is asked again.
        case plannedBreakdown
    }

    let directory: URL

    static let shared = ActivityDiskCache(
        directory: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appending(path: "ActivityCache", directoryHint: .isDirectory)
    )

    func read(_ kind: Kind, id: String) -> (data: Data, savedAt: Date)? {
        let url = fileURL(kind, id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        return (data, savedAt)
    }

    func write(_ data: Data, _ kind: Kind, id: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(kind, id: id), options: .atomic)
    }

    func remove(_ kind: Kind, id: String) {
        try? FileManager.default.removeItem(at: fileURL(kind, id: id))
    }

    /// Everything, at sign-out — one athlete's sessions are not the next one's.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ kind: Kind, id: String) -> URL {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return directory.appending(path: "\(safe)-\(kind.rawValue).json")
    }
}

/// When a cached copy can be shown without asking the server.
nonisolated enum ActivityCachePolicy {
    /// A session's detail changes when it is linked, analysed or rated — the app's own edits
    /// rewrite the copy at once; this covers edits made on the web.
    static let detailLifetime: TimeInterval = 12 * 3600

    static func isFresh(_ kind: ActivityDiskCache.Kind, savedAt: Date, now: Date = Date()) -> Bool {
        switch kind {
        // Only streams the server said were available are ever written, and a recorded
        // session's samples do not change.
        case .stream: true
        case .detail: now.timeIntervalSince(savedAt) < detailLifetime
        // A plan is edited — by the athlete, the coach, an adaptation — so its copy is shown
        // but always asked again.
        case .plannedBreakdown: false
        }
    }
}

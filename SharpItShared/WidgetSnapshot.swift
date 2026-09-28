import Foundation

/// What the widgets show, written by the app into the App Group each time it reads the day.
///
/// A widget never calls the API: it holds no Clerk session, and its refresh budget is a few
/// dozen reloads a day. The app writes this after every read of Résumé — on opening, on each
/// return, and when a silent push after a server sync wakes it — then asks WidgetKit to redraw.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// `yyyy-MM-dd`: a snapshot of another day is shown as stale, never as today.
    var trainingDayId: String
    var writtenAt: Date
    var verdict: Verdict?
    var sessions: [Session]

    nonisolated struct Verdict: Codable, Equatable, Sendable {
        /// « Feu vert », « Récupère »…
        var status: String
        var headline: String
        var action: String?
        var posture: V1TodayPosture
    }

    nonisolated struct Session: Codable, Equatable, Sendable, Identifiable {
        /// The activity's id once done, else the line's.
        var id: String
        var isDone: Bool
        var title: String
        var sport: V1ActivityType
        /// The prescription behind a planned line, when it can be opened on its own.
        var plannedSessionId: String?
        /// As Résumé shows them, first ones first.
        var figures: [Figure]

        /// Where a tap on the session lands: the activity once done, its prescription before.
        var link: URL {
            if isDone { return WidgetSnapshot.link("/activity/\(id)") }
            return WidgetSnapshot.link(plannedSessionId.map { "/plan/session/\($0)" } ?? "/plan")
        }
    }

    /// A number and its unit, set apart so the number can take the instrument face.
    nonisolated struct Figure: Codable, Equatable, Sendable {
        var value: String
        var unit: String
    }

    /// The app's links are `https://sharpit.app` paths, as for any link it opens.
    static func link(_ path: String) -> URL {
        URL(string: "https://sharpit.app\(path)")!
    }

    /// The session to put forward: the first one still to do, else the last one done.
    var leadSession: Session? {
        sessions.first { !$0.isDone } ?? sessions.last
    }

    func isFor(day: Date, calendar: Calendar = .current) -> Bool {
        trainingDayId == Self.dayId(day, calendar: calendar)
    }

    static func dayId(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}

/// The snapshot's file in the App Group container, shared by the app and the widgets.
nonisolated enum WidgetSnapshotStore {
    static let appGroup = "group.app.sharpit.ios"
    static let fileName = "widget-snapshot.json"

    static func read(from directory: URL? = containerURL) -> WidgetSnapshot? {
        guard let url = directory?.appending(path: fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot, to directory: URL? = containerURL) throws {
        guard let url = directory?.appending(path: fileName) else { return }
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Signing out or deleting the account leaves nothing of the athlete on the home screen.
    static func erase(in directory: URL? = containerURL) {
        guard let url = directory?.appending(path: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

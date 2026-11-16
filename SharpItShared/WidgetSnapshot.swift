import Foundation
import SwiftUI

/// What the widgets show, written by the app into the App Group.
///
/// A widget never calls the API: it holds no Clerk session, and its refresh budget is a few
/// dozen reloads a day. The app writes each section as it reads it — the day from Résumé, the
/// food log from its card, the weight from Corps — and all of them when a silent push after a
/// server sync wakes it, then asks WidgetKit to redraw. Sections are merged, never replaced
/// whole: reading the food log does not erase the day.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var day: Day?
    var nutrition: Nutrition?
    var weight: Weight?
    var regularity: Regularity?
    var training: Training?
    var goal: Goal?
    /// The session recorded last, with its route when it has one.
    var latestActivity: LatestActivity?
    /// The parts of SharpIt the athlete uses: a widget of a feature turned off says so.
    var features: V1FeaturePrefs?
    /// SharpIt Pro: the extra widgets (sleep, weight, volume, regularity, goal) are Pro. Nil until
    /// the app has read the tier — they show meanwhile rather than lock a Pro athlete out.
    var isPro: Bool?

    init(
        day: Day? = nil,
        nutrition: Nutrition? = nil,
        weight: Weight? = nil,
        regularity: Regularity? = nil,
        training: Training? = nil,
        goal: Goal? = nil,
        latestActivity: LatestActivity? = nil,
        features: V1FeaturePrefs? = nil
    ) {
        self.day = day
        self.nutrition = nutrition
        self.weight = weight
        self.regularity = regularity
        self.training = training
        self.goal = goal
        self.latestActivity = latestActivity
        self.features = features
    }

    // MARK: Day

    /// Résumé's day: the verdict, the sessions, last night's sleep.
    nonisolated struct Day: Codable, Equatable, Sendable {
        /// `yyyy-MM-dd`: a day other than today is shown as stale, never as today.
        var trainingDayId: String
        var verdict: Verdict?
        var sessions: [Session]
        var sleep: Sleep?
        /// Kept so an older snapshot still decodes; no widget reads it any more.
        var energyBank: EnergyBank? = nil
        /// The morning's recovery, as Résumé's gauge reads it.
        var recovery: Sleep? = nil

        /// The session to put forward: the first one still to do, else the last one done.
        var leadSession: Session? {
            sessions.first { !$0.isDone } ?? sessions.last
        }
    }

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

    // MARK: Latest activity

    /// The session recorded last, whatever its day. Not `lastActivity`: an earlier build wrote
    /// that key in another shape, and a stale one on disk must stay an unknown key.
    nonisolated struct LatestActivity: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var sport: V1ActivityType
        var date: Date
        /// Up to three, each under its name: « Distance », « Durée », « Allure moyenne ».
        var stats: [Stat]
        /// The GPS route as `[x, y]` in a unit square (`WidgetRoute.fit`); nil for a session
        /// without one — a pool swim, strength, a home trainer.
        var route: [[Double]]?
        /// The session whose maps sit beside the snapshot (`WidgetSnapshotStore.latestActivityMapURL`):
        /// a map is shown only while it is this session's, never the previous one's.
        var mapActivityId: String? = nil

        var hasMap: Bool { mapActivityId == id }

        var link: URL { WidgetSnapshot.link("/activity/\(id)") }
    }

    /// A figure under its name.
    nonisolated struct Stat: Codable, Equatable, Sendable {
        var label: String
        var value: String
        var unit: String

        var figure: Figure { Figure(value: value, unit: unit) }
    }

    /// A number and its unit, set apart so the number can take the instrument face.
    nonisolated struct Figure: Codable, Equatable, Sendable {
        var value: String
        var unit: String
    }

    /// Last night, as Résumé's gauge reads it.
    nonisolated struct Sleep: Codable, Equatable, Sendable {
        /// 0…100, the dial's value; nil when the gauge shows no number.
        var score: Int?
        /// What the gauge shows under the dial — « 7 h 12 », a cause…
        var caption: String?
    }

    /// SharpIt-native Energy Bank (ADR-079), as Résumé's day scores read it.
    nonisolated struct EnergyBank: Codable, Equatable, Sendable {
        var score: Int?
        var caption: String?
    }

    // MARK: Nutrition

    /// Today's food log, as its Résumé card reads it.
    nonisolated struct Nutrition: Codable, Equatable, Sendable {
        var trainingDayId: String
        /// Always true since the food log lives in SHARPIT (ADR-061); kept so a snapshot written
        /// by an older build still decodes.
        var isConnected: Bool
        var calories: Double?
        /// The day's budget, exercise included, as the server computes it.
        var calorieGoal: Double?
        var remaining: Double?
        var macros: [Macro]
    }

    nonisolated struct Macro: Codable, Equatable, Sendable, Identifiable {
        nonisolated enum Kind: String, Codable, Sendable { case protein, carbohydrates, fat }
        var kind: Kind
        var grams: Double
        var goalGrams: Double?

        var id: Kind { kind }
    }

    // MARK: Weight

    /// The latest weigh-in and where it stands against the athlete's target.
    nonisolated struct Weight: Codable, Equatable, Sendable {
        var kilograms: Double
        var measuredAt: Date
        /// The value `changeWindowDays` earlier, when the server has one.
        var previousKilograms: Double?
        var changeWindowDays: Int?
        var targetKilograms: Double?
    }

    // MARK: Regularity

    /// Résumé's regularity strip: the days around today and the week's session count, as the
    /// server counts them.
    nonisolated struct Regularity: Codable, Equatable, Sendable {
        var trainingDayId: String
        var days: [RegularityDay]
        var weekSessionCount: Int
    }

    nonisolated struct RegularityDay: Codable, Equatable, Sendable, Identifiable {
        /// `yyyy-MM-dd`.
        var date: String
        var weekdayLabel: String
        var dayOfMonth: Int
        var hasActivity: Bool
        var isToday: Bool
        var isFuture: Bool

        var id: String { date }
    }

    // MARK: Training

    /// What was recorded over the last two weeks, kept small: the volume widget sums it for
    /// the sport it was set to, and compares with last week at the same point.
    nonisolated struct Training: Codable, Equatable, Sendable {
        var sessions: [TrainedSession]
    }

    nonisolated struct TrainedSession: Codable, Equatable, Sendable {
        /// `yyyy-MM-dd`, the athlete's day.
        var dayId: String
        var sport: V1ActivityType
        var distanceMeters: Double?
        var durationSeconds: Double?
    }

    // MARK: Goal

    /// The next race, as Objectifs puts it on its plate.
    nonisolated struct Goal: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var date: Date
        var location: String?
        var format: String?
        var targetPerformance: String?
    }

    // MARK: Freshness

    func day(on date: Date, calendar: Calendar = .current) -> Day? {
        guard let day, day.trainingDayId == Self.dayId(date, calendar: calendar) else { return nil }
        return day
    }

    func nutrition(on date: Date, calendar: Calendar = .current) -> Nutrition? {
        guard let nutrition, nutrition.trainingDayId == Self.dayId(date, calendar: calendar) else { return nil }
        return nutrition
    }

    func regularity(on date: Date, calendar: Calendar = .current) -> Regularity? {
        guard let regularity, regularity.trainingDayId == Self.dayId(date, calendar: calendar) else { return nil }
        return regularity
    }

    /// The next race while it is still ahead.
    func goal(on date: Date, calendar: Calendar = .current) -> Goal? {
        guard let goal, calendar.startOfDay(for: goal.date) >= calendar.startOfDay(for: date) else { return nil }
        return goal
    }

    static func dayId(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// The app's links are `https://sharpit.app` paths, as for any link it opens.
    static func link(_ path: String) -> URL {
        URL(string: "https://sharpit.app\(path)")!
    }

    /// Where a tap on a widget lands: the page it stands for, or — when the widget shows a lock
    /// or a part of SharpIt the athlete hid — the page of Paramètres that undoes it, since the
    /// page itself would not be there.
    static func link(
        _ path: String,
        unlocked: Bool = true,
        feature: SharpitFeature? = nil,
        features: V1FeaturePrefs = V1FeaturePrefs()
    ) -> URL {
        if !unlocked { return link("/settings/pro") }
        if let feature, !features.isOn(feature) { return link("/settings/features") }
        return link(path)
    }
}

/// The snapshot's file in the App Group container, shared by the app and the widgets.
nonisolated enum WidgetSnapshotStore {
    static let appGroup = "group.app.sharpit.ios"
    static let fileName = "widget-snapshot.json"
    /// The map PNG an earlier build wrote for « Dernière activité »: only ever erased now.
    static let lastActivityMapFileName = "last-activity-map.png"

    /// The map under « Dernière activité », drawn by the app (a widget cannot draw one): one per
    /// face and per appearance.
    enum LatestActivityMap: String, CaseIterable, Sendable {
        case medium, large

        /// The face in points; the map is drawn at twice that.
        var size: CGSize {
            switch self {
            case .medium: CGSize(width: 364, height: 170)
            case .large: CGSize(width: 364, height: 382)
            }
        }

        /// The share of the face above the figures, where the route must sit.
        var routeShare: Double {
            switch self {
            case .medium: 0.62
            case .large: 0.74
            }
        }
    }

    static func latestActivityMapURL(_ map: LatestActivityMap, dark: Bool, in directory: URL? = containerURL) -> URL? {
        directory?.appending(path: "latest-activity-\(map.rawValue)-\(dark ? "dark" : "light").png")
    }

    static func read(from directory: URL? = containerURL) -> WidgetSnapshot? {
        guard let url = directory?.appending(path: fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        // A section a build no longer reads (« Dernière activité ») is an unknown key: ignored.
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot, to directory: URL? = containerURL) throws {
        guard let url = directory?.appending(path: fileName) else { return }
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Health figures, rebuilt from /api on the next refresh: kept out of backups (docs/adr/0017).
        BackupExclusion.exclude(url)
    }

    /// Changes one section and keeps the others. Returns whether anything changed.
    @discardableResult
    static func update(in directory: URL? = containerURL, _ change: (inout WidgetSnapshot) -> Void) -> Bool {
        let current = read(from: directory) ?? WidgetSnapshot()
        var next = current
        change(&next)
        guard next != current else { return false }
        try? write(next, to: directory)
        return true
    }

    /// Signing out or deleting the account leaves nothing of the athlete on the home screen.
    static func erase(in directory: URL? = containerURL) {
        guard let directory else { return }
        for name in [fileName, lastActivityMapFileName] {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        for map in LatestActivityMap.allCases {
            for dark in [false, true] {
                if let url = latestActivityMapURL(map, dark: dark, in: directory) { try? FileManager.default.removeItem(at: url) }
            }
        }
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

extension WidgetSnapshot.Macro.Kind {
    var label: String {
        switch self {
        case .protein: String(localized: "Protéines")
        case .carbohydrates: String(localized: "Glucides")
        case .fat: String(localized: "Lipides")
        }
    }

    /// One hue per macro, from the signal family — the app's nutrition columns and the widgets'.
    var tone: Color {
        switch self {
        case .protein: SharpitColor.primary
        case .carbohydrates: SharpitColor.highlight
        case .fat: SharpitColor.signalBase
        }
    }
}

/// A GPS route made ready to draw: the widget strokes points, it projects nothing.
nonisolated enum WidgetRoute {
    /// `[latitude, longitude]` pairs as `[x, y]` in a unit square — north up, the route's own
    /// proportions kept and centred, thinned to `maxPoints`. Nil when there is nothing to draw:
    /// fewer than two points, or a route that never left its start.
    static func fit(_ coordinates: [[Double]], maxPoints: Int = 120) -> [[Double]]? {
        let valid = coordinates.filter { $0.count >= 2 && abs($0[0]) <= 90 && abs($0[1]) <= 180 && $0[0].isFinite && $0[1].isFinite }
        guard valid.count >= 2, maxPoints >= 2 else { return nil }
        let step = max(1, Int((Double(valid.count) / Double(maxPoints)).rounded(.up)))
        var kept = stride(from: 0, to: valid.count, by: step).map { valid[$0] }
        if let last = valid.last, kept.last != last { kept.append(last) }

        let latitudes = kept.map { $0[0] }
        let midLatitude = ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2
        // A degree of longitude shrinks with latitude: without this a route at 48° N is drawn too wide.
        let shrink = cos(midLatitude * .pi / 180)
        let xs = kept.map { $0[1] * shrink }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = latitudes.min(), let maxY = latitudes.max() else { return nil }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return nil }
        let padX = (1 - (maxX - minX) / span) / 2
        let padY = (1 - (maxY - minY) / span) / 2
        return zip(xs, latitudes).map { x, latitude in
            [padX + (x - minX) / span, padY + (maxY - latitude) / span]
        }
    }
}

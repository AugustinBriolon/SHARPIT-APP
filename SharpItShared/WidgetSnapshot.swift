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
        features: V1FeaturePrefs? = nil
    ) {
        self.day = day
        self.nutrition = nutrition
        self.weight = weight
        self.regularity = regularity
        self.training = training
        self.goal = goal
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

extension WidgetSnapshot.Macro.Kind {
    var label: String {
        switch self {
        case .protein: "Protéines"
        case .carbohydrates: "Glucides"
        case .fat: "Lipides"
        }
    }

    /// One hue per macro, from the signal family — the app's nutrition columns and the widgets'.
    var tone: Color {
        switch self {
        case .protein: SharpitColor.signalRecovery
        case .carbohydrates: SharpitColor.signalBase
        case .fat: SharpitColor.signalTempo
        }
    }
}

import Foundation

/// `GET /api/v1/goals/achievements` — each time a goal was reached, newest first: a weekly
/// volume kept for a week, a month, a chrono run once (`periodKey` `_performance`).
nonisolated struct V1GoalAchievement: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    /// `auto` (a session met it) or `manual` (marked by the athlete).
    let source: String
    let value: Double?
    let targetValue: Double?
    /// `2026-W27`, `2026-07`, `2026`, or `_performance`.
    let periodKey: String
    let achievedAt: Date
    let goal: Goal
    let activity: Activity?

    nonisolated struct Goal: Decodable, Sendable, Equatable {
        let id: String
        let title: String
        let unit: String?
        let metricKey: String?
    }

    nonisolated struct Activity: Decodable, Sendable, Equatable {
        let id: String
        let title: String?
    }

    init(
        id: String,
        source: String = "auto",
        value: Double? = nil,
        targetValue: Double? = nil,
        periodKey: String,
        achievedAt: Date,
        goal: Goal,
        activity: Activity? = nil
    ) {
        self.id = id
        self.source = source
        self.value = value
        self.targetValue = targetValue
        self.periodKey = periodKey
        self.achievedAt = achievedAt
        self.goal = goal
        self.activity = activity
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, value, targetValue, periodKey, achievedAt, goal, activity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? "auto"
        value = try? container.decodeIfPresent(Double.self, forKey: .value)
        targetValue = try? container.decodeIfPresent(Double.self, forKey: .targetValue)
        periodKey = (try? container.decodeIfPresent(String.self, forKey: .periodKey)) ?? ""
        achievedAt = try Date.fromAPI(try container.decode(String.self, forKey: .achievedAt))
        goal = try container.decode(Goal.self, forKey: .goal)
        activity = try? container.decodeIfPresent(Activity.self, forKey: .activity)
    }

    var isManual: Bool { source == "manual" }
}

/// How an achievement reads, in the web's words (`goal-achievements-history.tsx`,
/// `formatGoalDisplayValue`, `formatAchievementPeriodKey`).
nonisolated enum GoalAchievementReadout {
    private static let french = Locale(identifier: "fr_FR")

    /// « 42,2 km · Semaine 27 · 2026 · 5 juil. 2026 · marqué manuellement »
    static func line(_ achievement: V1GoalAchievement) -> String {
        var parts = [value(achievement.value, unit: achievement.goal.unit, metricKey: achievement.goal.metricKey)]
        if let period = period(achievement.periodKey) { parts.append(period) }
        parts.append(achievement.achievedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(french)))
        if achievement.isManual { parts.append("marqué manuellement") }
        return parts.joined(separator: " · ")
    }

    /// The figure reached, in the goal's unit: seconds as a chrono, metres as km.
    static func value(_ value: Double?, unit: String?, metricKey: String?) -> String {
        guard let value else { return "—" }
        if unit == "chrono" || isPerformance(metricKey) {
            return chrono(value)
        }
        switch unit {
        case "h"?:
            let hours = value / 3600
            return hours >= 10 ? "\(Int(hours.rounded())) h" : "\(decimal(hours)) h"
        case "km"?:
            let km = value / 1000
            return km >= 100 ? "\(Int(km.rounded())) km" : "\(decimal(km)) km"
        case "m"?:
            return "\(Int(value.rounded())) m"
        case "séances"?:
            let count = Int(value.rounded())
            return "\(count) séance\(value > 1 ? "s" : "")"
        case let unit?:
            return "\(plain(value)) \(unit)"
        case nil:
            return plain(value)
        }
    }

    /// « Semaine 27 · 2026 », « juillet 2026 », « Année 2026 »; nil for a chrono, which has no period.
    static func period(_ key: String) -> String? {
        if key == "_performance" || key.isEmpty { return nil }
        let parts = key.split(separator: "-").map(String.init)
        if parts.count == 2, parts[0].count == 4, parts[1].hasPrefix("W"), parts[1].count == 3 {
            return "Semaine \(parts[1].dropFirst()) · \(parts[0])"
        }
        if parts.count == 2, parts[0].count == 4, parts[1].count == 2,
           let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let date = Calendar(identifier: .gregorian).date(from: components) else { return key }
            let formatter = DateFormatter()
            formatter.locale = french
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date)
        }
        if parts.count == 1, key.count == 4, Int(key) != nil {
            return "Année \(key)"
        }
        return key
    }

    /// « 3:45 » or « 1:02:03 ».
    static func chrono(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }

    /// The web stores a chrono goal's config as JSON in `metricKey` (`{ v: 1, template: 'performance' }`).
    static func isPerformance(_ metricKey: String?) -> Bool {
        guard let metricKey, let data = metricKey.data(using: .utf8),
              let config = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return false }
        return config["template"]?.string == "performance"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func plain(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : decimal(value)
    }
}

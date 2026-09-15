import Foundation

struct V1TodayResponse: Codable, Sendable, Equatable {
    var apiVersion: Int
    var trainingDayId: String
    var empty: V1TodayEmpty?
    var verdict: V1TodayVerdict
    var weather: V1TodayWeather?
    var sessions: [V1TodaySession]
    var signals: [V1TodaySignal]
}

struct V1TodayEmpty: Codable, Sendable, Equatable {
    var title: String
    var message: String?
    var code: V1TodayEmptyCode
    var webURL: String
}

enum V1TodayEmptyCode: String, Codable, Sendable {
    case noContent = "NO_CONTENT"
}

struct V1TodayVerdict: Codable, Sendable, Equatable {
    var eyebrow: String
    var headline: String
    var subline: String
    var posture: V1TodayPosture
    var confidencePct: Int?
    var limitingCause: String?
}

enum V1TodayPosture: String, Codable, Sendable {
    case protect
    case steady
    case push
    case uncertain
}

struct V1TodayWeather: Codable, Sendable, Equatable {
    var city: String
    var tempC: Double
    var condition: String
}

struct V1TodaySession: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: V1TodaySessionKind
    var title: String
    var subtitle: String?
    var metrics: [V1TodayMetric]
}

enum V1TodaySessionKind: String, Codable, Sendable {
    case planned
    case done
}

struct V1TodayMetric: Codable, Sendable, Equatable {
    var label: String
    var value: String
    var unit: String
}

struct V1TodaySignal: Codable, Sendable, Equatable, Identifiable {
    var key: V1TodaySignalKey
    var score: String
    var caption: String?

    var id: V1TodaySignalKey { key }
}

enum V1TodaySignalKey: String, Codable, Sendable {
    case sleep
    case recovery
    case effort
    case adaptation
}

enum TrainingDayId {
    static func today(in calendar: Calendar = .current, now: Date = .now) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

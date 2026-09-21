import Foundation
import HealthKit

/// One sleep sample as Apple Health stores it: a stretch of time in one stage, by one app.
nonisolated struct HealthSleepSample: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case inBed, awake, asleep, core, deep, rem

        init?(healthValue: Int) {
            switch HKCategoryValueSleepAnalysis(rawValue: healthValue) {
            case .inBed: self = .inBed
            case .awake: self = .awake
            case .asleepUnspecified: self = .asleep
            case .asleepCore: self = .core
            case .asleepDeep: self = .deep
            case .asleepREM: self = .rem
            default: return nil
            }
        }

        var isAsleep: Bool { self == .asleep || self == .core || self == .deep || self == .rem }
    }

    let start: Date
    let end: Date
    let stage: Stage
    var source: String = ""

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// One day of Apple Health, in the shape SHARPIT stores a day of health data.
nonisolated struct HealthDailySummary: Encodable, Equatable, Sendable {
    let date: String
    var sleepMinutes: Int?
    var sleepDeepMin: Int?
    var sleepRemMin: Int?
    var sleepLightMin: Int?
    var sleepAwakeMin: Int?
    /// Minutes after local midnight, as the server stores them.
    var sleepBedtimeMin: Int?
    var sleepWakeMin: Int?
    var restingHr: Int?
    var hrv: Int?
    var totalSteps: Int?
    var calories: Int?
    var weightKg: Double?

    init(date: String) {
        self.date = date
    }

    var isEmpty: Bool {
        sleepMinutes == nil && restingHr == nil && hrv == nil && totalSteps == nil
            && calories == nil && weightKg == nil
    }

    /// Stages apart by more than this belong to different sleeps — a nap is not the night.
    static let sessionGap: TimeInterval = 3 * 3_600

    static func merge(
        nights: [HealthSleepSample],
        restingHeartRate: [String: Double],
        hrv: [String: Double],
        steps: [String: Double],
        activeEnergy: [String: Double],
        bodyMass: [String: Double],
        calendar: Calendar = .current
    ) -> [HealthDailySummary] {
        var days: [String: HealthDailySummary] = [:]
        func edit(_ day: String, _ change: (inout HealthDailySummary) -> Void) {
            var summary = days[day] ?? HealthDailySummary(date: day)
            change(&summary)
            days[day] = summary
        }

        for night in Self.nights(from: nights, calendar: calendar) {
            edit(night.day) { $0.applyNight(night, calendar: calendar) }
        }
        for (day, value) in restingHeartRate { edit(day) { $0.restingHr = Int(value.rounded()) } }
        for (day, value) in hrv { edit(day) { $0.hrv = Int(value.rounded()) } }
        for (day, value) in steps { edit(day) { $0.totalSteps = Int(value.rounded()) } }
        for (day, value) in activeEnergy { edit(day) { $0.calories = Int(value.rounded()) } }
        for (day, value) in bodyMass { edit(day) { $0.weightKg = (value * 10).rounded() / 10 } }

        return days.values.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
    }

    // MARK: - Nights

    struct Night: Equatable {
        let day: String
        let start: Date
        let end: Date
        let samples: [HealthSleepSample]

        func minutes(_ stages: Set<HealthSleepSample.Stage>) -> Double {
            samples.filter { stages.contains($0.stage) }.reduce(0) { $0 + $1.minutes }
        }

        var asleepMinutes: Double { minutes([.asleep, .core, .deep, .rem]) }
    }

    /// Groups samples into sleeps, keeps one writer per sleep — the one that recorded the
    /// most sleep, since a Garmin and an Apple Watch both writing would count the night
    /// twice — and keeps the longest sleep of each wake day as that day's night.
    static func nights(from samples: [HealthSleepSample], calendar: Calendar = .current) -> [Night] {
        var sessions: [[HealthSleepSample]] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let last = sessions.last?.map(\.end).max(), sample.start.timeIntervalSince(last) <= sessionGap {
                sessions[sessions.count - 1].append(sample)
            } else {
                sessions.append([sample])
            }
        }

        let nights: [Night] = sessions.compactMap { session in
            let bySource = Dictionary(grouping: session, by: \.source)
            let chosen = bySource.values.max { lhs, rhs in
                asleep(lhs) < asleep(rhs)
            } ?? []
            guard asleep(chosen) > 0,
                  let start = chosen.map(\.start).min(),
                  let end = chosen.map(\.end).max() else { return nil }
            return Night(day: TrainingDayId.today(in: calendar, now: end), start: start, end: end, samples: chosen)
        }

        return Dictionary(grouping: nights, by: \.day).values.compactMap { sameDay in
            sameDay.max { $0.asleepMinutes < $1.asleepMinutes }
        }
    }

    private static func asleep(_ samples: [HealthSleepSample]) -> Double {
        samples.filter(\.stage.isAsleep).reduce(0) { $0 + $1.minutes }
    }

    private mutating func applyNight(_ night: Night, calendar: Calendar) {
        sleepMinutes = Int(night.asleepMinutes.rounded())
        let staged = night.minutes([.core, .deep, .rem]) > 0
        if staged {
            sleepDeepMin = Int(night.minutes([.deep]).rounded())
            sleepRemMin = Int(night.minutes([.rem]).rounded())
            sleepLightMin = Int(night.minutes([.core]).rounded())
        }
        let awake = night.minutes([.awake])
        sleepAwakeMin = awake > 0 ? Int(awake.rounded()) : nil
        sleepBedtimeMin = Self.minutesAfterMidnight(night.start, calendar: calendar)
        sleepWakeMin = Self.minutesAfterMidnight(night.end, calendar: calendar)
    }

    private static func minutesAfterMidnight(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

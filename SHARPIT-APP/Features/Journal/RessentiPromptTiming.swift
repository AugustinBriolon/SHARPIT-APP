import Foundation

/// When Résumé may open « Ressenti du jour » on its own. The server's day turns at midnight, but
/// a feeling is asked in the morning: never before 6 h, then once last night's sleep is in, or
/// from 10 h without it. Opening it by hand is never gated.
nonisolated enum RessentiPromptTiming {
    static let earliestHour = 6
    static let withoutSleepHour = 10

    static func isDue(now: Date, hasLastNightSleep: Bool, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard hour >= earliestHour else { return false }
        return hasLastNightSleep || hour >= withoutSleepHour
    }

    /// The sleep gauge carries a figure once the night is synced; « — » until then.
    static func hasLastNightSleep(_ gauges: [OvernightGaugeModel]) -> Bool {
        gauges.contains { $0.key == .sleep && $0.score.contains(where: \.isNumber) }
    }
}

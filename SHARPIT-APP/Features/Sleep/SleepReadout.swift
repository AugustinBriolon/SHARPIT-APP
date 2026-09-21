import SwiftUI

/// Formatting and tones for the sleep screen, kept out of the view so they can be tested.
enum SleepReadout {
    /// "7 h 32", "45 min".
    static func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let total = Int(minutes.rounded())
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// "+18 min", "−1 h 05". Nil and zero read as nothing to say.
    static func delta(_ minutes: Double?) -> String? {
        guard let minutes, Int(minutes.rounded()) != 0 else { return nil }
        let sign = minutes > 0 ? "+" : "−"
        return sign + duration(abs(minutes))
    }

    /// Minutes after midnight → "23:10". Values past 24 h wrap, as a bedtime can.
    static func clock(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let wrapped = ((Int(minutes.rounded()) % 1_440) + 1_440) % 1_440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    static func tone(for adequacy: V1SleepAdequacy.Key) -> Color {
        switch adequacy {
        case .excellent: SharpitColor.signalBase
        case .adequate: SharpitColor.signalRecovery
        case .insufficient: SharpitColor.signalCaution
        case .severelyInsufficient: SharpitColor.signalRisk
        case .pending, .missing, .unknown: SharpitColor.signalNeutral
        }
    }

    static func tone(for insight: V1RecoveryTone) -> Color {
        switch insight {
        case .good: SharpitColor.signalRecovery
        case .moderate: SharpitColor.signalCaution
        case .low: SharpitColor.signalRisk
        case .neutral: SharpitColor.signalNeutral
        }
    }

    /// Time from bedtime to wake, across midnight. Nil unless both are known.
    static func timeInBed(bedtime: Double?, wake: Double?) -> Double? {
        guard let bedtime, let wake else { return nil }
        let span = (wake - bedtime).truncatingRemainder(dividingBy: 1_440)
        return span < 0 ? span + 1_440 : span
    }

    /// The sleep bank's balance: debt reads as a withdrawal, none as balanced.
    static func bankBalance(debtMin: Double?) -> String {
        guard let debtMin else { return "—" }
        if debtMin.rounded() <= 0 { return "À l'équilibre" }
        return "−" + duration(debtMin)
    }

    static func bankTone(debtMin: Double?) -> Color {
        guard let debtMin else { return SharpitColor.mutedForeground }
        return debtMin.rounded() <= 0 ? SharpitColor.signalRecovery : SharpitColor.signalCaution
    }

    /// The sleep structure: the three stages of actual sleep, colored as the web's
    /// `PHASE_COLORS`. Time awake is not sleep, so it is not a share of it.
    enum Stage: CaseIterable, Identifiable {
        case deep, rem, light

        var id: Self { self }

        var label: String {
            switch self {
            case .deep: "Profond"
            case .rem: "Paradoxal"
            case .light: "Léger"
            }
        }

        var tone: Color {
            switch self {
            case .deep: SharpitColor.signalBase
            case .rem: SharpitColor.signalRecovery
            case .light: SharpitColor.signalTempo
            }
        }

        func minutes(in stages: V1SleepStages) -> Double? {
            switch self {
            case .deep: stages.deepMin
            case .rem: stages.remMin
            case .light: stages.lightMin
            }
        }
    }

    /// Each stage's share of the sleep, or nil when no stage was recorded.
    static func stageShares(_ stages: V1SleepStages) -> [(stage: Stage, share: Double)]? {
        let values = Stage.allCases.map { ($0, max($0.minutes(in: stages) ?? 0, 0)) }
        let total = values.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        return values.map { ($0.0, $0.1 / total) }
    }
}

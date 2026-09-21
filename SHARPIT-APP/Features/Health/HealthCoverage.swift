import Foundation

/// A signal SHARPIT uses, and what Apple Health can offer for it.
///
/// The catalogue is the question the diagnostic answers: for each thing the app reads from
/// Garmin today, does Apple Health hold it, and who wrote it? A signal with no Apple Health
/// equivalent is listed too, so the gap is visible rather than silently missing.
enum HealthSignal: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case sleepStages
    case restingHeartRate
    case heartRateVariability
    case heartRate
    case steps
    case activeEnergy
    case bodyMass
    case respiratoryRate
    case oxygenSaturation
    case vo2Max
    case workouts
    case workoutRoutes
    case bodyBattery
    case stress
    case trainingReadiness
    case sleepScore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: "Durée de sommeil"
        case .sleepStages: "Phases de sommeil"
        case .restingHeartRate: "FC de repos"
        case .heartRateVariability: "VFC"
        case .heartRate: "Fréquence cardiaque"
        case .steps: "Pas"
        case .activeEnergy: "Calories actives"
        case .bodyMass: "Poids"
        case .respiratoryRate: "Respiration"
        case .oxygenSaturation: "SpO₂"
        case .vo2Max: "VO₂ max"
        case .workouts: "Séances"
        case .workoutRoutes: "Tracés GPS"
        case .bodyBattery: "Body Battery"
        case .stress: "Stress"
        case .trainingReadiness: "Training Readiness"
        case .sleepScore: "Score de sommeil Garmin"
        }
    }

    /// Where SHARPIT uses it — why a gap matters.
    var usedFor: String {
        switch self {
        case .sleep, .sleepStages, .sleepScore: "Sommeil"
        case .restingHeartRate, .heartRateVariability, .bodyBattery, .trainingReadiness: "Récupération"
        case .heartRate, .workouts, .workoutRoutes: "Activité"
        case .steps, .activeEnergy, .stress: "Charge du jour"
        case .bodyMass: "Corps"
        case .respiratoryRate, .oxygenSaturation: "Santé"
        case .vo2Max: "Forme"
        }
    }

    /// Garmin computes these itself and never writes them to Apple Health.
    var hasHealthEquivalent: Bool {
        switch self {
        case .bodyBattery, .stress, .trainingReadiness, .sleepScore: false
        default: true
        }
    }
}

/// What Apple Health returned for one signal over the window read.
struct HealthSignalReading: Equatable, Sendable {
    /// Source apps that wrote samples, by display name.
    let sources: [String]
    /// Training day ids with at least one sample.
    let days: Set<String>

    static let empty = HealthSignalReading(sources: [], days: [])
}

/// One line of the diagnostic.
struct HealthCoverageRow: Identifiable, Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        /// Present on most days of the window.
        case covered
        /// Present, but on fewer than half the days.
        case partial
        case missing
        /// Apple Health has no such type; only Garmin can provide it.
        case noEquivalent
    }

    let signal: HealthSignal
    let verdict: Verdict
    let sources: [String]
    let dayCount: Int
    /// True when Garmin Connect is among the sources.
    let fromGarmin: Bool

    var id: HealthSignal { signal }
}

enum HealthCoverage {
    /// Garmin Connect writes to Apple Health under this name.
    static func isGarmin(_ source: String) -> Bool {
        let name = source.lowercased()
        return name.contains("garmin") || name == "connect"
    }

    static func rows(
        readings: [HealthSignal: HealthSignalReading],
        windowDays: Int
    ) -> [HealthCoverageRow] {
        HealthSignal.allCases.map { signal in
            guard signal.hasHealthEquivalent else {
                return HealthCoverageRow(signal: signal, verdict: .noEquivalent, sources: [], dayCount: 0, fromGarmin: false)
            }
            let reading = readings[signal] ?? .empty
            let verdict: HealthCoverageRow.Verdict = switch reading.days.count {
            case 0: .missing
            case ..<max(windowDays / 2, 1): .partial
            default: .covered
            }
            return HealthCoverageRow(
                signal: signal,
                verdict: verdict,
                sources: reading.sources.sorted(),
                dayCount: reading.days.count,
                fromGarmin: reading.sources.contains(where: isGarmin)
            )
        }
    }
}

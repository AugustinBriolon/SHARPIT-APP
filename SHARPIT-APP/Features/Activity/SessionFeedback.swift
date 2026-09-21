import SwiftUI

/// The athlete's feeling about a session, on the web's five-step scale.
///
/// The stored value is the web's word (`activity-feeling-scale.ts`), not the ordinal: the
/// server keeps the string, and the web reads it back verbatim. The app shows the ordinal
/// so feeling reads on the same kind of scale as effort.
enum SessionFeeling: Int, CaseIterable, Identifiable, Sendable {
    case veryBad = 1
    case bad
    case okay
    case good
    case veryGood

    var id: Int { rawValue }

    /// What the web stores and reads.
    var storedValue: String {
        switch self {
        case .veryBad: "Très mal"
        case .bad: "Mal"
        case .okay: "Correct"
        case .good: "Bien"
        case .veryGood: "Très bien"
        }
    }

    /// The web's hint, shown under the selected step.
    var hint: String {
        switch self {
        case .veryBad: "Très dur — signes de surmenage ou inconfort."
        case .bad: "Difficile, jambes lourdes ou manque d’énergie."
        case .okay: "Séance faite, sans plus ni moins."
        case .good: "Bon ressenti, effort maîtrisé."
        case .veryGood: "Fluide, énergie au rendez-vous."
        }
    }

    /// Reads the web's words, and the words earlier builds of this app wrote
    /// ("Très mauvais", "Mauvais", "Moyen") so those sessions still show a value.
    init?(stored: String?) {
        guard let stored else { return nil }
        let normalized = stored
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "tres mal", "tres mauvais": self = .veryBad
        case "mal", "mauvais": self = .bad
        case "correct", "moyen": self = .okay
        case "bien": self = .good
        case "tres bien", "excellent": self = .veryGood
        default: return nil
        }
    }
}

/// How the executed session compared with the plan, as the analysis states it.
enum SessionVerdict: String, Sendable {
    case asPlanned = "AS_PLANNED"
    case harder = "HARDER"
    case easier = "EASIER"
    case shorter = "SHORTER"
    case longer = "LONGER"
    case different = "DIFFERENT"

    /// `SESSION_VERDICT_LABELS` on the web.
    var label: String {
        switch self {
        case .asPlanned: "Conforme"
        case .harder: "Plus dur que prévu"
        case .easier: "Plus facile que prévu"
        case .shorter: "Plus court"
        case .longer: "Plus long"
        case .different: "Différent"
        }
    }

    var symbolName: String {
        switch self {
        case .asPlanned: "checkmark.circle.fill"
        case .harder: "arrow.up.right.circle.fill"
        case .easier: "arrow.down.right.circle.fill"
        case .shorter: "gauge.with.dots.needle.33percent"
        case .longer: "gauge.with.dots.needle.67percent"
        case .different: "arrow.triangle.branch"
        }
    }

    var tone: Color {
        switch self {
        case .asPlanned: SharpitColor.signalRecovery
        case .harder, .longer: SharpitColor.signalCaution
        case .easier, .shorter: SharpitColor.signalNeutral
        case .different: SharpitColor.signalRisk
        }
    }
}

/// Semantic tones for the numbers a session carries. Color here is state, never decoration:
/// each ramp reuses a ramp the web already defines.
enum SessionFeedbackTone {
    /// Effort follows the web's intensity ramp, recovery → VO2.
    static func effort(_ rpe: Int) -> Color {
        switch rpe {
        case ...2: SharpitColor.signalRecovery
        case 3...4: SharpitColor.signalBase
        case 5...6: SharpitColor.signalTempo
        case 7...8: SharpitColor.signalThreshold
        default: SharpitColor.signalVo2
        }
    }

    static func feeling(_ feeling: SessionFeeling) -> Color {
        switch feeling {
        case .veryBad: SharpitColor.signalRisk
        case .bad: SharpitColor.signalCaution
        case .okay: SharpitColor.signalNeutral
        case .good: SharpitColor.signalRecovery
        case .veryGood: SharpitColor.signalBase
        }
    }

    static func compliance(_ score: Double) -> Color {
        switch score {
        case 85...: SharpitColor.signalRecovery
        case 60..<85: SharpitColor.signalCaution
        default: SharpitColor.signalRisk
        }
    }
}

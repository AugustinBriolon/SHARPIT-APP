import Foundation

/// The first-login wizard's steps, in the web's order (`src/lib/onboarding/wizard/wizard-steps.ts`).
///
/// Sports → Équipement → Disponibilités → Intention → Sources. Equipment and availability sit
/// together: both describe the constraints a plan has to respect, before the goal it serves.
nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case sports
    case equipment
    case availability
    case intention
    case sources

    var id: Int { rawValue }

    /// Bare names — the progress rail owns the numbering.
    var label: String {
        switch self {
        case .sports: "Sports"
        case .equipment: "Équipement"
        case .availability: "Disponibilités"
        case .intention: "Intention"
        case .sources: "Sources"
        }
    }

    var title: String {
        switch self {
        case .sports: "Tes sports"
        case .equipment: "Ton matériel"
        case .availability: "Tes disponibilités"
        case .intention: "Ton objectif"
        case .sources: "Tes données"
        }
    }

    var intro: String {
        switch self {
        case .sports:
            "Sélectionne tes disciplines d'endurance et pratiques complémentaires."
        case .equipment:
            "Optionnel — adapte les séances au matériel dont tu disposes."
        case .availability:
            "Optionnel — cale tes séances sur ton rythme hebdomadaire réel."
        case .intention:
            "Optionnel — pose une course ou un palier cible pour guider ta préparation."
        case .sources:
            "Connecte Garmin ou active Apple Santé pour alimenter ton suivi athlète."
        }
    }

    /// Everything but Sports can be skipped: an athlete may not know their week or their goal yet.
    var allowsSkip: Bool {
        switch self {
        case .sports, .sources: false
        case .equipment, .availability, .intention: true
        }
    }

    /// 1-based, for « 2/5 ».
    var position: Int { rawValue + 1 }

    static var count: Int { allCases.count }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// What the intention step records — the web's `OnboardingIntentionKind` minus `later`,
/// which is the step's Passer.
nonisolated enum OnboardingIntentionKind: String, CaseIterable, Identifiable, Sendable {
    case race
    case metric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .race: "Une course"
        case .metric: "Un objectif chiffré"
        }
    }
}

/// The few fields the wizard asks for a first goal, turned into the same payload as the
/// web's `buildOnboardingGoalPayload` (`src/lib/onboarding/status/intention.ts`).
nonisolated struct OnboardingIntentionDraft: Equatable, Sendable {
    var kind: OnboardingIntentionKind = .race

    var raceTitle = ""
    var raceDate: Date
    var raceLocation = ""

    var metricTitle = ""
    var metricTargetText = ""
    var metricUnit = ""

    init(now: Date = Date(), calendar: Calendar = .current) {
        raceDate = calendar.date(byAdding: .month, value: 3, to: now) ?? now
    }

    /// Accepts « 42,2 » as the French keyboard types it.
    var metricTarget: Double? {
        Double(metricTargetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    var isValid: Bool {
        switch kind {
        case .race:
            return !raceTitle.trimmed.isEmpty
        case .metric:
            guard let target = metricTarget, target.isFinite, target > 0 else { return false }
            return !metricTitle.trimmed.isEmpty && !metricUnit.trimmed.isEmpty
        }
    }

    /// A race is the season's A goal; a metric starts from nothing measured yet.
    var goalInput: CreateGoalInput? {
        guard isValid else { return nil }
        switch kind {
        case .race:
            return CreateGoalInput(
                title: raceTitle.trimmed,
                kind: .race,
                priority: .a,
                targetDate: raceDate,
                location: raceLocation.trimmed.isEmpty ? nil : raceLocation.trimmed
            )
        case .metric:
            return CreateGoalInput(
                title: metricTitle.trimmed,
                kind: .metric,
                targetValue: metricTarget,
                unit: metricUnit.trimmed
            )
        }
    }
}

/// Weekday labels for the availability step, indexed by `Date#getDay` as the web stores them.
nonisolated enum OnboardingWeekday {
    static let shortLabels = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
    static let labels = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    static func label(_ day: Int) -> String {
        labels.indices.contains(day) ? labels[day] : ""
    }

    /// « 3 séances possibles · Mardi, Jeudi, Samedi » — nil when nothing is declared, rather
    /// than inventing a default.
    static func reading(_ availability: V1TrainingAvailability) -> String? {
        let days = availability.availableWeekdays
        guard !days.isEmpty else { return nil }
        let count = availability.targetSessionsPerWeek ?? days.count
        let sessions = count == 1 ? "1 séance possible" : "\(count) séances possibles"
        return "\(sessions) · \(days.map(label).joined(separator: ", "))"
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

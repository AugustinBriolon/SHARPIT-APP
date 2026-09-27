import Foundation

/// The first-login wizard's steps, in the order the athlete meets them.
///
/// The coach is built up: who they are (sports, kit, week, goal), then the consents the data
/// needs — just before the sources that bring the data in — then the first week it plans. The
/// privacy step is in the path only when the consents are owed (`OnboardingStore.path`).
nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case sports
    case equipment
    case week
    case goal
    case privacy
    case sources
    case firstWeek

    var id: Int { rawValue }

    /// Bare names — the header owns the counting.
    var label: String {
        switch self {
        case .welcome: "Bienvenue"
        case .sports: "Sports"
        case .equipment: "Matériel"
        case .week: "Ta semaine"
        case .goal: "Objectif"
        case .privacy: "Confidentialité"
        case .sources: "Sources"
        case .firstWeek: "Première semaine"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Construisons ton coach"
        case .sports: "Tes sports"
        case .equipment: "Ton matériel"
        case .week: "Ta semaine type"
        case .goal: "Ton objectif"
        case .privacy: "Tes données, tes règles"
        case .sources: "Branche tes appareils"
        case .firstWeek: "Ta première semaine"
        }
    }

    var intro: String {
        switch self {
        case .welcome:
            "Quelques questions, et SHARPIT te prépare un coach qui te connaît, avec tes premières séances."
        case .sports:
            "Touche tes disciplines. Au moins un sport d'endurance."
        case .equipment:
            "Seulement ce qui sert à tes sports, pour des séances que tu peux vraiment faire."
        case .week:
            "Glisse le doigt sur les jours où tu peux t'entraîner."
        case .goal:
            "Une course ou un palier : tout le plan se construit vers lui."
        case .privacy:
            "Avant de brancher tes appareils, choisis ce que SHARPIT peut faire de tes données."
        case .sources:
            "Ta montre et ton téléphone nourrissent ton coach. Tu pourras en ajouter plus tard."
        case .firstWeek:
            "Le coach place tes premières séances sur tes jours."
        }
    }

    /// The optional steps: an athlete may not know their kit, their week or their goal yet.
    var allowsSkip: Bool {
        switch self {
        case .equipment, .week, .goal: true
        case .welcome, .sports, .privacy, .sources, .firstWeek: false
        }
    }
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

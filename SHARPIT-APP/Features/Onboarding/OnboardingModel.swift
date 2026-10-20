import Foundation

/// The first-login wizard's steps, in the order the athlete meets them.
///
/// The coach is built up: who they are (name, body, sports, kit, week, goal, injuries), then the
/// consents the data needs — just before the sources that bring the data in — then the first week
/// it plans. The privacy step is in the path only when the consents are owed
/// (`OnboardingStore.path`).
nonisolated enum OnboardingStep: Int, CaseIterable, Identifiable, Codable, Sendable {
    case identity
    case motivation
    case sports
    case equipment
    case week
    case goal
    case injuries
    case privacy
    case sources
    case firstWeek

    var id: Int { rawValue }

    /// Bare names — the header owns the counting.
    var label: String {
        switch self {
        case .identity: String(localized: "Toi")
        case .motivation: String(localized: "Tes envies")
        case .sports: String(localized: "Sports")
        case .equipment: String(localized: "Matériel")
        case .week: String(localized: "Ta semaine")
        case .goal: String(localized: "Objectif")
        case .injuries: String(localized: "Blessures")
        case .privacy: String(localized: "Confidentialité")
        case .sources: String(localized: "Sources")
        case .firstWeek: String(localized: "Première semaine")
        }
    }

    var title: String {
        switch self {
        case .identity: String(localized: "Construisons ton coach")
        case .motivation: String(localized: "Ce que tu viens chercher")
        case .sports: String(localized: "Tes sports")
        case .equipment: String(localized: "Ton matériel")
        case .week: String(localized: "Ta semaine type")
        case .goal: String(localized: "Ton objectif")
        case .injuries: String(localized: "Tes blessures")
        case .privacy: String(localized: "Tes données, tes règles")
        case .sources: String(localized: "Branche tes appareils")
        case .firstWeek: String(localized: "Ta première semaine")
        }
    }

    var intro: String {
        switch self {
        case .identity:
            String(localized: "Quelques repères sur toi : le coach règle charges, allures et récupération à partir d'eux.")
        case .motivation:
            String(localized: "Ton coach est toujours là. Ajoute ce que tu veux suivre en plus : le reste disparaît, et revient quand tu veux dans Paramètres.")
        case .sports:
            String(localized: "Touche tes disciplines. Un sport d'endurance, ou la musculation seule.")
        case .equipment:
            String(localized: "Seulement ce qui sert à tes sports, pour des séances que tu peux vraiment faire.")
        case .week:
            String(localized: "Glisse le doigt sur les jours où tu peux t'entraîner.")
        case .goal:
            String(localized: "Une course ou un palier : tout le plan se construit vers lui.")
        case .injuries:
            String(localized: "Une douleur ou une blessure en cours ? Le coach adapte tes séances pour la ménager.")
        case .privacy:
            String(localized: "Avant de brancher tes appareils, choisis ce que SharpIt peut faire de tes données.")
        case .sources:
            String(localized: "Ta montre, ton téléphone et ton journal alimentaire nourrissent ton coach. Tu pourras en ajouter plus tard.")
        case .firstWeek:
            String(localized: "Le coach place tes premières séances sur tes jours.")
        }
    }

    /// The optional steps: an athlete may not know their kit, their week or their goal yet, and
    /// may have nothing to declare.
    var allowsSkip: Bool {
        switch self {
        case .equipment, .week, .goal, .injuries: true
        case .identity, .motivation, .sports, .privacy, .sources, .firstWeek: false
        }
    }
}

/// Who the athlete is, for the identity step: the first name goes to their Clerk account, the
/// rest to the profile.
nonisolated struct OnboardingIdentityDraft: Equatable, Codable, Sendable {
    var firstName = ""
    var sex: AthleteSex?
    var heightCm: Int?
    var birthDate: Date?

    var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Prénom, sexe, taille et date de naissance — le bouton « Commencer » reste gris tant
    /// qu'un champ manque.
    var isValid: Bool {
        !trimmedFirstName.isEmpty && sex != nil && heightCm != nil && birthDate != nil
    }

    /// The profile fields this step holds — only those answered, so nothing saved is cleared.
    /// The first name is Clerk's.
    var profilePatch: AthleteProfilePatch {
        var patch = AthleteProfilePatch()
        if let sex { patch.setSex(sex) }
        if let heightCm { patch.set(.heightCm, int: heightCm) }
        if let birthDate { patch.set(.birthDate, string: ProfileFieldFormat.isoDay(birthDate)) }
        return patch
    }
}

/// A pain or an injury declared in the onboarding: a zone of the body, what it is, the side and
/// how much it bothers. Nothing is chosen for the athlete; it is complete once each question
/// that applies is answered. Kept on the phone until the health consent is given, then written
/// as a physical note.
nonisolated struct OnboardingInjuryDraft: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        case pain = "PAIN"
        case injury = "INJURY"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .pain: String(localized: "Douleur")
            case .injury: String(localized: "Blessure")
            }
        }
    }

    enum Side: String, CaseIterable, Identifiable, Codable, Sendable {
        case left = "LEFT"
        case right = "RIGHT"
        case both = "BILATERAL"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .left: String(localized: "Gauche")
            case .right: String(localized: "Droite")
            case .both: String(localized: "Les deux")
            }
        }
    }

    /// How much it bothers, in words — stored on the web's 0…10 severity.
    enum Level: Int, CaseIterable, Identifiable, Codable, Sendable {
        case light = 2
        case moderate = 5
        case strong = 8

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .light: String(localized: "Légère")
            case .moderate: String(localized: "Modérée")
            case .strong: String(localized: "Forte")
            }
        }
    }

    /// The web's `COMMON_BODY_PARTS`, so a note written here reads the same on the web.
    static let bodyParts = [
        String(localized: "Genou"), String(localized: "Cheville"), String(localized: "Pied"), String(localized: "Mollet"), String(localized: "Cuisse"), String(localized: "Ischio"), String(localized: "Hanche"),
        String(localized: "Bassin"), String(localized: "Dos"), String(localized: "Lombaires"), String(localized: "Épaule"), String(localized: "Cou"), String(localized: "Tendon d'Achille"),
    ]

    /// Grouped under « Bas du corps » in the injuries step.
    static let lowerBodyParts: Set<String> = [
        String(localized: "Genou"), String(localized: "Cheville"), String(localized: "Pied"), String(localized: "Mollet"), String(localized: "Cuisse"), String(localized: "Ischio"), String(localized: "Hanche"), String(localized: "Bassin"), String(localized: "Tendon d'Achille"),
    ]

    /// Zones that come in pairs, and so ask for a side.
    static let pairedParts: Set<String> = [
        String(localized: "Genou"), String(localized: "Cheville"), String(localized: "Pied"), String(localized: "Mollet"), String(localized: "Cuisse"), String(localized: "Ischio"), String(localized: "Hanche"), String(localized: "Épaule"), String(localized: "Tendon d'Achille"),
    ]

    var id: String { bodyPart }
    let bodyPart: String
    var kind: Kind?
    var side: Side?
    var level: Level?

    init(bodyPart: String) {
        self.bodyPart = bodyPart
    }

    var asksForSide: Bool { Self.pairedParts.contains(bodyPart) }

    var isComplete: Bool { kind != nil && level != nil && (!asksForSide || side != nil) }

    /// « Douleur genou droit » — the note's title, as an athlete would write it.
    var title: String {
        var words = [(kind ?? .pain).label, bodyPart.lowercased()]
        switch side {
        case .left: words.append("gauche")
        case .right: words.append("droit")
        case .both: words.append(String(localized: "des deux côtés"))
        case nil: break
        }
        return words.joined(separator: " ")
    }

    var note: CreatePhysicalNoteInput {
        CreatePhysicalNoteInput(
            category: (kind ?? .pain).rawValue,
            title: title,
            bodyPart: bodyPart,
            side: side?.rawValue ?? "NA",
            severity: (level ?? .moderate).rawValue,
            affectsTraining: true
        )
    }
}

/// What the intention step records — the web's `OnboardingIntentionKind` minus `later`,
/// which is the step's Passer.
nonisolated enum OnboardingIntentionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case race
    case metric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .race: String(localized: "Une course")
        case .metric: String(localized: "Un objectif chiffré")
        }
    }
}

/// The few fields the wizard asks for a first goal, turned into the same payload as the
/// web's `buildOnboardingGoalPayload` (`src/lib/onboarding/status/intention.ts`).
nonisolated struct OnboardingIntentionDraft: Equatable, Codable, Sendable {
    var kind: OnboardingIntentionKind = .race

    /// Optional custom name (« Marathon de Paris »); empty → format label.
    var raceTitle = ""
    var raceDate: Date
    var raceLocation = ""
    /// ADR-082 structured race — required for a race intention.
    var discipline: RaceDiscipline?
    var formatKey = ""
    /// « Terminer », « Sub 5 h » — optional.
    var targetPerformance = ""

    var metricTitle = ""
    var metricTargetText = ""
    var metricUnit = ""

    init(now: Date = Date(), calendar: Calendar = .current) {
        raceDate = calendar.date(byAdding: .month, value: 3, to: now) ?? now
    }

    var selectedFormat: RaceFormatEntry? {
        RaceFormatCatalog.entry(key: formatKey)
    }

    /// Accepts « 42,2 » as the French keyboard types it.
    var metricTarget: Double? {
        Double(metricTargetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    var isValid: Bool {
        switch kind {
        case .race:
            return discipline != nil && !formatKey.trimmed.isEmpty && RaceFormatCatalog.entry(key: formatKey) != nil
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
            let format = selectedFormat
            let title = raceTitle.trimmed.isEmpty ? (format?.label ?? formatKey) : raceTitle.trimmed
            let distances = format?.distances
            return CreateGoalInput(
                title: title,
                kind: .race,
                priority: .a,
                targetDate: raceDate,
                location: raceLocation.trimmed.isEmpty ? nil : raceLocation.trimmed,
                raceFormat: format?.label,
                targetPerformance: targetPerformance.trimmed.isEmpty ? nil : targetPerformance.trimmed,
                discipline: discipline?.rawValue,
                formatKey: formatKey,
                swimM: distances?.swimM,
                bikeM: distances?.bikeM,
                runM: distances?.runM,
                run2M: distances?.run2M,
                segments: distances?.segments
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
    static let shortLabels = [String(localized: "Dim"), String(localized: "Lun"), String(localized: "Mar"), String(localized: "Mer"), String(localized: "Jeu"), String(localized: "Ven"), String(localized: "Sam")]
    static let labels = [String(localized: "Dimanche"), String(localized: "Lundi"), String(localized: "Mardi"), String(localized: "Mercredi"), String(localized: "Jeudi"), String(localized: "Vendredi"), String(localized: "Samedi")]

    static func label(_ day: Int) -> String {
        labels.indices.contains(day) ? labels[day] : ""
    }

    /// « 3 séances possibles · Mardi, Jeudi, Samedi » — nil when nothing is declared, rather
    /// than inventing a default.
    static func reading(_ availability: V1TrainingAvailability) -> String? {
        let days = availability.availableWeekdays
        guard !days.isEmpty else { return nil }
        let count = availability.targetSessionsPerWeek ?? days.count
        let sessions = count == 1 ? String(localized: "1 séance possible") : String(localized: "\(count) séances possibles")
        return "\(sessions) · \(days.map(label).joined(separator: ", "))"
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Why the athlete comes, beyond the coaching every account gets: each answer turns a part of
/// SharpIt on, and what is left unticked stays out of the app until Paramètres brings it back.
nonisolated enum OnboardingMotivation {
    /// The plan, the coach, the sessions — presented as available during onboarding; Pro is
    /// asked later, when the week would enter the plan (SHARPIT ADR-097).
    static let coachingTitle = String(localized: "Être coaché vers mon objectif")
    static let coachingDetail = String(localized: "Ton plan, tes séances et ton coach.")

    /// The question as the athlete reads it, one per feature.
    static func title(_ feature: SharpitFeature) -> String {
        switch feature {
        case .health: String(localized: "Suivre ma santé")
        case .journal: String(localized: "Comprendre l'effet de mes habitudes")
        case .nutrition: String(localized: "Suivre ce que je mange")
        case .regularity: String(localized: "Garder un œil sur ma régularité")
        }
    }

    static func detail(_ feature: SharpitFeature) -> String {
        switch feature {
        case .health: String(localized: "Cœur au repos, VFC, sommeil, VO₂max : l'onglet Santé.")
        case .journal: String(localized: "Alcool, écrans, humeur : leur effet sur ta nuit et ta récupération.")
        case .nutrition: String(localized: "Tes repas face à ta charge du jour.")
        case .regularity: String(localized: "Tes jours d'entraînement autour d'aujourd'hui, sur Résumé et en widget.")
        }
    }

    /// Health first: it is what most athletes come for after the coach.
    static let order: [SharpitFeature] = [.health, .journal, .nutrition, .regularity]
}

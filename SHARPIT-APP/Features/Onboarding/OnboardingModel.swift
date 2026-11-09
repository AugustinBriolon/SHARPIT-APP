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
        case .injuries: String(localized: "Corps")
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
        case .equipment: String(localized: "En plus, si tu as")
        case .week: String(localized: "Ta semaine type")
        case .goal: String(localized: "Ton objectif")
        case .injuries: String(localized: "Ton corps")
        case .privacy: String(localized: "Tes données, tes règles")
        case .sources: String(localized: "Tes sources")
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
            String(localized: "Optionnel : ce qui ouvre d'autres séances. Sans rien coché, le coach prévoit des séances dehors, sans matériel.")
        case .week:
            String(localized: "Choisis l'intensité que tu veux donner à tes semaines, puis les jours qui vont avec.")
        case .goal:
            String(localized: "Une course, un chiffre ou juste la régularité : ton plan se construit autour.")
        case .injuries:
            String(localized: "Douleur, blessure en cours ou ancienne, ou un terrain à ménager : le coach en tient compte.")
        case .privacy:
            String(localized: "Avant de brancher tes appareils, choisis ce que SharpIt peut faire de tes données.")
        case .sources:
            String(localized: "Montre, téléphone ou rien du tout : Apple Santé compte déjà tes pas et tes marches. Tu pourras brancher une montre plus tard.")
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

/// What the athlete declares on the body step: a zone that hurts, an injury in progress, an old
/// one still fragile — each placed on the silhouette — or a health ground with no zone
/// (osteoporosis, water retention…). Nothing is chosen for the athlete; it is complete once each
/// question that applies is answered. Kept on the phone until the health consent is given, then
/// written as a physical note.
nonisolated struct OnboardingInjuryDraft: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        case pain = "PAIN"
        case injury = "INJURY"
        /// Healed, but the coach should still go easy on it (SHARPIT `MONITORING`).
        case fragile = "FRAGILE"
        /// A health ground with no zone on the body.
        case condition = "CONDITION"

        var id: String { rawValue }

        /// The kinds asked of a zone on the body.
        static let zoneKinds: [Kind] = [.pain, .injury, .fragile]

        var label: String {
            switch self {
            case .pain: String(localized: "Douleur")
            case .injury: String(localized: "Blessure en cours")
            case .fragile: String(localized: "Ancienne blessure, encore fragile")
            case .condition: String(localized: "Terrain de santé")
            }
        }

        /// The note's first word.
        var titleWord: String {
            switch self {
            case .pain: String(localized: "Douleur")
            case .injury: String(localized: "Blessure")
            case .fragile: String(localized: "Fragilité")
            case .condition: ""
            }
        }

        /// The web's `PhysicalCategory`.
        var category: String {
            switch self {
            case .pain: "PAIN"
            case .injury, .fragile: "INJURY"
            case .condition: "OTHER"
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

    /// The grounds offered under the body; the cycle only to a woman.
    static func conditions(for sex: AthleteSex?) -> [String] {
        let shared = [String(localized: "Ostéoporose"), String(localized: "Rétention d'eau")]
        return sex == .female ? shared + [String(localized: "Cycle menstruel")] : shared
    }

    /// The web's `COMMON_BODY_PARTS` the silhouette draws — never the onboarding's old « Cuisse ».
    static let bodyParts: [String] = SensitiveZoneBody.mappedParts.filter { $0 != "Cuisse" }.sorted()

    var id: String { bodyPart }
    /// The zone, or the ground's name for a condition.
    let bodyPart: String
    var kind: Kind?
    var side: Side?
    var level: Level?

    init(bodyPart: String, side: Side? = nil) {
        self.bodyPart = bodyPart
        self.side = side
    }

    static func condition(_ name: String) -> OnboardingInjuryDraft {
        var draft = OnboardingInjuryDraft(bodyPart: name)
        draft.kind = .condition
        return draft
    }

    var isCondition: Bool { kind == .condition }

    var asksForSide: Bool { !isCondition && SensitiveZoneBody.isPaired(bodyPart) }

    /// A fragile zone or a ground does not hurt now: no level to ask.
    var asksForLevel: Bool { kind == .pain || kind == .injury }

    var isComplete: Bool {
        kind != nil && (!asksForLevel || level != nil) && (!asksForSide || side != nil)
    }

    /// « Douleur genou droit », « Fragilité cheville gauche », « Ostéoporose ».
    var title: String {
        if isCondition { return bodyPart }
        var words = [(kind ?? .pain).titleWord, bodyPart.lowercased()]
        switch side {
        case .left: words.append("gauche")
        case .right: words.append("droit")
        case .both: words.append(String(localized: "des deux côtés"))
        case nil: break
        }
        return words.joined(separator: " ")
    }

    var note: CreatePhysicalNoteInput {
        let kind = kind ?? .pain
        return CreatePhysicalNoteInput(
            category: kind.category,
            title: title,
            bodyPart: isCondition ? nil : bodyPart,
            side: side?.rawValue ?? "NA",
            severity: asksForLevel ? (level ?? .moderate).rawValue : Level.light.rawValue,
            affectsTraining: true,
            // Nothing hurts now: the coach watches it rather than treating it.
            status: asksForLevel ? nil : "MONITORING"
        )
    }
}

/// What the intention step records — the web's `OnboardingIntentionKind` minus `later`,
/// which is the step's Passer.
nonisolated enum OnboardingIntentionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case race
    case metric
    /// Keep fit, train regularly: no date and no figure.
    case habit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .race: String(localized: "Une course")
        case .metric: String(localized: "Un chiffre à atteindre")
        case .habit: String(localized: "Garder la forme")
        }
    }

    var symbolName: String {
        switch self {
        case .race: "flag.checkered"
        case .metric: "gauge.with.needle"
        case .habit: "figure.walk.motion"
        }
    }

    var detail: String {
        switch self {
        case .race: String(localized: "Une date, une distance.")
        case .metric: String(localized: "Une FTP, une VMA, une charge…")
        case .habit: String(localized: "Bouger régulièrement et rester en forme, sans échéance.")
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
        case .habit:
            return true
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
        case .habit:
            return CreateGoalInput(title: String(localized: "Garder la forme"), kind: .habit)
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

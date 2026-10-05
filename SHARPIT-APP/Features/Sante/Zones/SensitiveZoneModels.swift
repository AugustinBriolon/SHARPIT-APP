import Foundation

/// The words and choices of the zones pages. The web decides what a zone does to the plan; these
/// only name the options the athlete picks from (SHARPIT ADR-068).
nonisolated enum SensitiveZoneOptions {
    struct Choice: Identifiable, Hashable, Sendable {
        let value: String
        let label: String
        var id: String { value }
    }

    static let categories = [
        Choice(value: "PAIN", label: "Douleur"),
        Choice(value: "INJURY", label: "Blessure"),
        Choice(value: "MOBILITY", label: "Mobilité"),
        Choice(value: "POSTURE", label: "Posture"),
        Choice(value: "OTHER", label: "Autre"),
    ]

    static let sides = [
        Choice(value: "NA", label: "Sans objet"),
        Choice(value: "LEFT", label: "Gauche"),
        Choice(value: "RIGHT", label: "Droite"),
        Choice(value: "BILATERAL", label: "Les deux"),
    ]

    /// What the athlete can still do — the web reads it with the severity to grade the plan.
    static let impacts = [
        Choice(value: "NONE", label: "Aucune gêne"),
        Choice(value: "MILD", label: "Gêne légère"),
        Choice(value: "MODERATE", label: "Gêne modérée"),
        Choice(value: "LIMITING", label: "Limite l'entraînement"),
        Choice(value: "STOPPED", label: "Empêche de s'entraîner"),
    ]

    /// Posture and mobility are worked on, not avoided: their impact question reads differently.
    static func isCorrective(_ category: String) -> Bool {
        category == "POSTURE" || category == "MOBILITY"
    }

    static func label(_ value: String, in choices: [Choice]) -> String {
        choices.first { $0.value == value }?.label ?? value
    }
}

/// A zone being declared or edited.
nonisolated struct SensitiveZoneDraft: Equatable, Sendable {
    var category = "PAIN"
    var title = ""
    /// One of the offered body parts, or nil when the athlete writes their own.
    var bodyPart: String?
    var customBodyPart = ""
    var side = "NA"
    var severity = 3
    var functionalImpact: String?
    var description = ""
    var affectsTraining = true

    init() {}

    init(zone: V1SensitiveZone, offered: [String]) {
        category = zone.category
        title = zone.title
        if let part = zone.bodyPart, offered.contains(part) {
            bodyPart = part
        } else {
            customBodyPart = zone.bodyPart ?? ""
        }
        side = zone.side
        severity = zone.severity ?? 0
        functionalImpact = zone.functionalImpact
        description = zone.description ?? ""
        affectsTraining = zone.affectsTraining
    }

    var region: String? {
        if let bodyPart { return bodyPart }
        let custom = customBodyPart.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? nil : custom
    }

    /// The name the athlete gave, or « Douleur · Genou » when they gave none.
    var resolvedTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let kind = SensitiveZoneOptions.label(category, in: SensitiveZoneOptions.categories)
        return [kind, region].compactMap { $0 }.joined(separator: " · ")
    }

    var isComplete: Bool { region != nil }

    private var trimmedDescription: String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var createInput: CreatePhysicalNoteInput {
        CreatePhysicalNoteInput(
            category: category,
            title: resolvedTitle,
            bodyPart: region ?? "",
            side: side,
            severity: severity,
            affectsTraining: affectsTraining,
            functionalImpact: functionalImpact,
            description: trimmedDescription
        )
    }

    /// Only what changed against the zone as served.
    func patch(from zone: V1SensitiveZone) -> PhysicalNotePatch {
        var patch = PhysicalNotePatch()
        if category != zone.category { patch.category = category }
        if resolvedTitle != zone.title { patch.title = resolvedTitle }
        if region != zone.bodyPart { patch.bodyPart = region }
        if side != zone.side { patch.side = side }
        if severity != zone.severity { patch.severity = severity }
        if functionalImpact != zone.functionalImpact { patch.functionalImpact = functionalImpact }
        if trimmedDescription != zone.description { patch.description = trimmedDescription ?? "" }
        if affectsTraining != zone.affectsTraining { patch.affectsTraining = affectsTraining }
        return patch
    }
}

/// One follow-up being written.
nonisolated struct ZoneCheckinDraft: Equatable, Sendable {
    var severity: Int?
    var functionalImpact: String?
    var comment = ""

    var isComplete: Bool { severity != nil }

    var input: PhysicalCheckinInput? {
        guard let severity else { return nil }
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhysicalCheckinInput(
            severity: severity,
            functionalImpact: functionalImpact,
            comment: text.isEmpty ? nil : text
        )
    }
}

/// The status changes a zone offers, in the order they read.
nonisolated enum ZoneStatusAction: String, CaseIterable, Identifiable, Sendable {
    case monitor = "MONITORING"
    case resume = "ACTIVE"
    case resolve = "RESOLVED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monitor: "Passer sous surveillance"
        case .resume: "Remettre en cours"
        case .resolve: "Marquer résolue"
        }
    }

    var symbol: String {
        switch self {
        case .monitor: "eye"
        case .resume: "arrow.uturn.backward"
        case .resolve: "checkmark.circle"
        }
    }

    /// From a resolved zone, the only way is back: a relapse.
    static func available(for status: String) -> [ZoneStatusAction] {
        switch status {
        case "ACTIVE": [.monitor, .resolve]
        case "MONITORING": [.resume, .resolve]
        default: []
        }
    }
}

/// The lines Santé shows about the zones, before opening them.
nonisolated enum SensitiveZoneReadout {
    /// « 1 à protéger · 2 à corriger », or nil when nothing is open.
    static func summary(_ zones: [V1SensitiveZone]) -> String? {
        let open = zones.filter { !$0.isResolved }
        guard !open.isEmpty else { return nil }
        let groups: [(V1SensitiveZone.Strategy, String)] = [
            (.protect, "à protéger"),
            (.progressive, "en reprise"),
            (.correct, "à corriger"),
        ]
        let parts = groups.compactMap { strategy, words -> String? in
            let count = open.filter { $0.strategy == strategy }.count
            return count > 0 ? "\(count) \(words)" : nil
        }
        return parts.isEmpty ? plural(open.count, "zone suivie", "zones suivies") : parts.joined(separator: " · ")
    }

    /// The question that leads Santé's card, when one is owed.
    static func prompt(_ zones: [V1SensitiveZone]) -> String? {
        let suggested = zones.filter(\.resolutionSuggested)
        if let first = suggested.first {
            return suggested.count == 1
                ? "« \(first.title) » ne fait plus mal : c'est résolu ?"
                : "\(suggested.count) zones ne font plus mal : à clore ?"
        }
        return zones.first { $0.followUpQuestion != nil }?.followUpQuestion
    }

    static func severity(_ value: Int?) -> String {
        value.map { "\($0)/10" } ?? "—"
    }

    static func upcoming(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 séance à venir la sollicite"
        default: "\(count) séances à venir la sollicitent"
        }
    }

    static func relapses(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "1 rechute"
        default: "\(count) rechutes"
        }
    }

    private static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}

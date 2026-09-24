import SwiftUI

/// A calendar change the coach proposed, as the thread shows it — the web's
/// `coach-tool-approval-helpers.tsx` and `tool-activity.tsx`, worded the same.
nonisolated struct CoachProposal: Equatable, Identifiable {
    enum Status: Equatable {
        /// Waiting for Valider or Refuser.
        case awaiting(approvalId: String)
        /// Validated, and on its way to the server.
        case accepted
        case refused
        /// Carried out by the server.
        case applied
        case failed(String)
        /// Still being written by the coach.
        case drafting
    }

    let id: String
    let toolType: String
    let status: Status
    let headline: String
    let date: String?
    let intentLine: String?
    let steps: [String]

    var isDelete: Bool { toolType == "tool-deletePlannedSession" }

    /// « Ajouter une séance », « Modifier une séance »…
    var proposal: String { Self.proposalLabels[toolType] ?? "Proposition" }

    /// « Séance ajoutée », « Séance supprimée »…
    var doneLabel: String { Self.doneLabels[toolType] ?? "Fait" }

    var symbolName: String {
        switch toolType {
        case "tool-createPlannedSession": "calendar.badge.plus"
        case "tool-createBrickSession": "square.stack.3d.up"
        case "tool-updatePlannedSession": "pencil.line"
        case "tool-deletePlannedSession": "calendar.badge.minus"
        case "tool-setTravelContext": "mappin.and.ellipse"
        default: "heart.text.square"
        }
    }

    private static let proposalLabels = [
        "tool-createPlannedSession": "Ajouter une séance",
        "tool-createBrickSession": "Ajouter un brick (multisport)",
        "tool-updatePlannedSession": "Modifier une séance",
        "tool-deletePlannedSession": "Supprimer une séance",
        "tool-setTravelContext": "Enregistrer un contexte voyage",
        "tool-setTrainingConstraint": "Enregistrer une contrainte",
    ]

    private static let doneLabels = [
        "tool-createPlannedSession": "Séance ajoutée",
        "tool-createBrickSession": "Brick ajouté",
        "tool-updatePlannedSession": "Séance modifiée",
        "tool-deletePlannedSession": "Séance supprimée",
        "tool-setTravelContext": "Contexte voyage enregistré",
        "tool-setTrainingConstraint": "Contrainte enregistrée",
    ]

    private static let failureHints = [
        "tool-createPlannedSession": "Cette séance n'a pas pu être ajoutée",
        "tool-createBrickSession": "Ce brick n'a pas pu être ajouté",
        "tool-updatePlannedSession": "Cette séance n'a pas pu être modifiée",
        "tool-deletePlannedSession": "Cette séance n'a pas pu être supprimée",
        "tool-setTravelContext": "Ce contexte voyage n'a pas pu être enregistré",
        "tool-setTrainingConstraint": "Cette contrainte n'a pas pu être enregistrée",
    ]

    private static let sportLabels = [
        "RUN": "Course", "BIKE": "Vélo", "SWIM": "Natation", "STRENGTH": "Musculation",
        "TRIATHLON": "Triathlon", "HIKE": "Randonnée", "OTHER": "Autre",
    ]

    private static let intensityLabels = [
        "RECOVERY": "Récupération", "ENDURANCE": "Endurance", "TEMPO": "Tempo",
        "THRESHOLD": "Seuil", "VO2MAX": "VO2max", "RACE": "Compétition",
    ]

    private static let stepKinds = [
        "warmup": "Échauffement", "interval": "Travail", "recovery": "Récup",
        "rest": "Repos", "cooldown": "Retour au calme",
    ]

    private static let maxSteps = 6

    /// Nil for a part that is not a calendar proposal.
    init?(part: JSONValue) {
        guard let type = part["type"]?.string, CoachUIParts.calendarToolTypes.contains(type) else { return nil }
        let input = part["input"] ?? .object([:])
        let output = part["output"]

        id = part["toolCallId"]?.string ?? part["approval"]?["id"]?.string ?? type
        toolType = type

        let state = part["state"]?.string ?? ""
        let approval = part["approval"]
        switch state {
        case "approval-requested" where approval?["isAutomatic"] != .bool(true):
            status = .awaiting(approvalId: approval?["id"]?.string ?? "")
        case "approval-responded":
            status = approval?["approved"] == .bool(false) ? .refused : .accepted
        case "output-denied":
            status = .refused
        case "output-available" where output?["ok"] != .bool(false):
            status = .applied
        case "output-available", "output-error":
            let raw = (output?["error"]?.string ?? part["errorText"]?.string)?.trimmingCharacters(in: .whitespaces)
            status = .failed(Self.humanized(raw) ?? Self.failureHints[type] ?? "L'opération n'a pas abouti")
        default:
            status = .drafting
        }

        let title = (output?["title"]?.string ?? input["title"]?.string)?.trimmingCharacters(in: .whitespaces)
        date = (input["date"]?.string ?? output?["date"]?.string).map(Self.formattedDate)

        switch type {
        case "tool-deletePlannedSession":
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Séance ciblée"
            intentLine = nil
            steps = []
        case "tool-createBrickSession":
            let legs = input["legs"]?.array ?? []
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Brick multisport"
            intentLine = legs.isEmpty ? nil : "\(legs.count) jambes"
            steps = legs.prefix(Self.maxSteps).map { leg in
                let sport = leg["type"]?.string.flatMap { Self.sportLabels[$0] } ?? "Jambe"
                let name = leg["title"]?.string?.trimmingCharacters(in: .whitespaces)
                return [name.flatMap { $0.isEmpty ? nil : $0 } ?? sport, Self.minutes(leg["durationMin"])]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
        case "tool-setTravelContext":
            headline = input["locationLabel"]?.string ?? title ?? Self.proposalLabels[type] ?? "Proposition"
            intentLine = [input["startDate"]?.string, input["endDate"]?.string]
                .compactMap { $0.map(Self.formattedDate) }
                .joined(separator: " → ")
                .nilIfEmpty
            steps = []
        default:
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.proposalLabels[type] ?? "Proposition"
            intentLine = Self.intentLine(input)
            steps = Self.steps(input)
        }
    }

    private static func minutes(_ value: JSONValue?) -> String? {
        guard case .number(let minutes) = value else { return nil }
        return "\(Int(minutes)) min"
    }

    private static func intensity(_ value: JSONValue?) -> String? {
        guard let raw = value?.string else { return nil }
        return intensityLabels[raw] ?? raw
    }

    private static func intentLine(_ input: JSONValue) -> String? {
        var parts: [String] = []
        if let sport = input["type"]?.string.flatMap({ sportLabels[$0] }) { parts.append(sport) }
        if let duration = minutes(input["durationMin"]) { parts.append(duration) }
        if let intensity = intensity(input["intensity"]) { parts.append(intensity) }
        if case .number(let load) = input["load"] { parts.append("charge \(Int(load.rounded()))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Endurance blocks, else the strength sets, else the description's lines.
    private static func steps(_ input: JSONValue) -> [String] {
        let blocks = input["endurancePrescription"]?["blocks"]?.array ?? []
        var lines: [String] = []
        for block in blocks {
            let blockSteps = block["steps"]?.array ?? []
            if case .number(let times) = block["times"], times > 1, !blockSteps.isEmpty {
                lines.append("\(Int(times))× " + blockSteps.map(step).joined(separator: " + "))
            } else {
                lines.append(contentsOf: blockSteps.map(step))
            }
            if lines.count >= maxSteps { break }
        }
        if !lines.isEmpty { return Array(lines.prefix(maxSteps)) }

        let sets = (input["strengthPrescription"]?["sets"]?.array ?? []).sorted {
            orderValue($0) < orderValue($1)
        }
        if !sets.isEmpty {
            return sets.prefix(maxSteps).map { $0["exercise"]?.string?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Exercice" }
        }

        guard let description = input["description"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty
        else { return [] }
        let split = description
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: #"^[-•*\d.)\s]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if split.count > 1 { return Array(split.prefix(maxSteps)) }
        return [description.count <= 220 ? description : String(description.prefix(200)).trimmingCharacters(in: .whitespaces) + "…"]
    }

    private static func orderValue(_ set: JSONValue) -> Double {
        if case .number(let order) = set["order"] { return order }
        return 0
    }

    private static func step(_ step: JSONValue) -> String {
        let kind = step["kind"]?.string.map { stepKinds[$0] ?? $0 }
        var duration = minutes(step["minutes"])
        if duration == nil, case .number(let meters) = step["meters"] {
            duration = meters >= 1000 ? "\(formatted(meters / 1000)) km" : "\(Int(meters)) m"
        }
        let parts = [kind, duration, intensity(step["effort"])].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return step["notes"]?.string?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Étape"
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// « 2026-09-26 » → « samedi 26 septembre »; anything else as it came.
    static func formattedDate(_ raw: String) -> String {
        let day = String(raw.prefix(10))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    /// The web's `humanizeToolErrorMessage`: French passes through, English becomes a hint.
    private static func humanized(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("an error occurred") { return "L'opération n'a pas abouti" }
        if lower.contains("fetch failed") || lower.contains("network") { return "Problème de connexion — réessaie dans un instant" }
        if lower.contains("timeout") || lower.contains("timed out") { return "La requête a pris trop de temps" }
        if raw.range(of: "[àâäéèêëïîôùûüç]", options: [.regularExpression, .caseInsensitive]) != nil { return raw }
        return "L'opération n'a pas abouti"
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A proposal in the thread: a card to validate while it waits, a line once it is settled.
///
/// Deleting asks twice, as on the web — the first « Confirmer » names the consequence.
struct CoachProposalCard: View {
    let proposal: CoachProposal
    /// Nil while an answer is on its way: the buttons wait with it.
    let onAnswer: ((Bool) -> Void)?

    @State private var confirmingDelete = false

    var body: some View {
        switch proposal.status {
        case .awaiting:
            card
        case .drafting:
            line(proposal.proposal + "…", symbol: proposal.symbolName, tone: SharpitColor.mutedForeground, progress: true)
        case .accepted:
            line("Validé — \(proposal.proposal.lowercased())", symbol: "checkmark", tone: SharpitColor.mutedForeground, progress: true)
        case .applied:
            line(proposal.doneLabel + suffix, symbol: "checkmark.circle.fill", tone: SharpitColor.signalRecovery)
        case .refused:
            line("Refusé — \(proposal.proposal.lowercased())", symbol: "xmark.circle", tone: SharpitColor.mutedForeground)
        case .failed(let hint):
            line(hint + suffix, symbol: "exclamationmark.triangle.fill", tone: SharpitColor.signalRisk)
        }
    }

    private var suffix: String {
        proposal.headline == proposal.proposal ? "" : " — \(proposal.headline)"
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Image(systemName: proposal.symbolName)
                    .foregroundStyle(SharpitColor.primary)
                SharpitEyebrow(proposal.isDelete ? "Suppression à valider" : "Proposition du coach")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.headline)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                let meta = [proposal.date, proposal.isDelete ? nil : proposal.proposal].compactMap { $0 }
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            if let intent = proposal.intentLine {
                Text(intent)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.foreground)
            }
            if !proposal.steps.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    ForEach(Array(proposal.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                            Circle()
                                .fill(SharpitColor.mutedForeground)
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                            Text(step)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if proposal.isDelete, confirmingDelete {
                Text(proposal.date.map { "Cette séance sera retirée du plan (\($0)). Action irréversible." }
                    ?? "Cette séance sera retirée du plan. Action irréversible.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .transition(.opacity)
            }
            HStack(spacing: SharpitSpacing.sm) {
                Button(proposal.isDelete ? "Garder" : "Refuser") {
                    confirmingDelete = false
                    onAnswer?(false)
                }
                .buttonStyle(.bordered)
                .tint(SharpitColor.mutedForeground)

                Button(approveLabel, role: proposal.isDelete && confirmingDelete ? .destructive : nil) {
                    if proposal.isDelete, !confirmingDelete {
                        withAnimation(SharpitMotion.selection) { confirmingDelete = true }
                        return
                    }
                    onAnswer?(true)
                }
                .buttonStyle(.borderedProminent)
                .tint(proposal.isDelete && confirmingDelete ? SharpitColor.signalRisk : SharpitColor.primary)
            }
            .font(SharpitTypography.meta.weight(.semibold))
            .disabled(onAnswer == nil)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .sensoryFeedback(.selection, trigger: confirmingDelete)
    }

    private var approveLabel: String {
        guard proposal.isDelete else { return "Valider" }
        return confirmingDelete ? "Confirmer la suppression" : "Confirmer"
    }

    private func line(_ text: String, symbol: String, tone: Color, progress: Bool = false) -> some View {
        HStack(spacing: SharpitSpacing.xs) {
            if progress {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: symbol)
            }
            Text(text)
                .lineLimit(2)
        }
        .font(SharpitTypography.meta.weight(.semibold))
        .foregroundStyle(tone)
        .padding(.horizontal, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.xs)
        .sharpitSurface(.chip)
        .transition(.opacity)
    }
}

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
    /// The day the change bears on, to open the plan there once it is carried out.
    let day: Date?

    /// As read from the thread (`init?(part:)`), or built whole by a demo or a test.
    init(id: String, toolType: String, status: Status, headline: String, date: String? = nil, intentLine: String? = nil, steps: [String] = [], day: Date? = nil) {
        self.day = day
        self.id = id
        self.toolType = toolType
        self.status = status
        self.headline = headline
        self.date = date
        self.intentLine = intentLine
        self.steps = steps
    }

    var isDelete: Bool { toolType == "tool-deletePlannedSession" }

    /// « Ajouter une séance », « Modifier une séance »…
    var proposal: String { Self.proposalLabels[toolType] ?? String(localized: "Proposition") }

    /// « Séance ajoutée », « Séance supprimée »…
    var doneLabel: String { Self.doneLabels[toolType] ?? String(localized: "Fait") }

    var symbolName: String {
        switch toolType {
        case "tool-createPlannedSession": "calendar.badge.plus"
        case "tool-createBrickSession": "square.stack.3d.up"
        case "tool-updatePlannedSession": "pencil.line"
        case "tool-deletePlannedSession": "calendar.badge.minus"
        case "tool-setTravelContext": "mappin.and.ellipse"
        case "tool-proposePlaybookAction": "cross.case"
        default: "heart.text.square"
        }
    }

    private static let proposalLabels = [
        "tool-createPlannedSession": String(localized: "Ajouter une séance"),
        "tool-createBrickSession": String(localized: "Ajouter un brick (multisport)"),
        "tool-updatePlannedSession": String(localized: "Modifier une séance"),
        "tool-deletePlannedSession": String(localized: "Supprimer une séance"),
        "tool-setTravelContext": String(localized: "Enregistrer un contexte voyage"),
        "tool-setTrainingConstraint": String(localized: "Enregistrer une contrainte"),
        "tool-proposePlaybookAction": "Action absence / douleur",
    ]

    private static let doneLabels = [
        "tool-createPlannedSession": String(localized: "Séance ajoutée"),
        "tool-createBrickSession": String(localized: "Brick ajouté"),
        "tool-updatePlannedSession": String(localized: "Séance modifiée"),
        "tool-deletePlannedSession": String(localized: "Séance supprimée"),
        "tool-setTravelContext": String(localized: "Contexte voyage enregistré"),
        "tool-setTrainingConstraint": String(localized: "Contrainte enregistrée"),
        "tool-proposePlaybookAction": String(localized: "Action enregistrée"),
    ]

    private static let failureHints = [
        "tool-createPlannedSession": String(localized: "Cette séance n'a pas pu être ajoutée"),
        "tool-createBrickSession": String(localized: "Ce brick n'a pas pu être ajouté"),
        "tool-updatePlannedSession": String(localized: "Cette séance n'a pas pu être modifiée"),
        "tool-deletePlannedSession": String(localized: "Cette séance n'a pas pu être supprimée"),
        "tool-setTravelContext": String(localized: "Ce contexte voyage n'a pas pu être enregistré"),
        "tool-setTrainingConstraint": String(localized: "Cette contrainte n'a pas pu être enregistrée"),
        "tool-proposePlaybookAction": String(localized: "Cette action n'a pas pu être enregistrée"),
    ]

    private static let sportLabels = [
        "RUN": String(localized: "Course"), "BIKE": String(localized: "Vélo"), "SWIM": String(localized: "Natation"), "STRENGTH": String(localized: "Musculation"),
        "TRIATHLON": String(localized: "Triathlon"), "HIKE": String(localized: "Randonnée"), "OTHER": String(localized: "Autre"),
    ]

    private static let playbookActionLabels = [
        "CONTINUE": String(localized: "Continuer"),
        "LIGHTEN": String(localized: "Alléger"),
        "POSTPONE": String(localized: "Reporter"),
        "RESTART": String(localized: "Reprendre progressivement"),
        "PAUSE": String(localized: "Mettre en pause"),
    ]

    /// The French name of a session intensity, as the coach and the generator both show it.
    static let intensityLabels = [
        "RECOVERY": String(localized: "Récupération"), "ENDURANCE": String(localized: "Endurance"), "TEMPO": String(localized: "Tempo"),
        "THRESHOLD": String(localized: "Seuil"), "VO2MAX": "VO2max", "RACE": String(localized: "Compétition"),
    ]

    /// The French name of an endurance step kind, shared with the workout card.
    static let stepKinds = [
        "warmup": String(localized: "Échauffement"), "interval": String(localized: "Travail"), "recovery": String(localized: "Récup"),
        "rest": String(localized: "Repos"), "cooldown": String(localized: "Retour au calme"),
    ]

    private static let maxSteps = 6

    /// Nil for a part that is not a calendar / context proposal (`logFoods` has its own card).
    init?(part: JSONValue) {
        guard let type = part["type"]?.string,
              CoachUIParts.calendarToolTypes.contains(type),
              type != "tool-logFoods"
        else { return nil }
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
            status = .failed(Self.humanized(raw) ?? Self.failureHints[type] ?? String(localized: "L'opération n'a pas abouti"))
        default:
            status = .drafting
        }

        let title = (output?["title"]?.string ?? input["title"]?.string)?.trimmingCharacters(in: .whitespaces)
        let rawDate = input["date"]?.string ?? output?["date"]?.string
        date = rawDate.map(Self.formattedDate)
        day = rawDate.flatMap { APIDate.day(String($0.prefix(10))) }

        switch type {
        case "tool-deletePlannedSession":
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Séance ciblée")
            intentLine = nil
            steps = []
        case "tool-createBrickSession":
            let legs = input["legs"]?.array ?? []
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Brick multisport")
            intentLine = legs.isEmpty ? nil : "\(legs.count) jambes"
            steps = legs.prefix(Self.maxSteps).map { leg in
                let sport = leg["type"]?.string.flatMap { Self.sportLabels[$0] } ?? String(localized: "Jambe")
                let name = leg["title"]?.string?.trimmingCharacters(in: .whitespaces)
                return [name.flatMap { $0.isEmpty ? nil : $0 } ?? sport, Self.minutes(leg["durationMin"])]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
        case "tool-setTravelContext":
            headline = input["locationLabel"]?.string ?? title ?? Self.proposalLabels[type] ?? String(localized: "Proposition")
            intentLine = [input["startDate"]?.string, input["endDate"]?.string]
                .compactMap { $0.map(Self.formattedDate) }
                .joined(separator: " → ")
                .nilIfEmpty
            steps = []
        case "tool-proposePlaybookAction":
            let action = input["action"]?.string.flatMap { Self.playbookActionLabels[$0] }
            headline = input["label"]?.string
                ?? action
                ?? title
                ?? Self.proposalLabels[type]
                ?? String(localized: "Proposition")
            intentLine = input["rationale"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            steps = []
        default:
            headline = title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.proposalLabels[type] ?? String(localized: "Proposition")
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
        if case .number(let load) = input["load"] { parts.append(String(localized: "charge \(Int(load.rounded()))")) }
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
            return sets.prefix(maxSteps).map { $0["exercise"]?.string?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? String(localized: "Exercice") }
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
        return step["notes"]?.string?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? String(localized: "Étape")
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// « 2026-09-26 » → « samedi 26 septembre »; anything else as it came.
    static func formattedDate(_ raw: String) -> String {
        let day = String(raw.prefix(10))
        guard let date = APIDate.day(day) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    /// The web's `humanizeToolErrorMessage`: French passes through, English becomes a hint.
    private static func humanized(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("an error occurred") { return String(localized: "L'opération n'a pas abouti") }
        if lower.contains("fetch failed") || lower.contains("network") { return String(localized: "Problème de connexion. Réessaie dans un instant") }
        if lower.contains("timeout") || lower.contains("timed out") { return String(localized: "La requête a pris trop de temps") }
        if raw.range(of: "[àâäéèêëïîôùûüç]", options: [.regularExpression, .caseInsensitive]) != nil { return raw }
        return String(localized: "L'opération n'a pas abouti")
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A proposal in the thread, Clinique (the athlete's call, 2026-11-15). While it waits, a bordered
/// card to decide on: what the coach wants to do as a pill beside the day, the session as the
/// title, its figures on one line, the steps as numbered lines, then one ink action over the two
/// quiet ones. Once settled, one line that keeps its place in the thread — the session and what
/// became of it as a status pill. No hue but a status's.
///
/// Deleting is confirmed by holding its button (`CliniqueHoldButton`), the consequence said over
/// it — not by a second tap on a button that changed its words (the athlete's call, 2026-11-22).
/// A change carried out opens the plan on its day.
struct CoachProposalCard: View {
    let proposal: CoachProposal
    /// Nil while an answer is on its way: the buttons wait with it.
    /// Bool is approval; optional reasonOverride covers « Modifier » (revise).
    let onAnswer: ((Bool, String?) -> Void)?
    /// Opens the plan on the day of a change carried out.
    var onOpenPlan: ((Date) -> Void)? = nil

    var body: some View {
        Group {
            if case .awaiting = proposal.status {
                card
            } else {
                receipt
            }
        }
        .animation(SharpitMotion.reveal, value: proposal.status)
    }

    // MARK: Awaiting

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SharpitSpacing.xs) {
                CliniqueStatusPill(proposal.proposal, status: proposal.isDelete ? .alert : .unknown)
                Spacer(minLength: SharpitSpacing.xs)
                if let date = proposal.date {
                    Text(date)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                }
            }

            Text(proposal.headline)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let facts = CoachProposalReadout.facts(proposal.intentLine) {
                Text(facts)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }

            if !proposal.steps.isEmpty {
                steps.padding(.top, 12)
            }

            if proposal.isDelete {
                Text(
                    proposal.date.map { String(localized: "Cette séance sera retirée du plan (\($0)). Action irréversible.") }
                        ?? String(localized: "Cette séance sera retirée du plan. Action irréversible.")
                )
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(SharpitColor.statusAlertForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }

            actions.padding(.top, 14)
        }
        .cliniqueCard()
    }

    /// The session's steps, each a line under a hairline: its number, then what to do.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(proposal.steps.enumerated()), id: \.offset) { index, step in
                CliniqueDivider()
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                    Text("\(index + 1)")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .frame(width: 16, alignment: .leading)
                    Text(step)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
            CliniqueDivider()
        }
    }

    /// The answer that changes the plan in ink across the card; the ways out side by side under it.
    private var actions: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if proposal.isDelete {
                CliniqueHoldButton(title: CoachProposalReadout.approve(proposal)) { onAnswer?(true, nil) }
            } else {
                Button { onAnswer?(true, nil) } label: {
                    Text(CoachProposalReadout.approve(proposal)).frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary))
            }

            HStack(spacing: SharpitSpacing.xs) {
                if !proposal.isDelete {
                    Button { onAnswer?(false, CoachUIParts.reviseReason) } label: {
                        Text("Modifier").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .outline))
                }
                Button { onAnswer?(false, nil) } label: {
                    Text(proposal.isDelete ? String(localized: "Garder la séance") : String(localized: "Ignorer")).frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: proposal.isDelete ? .outline : .plain))
            }
        }
        .disabled(onAnswer == nil)
        .opacity(onAnswer == nil ? 0.5 : 1)
    }

    // MARK: Settled

    /// What was proposed, and what became of it. Kept in the thread, never collapsed to a chip.
    /// A session added or changed opens the plan on its day: the line then carries a chevron.
    @ViewBuilder
    private var receipt: some View {
        if let day = proposal.day, let onOpenPlan, proposal.status == .applied, !proposal.isDelete {
            Button { onOpenPlan(day) } label: { receiptLine(opens: true) }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint(String(localized: "Ouvre le plan à ce jour"))
                .transition(.opacity)
        } else {
            receiptLine(opens: false)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
        }
    }

    private func receiptLine(opens: Bool) -> some View {
        let outcome = CoachProposalReadout.outcome(proposal)
        return HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.headline)
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(outcome.isStruck ? SharpitColor.slate : SharpitColor.foreground)
                    .strikethrough(outcome.isStruck, color: SharpitColor.slate)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let detail = outcome.detail ?? proposal.date {
                    Text(detail)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            if outcome.isWorking {
                ProgressView().controlSize(.small).tint(SharpitColor.slate)
            } else {
                CliniqueStatusPill(outcome.word, status: outcome.status)
            }
            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
        }
        .cliniqueCard()
        .contentShape(Rectangle())
        .accessibilityValue(outcome.word)
    }
}

/// How a proposal reads on its card: its figures, its main answer, and what became of it.
nonisolated enum CoachProposalReadout {
    struct Outcome: Equatable {
        let word: String
        let status: CliniqueStatus
        /// Said under the session instead of its day: why it failed.
        var detail: String? = nil
        var isWorking = false
        var isStruck = false
    }

    /// « Course · 45 min · Seuil · charge 60 », each figure kept whole when the line breaks.
    static func facts(_ intentLine: String?) -> String? {
        guard let parts = intentLine?.components(separatedBy: " · ").filter({ !$0.isEmpty }), !parts.isEmpty else { return nil }
        return parts.joinedAsFacts()
    }

    /// The ink button says what it does: « Ajouter au plan », never a bare « Appliquer ».
    /// A deletion says how it is confirmed: by holding.
    static func approve(_ proposal: CoachProposal) -> String {
        switch proposal.toolType {
        case "tool-createPlannedSession", "tool-createBrickSession": String(localized: "Ajouter au plan")
        case "tool-updatePlannedSession": String(localized: "Appliquer la modification")
        case "tool-deletePlannedSession": String(localized: "Maintenir pour supprimer")
        default: String(localized: "Enregistrer")
        }
    }

    static func outcome(_ proposal: CoachProposal) -> Outcome {
        switch proposal.status {
        case .awaiting: Outcome(word: String(localized: "À valider"), status: .watch)
        case .drafting: Outcome(word: proposal.proposal, status: .unknown, isWorking: true)
        case .accepted: Outcome(word: String(localized: "En cours d'application"), status: .unknown, isWorking: true)
        case .applied: Outcome(word: proposal.doneLabel, status: proposal.isDelete ? .unknown : .good)
        case .refused: Outcome(word: String(localized: "Refusé"), status: .unknown, isStruck: true)
        case .failed(let hint): Outcome(word: String(localized: "Échec"), status: .alert, detail: hint)
        }
    }
}

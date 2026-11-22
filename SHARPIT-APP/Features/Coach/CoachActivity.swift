import SwiftUI

/// What the coach is doing while no words arrive, read from the turn's own parts — never a
/// script on a timer. The route's stream says it: nothing yet while the server gathers the
/// athlete's state, a step opened while the model thinks, a tool named when it reads the plan or
/// builds a session. Once words arrive the answer shows itself, and there is nothing to say.
nonisolated enum CoachActivity: Equatable {
    /// Before the server's first chunk: it reads the athlete's state to brief the model.
    case gathering
    /// The model has the brief and has not written or called anything yet.
    case thinking
    /// A tool is being called — its part type, `tool-listPlannedSessions`.
    case tool(String)
    /// The model has what its tools returned and has not written yet.
    case analysing
    /// An approved change is being carried out server-side.
    case applying

    /// The tools that only hand the answer its closing touches: saying so would flash a line
    /// for a few milliseconds under an answer already written.
    private static let silentTools: Set<String> = ["tool-suggestFollowUps"]

    /// Nil when the turn speaks for itself: words are arriving, or a card waits for an answer.
    static func current(parts: [JSONValue]) -> CoachActivity? {
        guard let last = parts.last, let type = last["type"]?.string else { return .gathering }
        let state = last["state"]?.string

        if type == "text" {
            // An opened text part with no word yet is still the model about to write.
            let isEmpty = (last["text"]?.string ?? "").isEmpty
            return isEmpty && state == "streaming" ? beforeWords(parts) : nil
        }
        if type.hasPrefix("tool-") {
            if silentTools.contains(type) { return nil }
            switch state {
            case "input-streaming", "input-available":
                return .tool(type)
            case "approval-responded":
                return last["approval"]?["approved"] == .bool(true) ? .applying : nil
            case "approval-requested":
                return nil
            default:
                // A card drawn ends the turn (the server's `drewCoachCard`); a change carried
                // out or a read answered is followed by the model's words.
                return drawsCard(last) ? nil : .analysing
            }
        }
        return beforeWords(parts)
    }

    private static func beforeWords(_ parts: [JSONValue]) -> CoachActivity {
        let hasRead = parts.contains { part in
            (part["type"]?.string?.hasPrefix("tool-") ?? false) && CoachUIParts.isTerminal(part["state"]?.string)
        }
        return hasRead ? .analysing : .thinking
    }

    private static func drawsCard(_ part: JSONValue) -> Bool {
        guard part["state"]?.string == "output-available", part["output"]?["ok"] != .bool(false) else { return false }
        return CoachWorkout(part: part) != nil || CoachDataCard(part: part) != nil
    }

    /// One line, a noun and what it bears on, short enough for the narrowest iPhone.
    var label: String {
        switch self {
        case .gathering: String(localized: "Lecture de tes données")
        case .thinking: String(localized: "Réflexion")
        case .analysing: String(localized: "Analyse")
        case .applying: String(localized: "Application du changement")
        case .tool(let type): Self.toolLabel(type)
        }
    }

    private static func toolLabel(_ type: String) -> String {
        switch type {
        case "tool-listPlannedSessions": String(localized: "Lecture de ton plan")
        case "tool-getCalendarAvailability": String(localized: "Lecture de ton agenda")
        case "tool-getScenarioProjection": String(localized: "Projection de ta forme")
        case "tool-searchWatchExercises": String(localized: "Recherche d'exercices")
        case "tool-explainDayScores": String(localized: "Lecture de tes scores du jour")
        case "tool-compareSleepVsReadiness": String(localized: "Comparaison sommeil et forme")
        case "tool-explainTargetBand": String(localized: "Calcul de ta cible d'effort")
        case "tool-listCoachMemory": String(localized: "Lecture de la mémoire")
        case "tool-upsertCoachMemoryNote", "tool-archiveCoachMemoryNote":
            String(localized: "Mise à jour de la mémoire")
        case "tool-createPlannedSession", "tool-createBrickSession", "tool-presentWorkout":
            String(localized: "Construction de la séance")
        case "tool-updatePlannedSession": String(localized: "Ajustement de la séance")
        case "tool-deletePlannedSession": String(localized: "Préparation de la suppression")
        case "tool-setTravelContext", "tool-setTrainingConstraint":
            String(localized: "Prise en compte de ta contrainte")
        case "tool-logFoods": String(localized: "Estimation de ton repas")
        // A tool the app does not know yet still reads something of the athlete's.
        default: String(localized: "Lecture de tes données")
        }
    }
}

/// The coach's activity as one quiet line where its answer will be: slate words a band of ink
/// passes over, changing in place as the work moves on. It stands for the wait only — once the
/// answer writes itself the line is gone, and nothing of it stays in the thread.
struct CoachActivityLine: View {
    let activity: CoachActivity

    /// A line stays long enough to be read: steps a few milliseconds apart would only flicker.
    private static let minimumStay: Duration = .milliseconds(650)
    private static let bandWidth: CGFloat = 130

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?
    @State private var shownAt = ContinuousClock.now
    @State private var sweeps = false

    var body: some View {
        let label = shown ?? activity.label
        // The band lives outside the words it crosses and spans the row, not the words: a line
        // taking another's place is crossed by the same sweep, which a change of width would stop.
        words(label, in: SharpitColor.slate)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .overlay {
                if !reduceMotion {
                    words(label, in: SharpitColor.foreground)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .mask { band }
                }
            }
        .animation(SharpitMotion.fade, value: label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Le coach répond : \(label)"))
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) { sweeps = true }
        }
        .task(id: activity.label) {
            let next = activity.label
            guard shown != nil else {
                shown = next
                shownAt = .now
                return
            }
            let stayed = ContinuousClock.now - shownAt
            if stayed < Self.minimumStay {
                try? await Task.sleep(for: Self.minimumStay - stayed)
                guard !Task.isCancelled else { return }
            }
            shown = next
            shownAt = .now
        }
    }

    private func words(_ label: String, in color: Color) -> some View {
        ZStack(alignment: .leading) {
            Text(label)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(color)
                .lineLimit(1)
                .id(label)
                .transition(.opacity)
        }
    }

    /// The band of ink crossing the words, from before their first letter to past their last.
    private var band: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.bandWidth)
                .offset(x: sweeps ? proxy.size.width : -Self.bandWidth)
        }
    }
}

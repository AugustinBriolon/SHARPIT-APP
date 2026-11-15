import SwiftUI

/// « Échauffement et étirements » on a session already done: one line of « Ta séance » saying
/// what was done of the warm-up and the stretches the plan carried, opening their drawer — the
/// moves, and « Fait / Raccourci / Sauté » for what was forgotten at the time. Read from the plan
/// session the activity is linked to; nothing shows when that session carried none.
struct ActivityRoutinesSection: View {
    let sessionId: String
    /// The activity's day: the plan is read around it, since the session may sit a day apart.
    let around: Date
    let tokenProvider: () async throws -> String

    @State private var session: V1PlannedSessionItem?
    @State private var said: [V1RoutinePart: V1RoutineStatus] = [:]
    @State private var isShowingRoutines = false

    var body: some View {
        if let routines = session?.breakdown?.routines, SessionRoutinesReadout.hasMoves(routines) {
            CliniqueDivider()
            ActivityContextRow(
                title: String(localized: "Échauffement et étirements"),
                value: ActivityRoutinesReadout.line(routines, said: said),
                action: { isShowingRoutines = true }
            )
            .accessibilityHint("Ouvre l'échauffement et les étirements")
            .sheet(isPresented: $isShowingRoutines) {
                SessionRoutinesSheet(routines: routines, durationMin: session?.durationMin) { part, status in
                    said[part] = status
                    record(status, part)
                }
            }
            .task(id: sessionId) { await load() }
        } else {
            Color.clear.frame(height: 0).task(id: sessionId) { await load() }
        }
    }

    private func load() async {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -7, to: around),
              let to = calendar.date(byAdding: .day, value: 7, to: around),
              let token = try? await tokenProvider(),
              let sessions = try? await PlannedSessionClient().plannedSessions(from: from, to: to, token: token)
        else { return }
        session = sessions.first { $0.id == sessionId }
        let routines = session?.breakdown?.routines
        said = [:]
        said[.warmup] = routines?.warmup.routineStatus
        said[.cooldown] = routines?.cooldown.routineStatus
    }

    private func record(_ status: V1RoutineStatus?, _ part: V1RoutinePart) {
        var patch = PlannedSessionFields()
        patch.setRoutineStatus(status, for: part)
        let fields = patch
        let id = sessionId
        Task {
            do {
                try await SharpitRetry.run {
                    _ = try await PlannedSessionClient().updateSession(id: id, fields: fields, token: try await tokenProvider())
                }
            } catch {
                SharpitWriteFailures.shared.report(String(localized: "Ta réponse n'a pas pu être enregistrée. Réessaie dans un instant."))
            }
        }
    }
}

nonisolated enum ActivityRoutinesReadout {
    /// The routines of the plan session an activity is linked to; nil when none was written.
    static func routines(of sessionId: String, in sessions: [V1PlannedSessionItem]) -> V1SessionRoutines? {
        sessions.first { $0.id == sessionId }?.breakdown?.routines
    }

    /// « Fait · Sauté »: what was said of each routine that has moves, the warm-up first;
    /// « À dire » while nothing was said of any.
    static func line(_ routines: V1SessionRoutines, said: [V1RoutinePart: V1RoutineStatus]) -> String {
        let parts: [(V1RoutinePart, V1SessionRoutine)] = [(.warmup, routines.warmup), (.cooldown, routines.cooldown)]
        let answers = parts.filter { !$0.1.moves.isEmpty }.map { said[$0.0]?.label }
        guard answers.contains(where: { $0 != nil }) else { return String(localized: "À dire") }
        return answers.map { $0 ?? "—" }.joined(separator: " · ")
    }
}

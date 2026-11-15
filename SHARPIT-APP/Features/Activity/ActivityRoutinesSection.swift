import SwiftUI

/// « Échauffement et étirements » on a session already done: the warm-up and the stretches the plan
/// carried, each with its « Fait / Raccourci / Sauté » — so what was forgotten at the time can
/// still be said afterwards. Read from the plan session the activity is linked to; nothing
/// shows when that session carried none.
struct ActivityRoutinesSection: View {
    let sessionId: String
    /// The activity's day: the plan is read around it, since the session may sit a day apart.
    let around: Date
    let tokenProvider: () async throws -> String

    @State private var routines: V1SessionRoutines?

    var body: some View {
        if let routines, !routines.warmup.moves.isEmpty || !routines.cooldown.moves.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ActivitySectionTitle(String(localized: "Échauffement et étirements"))
                    .padding(.bottom, 4)
                if !routines.warmup.moves.isEmpty {
                    SessionRoutinePanel(title: String(localized: "Échauffement avant"), routine: routines.warmup) { record($0, .warmup) }
                }
                if !routines.cooldown.moves.isEmpty {
                    SessionRoutinePanel(title: String(localized: "Étirements ciblés"), routine: routines.cooldown) { record($0, .cooldown) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        routines = ActivityRoutinesReadout.routines(of: sessionId, in: sessions)
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
}

import Foundation
import Observation

/// The athlete's own changes to the plan: add a session, edit it, move it, delete it.
///
/// Owned by `PlanView`, so a write outlives the drawer or the form that started it. An edit,
/// a move and a deletion show on the tap and go out behind through `SharpitRetry`; a creation
/// waits for the server, since the plan needs its id. Every write ends in `onChanged`, which
/// bumps the calendar revision: Plan reads the week again, Résumé, the reminders and the
/// iPhone calendar follow. That reload is also what puts a refused change back.
@MainActor
@Observable
final class PlanEditor {
    private let mutator: any PlannedSessionMutating
    private let tokenProvider: () async throws -> String
    private let plan: PlanStore
    /// Set by `PlanView` once the router is in its environment.
    @ObservationIgnored var onChanged: () -> Void = {}

    init(
        mutator: any PlannedSessionMutating,
        tokenProvider: @escaping () async throws -> String,
        plan: PlanStore
    ) {
        self.mutator = mutator
        self.tokenProvider = tokenProvider
        self.plan = plan
    }

    /// Adds the session and shows it once the server has it.
    /// - Returns: the session created, or throws with the server's reason.
    @discardableResult
    func create(_ draft: PlannedSessionDraft) async throws -> V1PlannedSessionItem {
        let fields = draft.creation()
        let created = try await SharpitRetry.run {
            try await mutator.createSession(fields, token: try await tokenProvider())
        }
        plan.show(created)
        onChanged()
        return created
    }

    /// Writes what changed in `draft` since `original`, shown at once.
    /// - Returns: the session as it now reads on screen, to show in its drawer.
    @discardableResult
    func save(_ draft: PlannedSessionDraft, from original: PlannedSessionDraft, of session: V1PlannedSessionItem) -> V1PlannedSessionItem {
        let fields = draft.changes(from: original)
        guard !fields.isEmpty else { return session }
        let edited = session.applying(draft)
        plan.show(edited)
        write(failure: Self.saveFailure) { mutator, token in
            _ = try await mutator.updateSession(id: session.id, fields: fields, token: token)
        }
        return edited
    }

    /// Moves the session to `day`, keeping everything else.
    /// - Returns: the session as it now reads on screen.
    @discardableResult
    func move(_ session: V1PlannedSessionItem, to day: Date) -> V1PlannedSessionItem {
        var draft = PlannedSessionDraft(session: session)
        let original = draft
        draft.day = Calendar.current.startOfDay(for: day)
        return save(draft, from: original, of: session)
    }

    func delete(_ session: V1PlannedSessionItem) {
        plan.showRemoved(sessionId: session.id)
        write(failure: Self.deleteFailure) { mutator, token in
            try await mutator.deleteSession(id: session.id, token: token)
        }
    }

    /// Sends a write behind the screen: retried while the network is the problem, said in
    /// the toast if it fails for good. Either way the plan is read again.
    private func write(
        failure: String,
        _ operation: @escaping @Sendable (any PlannedSessionMutating, String) async throws -> Void
    ) {
        Task {
            do {
                try await SharpitRetry.run {
                    try await operation(mutator, try await tokenProvider())
                }
            } catch let SharpitAPIError.message(reason) {
                SharpitWriteFailures.shared.report(reason)
            } catch {
                SharpitWriteFailures.shared.report(failure)
            }
            onChanged()
        }
    }

    static let saveFailure = "La séance n’a pas pu être modifiée. Réessaie dans un instant."
    static let deleteFailure = "La séance n’a pas pu être supprimée. Réessaie dans un instant."
}

extension V1PlannedSessionItem {
    /// The session as `draft` says it now reads — what Plan and the drawer show until the
    /// server's copy comes back. The breakdown is the server's to resolve, so it stays as it
    /// was, and goes when the sport changes: steps written for one sport say nothing of another.
    func applying(_ draft: PlannedSessionDraft) -> V1PlannedSessionItem {
        let sportChanged = draft.sport.rawValue != type?.uppercased()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return V1PlannedSessionItem(
            id: id,
            date: draft.day,
            startTime: draft.startTime.map(PlannedSessionClock.string),
            title: title.isEmpty ? nil : title,
            type: draft.sport.rawValue,
            durationMin: draft.durationMin,
            intensity: draft.intensity?.rawValue,
            load: load,
            notes: notes,
            description: description.isEmpty ? nil : description,
            strengthPrescription: draft.isStrength ? StrengthExerciseDraft.prescription(draft.exercises) : nil,
            endurancePrescription: sportChanged ? nil : endurancePrescription,
            goalId: goalId,
            completed: completed,
            activityId: activityId,
            activity: activity,
            breakdown: sportChanged ? nil : breakdown,
            garminWorkoutId: garminWorkoutId,
            garminWorkoutScheduledDate: garminWorkoutScheduledDate,
            garminWorkoutPushedAt: garminWorkoutPushedAt,
            brickGroupId: brickGroupId,
            brickOrder: brickOrder,
            isKey: isKey
        )
    }
}

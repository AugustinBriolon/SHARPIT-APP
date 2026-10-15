import Foundation
import Observation

/// Résumé « Ressenti du jour » — primary feeling rating + optional journal details.
///
/// Server is the source of truth for whether today's check-in exists
/// (`GET /api/v1/wellness-checkin/status`). Dismissal and draft live on disk
/// (`WellnessCheckInLocalStore`), never in UserDefaults.
@MainActor
@Observable
final class RessentiDuJourStore {
    enum Phase: Equatable {
        case idle
        case submitting
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Primary morning feeling — maps onto wellness `mood`.
    var feeling: SessionFeeling?
    var energy: WellnessScore?
    var soreness: WellnessScore?
    var stress: WellnessScore?
    var notes = ""
    var detailsExpanded = false
    /// Set after a successful save so the host can fade the plate when the code changed.
    private(set) var submittedVerdict: V1WellnessVerdictSummary?
    private(set) var didSave = false

    private let client: any WellnessServing
    private let tokenProvider: () async throws -> String
    private let local: WellnessCheckInLocalStore
    private let athleteId: String
    /// Always today's local training day — never another day from this sheet.
    private let trainingDayId: String

    var canSubmit: Bool { feeling != nil && phase != .submitting }

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        athleteId: String,
        trainingDayId: String = TrainingDayId.today(),
        local: WellnessCheckInLocalStore = .shared
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.athleteId = athleteId
        self.trainingDayId = trainingDayId
        self.local = local
        restoreDraft()
    }

    func restoreDraft() {
        guard let draft = local.draft(athleteId: athleteId, localDate: trainingDayId) else { return }
        feeling = draft.feeling.flatMap(SessionFeeling.init(rawValue:))
        energy = draft.energy.flatMap(WellnessScore.init(rawValue:))
        soreness = draft.soreness.flatMap(WellnessScore.init(rawValue:))
        stress = draft.stress.flatMap(WellnessScore.init(rawValue:))
        notes = draft.notes ?? ""
        detailsExpanded = draft.detailsExpanded ?? false
    }

    func persistDraft() {
        local.saveDraft(
            WellnessCheckInLocalStore.Draft(
                feeling: feeling?.rawValue,
                energy: energy?.rawValue,
                soreness: soreness?.rawValue,
                stress: stress?.rawValue,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                detailsExpanded: detailsExpanded
            ),
            athleteId: athleteId,
            localDate: trainingDayId
        )
    }

    func dismissForLater() {
        persistDraft()
        local.dismiss(athleteId: athleteId, localDate: trainingDayId)
    }

    /// Builds the wire entry: feeling → mood; unset detail scales default to the mid tile.
    func makeEntry() -> V1WellnessEntry? {
        guard let feeling else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return V1WellnessEntry(
            mood: feeling.rawValue,
            energyLevel: (energy ?? .three).rawValue,
            perceivedSoreness: WellnessSoreness.domain(fromUI: soreness ?? .three),
            stressLevel: (stress ?? .three).rawValue,
            notes: trimmed.isEmpty ? nil : String(trimmed.prefix(500))
        )
    }

    /// Waits for the server, then clears the draft. Returns the additive verdict summary.
    @discardableResult
    func submit() async -> V1WellnessVerdictSummary? {
        guard let entry = makeEntry() else { return nil }
        phase = .submitting
        do {
            let response = try await SharpitRetry.run {
                try await self.client.submitWellnessCheckin(
                    entry,
                    trainingDayId: self.trainingDayId,
                    token: try await self.tokenProvider()
                )
            }
            local.clearDraft(athleteId: athleteId)
            submittedVerdict = response.verdict
            didSave = true
            phase = .idle
            return response.verdict
        } catch {
            phase = .failed(Self.message(for: error))
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return "Ton ressenti n'a pas pu être enregistré."
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

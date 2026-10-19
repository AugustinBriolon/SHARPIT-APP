import Foundation
import Observation

/// Résumé « Ressenti du jour » — primary feeling rating + optional journal details.
///
/// Server is the source of truth for whether today's check-in exists
/// (`GET /api/v1/wellness-checkin/status`). Dismissal and draft live on disk
/// (`WellnessCheckInLocalStore`), never in UserDefaults.
///
/// Saves are optimistic: the sheet closes and the morning-feel badge clears on tap;
/// state is final only after the server confirms. On failure the draft stays on disk
/// so the sheet can reopen with the typed input and « Pas enregistré, réessaie ».
@MainActor
@Observable
final class RessentiDuJourStore {
    enum Phase: Equatable {
        case idle
        case submitting
        case failed(String)
    }

    /// Exact copy shown when a background save fails for good.
    static let saveFailureMessage = String(localized: "Pas enregistré, réessaie")

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
    /// Optimistic then confirmed — cleared again if the server refuses.
    private(set) var didSave = false

    private let client: any WellnessServing
    private let tokenProvider: () async throws -> String
    private let local: WellnessCheckInLocalStore
    private let athleteId: String
    /// Always today's local training day — never another day from this sheet.
    private let trainingDayId: String
    @ObservationIgnored private var write: Task<Void, Never>?

    var canSubmit: Bool { feeling != nil && phase != .submitting }

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        athleteId: String,
        trainingDayId: String = TrainingDayId.today(),
        local: WellnessCheckInLocalStore = .shared,
        initialFailureMessage: String? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.athleteId = athleteId
        self.trainingDayId = trainingDayId
        self.local = local
        if let initialFailureMessage {
            phase = .failed(initialFailureMessage)
        }
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

    /// Waits for the check-in sent last — for a test.
    func settle() async {
        await write?.value
    }

    /// Optimistic save: persists the draft, marks `didSave`, and sends behind the closed sheet.
    ///
    /// Returns `false` when nothing can be sent (no feeling). Captures dependencies so the
    /// write outlives the sheet's store. Never logs health values, notes, or tokens.
    @discardableResult
    func submitOptimistic(
        onConfirmed: @escaping @MainActor (V1WellnessVerdictSummary?) -> Void,
        onFailed: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let entry = makeEntry() else { return false }
        persistDraft()
        didSave = true
        phase = .submitting

        let client = self.client
        let tokenProvider = self.tokenProvider
        let trainingDayId = self.trainingDayId
        let local = self.local
        let athleteId = self.athleteId

        write = Task { [weak self] in
            do {
                let response = try await SharpitRetry.run {
                    try await client.submitWellnessCheckin(
                        entry,
                        trainingDayId: trainingDayId,
                        token: try await tokenProvider()
                    )
                }
                local.clearDraft(athleteId: athleteId)
                await MainActor.run {
                    self?.submittedVerdict = response.verdict
                    self?.phase = .idle
                }
                await onConfirmed(response.verdict)
            } catch is CancellationError {
            } catch {
                // Draft stays on disk — the host reopens the sheet with it.
                await MainActor.run {
                    self?.didSave = false
                    self?.phase = .failed(Self.saveFailureMessage)
                }
                await onFailed()
            }
        }
        return true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

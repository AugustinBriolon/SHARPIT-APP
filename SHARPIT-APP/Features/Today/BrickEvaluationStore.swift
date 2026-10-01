import Foundation
import Observation

/// How the transitions of a brick went, on the web's five-step scale (`TRANSITION_OPTIONS`).
enum BrickTransitionRating: Int, CaseIterable, Sendable {
    case missed = 1
    case hard
    case fair
    case good
    case smooth

    var hint: String {
        switch self {
        case .missed: "Jambes coupées, rythme jamais retrouvé."
        case .hard: "Longues à digérer, allure en dessous."
        case .fair: "Quelques minutes pour retrouver le rythme."
        case .good: "Rythme retrouvé vite, sans à-coup."
        case .smooth: "Enchaînement naturel, aucune rupture."
        }
    }
}

/// The athlete's verdict on a whole brick, saved as they tap — as `ActivitySubjectiveStore`
/// does for one session.
///
/// The server replaces every field on each write, so nothing is sent before the stored
/// evaluation has been read: a tap on a blank form would otherwise erase the web's answers.
@MainActor
@Observable
final class BrickEvaluationStore: Identifiable {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rpe: Int?
    private(set) var transitionRating: Int?
    private(set) var feeling: SessionFeeling?
    private(set) var notes = ""
    private(set) var status: SubjectiveSaveStatus = .idle

    let id: String
    private let client: any BrickEvaluationServing
    private let tokenProvider: () async throws -> String
    private let saveDelay: Duration
    /// A feeling the web wrote in words this app does not map; sent back until a step is picked.
    private var unmappedFeeling: String?
    private var pendingSave: Task<Void, Never>?
    private var hasUnsentChange = false

    init(
        brickGroupId: String,
        client: any BrickEvaluationServing,
        tokenProvider: @escaping () async throws -> String,
        saveDelay: Duration = .milliseconds(600)
    ) {
        id = brickGroupId
        self.client = client
        self.tokenProvider = tokenProvider
        self.saveDelay = saveDelay
    }

    var isEmpty: Bool {
        rpe == nil && transitionRating == nil && feeling == nil && unmappedFeeling == nil
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        do {
            let stored = try await SharpitRetry.run {
                try await client.evaluation(brickGroupId: id, token: try await tokenProvider())
            }
            apply(stored)
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            phase = .unavailable("Évaluation indisponible pour l'instant.")
        }
    }

    func setRPE(_ value: Int) {
        guard rpe != value || hasFailed else { return }
        rpe = value
        answered()
    }

    func setTransitionRating(_ value: Int) {
        guard transitionRating != value || hasFailed else { return }
        transitionRating = value
        answered()
    }

    func setFeeling(_ value: SessionFeeling) {
        guard feeling != value || hasFailed else { return }
        feeling = value
        unmappedFeeling = nil
        answered()
    }

    func setNotes(_ value: String) {
        guard notes != value else { return }
        notes = value
        scheduleSave()
    }

    /// Writes anything still pending — called when the sheet closes.
    func flush() async {
        guard hasUnsentChange else { return }
        pendingSave?.cancel()
        await save()
    }

    private var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private func apply(_ stored: V1BrickEvaluation?) {
        rpe = stored?.rpe
        transitionRating = stored?.transitionRating
        feeling = SessionFeeling(stored: stored?.feeling)
        unmappedFeeling = feeling == nil ? stored?.feeling : nil
        notes = stored?.notes ?? ""
    }

    private func answered() {
        SharpitHaptics.play(.soft)
        scheduleSave()
    }

    private func scheduleSave() {
        guard phase == .ready else { return }
        hasUnsentChange = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private var evaluation: V1BrickEvaluation {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return V1BrickEvaluation(
            brickGroupId: id,
            rpe: rpe,
            transitionRating: transitionRating,
            feeling: feeling?.storedValue ?? unmappedFeeling,
            notes: trimmed.isEmpty ? nil : trimmed
        )
    }

    private func save() async {
        hasUnsentChange = false
        let sent = evaluation
        status = .saving
        do {
            try await SharpitRetry.run {
                try await client.save(sent, token: try await tokenProvider())
            }
            status = .saved
        } catch is CancellationError {
            status = .idle
        } catch let error as SharpitAPIError where error == .unauthorized {
            status = .failed("Session expirée. Reconnecte-toi.")
        } catch {
            status = .failed("Non enregistré. Touche une valeur pour réessayer.")
        }
    }
}

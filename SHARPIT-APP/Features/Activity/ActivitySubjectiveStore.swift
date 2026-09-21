import Foundation
import Observation

/// Effort and feeling for one session, saved as the athlete taps.
///
/// There is no save button: a tap is the answer, as in the journal. Writes are debounced so
/// moving from 6 to 7 to 8 costs one request, and the value stays on screen whether or not
/// the write lands — losing a tap would be worse than showing it unsaved.
@MainActor
@Observable
final class ActivitySubjectiveStore: Identifiable {
    enum Status: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private(set) var rpe: Int?
    private(set) var feeling: SessionFeeling?
    private(set) var status: Status = .idle

    private let activityId: String
    private let client: any ActivityServing
    private let tokenProvider: () async throws -> String
    private let saveDelay: Duration
    private let onSaved: (Double?, String?) -> Void
    /// A feeling the web wrote in words this app does not map ("Fluide"). It is sent back
    /// unchanged until the athlete picks a step, so opening the drawer never erases it.
    private let unmappedFeeling: String?
    private var pendingSave: Task<Void, Never>?
    /// True from a tap until its write starts, so closing the drawer right after a save
    /// does not send the same values twice.
    private var hasUnsentChange = false

    init(
        activityId: String,
        rpe: Double?,
        feeling: String?,
        client: any ActivityServing,
        tokenProvider: @escaping () async throws -> String,
        saveDelay: Duration = .milliseconds(400),
        onSaved: @escaping (Double?, String?) -> Void = { _, _ in }
    ) {
        self.activityId = activityId
        self.client = client
        self.tokenProvider = tokenProvider
        self.saveDelay = saveDelay
        self.onSaved = onSaved
        self.rpe = rpe.map { Int($0.rounded()) }
        self.feeling = SessionFeeling(stored: feeling)
        unmappedFeeling = SessionFeeling(stored: feeling) == nil ? feeling : nil
    }

    func setRPE(_ value: Int) {
        guard rpe != value || hasFailed else { return }
        rpe = value
        SharpitHaptics.play(.light)
        scheduleSave()
    }

    func setFeeling(_ value: SessionFeeling) {
        guard feeling != value || hasFailed else { return }
        feeling = value
        SharpitHaptics.play(.light)
        scheduleSave()
    }

    /// Writes anything still pending — called when the drawer closes.
    func flush() async {
        guard hasUnsentChange else { return }
        pendingSave?.cancel()
        await save()
    }

    private var hasFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var storedFeeling: String? {
        feeling?.storedValue ?? unmappedFeeling
    }

    private func scheduleSave() {
        hasUnsentChange = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        hasUnsentChange = false
        let sentRPE = rpe.map(Double.init)
        let sentFeeling = storedFeeling
        status = .saving
        do {
            let token = try await tokenProvider()
            try await client.updateSubjective(id: activityId, rpe: sentRPE, feeling: sentFeeling, token: token)
            status = .saved
            onSaved(sentRPE, sentFeeling)
        } catch is CancellationError {
            status = .idle
        } catch let error as SharpitAPIError where error == .unauthorized {
            status = .failed("Session expirée. Reconnecte-toi.")
        } catch {
            status = .failed("Non enregistré. Touche une valeur pour réessayer.")
        }
    }
}

import Foundation
import Observation

/// The day's journal and the preferences that decide what it asks for.
///
/// The athlete never saves: a tap is the answer. Writes are debounced so cycling a
/// signal through its three states costs one request instead of three.
@MainActor
@Observable
final class JournalStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var entry: V1DayJournalEntry
    private(set) var prefs: JournalPrefs = .empty
    private(set) var isPro = false
    /// Set when a write did not land. The answer stays on screen either way — losing
    /// what the athlete just tapped would be worse than showing it unsaved.
    private(set) var saveFailure: String?

    private let client: any JournalServing
    private let tokenProvider: () async throws -> String
    private let saveDelay: Duration
    private var pendingSave: Task<Void, Never>?

    init(
        client: any JournalServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String = TrainingDayId.today(),
        saveDelay: Duration = .milliseconds(700)
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.saveDelay = saveDelay
        entry = V1DayJournalEntry(trainingDayId: trainingDayId)
    }

    // MARK: Reading

    func load() async {
        if phase != .ready { phase = .loading }
        do {
            let token = try await tokenProvider()
            async let prefsResult = client.journalPrefs(token: token)
            async let entryResult = client.dayJournal(
                trainingDayId: entry.trainingDayId,
                token: token
            )
            let (loadedPrefs, loadedIsPro) = try await prefsResult
            entry = try await entryResult
            prefs = loadedPrefs
            isPro = loadedIsPro
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(Self.message(for: error, fallback: "Ton journal n'a pas pu être chargé."))
        }
    }

    /// The trackables the athlete turned on, in catalogue order, then their own items.
    var visibleTrackables: [JournalTrackable] {
        JournalCatalogue.all.filter { prefs.isEnabled($0.id) }
    }

    var visibleCustomItems: [JournalCustomItem] {
        prefs.customItems.filter(\.enabled)
    }

    var hasNothingToShow: Bool {
        visibleTrackables.isEmpty && visibleCustomItems.isEmpty
    }

    var moodLabel: String? {
        entry.moodLabel
    }

    var trainingDayId: String { entry.trainingDayId }

    // MARK: Writing the day

    func cycle(factorId: String) {
        entry.factors[factorId] = entry.state(of: factorId).next
        SharpitHaptics.play(.light)
        scheduleSave()
    }

    func set(factorId: String, to state: JournalFactorState) {
        guard entry.state(of: factorId) != state else { return }
        entry.factors[factorId] = state
        SharpitHaptics.play(.light)
        scheduleSave()
    }

    /// Echoes the morning check-in's mood onto the day, as the web does. The journal
    /// does not own the value — the check-in does — it only shows what was answered.
    func applyMoodLabel(_ label: String) {
        entry.moodLabel = label
        scheduleSave()
    }

    /// Steps match the web's: one cup of coffee, one large glass.
    func adjustCaffeine(by delta: Int) {
        entry.caffeineMg = max(0, (entry.caffeineMg ?? 0) + delta)
        scheduleSave()
    }

    func adjustHydration(by delta: Int) {
        entry.hydrationMl = max(0, (entry.hydrationMl ?? 0) + delta)
        scheduleSave()
    }

    private func scheduleSave() {
        saveFailure = nil
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            await self?.saveEntry()
        }
    }

    /// Writes anything still pending. Called when the screen goes away, so a tap made
    /// a moment before leaving is not lost with the view.
    func flushPendingSave() async {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        await saveEntry()
    }

    private func saveEntry() async {
        do {
            let token = try await tokenProvider()
            entry = try await client.saveDayJournal(entry, token: token)
            saveFailure = nil
        } catch is CancellationError {
        } catch {
            saveFailure = Self.message(for: error, fallback: "Journal non enregistré. Réessaie.")
        }
    }

    // MARK: Writing the preferences

    func setTrackableEnabled(_ id: String, _ enabled: Bool) async {
        guard !enabled || prefs.canEnableAnother(isPro: isPro) else { return }
        var next = prefs
        next.setEnabled(id, enabled)
        await savePrefs(next)
    }

    func addCustomItem(label: String) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPro, (1...48).contains(trimmed.count), prefs.canEnableAnother(isPro: isPro) else {
            return
        }
        var next = prefs
        next.setCustomItems(
            prefs.customItems + [
                JournalCustomItem(id: JournalPrefs.makeCustomId(), label: trimmed, enabled: true)
            ]
        )
        await savePrefs(next)
    }

    func setCustomItemEnabled(_ id: String, _ enabled: Bool) async {
        guard !enabled || prefs.canEnableAnother(isPro: isPro) else { return }
        var next = prefs
        next.setCustomItems(
            prefs.customItems.map { $0.id == id ? JournalCustomItem(id: $0.id, label: $0.label, enabled: enabled) : $0 }
        )
        await savePrefs(next)
    }

    func removeCustomItem(_ id: String) async {
        var next = prefs
        next.setCustomItems(prefs.customItems.filter { $0.id != id })
        await savePrefs(next)
    }

    private func savePrefs(_ next: JournalPrefs) async {
        let previous = prefs
        prefs = next
        do {
            let token = try await tokenProvider()
            // The server caps a free plan and strips custom items, so its answer wins.
            let result = try await client.saveJournalPrefs(next, token: token)
            prefs = result.prefs
            isPro = result.isPro
            saveFailure = nil
        } catch {
            prefs = previous
            saveFailure = Self.message(for: error, fallback: "Préférences non enregistrées. Réessaie.")
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return fallback
    }
}

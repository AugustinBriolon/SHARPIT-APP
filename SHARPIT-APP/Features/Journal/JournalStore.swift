import Foundation
import Observation
import SwiftData

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
    /// The derived lines, read-only and possibly empty: the checklist is a reading of the
    /// day's devices, so its absence never stops the athlete recording their own answers.
    private(set) var checklist: [V1JournalAutoChecklistItem] = []
    /// Set when a write did not land. The answer stays on screen either way — losing
    /// what the athlete just tapped would be worse than showing it unsaved.
    private(set) var saveFailure: String?
    private(set) var selectedDate: Date
    private(set) var completedDayIds: Set<String> = []

    private let client: any JournalServing
    private let tokenProvider: () async throws -> String
    private let saveDelay: Duration
    /// Optional so a preview or a test can run without a store, as `TodayStore` does.
    private let modelContext: ModelContext?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Bumped on every local edit, so a save can tell whether the athlete tapped again
    /// while its request was in flight.
    @ObservationIgnored private var localRevision = 0

    init(
        client: any JournalServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String = TrainingDayId.today(),
        saveDelay: Duration = .milliseconds(700),
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.saveDelay = saveDelay
        self.modelContext = modelContext
        self.selectedDate = TrainingDayId.date(trainingDayId) ?? .now
        entry = V1DayJournalEntry(trainingDayId: trainingDayId)
        loadCompletedDayIds()
    }

    // MARK: Reading

    func load() async {
        // Paint the last day the app saw before asking the network, so the journal opens on
        // content. The cache is never the truth — every answer still goes to the server — it
        // only decides what fills the screen while the request is in flight.
        let hadCache = hydrateFromCache()
        if !hadCache, phase != .ready { phase = .loading }
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
            // After the preferences, because they decide whether it is worth asking.
            await loadChecklist(token: token)
            persistCache()
        } catch is CancellationError {
        } catch {
            let message = Self.message(for: error, fallback: "Ton journal n'a pas pu être chargé.")
            // A painted cache survives a failed refresh: replacing yesterday's answers with a
            // full-screen error would lose what the athlete already recorded from view.
            if hadCache {
                saveFailure = message
            } else {
                phase = .failed(message)
            }
        }
    }

    @discardableResult
    private func hydrateFromCache() -> Bool {
        guard let modelContext else { return false }
        guard let cached = try? JournalSnapshotRepository.load(
            trainingDayId: entry.trainingDayId,
            context: modelContext
        ), !cached.isEmpty else { return false }

        if let cachedEntry = cached.entry { entry = cachedEntry }
        if let cachedPrefs = cached.prefs { prefs = cachedPrefs }
        checklist = cached.signals?.checklist ?? []
        phase = .ready
        return true
    }

    private func persistCache() {
        guard let modelContext else { return }
        // Persistence failure must not break a journal that is already on screen.
        try? JournalSnapshotRepository.save(
            trainingDayId: entry.trainingDayId,
            entry: entry,
            prefs: prefs,
            signals: V1JournalDaySignals(trainingDayId: entry.trainingDayId, checklist: checklist),
            context: modelContext
        )
    }

    /// Reads the derived lines, and only when the athlete turned one on.
    ///
    /// Never throws onward: a failed read leaves the checklist empty and the journal usable.
    /// It is the one part of the screen the athlete cannot act on, so it is also the one part
    /// whose absence is not worth an error.
    private func loadChecklist(token: String) async {
        guard prefs.hasAnyAutoItem else {
            // Nothing enabled: the section is gone, so whatever was cached is stale.
            checklist = []
            return
        }
        guard let signals = try? await client.journalDaySignals(
            trainingDayId: entry.trainingDayId,
            token: token
        ) else {
            // Keep what is on screen. Clearing here would erase a checklist the cache had
            // already painted, and the next `persistCache` would write that emptiness back.
            return
        }
        checklist = signals.checklist
    }

    /// The trackables the athlete turned on, in catalogue order, then their own items.
    var visibleTrackables: [JournalTrackable] {
        JournalCatalogue.all.filter { prefs.isEnabled($0.id) }
    }

    /// The signals that describe the night ending this morning, as the web's "Nuit dernière"
    /// section shows them.
    var priorNightTrackables: [JournalTrackable] {
        factorTrackables(in: .priorNight)
    }

    /// The signals that describe the day itself. The three day metrics are excluded: they are
    /// values with their own section, not yes / no answers.
    var dayTrackables: [JournalTrackable] {
        factorTrackables(in: .calendarDay)
    }

    private func factorTrackables(in window: JournalDayWindow) -> [JournalTrackable] {
        visibleTrackables
            .filter { $0.kind == .factor && $0.window == window }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.category.sortOrder != rhs.element.category.sortOrder {
                    return lhs.element.category.sortOrder < rhs.element.category.sortOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var visibleCustomItems: [JournalCustomItem] {
        prefs.customItems.filter(\.enabled)
    }

    /// True when there is nothing on screen at all. The checklist counts: an athlete who
    /// enabled only derived lines has a journal to read, even with nothing to answer.
    var hasNothingToShow: Bool {
        visibleTrackables.isEmpty && visibleCustomItems.isEmpty && checklist.isEmpty
    }

    var moodLabel: String? {
        entry.moodLabel
    }

    var trainingDayId: String { entry.trainingDayId }

    // MARK: Date Navigation & Completion

    private func loadCompletedDayIds() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<JournalDaySnapshot>()
        guard let snapshots = try? modelContext.fetch(descriptor) else { return }
        var ids: Set<String> = []
        for snapshot in snapshots {
            guard let data = snapshot.entryJSON,
                  let cachedEntry = try? JSONDecoder().decode(V1DayJournalEntry.self, from: data) else { continue }
            if cachedEntry.hasAnyAnswer {
                ids.insert(snapshot.trainingDayId)
            }
        }
        completedDayIds = ids
    }

    func isDayCompleted(date: Date) -> Bool {
        let id = TrainingDayId.today(now: date)
        if id == entry.trainingDayId {
            return entry.hasAnyAnswer
        }
        return completedDayIds.contains(id)
    }

    private func updateCompletionState() {
        if entry.hasAnyAnswer {
            completedDayIds.insert(entry.trainingDayId)
        } else {
            completedDayIds.remove(entry.trainingDayId)
        }
    }

    func selectDate(_ date: Date) async {
        guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }
        await flushPendingSave()
        selectedDate = date
        let newDayId = TrainingDayId.today(now: date)
        entry = V1DayJournalEntry(trainingDayId: newDayId)
        checklist = []
        saveFailure = nil

        let hadCache = hydrateFromCache()
        if !hadCache {
            phase = .loading
        }

        do {
            let token = try await tokenProvider()
            entry = try await client.dayJournal(trainingDayId: newDayId, token: token)
            phase = .ready
            await loadChecklist(token: token)
            persistCache()
            updateCompletionState()
        } catch is CancellationError {
        } catch {
            let message = Self.message(for: error, fallback: "Impossible de charger le journal pour ce jour.")
            if hadCache {
                saveFailure = message
            } else {
                phase = .failed(message)
            }
        }
    }

    // MARK: Writing the day

    func cycle(factorId: String) {
        entry.factors[factorId] = entry.state(of: factorId).next
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    func set(factorId: String, to state: JournalFactorState) {
        guard entry.state(of: factorId) != state else { return }
        entry.factors[factorId] = state
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    /// Echoes the morning check-in's mood onto the day, as the web does. The journal
    /// does not own the value — the check-in does — it only shows what was answered.
    func applyMoodLabel(_ label: String) {
        entry.moodLabel = label
        updateCompletionState()
        scheduleSave()
    }

    /// Steps match the web's: one cup of coffee, one large glass.
    func adjustCaffeine(by delta: Int) {
        entry.caffeineMg = max(0, (entry.caffeineMg ?? 0) + delta)
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    func setCaffeine(_ mg: Int) {
        let clamped = max(0, mg)
        guard (entry.caffeineMg ?? 0) != clamped else { return }
        entry.caffeineMg = clamped
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    func adjustHydration(by delta: Int) {
        entry.hydrationMl = max(0, (entry.hydrationMl ?? 0) + delta)
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    func setHydration(_ ml: Int) {
        let clamped = max(0, ml)
        guard (entry.hydrationMl ?? 0) != clamped else { return }
        entry.hydrationMl = clamped
        SharpitHaptics.play(.light)
        updateCompletionState()
        scheduleSave()
    }

    private func scheduleSave() {
        localRevision += 1
        if saveFailure != nil {
            saveFailure = nil
        }
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
        let sentRevision = localRevision
        do {
            let token = try await tokenProvider()
            let saved = try await client.saveDayJournal(entry, token: token)
            // A tap made during the request is newer than the server's echo: adopting the
            // echo would flip that answer back on screen, and the next save would send the
            // reverted value.
            if localRevision == sentRevision {
                entry = saved
            }
            saveFailure = nil
            // Written from the server's echo, so the cache holds what was accepted rather
            // than what was tapped.
            persistCache()
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
            // Turning a derived line on or off changes what the checklist should show.
            await loadChecklist(token: token)
            persistCache()
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

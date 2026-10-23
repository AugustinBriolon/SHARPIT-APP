import Foundation

/// Coalesces concurrent loads and skips work while a successful result is still fresh.
///
/// Tab `.task` re-runs every time the athlete returns to an onglet; without this, spam-tapping
/// the navbar floods the API. Same idea as `ProviderSyncStore.joining` + `staleAfter`.
@MainActor
final class LoadGate {
    /// Long enough to absorb navbar spam; short enough that a real return still feels fresh.
    static let tabStaleAfter: TimeInterval = 45

    private var lastSuccessAt: Date?
    /// What the last success and the run in flight were for: a day, say.
    private var lastSuccessKey: String?
    private var inFlight: (key: String, task: Task<Bool, Never>)?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Runs `work` once. Concurrent callers for the same `key` await the same task; another key
    /// runs its own — a day picked while the one before still loads must be read, not joined.
    /// Skips when a success for the key is still fresh unless `force`. `work` returns whether to
    /// advance the freshness clock.
    @discardableResult
    func run(
        key: String = "",
        force: Bool = false,
        staleAfter: TimeInterval = tabStaleAfter,
        _ work: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let inFlight, inFlight.key == key { return await inFlight.task.value }
        if !force, lastSuccessKey == key, let last = lastSuccessAt, now().timeIntervalSince(last) < staleAfter {
            return false
        }
        let task = Task { await work() }
        inFlight = (key, task)
        let ok = await task.value
        // A later run for another key may have taken the slot since.
        if inFlight?.key == key { inFlight = nil }
        if ok {
            lastSuccessAt = now()
            lastSuccessKey = key
        }
        return ok
    }

    func invalidate() {
        lastSuccessAt = nil
    }
}

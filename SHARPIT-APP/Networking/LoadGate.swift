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
    private var inFlight: Task<Bool, Never>?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Runs `work` once. Concurrent callers await the same task. Skips when a success is still
    /// fresh unless `force`. `work` returns whether to advance the freshness clock.
    @discardableResult
    func run(
        force: Bool = false,
        staleAfter: TimeInterval = tabStaleAfter,
        _ work: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let inFlight { return await inFlight.value }
        if !force, let last = lastSuccessAt, now().timeIntervalSince(last) < staleAfter {
            return false
        }
        let task = Task { await work() }
        inFlight = task
        let ok = await task.value
        inFlight = nil
        if ok { lastSuccessAt = now() }
        return ok
    }

    func invalidate() {
        lastSuccessAt = nil
    }
}

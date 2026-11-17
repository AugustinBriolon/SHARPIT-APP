import Foundation
import Observation

/// Keeps the athlete's data fresh without a detour through the web.
///
/// The server pulls Garmin and the other providers only on a schedule, so a night slept
/// after the last run stayed invisible until someone pressed "sync" on the web. The app now
/// asks for a pull itself when it opens, when it comes back to the foreground, and on
/// pull-to-refresh — and only when the last pull is old enough to be worth one.
@MainActor
@Observable
final class ProviderSyncStore {
    enum State: Equatable {
        case idle
        case syncing
        case failed
    }

    /// Past this age a pull is worth its cost; under it, the app reads what the server has.
    static let staleAfter: TimeInterval = 15 * 60

    private(set) var state: State = .idle
    private(set) var lastSyncAt: Date?
    /// False once the server says no provider is connected: there is then nothing to pull.
    private(set) var hasProviders = true

    private let client: any SyncServing
    private let tokenProvider: () async throws -> String
    private let now: () -> Date
    /// The check or pull under way. Launch and foregrounding arrive together; the second
    /// caller waits on the first instead of starting its own.
    private var inFlight: Task<Bool, Never>?

    init(
        client: any SyncServing,
        tokenProvider: @escaping () async throws -> String,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.now = now
    }

    /// Pulls only when the last pull is stale. True when fresh data arrived, so the caller
    /// reloads what it shows.
    func syncIfStale() async -> Bool {
        await joining { await self.checkThenPull() }
    }

    /// Pulls the app started by itself that failed in a row. One is not worth a word: the
    /// screen was left mid-pull, the network dropped, and the next one usually lands.
    private var quietFailures = 0

    /// Pulls now, whatever the age of the last pull — the athlete asked for it.
    func syncNow() async -> Bool {
        await joining { await self.pullIfConnected() }
    }

    private func joining(_ work: @escaping @MainActor () async -> Bool) async -> Bool {
        if let inFlight { return await inFlight.value }
        let task = Task { await work() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func checkThenPull() async -> Bool {
        do {
            let token = try await tokenProvider()
            let status = try await client.syncStatus(token: token)
            apply(status)
        } catch {
            return false
        }
        guard hasProviders else { return false }
        if let lastSyncAt, now().timeIntervalSince(lastSyncAt) < Self.staleAfter {
            return false
        }
        return await pull(asked: false)
    }

    private func pullIfConnected() async -> Bool {
        guard hasProviders else { return false }
        return await pull(asked: true)
    }

    /// `asked`: the athlete pulled to refresh, so a failure is theirs to hear. A pull the app
    /// started itself says « Synchronisation impossible » only the second time running.
    private func pull(asked: Bool) async -> Bool {
        state = .syncing
        do {
            let token = try await tokenProvider()
            apply(try await client.sync(token: token))
            state = .idle
            quietFailures = 0
            return true
        } catch let error as SharpitAPIError where error == .rateLimited {
            // A pull ran moments ago; what the server holds is already fresh.
            state = .idle
            return false
        } catch where Self.isCancellation(error) {
            // The screen that asked went away: nothing failed, the server carries on.
            state = .idle
            return false
        } catch {
            quietFailures += asked ? 0 : 1
            state = asked || quietFailures >= 2 ? .failed : .idle
            return false
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func apply(_ status: V1SyncStatus) {
        lastSyncAt = status.lastSyncAt
        hasProviders = !status.providers.isEmpty
    }
}

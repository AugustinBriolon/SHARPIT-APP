import Foundation
import Observation

/// Brings in every activity Garmin holds, once per athlete.
///
/// The regular pull only reaches back to the last one — and a first connection only to a
/// window of recent weeks — so everything older than that never reached SHARPIT. This runs
/// the web's full-history import the first time Garmin is seen connected, and never again
/// once it has finished: it is remembered per Clerk user. A run that fails or is cut off is
/// not remembered, so the next launch carries on — the server skips what it already holds.
///
/// The activities' streams (GPS, heart rate) are not in this pass: the server backfills them
/// a batch at a time on every regular pull.
@MainActor
@Observable
final class GarminHistoryImport {
    enum State: Equatable {
        case idle
        case importing
        /// Finished, with how many activities were new.
        case finished(imported: Int)
        case failed
    }

    private(set) var state: State = .idle
    /// Bumped when a run brought activities in, so a list on screen reloads.
    private(set) var completedAt: Date?

    private let client: any GarminHistoryImporting
    private let statusClient: any SyncServing
    private let defaults: UserDefaults

    init(
        client: any GarminHistoryImporting,
        statusClient: any SyncServing,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.statusClient = statusClient
        self.defaults = defaults
    }

    static func key(_ userId: String) -> String { "sharpit.garmin.historyImported.\(userId)" }

    func isDone(for userId: String) -> Bool {
        defaults.bool(forKey: Self.key(userId))
    }

    /// Runs the import when this athlete has Garmin connected and has never finished one.
    func runIfNeeded(userId: String?, tokenProvider: () async throws -> String) async {
        guard let userId, !isDone(for: userId), state != .importing else { return }
        guard
            let token = try? await tokenProvider(),
            let status = try? await statusClient.syncStatus(token: token),
            status.providers.contains(where: { $0.key == "garmin" })
        else { return }

        state = .importing
        do {
            let imported = try await client.importFullGarminHistory(token: try await tokenProvider())
            defaults.set(true, forKey: Self.key(userId))
            state = .finished(imported: imported)
            completedAt = Date()
        } catch {
            state = .failed
        }
    }
}

import Foundation
import Observation
import SwiftData

/// The athlete's profile, loaded once and shared by everything that reads it: Profil,
/// Seuils & repères, and the reading density every technical surface asks about.
///
/// One store rather than one per screen, because a save on Seuils changes what Profil holds
/// and the density is read far from either.
@MainActor
@Observable
final class AthleteProfileStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .idle
    private(set) var profile = V1AthleteProfile()
    private(set) var history: [V1ThresholdSnapshot] = []
    /// Set when a refresh over a painted cache failed. The profile stays on screen either
    /// way — a screen never trades known content for an error banner (`docs/adr/0008`).
    private(set) var refreshFailure: String?

    private let client: any AthleteProfileServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?
    private let failures: SharpitWriteFailures
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var pendingWrites = 0

    init(
        client: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil,
        failures: SharpitWriteFailures = .shared
    ) {
        self.failures = failures
        self.client = client
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
    }

    var isExpertReading: Bool { profile.isExpertReading }

    func load() async {
        guard phase != .loading else { return }
        let hadCache = hydrateFromCache()
        if !hadCache { phase = .loading }
        do {
            let token = try await tokenProvider()
            profile = try await client.athleteProfile(token: token)
            phase = .loaded
            refreshFailure = nil
            persistCache()
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if hadCache {
                refreshFailure = "Profil non actualisé."
            } else {
                phase = .failed("Chargement du profil impossible.")
            }
        }
    }

    @discardableResult
    private func hydrateFromCache() -> Bool {
        guard let cached = ResponseCache.read(
            V1AthleteProfile.self,
            key: ResponseCacheKey.athleteProfile,
            context: modelContext
        ) else { return false }
        profile = cached
        phase = .loaded
        return true
    }

    private func persistCache() {
        ResponseCache.write(profile, key: ResponseCacheKey.athleteProfile, context: modelContext)
    }

    /// The threshold snapshots, loaded on demand: only Seuils reads them.
    func loadHistory() async {
        guard history.isEmpty else { return }
        guard let token = try? await tokenProvider() else { return }
        history = (try? await client.thresholdHistory(token: token)) ?? []
    }

    /// Applies a patch at once and writes it behind: the screen never waits on the server.
    ///
    /// Writes go out one after another, in the order they were made. A write that fails for
    /// good (`SharpitRetry`) is said in the app's toast and the profile is read again, so what
    /// shows is what the server holds rather than a change that never landed.
    func save(_ patch: AthleteProfilePatch) {
        guard !patch.isEmpty else { return }
        profile = profile.applying(patch)
        persistCache()
        pendingWrites += 1
        let previous = writeChain
        writeChain = Task { [weak self] in
            await previous?.value
            await self?.write(patch)
        }
    }

    /// Waits for every write made so far — for a test, or a caller that must read the echo.
    func settle() async {
        await writeChain?.value
    }

    private func write(_ patch: AthleteProfilePatch) async {
        defer { pendingWrites -= 1 }
        do {
            let saved = try await SharpitRetry.run { [client, tokenProvider] in
                try await client.patchAthleteProfile(patch, token: try await tokenProvider())
            }
            // A change made meanwhile is newer than this echo; its own write brings the next one.
            if pendingWrites == 1 {
                profile = saved
                persistCache()
            }
            // A saved threshold writes a snapshot server-side; the list held here is stale.
            history = []
        } catch {
            failures.report(Self.failureMessage(for: error))
            await load()
        }
    }

    private static func failureMessage(for error: any Error) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return "Profil non enregistré. Réessaie plus tard."
    }

    /// Switches the reading density. Its own method because it saves on the tap, with no
    /// form to submit — as the web's picker does.
    func setExpertReading(_ isExpert: Bool) {
        var patch = AthleteProfilePatch()
        patch.set(
            .displayMode,
            string: isExpert ? AthleteProfileField.expertDisplayMode : AthleteProfileField.essentialDisplayMode
        )
        save(patch)
    }
}

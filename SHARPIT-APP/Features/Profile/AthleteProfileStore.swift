import Foundation
import Observation

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
    /// Set while a save is in flight, so a form can refuse a second submit.
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let client: any AthleteProfileServing
    private let tokenProvider: () async throws -> String

    init(client: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var isExpertReading: Bool { profile.isExpertReading }

    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let token = try await tokenProvider()
            profile = try await client.athleteProfile(token: token)
            phase = .loaded
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            phase = .failed("Chargement du profil impossible.")
        }
    }

    /// The threshold snapshots, loaded on demand: only Seuils reads them.
    func loadHistory() async {
        guard history.isEmpty else { return }
        guard let token = try? await tokenProvider() else { return }
        history = (try? await client.thresholdHistory(token: token)) ?? []
    }

    /// Saves the fields of one patch and adopts the profile the server returns.
    ///
    /// Returns false when nothing was written, so a form can stay open on an error rather
    /// than dismissing on a save that did not happen.
    @discardableResult
    func save(_ patch: AthleteProfilePatch) async -> Bool {
        guard !isSaving else { return false }
        guard !patch.isEmpty else { return true }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let token = try await tokenProvider()
            profile = try await client.patchAthleteProfile(patch, token: token)
            // A saved threshold writes a snapshot server-side; the list held here is stale.
            history = []
            return true
        } catch SharpitAPIError.unauthorized {
            saveError = "Session expirée. Reconnecte-toi."
            return false
        } catch {
            saveError = "Enregistrement impossible. Réessaie."
            return false
        }
    }

    /// Switches the reading density. Its own method because it saves on the tap, with no
    /// form to submit — as the web's picker does.
    func setExpertReading(_ isExpert: Bool) async {
        var patch = AthleteProfilePatch()
        patch.set(
            .displayMode,
            string: isExpert ? AthleteProfileField.expertDisplayMode : AthleteProfileField.essentialDisplayMode
        )
        await save(patch)
    }
}

import Foundation
import Observation

/// Seuils & repères' two ways to set the references without typing them: the records'
/// estimates (`/api/v1/athlete-profile/apply-estimates`) and Garmin's own values
/// (`/api/v1/athlete-profile/import-garmin`).
///
/// The estimates are a write like any other: kept ones show in the profile on the tap and go
/// out behind through `SharpitRetry`, then the profile is read back. Garmin is different — the
/// values are not known until Garmin answers — so the import says it is working and waits.
@MainActor
@Observable
final class ThresholdSuggestionStore {
    enum ImportState: Equatable {
        case idle
        case importing
        /// Garmin answered: what came in, in the web's words.
        case done(String)
        case failed(String)
    }

    /// Nil until read, and after a read that failed: the card simply does not show.
    private(set) var preview: V1ThresholdApplyPreview?
    /// Proposals the athlete unticked. Everything offered is kept by default, as on the web.
    private(set) var refused: Set<V1ThresholdField> = []
    private(set) var importState: ImportState = .idle
    /// Bumped once the server's profile is back after an apply or an import, so the form
    /// takes the stored values even where they differ from what was shown.
    private(set) var revision = 0

    private let client: any ThresholdEstimating
    private let tokenProvider: () async throws -> String
    private let failures: SharpitWriteFailures

    init(
        client: any ThresholdEstimating,
        tokenProvider: @escaping () async throws -> String,
        failures: SharpitWriteFailures = .shared
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.failures = failures
    }

    var offered: [V1ThresholdChange] { preview?.changes ?? [] }

    var accepted: [V1ThresholdField] {
        offered.map(\.field).filter { !refused.contains($0) }
    }

    var isImporting: Bool { importState == .importing }

    func isAccepted(_ field: V1ThresholdField) -> Bool {
        !refused.contains(field)
    }

    func toggle(_ field: V1ThresholdField) {
        if refused.contains(field) {
            refused.remove(field)
        } else {
            refused.insert(field)
        }
    }

    func loadPreview() async {
        guard let token = try? await tokenProvider() else { return }
        do {
            let fresh = try await client.thresholdPreview(token: token)
            if fresh != preview {
                preview = fresh
                refused = []
            }
        } catch {
            // A proposal that cannot be read is not shown; the manual fields stay usable.
        }
    }

    /// Writes the kept proposals. The profile shows them at once; the server's profile replaces
    /// them once the write lands, and a refusal is said and puts the stored values back.
    @discardableResult
    func apply(to profile: AthleteProfileStore) -> Task<Void, Never>? {
        guard let preview else { return nil }
        let fields = accepted
        guard !fields.isEmpty else { return nil }
        let kept = Set(fields)
        profile.show(preview.patch(for: kept))
        self.preview = preview.removing(kept)
        refused = []
        return Task {
            // A threshold typed just before goes out first, so it cannot land over the estimate.
            await profile.settle()
            do {
                try await SharpitRetry.run { [client, tokenProvider] in
                    try await client.applyThresholdEstimates(fields: fields, token: try await tokenProvider())
                }
            } catch {
                failures.report(Self.applyFailure(for: error))
            }
            await profile.refresh()
            await loadPreview()
            revision += 1
        }
    }

    /// Asks Garmin for its thresholds; the server writes what came and the profile is read back.
    func importFromGarmin(into profile: AthleteProfileStore) async {
        guard importState != .importing else { return }
        importState = .importing
        do {
            let token = try await tokenProvider()
            let result = try await client.importGarminThresholds(token: token)
            importState = .done(result.message)
        } catch {
            importState = .failed(Self.importFailure(for: error))
            return
        }
        await profile.refresh()
        await loadPreview()
        revision += 1
    }

    static func applyFailure(for error: any Error) -> String {
        switch error as? SharpitAPIError {
        case .message(let reason)?: reason
        case .unauthorized?: "Session expirée. Reconnecte-toi."
        default: "Seuils non appliqués. Réessaie plus tard."
        }
    }

    static func importFailure(for error: any Error) -> String {
        switch error as? SharpitAPIError {
        case .message(let reason)?: reason
        case .unauthorized?: "Session expirée. Reconnecte-toi."
        case .transport?: "Pas de connexion. Réessaie une fois en ligne."
        default: "Impossible d'importer les seuils depuis Garmin."
        }
    }
}

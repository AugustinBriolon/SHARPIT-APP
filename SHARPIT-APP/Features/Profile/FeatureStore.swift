import Observation
import SwiftUI
import WidgetKit

/// The parts of SharpIt the athlete uses, read once and handed to every surface through the
/// environment — the shape of `DisplayModeStore`. A switch saves on the tap and applies at once;
/// a save that fails puts the switch back.
///
/// The last known choice is kept in the widget snapshot, so the app opens with the right tabs
/// and the widgets know a feature is off without asking the API.
@MainActor
@Observable
final class FeatureStore {
    private(set) var prefs: V1FeaturePrefs
    private(set) var saveError: String?

    private let client: any AthleteProfileServing
    private let snapshotDirectory: URL?

    init(client: any AthleteProfileServing, snapshotDirectory: URL? = WidgetSnapshotStore.containerURL) {
        self.client = client
        self.snapshotDirectory = snapshotDirectory
        prefs = WidgetSnapshotStore.read(from: snapshotDirectory)?.features ?? V1FeaturePrefs()
    }

    func isOn(_ feature: SharpitFeature) -> Bool { prefs.isOn(feature) }

    /// Silent on failure: the last known choice stays, all on by default.
    func load(tokenProvider: () async throws -> String) async {
        guard let token = try? await tokenProvider(),
              let profile = try? await client.athleteProfile(token: token) else { return }
        adopt(profile.featurePrefs ?? V1FeaturePrefs())
    }

    func set(_ feature: SharpitFeature, on: Bool, tokenProvider: () async throws -> String) async {
        let previous = prefs
        var next = prefs
        next.set(feature, on)
        adopt(next)
        saveError = nil
        var patch = AthleteProfilePatch()
        patch.setFeature(feature, on: on)
        do {
            let token = try await tokenProvider()
            let profile = try await client.patchAthleteProfile(patch, token: token)
            adopt(profile.featurePrefs ?? next)
        } catch {
            adopt(previous)
            saveError = "Enregistrement impossible. Réessaie."
        }
    }

    private func adopt(_ next: V1FeaturePrefs) {
        prefs = next
        if WidgetSnapshotStore.update(in: snapshotDirectory, { $0.features = next }) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private struct FeatureStoreKey: EnvironmentKey {
    @MainActor static let defaultValue: FeatureStore? = nil
}

extension EnvironmentValues {
    /// Nil where no store was injected — a preview, a test: every feature is then on.
    var features: FeatureStore? {
        get { self[FeatureStoreKey.self] }
        set { self[FeatureStoreKey.self] = newValue }
    }
}

extension FeatureStore? {
    /// A missing store means every feature on.
    @MainActor
    func isOn(_ feature: SharpitFeature) -> Bool { self?.isOn(feature) ?? true }
}

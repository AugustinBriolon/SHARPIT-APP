import Foundation
import Testing
@testable import Sharpit

private actor FeatureProfileClient: AthleteProfileServing {
    var stored = V1FeaturePrefs()
    var failsPatch = false

    func setFailsPatch(_ fails: Bool) { failsPatch = fails }

    func athleteProfile(token: String) async throws -> V1AthleteProfile {
        V1AthleteProfile(featurePrefs: stored)
    }

    func patchAthleteProfile(_ patch: AthleteProfilePatch, token: String) async throws -> V1AthleteProfile {
        if failsPatch { throw URLError(.notConnectedToInternet) }
        if case .object(let object)? = patch.fields["featurePrefs"] {
            for feature in SharpitFeature.allCases {
                if case .bool(let on)? = object[feature.rawValue] { stored.set(feature, on) }
            }
        }
        return V1AthleteProfile(featurePrefs: stored)
    }

    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] { [] }
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func aMissingFeatureKeyIsOn() throws {
    let prefs = try JSONDecoder().decode(V1FeaturePrefs.self, from: Data(#"{ "version": 1, "nutrition": false }"#.utf8))

    #expect(!prefs.nutrition)
    #expect(prefs.journal && prefs.health && prefs.regularity)
}

@MainActor
@Test func turningAFeatureOffSavesItAndTellsTheWidgets() async {
    let directory = tempDirectory()
    let client = FeatureProfileClient()
    let store = FeatureStore(client: client, snapshotDirectory: directory)

    await store.set(.nutrition, on: false, tokenProvider: { "t" })

    #expect(!store.isOn(.nutrition))
    #expect(store.isOn(.journal))
    #expect(await client.stored.nutrition == false)
    #expect(WidgetSnapshotStore.read(from: directory)?.features?.nutrition == false)
    // The next launch opens with the same choice, before the network answers.
    #expect(!FeatureStore(client: client, snapshotDirectory: directory).isOn(.nutrition))
}

@MainActor
@Test func aSaveThatFailsPutsTheSwitchBack() async {
    let client = FeatureProfileClient()
    await client.setFailsPatch(true)
    let store = FeatureStore(client: client, snapshotDirectory: tempDirectory())

    await store.set(.health, on: false, tokenProvider: { "t" })

    #expect(store.isOn(.health))
    #expect(store.saveError != nil)
}

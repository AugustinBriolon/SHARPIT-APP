import Foundation
import Testing
@testable import Sharpit

nonisolated private let answerJSON = """
{
  "prefs": { "version": 1, "classes": {
    "activities": { "primary": "garmin", "enabled": ["garmin", "apple-health"] },
    "wearable_health": { "primary": "garmin", "enabled": ["garmin", "apple-health"] },
    "body": { "primary": "apple-health", "enabled": ["apple-health"] },
    "nutrition": { "primary": null, "enabled": [] },
    "calendar": { "primary": null, "enabled": [] }
  } },
  "connected": ["garmin", "apple-health"],
  "classes": [
    { "id": "activities", "label": "Activités", "description": "Séances.", "providers": [
      { "id": "garmin", "name": "Garmin" }, { "id": "strava", "name": "Strava" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "wearable_health", "label": "Santé wearable", "description": "Sommeil.", "providers": [
      { "id": "garmin", "name": "Garmin" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "body", "label": "Corps", "description": "Poids.", "providers": [
      { "id": "withings", "name": "Withings" }, { "id": "apple-health", "name": "Apple Santé" } ] },
    { "id": "nutrition", "label": "Nutrition", "description": "Calories.", "providers": [
      { "id": "sharpit", "name": "Journal SharpIt" } ] }
  ]
}
"""

private actor StubSourcePrefs: SourcePrefsServing {
    private(set) var patches: [String] = []
    var refuses = false

    func refuse() { refuses = true }

    func sourcePrefs(token: String) async throws -> V1SourcePrefsResponse {
        try JSONDecoder().decode(V1SourcePrefsResponse.self, from: Data(answerJSON.utf8))
    }

    func updateSourcePrefs(_ action: SourcePrefsAction, dataClass: String, provider: String, token: String) async throws -> V1SourcePrefs {
        patches.append("\(action.rawValue) \(dataClass) \(provider)")
        if refuses { throw SharpitAPIError.badRequest }
        var prefs = try await sourcePrefs(token: token).prefs
        if action == .setPrimary { prefs.classes[dataClass]?.primary = provider }
        return prefs
    }
}

@MainActor
@Test func onlyClassesAConnectedSourceCanFeedAreShown() async {
    let store = SourcePrefsStore(client: StubSourcePrefs(), tokenProvider: { "t" })
    await store.load()

    #expect(store.classes.map(\.id) == ["activities", "wearable_health", "body"])
    #expect(store.offersPrimary(in: "wearable_health"))
    #expect(!store.offersPrimary(in: "body"))
    #expect(store.isPrimary("garmin", in: "activities"))
}

@MainActor
@Test func choosingAPrimaryShowsAtOnceAndIsSent() async {
    let client = StubSourcePrefs()
    let store = SourcePrefsStore(client: client, tokenProvider: { "t" })
    await store.load()

    await store.setPrimary("apple-health", in: "wearable_health")

    #expect(store.isPrimary("apple-health", in: "wearable_health"))
    #expect(await client.patches == ["setPrimary wearable_health apple-health"])
}

@MainActor
@Test func turningThePrimaryOffHandsItToTheNextSource() async {
    let client = StubSourcePrefs()
    await client.refuse()
    let failures = SharpitWriteFailures()
    let store = SourcePrefsStore(client: client, tokenProvider: { "t" }, failures: failures)
    await store.load()

    await store.setEnabled("garmin", in: "activities", false)

    // Refused: said once, and the web's prefs read back.
    #expect(failures.latest?.message == "Source non enregistrée. Réessaie plus tard.")
    #expect(store.isEnabled("garmin", in: "activities"))
    #expect(await client.patches == ["disable activities garmin"])
}

@Test func unknownProvidersShowWithoutALogo() {
    #expect(ProviderLogo.Provider(integrationId: "apple-health") == .appleHealth)
    #expect(ProviderLogo.Provider(integrationId: "withings") == .withings)
    #expect(ProviderLogo.Provider(integrationId: "sharpit") == .sharpit)
    #expect(ProviderLogo.Provider(integrationId: "polar") == nil)
}

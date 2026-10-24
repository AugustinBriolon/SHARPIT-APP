import AuthenticationServices
import CloudKit
import Foundation
import Testing
@testable import Sharpit

// MARK: - Apple Santé

/// The switch says on or off; the line only turns into a reason when the switch alone would mislead.
@Test func appleHealthSubtitleOnlyBecomesAReasonWhenSomethingStopsIt() {
    let normal = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .idle)
    let sending = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .sending)
    let unavailable = ConnectionsReadout.appleHealthSubtitle(isAvailable: false, state: .idle)
    let refused = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .failed("Accès refusé."))

    #expect(normal == .init(text: "Séances, sommeil et cœur de ta montre", isProblem: false))
    #expect(sending == normal)
    #expect(unavailable == .init(text: "Indisponible sur cet appareil", isProblem: false))
    #expect(refused == .init(text: "Accès refusé.", isProblem: true))
}

// MARK: - Provider OAuth in-app session

private struct StubOAuthHandoff: ProviderOAuthHandoffServing {
    var result: Result<URL, Error> = .success(URL(string: "https://sharpit.app/sign-in?__clerk_ticket=t")!)

    func providerHandoffURL(_ source: DisconnectableSource, token _: String) async throws -> URL {
        _ = source
        return try result.get()
    }
}

private func connectOAuth(
    source: DisconnectableSource = .strava,
    handoff: StubOAuthHandoff = StubOAuthHandoff(),
    closingOn result: Result<URL, Error>
) async -> ProviderOAuthConnectOutcome {
    await ProviderOAuthConnect.run(
        source: source,
        client: handoff,
        tokenProvider: { "jwt" }
    ) { _, _ in try result.get() }
}

@Test func anOAuthSessionClosingOnTheCallbackSaysHowItEnded() async {
    let connected = await connectOAuth(
        closingOn: .success(URL(string: "https://sharpit.app/connect/strava/callback?strava=connected")!)
    )
    let denied = await connectOAuth(
        source: .google,
        closingOn: .success(URL(string: "https://sharpit.app/connect/google/callback?google=denied")!)
    )
    #expect(connected == .connected)
    #expect(connected.isLinked)
    #expect(denied == .denied)
    #expect(!denied.isLinked)
}

@Test func closingTheOAuthSheetIsACancellationNotAFailure() async {
    let outcome = await connectOAuth(closingOn: .failure(ASWebAuthenticationSessionError(.canceledLogin)))
    #expect(outcome == .cancelled)
}

@Test func anOAuthCallbackForTheWrongProviderIsAFailure() async {
    let mismatch = await connectOAuth(
        source: .strava,
        closingOn: .success(URL(string: "https://sharpit.app/connect/google/callback?google=connected")!)
    )
    #expect(mismatch == .failed)
}

@Test func oauthOutcomesReadTheWebsStatusesAndSayThemInFrench() {
    #expect(ProviderOAuthConnectOutcome(status: "already_connected") == .alreadyConnected)
    #expect(ProviderOAuthConnectOutcome(status: "unknown") == .failed)
    #expect(ProviderOAuthConnect.callbackPath(for: .withings) == "/connect/withings/callback")
    #expect(ProviderOAuthConnect.callbackPath(for: .garmin) == "/connect/garmin/callback")
    #expect(ProviderOAuthConnectOutcome.connected.message(for: .strava).hasPrefix("Strava connecté"))
    #expect(ProviderOAuthConnectOutcome.cancelled.tone == .syncing)
}

@Test func settingsCountsEveryLinkedSourceNotOnlyAppleHealth() {
    let linked = ConnectionsReadout.linkedSources(
        providerKeys: ["strava", "google", "withings", "garmin"],
        appleHealthEnabled: true,
        appleCalendarLinked: true
    )
    #expect(linked.count == 6)
    #expect(ConnectionsReadout.sourcesSummary(linked) == "6 sources connectées")
    #expect(ConnectionsReadout.sourcesSummary([.appleHealth]) == "Apple Santé connecté")
    #expect(ConnectionsReadout.sourcesSummary([]) == "Aucune source connectée")
}

import AuthenticationServices
import CloudKit
import Foundation
import Testing
@testable import Sharpit

// MARK: - Garmin

@Test func garminBadgeIsReadFromTheProviderListNotAssumed() {
    let connected = V1SyncStatus(
        lastSyncAt: nil,
        providers: [V1SyncProvider(key: "garmin", label: "Garmin", lastSyncAt: nil)]
    )
    let withoutGarmin = V1SyncStatus(lastSyncAt: nil, providers: [])

    #expect(ConnectionsReadout.garmin(status: connected) == .init(text: "Connecté", tone: .positive))
    #expect(ConnectionsReadout.garmin(status: withoutGarmin) == .init(text: "Non connecté", tone: .neutral))
    #expect(ConnectionsReadout.garmin(status: nil) == .init(text: "—", tone: .neutral))
}

// MARK: - Apple Santé

/// The switch says on or off; the line only turns into a reason when the switch alone would mislead.
@Test func appleHealthSubtitleOnlyBecomesAReasonWhenSomethingStopsIt() {
    let normal = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .idle)
    let sending = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .sending)
    let unavailable = ConnectionsReadout.appleHealthSubtitle(isAvailable: false, state: .idle)
    let refused = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .failed("Accès refusé."))

    #expect(normal == .init(text: "Complète Garmin entre deux synchros", isProblem: false))
    #expect(sending == normal)
    #expect(unavailable == .init(text: "Indisponible sur cet iPhone", isProblem: false))
    #expect(refused == .init(text: "Accès refusé.", isProblem: true))
}

// MARK: - iCloud

@Test func everyICloudStatusHasAShortReading() {
    #expect(ConnectionsReadout.iCloud(.available) == "Actif")
    #expect(ConnectionsReadout.iCloud(.noAccount) == "Aucun compte")
    #expect(ConnectionsReadout.iCloud(.restricted) == "Restreint")
    #expect(ConnectionsReadout.iCloud(.temporarilyUnavailable) == "Indisponible")
    #expect(ConnectionsReadout.iCloud(.couldNotDetermine) == "Inconnu")
    #expect(ConnectionsReadout.iCloud(nil) == "—")
}

// MARK: - Garmin In-App Connection

private nonisolated final class GarminStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GarminConnectClientTests {
    private func makeClient(status: Int, response: String) -> SharpitClient {
        GarminStubURLProtocol.status = status
        GarminStubURLProtocol.responseData = Data(response.utf8)
        GarminStubURLProtocol.lastRequest = nil
        GarminStubURLProtocol.lastBody = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GarminStubURLProtocol.self]
        return SharpitClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://api.sharpit.app")!
        )
    }

    @Test func asksTheV1ContractForTheHandoffWithTheBearer() async throws {
        let entry = "https://sharpit.app/sign-in?__clerk_ticket=t&redirect_url=x"
        let client = makeClient(status: 200, response: #"{"apiVersion":1,"url":"\#(entry)"}"#)

        let url = try await client.garminHandoffURL(token: "jwt")

        let request = try #require(GarminStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://api.sharpit.app/api/v1/garmin/handoff")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
        #expect(url.absoluteString == entry)
    }
}

// MARK: - Garmin in-app session

private struct StubHandoff: GarminHandoffServing {
    var result: Result<URL, Error> = .success(URL(string: "https://sharpit.app/sign-in?__clerk_ticket=t")!)

    func garminHandoffURL(token _: String) async throws -> URL {
        try result.get()
    }
}

private func connect(
    handoff: StubHandoff = StubHandoff(),
    closingOn result: Result<URL, Error>
) async -> GarminConnectOutcome {
    await GarminConnect.run(client: handoff, tokenProvider: { "jwt" }) { _ in try result.get() }
}

@Test func theSessionClosingOnTheCallbackSaysHowItEnded() async {
    let connected = await connect(closingOn: .success(URL(string: "https://sharpit.app/connect/garmin/callback?garmin=connected")!))
    let consent = await connect(closingOn: .success(URL(string: "https://sharpit.app/connect/garmin/callback?garmin=consent_required")!))
    #expect(connected == .connected)
    #expect(connected.isLinked)
    #expect(consent == .consentRequired)
    #expect(!consent.isLinked)
}

@Test func closingTheSheetIsACancellationNotAFailure() async {
    let outcome = await connect(closingOn: .failure(ASWebAuthenticationSessionError(.canceledLogin)))
    #expect(outcome == .cancelled)
}

@Test func aCallbackOffTheApexOrNoHandoffIsAFailure() async {
    let offApex = await connect(closingOn: .success(URL(string: "https://api.sharpit.app/connect/garmin/callback?garmin=connected")!))
    let noHandoff = await connect(
        handoff: StubHandoff(result: .failure(SharpitAPIError.server)),
        closingOn: .success(URL(string: "https://sharpit.app/connect/garmin/callback?garmin=connected")!)
    )
    #expect(offApex == .failed)
    #expect(noHandoff == .failed)
}

@Test func outcomesReadTheWebsStatusesAndSayThemInFrench() {
    #expect(GarminConnectOutcome(status: "already_connected") == .alreadyConnected)
    #expect(GarminConnectOutcome(status: "unknown") == .failed)
    #expect(GarminConnectOutcome(status: nil) == .failed)
    #expect(GarminConnectOutcome.connected.tone == .success)
    #expect(GarminConnectOutcome.denied.tone == .error)
    #expect(GarminConnectOutcome.cancelled.message == "Connexion Garmin annulée")
}

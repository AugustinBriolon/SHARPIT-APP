import Foundation
import Testing
@testable import Sharpit

// MARK: - Garmin linked by a personal API key

@Test func garminIsOfferedOnlyWhenTheServerOpensTheKeyForm() {
    let closed = ConnectionsReadout.split(linked: [], unavailable: [.garmin])
    #expect(!closed.available.contains(.garmin))

    let open = ConnectionsReadout.split(linked: [])
    #expect(open.available.last == .garmin)
}

@Test func garminsRowShowsOnlyTheKeysLastFourCharacters() {
    let line = ConnectionsReadout.garminKeyLine(last4: "1234")
    #expect(line.text == "Clé ••••1234")
    #expect(!line.isProblem)
}

@Test func aGarminRowWithoutAKeyAsksForANewOne() {
    #expect(ConnectionsReadout.garminKeyLine(last4: nil).isProblem)
    #expect(ConnectionsReadout.garminKeyLine(last4: "").isProblem)
}

@Test func aRefusedGarminKeySaysGarminsReason() {
    let refusal = "Clé API Garmin refusée ou expirée. Crée une nouvelle clé sur Garmin Connect."
    #expect(ConnectionsReadout.garminKeyFailure(SharpitAPIError.message(refusal)) == refusal)
    #expect(ConnectionsReadout.garminKeyFailure(SharpitAPIError.transport).hasPrefix("Pas de connexion internet"))
}

@Test func garminDisconnectsThroughItsOwnRouteAndIsNotAnOAuthHandoff() {
    #expect(DisconnectableSource.garmin.path == "/api/v1/garmin/disconnect")
    #expect(ManagedSource.garmin.oauth == .garmin)
    #expect(!DisconnectableSource.garmin.connectsViaOAuthHandoff)
}

private nonisolated final class GarminStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GarminKeyNetworkTests {
    private let base = URL(string: "https://api.example.test")!

    private func client(status: Int, response: String) -> GarminKeyClient {
        GarminStubURLProtocol.status = status
        GarminStubURLProtocol.responseData = Data(response.utf8)
        GarminStubURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GarminStubURLProtocol.self]
        return GarminKeyClient(session: URLSession(configuration: configuration), baseURL: base)
    }

    @Test func theStatusReadsTheMaskedKey() async throws {
        let status = try await client(
            status: 200,
            response: #"{"available":true,"connected":true,"apiKeyLast4":"1234","lastSyncAt":null}"#
        ).status(token: "tok")
        #expect(status == V1GarminKeyStatus(available: true, connected: true, apiKeyLast4: "1234"))
        let request = try #require(GarminStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/api/v1/garmin/connect")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func connectingPostsTheKeyWithTheBearer() async throws {
        try await client(status: 200, response: #"{"success":true,"apiKeyLast4":"1234"}"#)
            .connect(apiKey: "gpk_1234", token: "tok")
        let request = try #require(GarminStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func aKeyGarminRefusesCarriesTheServersMessage() async {
        let refusal = "Clé API Garmin refusée ou expirée. Crée une nouvelle clé sur Garmin Connect."
        await #expect(throws: SharpitAPIError.message(refusal)) {
            try await client(status: 400, response: #"{"error":"\#(refusal)"}"#)
                .connect(apiKey: "bad", token: "tok")
        }
    }
}

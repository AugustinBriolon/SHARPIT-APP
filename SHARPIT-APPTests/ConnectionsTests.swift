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
            baseURL: URL(string: "https://sharpit.app")!
        )
    }

    @Test func postsTheCredentialsToTheV1ContractWithTheBearer() async throws {
        let client = makeClient(status: 200, response: #"{"success":true,"displayName":"Athlete Garmin"}"#)

        let response = try await client.connectGarmin(username: "athlete@example.com", password: "pw", token: "jwt")

        let request = try #require(GarminStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://sharpit.app/api/v1/garmin/connect")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
        let body = try JSONSerialization.jsonObject(with: try #require(GarminStubURLProtocol.lastBody)) as? [String: String]
        #expect(body == ["username": "athlete@example.com", "password": "pw"])
        #expect(response.success)
        #expect(response.displayName == "Athlete Garmin")
    }

    @Test func surfacesTheServersWrongCredentialsMessage() async throws {
        let message = "Identifiants Garmin incorrects. Vérifie ton e-mail et ton mot de passe."
        let client = makeClient(status: 401, response: #"{"error":"\#(message)"}"#)

        await #expect(throws: SharpitAPIError.message(message)) {
            _ = try await client.connectGarmin(username: "athlete@example.com", password: "wrong", token: "jwt")
        }
    }

    @Test func keepsRateLimitingDistinctWhenTheBodyCarriesNoMessage() async throws {
        let client = makeClient(status: 429, response: "")

        await #expect(throws: SharpitAPIError.rateLimited) {
            _ = try await client.connectGarmin(username: "athlete@example.com", password: "pw", token: "jwt")
        }
    }
}

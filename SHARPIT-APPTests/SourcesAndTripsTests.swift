import Foundation
import Testing
@testable import Sharpit

private func utcDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

// MARK: - Disconnecting a source

@Test func eachDisconnectableSourcePostsToItsOwnV1Route() {
    #expect(DisconnectableSource.garmin.path == "/api/v1/garmin/disconnect")
    #expect(DisconnectableSource.withings.path == "/api/v1/withings/disconnect")
    #expect(DisconnectableSource.google.path == "/api/v1/google/disconnect")
    #expect(DisconnectableSource.google.confirmationTitle == "Déconnecter Google Agenda ?")
}

@Test func connectedSourcesAreReadFromTheSyncStatusInTheScreensOrder() {
    let status = V1SyncStatus(
        lastSyncAt: nil,
        providers: [
            V1SyncProvider(key: "google", label: "Google Agenda", lastSyncAt: nil),
            V1SyncProvider(key: "strava", label: "Strava", lastSyncAt: nil),
            V1SyncProvider(key: "withings", label: "Withings", lastSyncAt: nil),
        ]
    )
    #expect(DisconnectableSource.connected(in: status) == [.withings, .google])
    #expect(DisconnectableSource.connected(in: nil).isEmpty)
}

@Test func theSourcesFooterSaysWhereWebSourcesConnect() {
    #expect(ConnectionsReadout.webSourcesFooter(connected: []).contains("sharpit.app"))
    #expect(ConnectionsReadout.webSourcesFooter(connected: [.garmin]) == ConnectionsReadout.webSourcesFooter(connected: []))
    #expect(ConnectionsReadout.webSourcesFooter(connected: [.withings]).hasPrefix("Touche une source"))
}

@Test func aFailedDisconnectionSaysTheServersReasonOrTheFix() {
    #expect(ConnectionsReadout.disconnectFailure(.withings, error: SharpitAPIError.message("Déconnexion échouée")) == "Déconnexion échouée")
    #expect(ConnectionsReadout.disconnectFailure(.google, error: SharpitAPIError.transport).contains("Google Agenda est toujours relié"))
    #expect(ConnectionsReadout.disconnectFailure(.garmin, error: SharpitAPIError.server).hasPrefix("Déconnexion de Garmin impossible"))
}

private nonisolated final class SourcesStubURLProtocol: URLProtocol, @unchecked Sendable {
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
struct SourcesNetworkTests {
    private func session(status: Int, response: String) -> URLSession {
        SourcesStubURLProtocol.status = status
        SourcesStubURLProtocol.responseData = Data(response.utf8)
        SourcesStubURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourcesStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let base = URL(string: "https://api.example.test")!

    @Test func disconnectingPostsWithTheBearer() async throws {
        let client = SourceDisconnectClient(session: session(status: 200, response: #"{"ok":true}"#), baseURL: base)
        try await client.disconnect(.withings, token: "tok")
        let request = try #require(SourcesStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.example.test/api/v1/withings/disconnect")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func aServerFailureOnDisconnectIsRetryable() async {
        let client = SourceDisconnectClient(session: session(status: 500, response: #"{"error":"Déconnexion échouée"}"#), baseURL: base)
        await #expect(throws: SharpitAPIError.server) {
            try await client.disconnect(.google, token: "tok")
        }
    }

    @Test func theExportIsTheServersJSONObject() async throws {
        let client = PrivacyExportClient(session: session(status: 200, response: #"{"profile":{"id":"a1"}}"#), baseURL: base)
        let data = try await client.exportData(token: "tok")
        #expect(PrivacyExport.isJSONObject(data))
        #expect(SourcesStubURLProtocol.lastRequest?.url?.absoluteString == "https://api.example.test/api/v1/privacy/export")
        #expect(SourcesStubURLProtocol.lastRequest?.httpMethod == "GET")
    }

    @Test func anExportThatIsNotJSONIsAServerFailure() async {
        let client = PrivacyExportClient(session: session(status: 200, response: "<html></html>"), baseURL: base)
        await #expect(throws: SharpitAPIError.server) {
            try await client.exportData(token: "tok")
        }
    }
}

// MARK: - Data export

@Test func theExportFileIsNamedByItsDayNeverByTheAthlete() {
    let name = PrivacyExport.fileName(on: utcDate("2026-10-05T09:30:00Z"), calendar: utcCalendar)
    #expect(name == "sharpit-export-2026-10-05.json")
}

@Test func theExportIsWrittenToATemporaryFile() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = Data(#"{"a":1}"#.utf8)
    let url = try PrivacyExport.write(data, on: .now, in: directory)
    #expect(try Data(contentsOf: url) == data)
    #expect(url.pathExtension == "json")
}

// MARK: - Travel in Plan's week

@Test func onlyTripsOverlappingTheWeekShowOnPlan() {
    let week = (0..<7).map { utcDate("2026-10-05T00:00:00Z").addingTimeInterval(Double($0) * 86_400) }
    let lisbon = CoachMemoryEntry(
        type: .travel, label: "Lisbonne",
        startDate: utcDate("2026-10-10T00:00:00Z"), endDate: utcDate("2026-10-14T00:00:00Z")
    )
    let before = CoachMemoryEntry(
        type: .travel, locationLabel: "Lyon",
        startDate: utcDate("2026-09-28T00:00:00Z"), endDate: utcDate("2026-10-04T00:00:00Z")
    )
    let edge = CoachMemoryEntry(
        type: .travel, locationLabel: "Nantes",
        startDate: utcDate("2026-10-01T00:00:00Z"), endDate: utcDate("2026-10-05T00:00:00Z")
    )
    let constraint = CoachMemoryEntry(
        type: .constraint, label: "Genou",
        startDate: utcDate("2026-10-05T00:00:00Z"), endDate: utcDate("2026-10-08T00:00:00Z")
    )
    let trips = PlanTravel.trips([lisbon, before, edge, constraint], overlapping: week, calendar: utcCalendar)
    #expect(trips.map(\.displayTitle) == ["Nantes", "Lisbonne"])
    #expect(PlanTravel.chipTitle(trips) == "Nantes +1")
    #expect(PlanTravel.chipTitle([]) == nil)
}

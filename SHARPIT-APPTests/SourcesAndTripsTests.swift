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

    @Test func aHikeTripConflictCarriesTheServersReason() async {
        let client = HikeTripClient(
            session: session(status: 409, response: #"{"error":"Une activité appartient déjà à un autre séjour","tripId":"t2"}"#),
            baseURL: base
        )
        await #expect(throws: SharpitAPIError.message("Une activité appartient déjà à un autre séjour")) {
            _ = try await client.createHikeTrip(name: "Queyras", activityIds: ["a", "b"], token: "tok")
        }
        #expect(SourcesStubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(SourcesStubURLProtocol.lastRequest?.url?.absoluteString == "https://api.example.test/api/v1/hike-trips")
    }

    @Test func deletingAHikeTripAcceptsAnEmpty204() async throws {
        let client = HikeTripClient(session: session(status: 204, response: ""), baseURL: base)
        try await client.deleteHikeTrip(id: "t1", token: "tok")
        #expect(SourcesStubURLProtocol.lastRequest?.httpMethod == "DELETE")
        #expect(SourcesStubURLProtocol.lastRequest?.url?.absoluteString == "https://api.example.test/api/v1/hike-trips/t1")
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

// MARK: - Séjours de randonnée

private let tripJSON = """
[{
  "id": "t1",
  "name": "Queyras · août",
  "createdAt": "2026-08-20T10:00:00.000Z",
  "updatedAt": "2026-08-21T10:00:00.000Z",
  "activities": [
    {"id": "a2", "type": "HIKE", "date": "2026-08-13T07:00:00.000Z", "title": "Étape 2", "duration": 18000,
     "load": 120, "observedLocationLabel": "Saint-Véran",
     "hikeMetrics": {"distanceM": 16000, "elevationM": 900, "elevationLossM": 700}},
    {"id": "a1", "type": "HIKE", "date": "2026-08-12T07:00:00.000Z", "title": null, "duration": 14400,
     "load": null, "observedLocationLabel": "Ceillac",
     "hikeMetrics": {"distanceM": 12500, "elevationM": 750, "elevationLossM": null}},
    {"id": "a3", "type": "HIKE", "date": "2026-08-14T07:00:00.000Z", "title": "Retour", "duration": null,
     "load": 80, "observedLocationLabel": "Saint-Véran", "hikeMetrics": null}
  ],
  "summary": {"memberCount": 3}
}]
"""

@Test func aHikeTripDecodesItsStagesInWalkingOrder() throws {
    let trips = try JSONDecoder().decode([V1HikeTrip].self, from: Data(tripJSON.utf8))
    let trip = try #require(trips.first)
    #expect(trip.name == "Queyras · août")
    #expect(trip.activities.map(\.id) == ["a1", "a2", "a3"])
    #expect(trip.activities[0].displayTitle == "Randonnée")
    #expect(trip.activities[1].elevationLossM == 700)
    #expect(trip.activities[2].distanceM == nil)
}

@Test func theTripSummarySumsOnlyWhatTheStagesCarry() throws {
    let trip = try #require(try JSONDecoder().decode([V1HikeTrip].self, from: Data(tripJSON.utf8)).first)
    let summary = trip.summary
    #expect(summary.memberCount == 3)
    #expect(summary.distanceM == 28_500)
    #expect(summary.elevationM == 1_650)
    #expect(summary.elevationLossM == 700)
    #expect(summary.durationSec == 32_400)
    #expect(summary.load == 200)
    #expect(summary.locationLabels == ["Ceillac", "Saint-Véran"])
    #expect(summary.startAt == utcDate("2026-08-12T07:00:00Z"))
    #expect(summary.endAt == utcDate("2026-08-14T07:00:00Z"))
    #expect(HikeTripSummary(members: []).distanceM == nil)
}

@Test func aTripReadsAsItsDaysStagesAndDistance() throws {
    let trip = try #require(try JSONDecoder().decode([V1HikeTrip].self, from: Data(tripJSON.utf8)).first)
    let utc = TimeZone(identifier: "UTC")!
    #expect(HikeTripReadout.listMeta(trip.summary, timeZone: utc) == ["12 – 14 août 2026", "3 étapes", "28,5 km"])
    #expect(HikeTripReadout.stepCount(1) == "1 étape")
    #expect(HikeTripReadout.stepCount(0) == nil)
    #expect(HikeTripReadout.distance(850) == "850 m")
    #expect(HikeTripReadout.waypoints(trip.summary.locationLabels) == "Ceillac → Saint-Véran")
    #expect(HikeTripReadout.dayRange(
        from: utcDate("2026-09-28T08:00:00Z"), to: utcDate("2026-10-02T08:00:00Z"), timeZone: utc
    ) == "28 sept. – 2 oct. 2026")
    let stage = trip.activities[1]
    #expect(HikeTripReadout.memberMeta(stage, timeZone: utc).dropFirst() == ["16,0 km", "D+ 900 m", "5 h"])
}

@Test func aTripPatchSendsOnlyWhatChanged() {
    let rename = HikeTripPatch(name: "  Queyras  ")
    #expect(rename.body["name"] as? String == "Queyras")
    #expect(rename.body["addActivityIds"] == nil)
    let add = HikeTripPatch(addActivityIds: ["a4"])
    #expect(add.body["addActivityIds"] as? [String] == ["a4"])
    #expect(add.body["name"] == nil)
    #expect(HikeTripPatch().isEmpty)
    #expect(HikeTripPatch(name: "   ").isEmpty)
}

@Test func onlyHikesOutsideASejourCanJoinOne() throws {
    let trip = try #require(try JSONDecoder().decode([V1HikeTrip].self, from: Data(tripJSON.utf8)).first)
    let history = [
        V1ActivityListItem(id: "a1", type: .hike, date: utcDate("2026-08-12T07:00:00Z")),
        V1ActivityListItem(id: "a9", type: .hike, date: utcDate("2026-09-01T07:00:00Z")),
        V1ActivityListItem(id: "r1", type: .run, date: utcDate("2026-09-02T07:00:00Z")),
        V1ActivityListItem(id: "a8", type: .hike, date: utcDate("2026-09-05T07:00:00Z")),
    ]
    let hikes = HikeTripStore.hikes(in: history)
    #expect(hikes.map(\.id) == ["a8", "a9", "a1"])
    #expect(HikeTripStore.available(hikes: hikes, trips: [trip]).map(\.id) == ["a8", "a9"])
}

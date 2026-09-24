import Foundation
import Testing
@testable import Sharpit

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func at(_ isoDay: String, hour: Int = 8) -> Date {
    let parts = isoDay.split(separator: "-").compactMap { Int($0) }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
}

/// Built by decoding, because the wire types are `Decodable` only.
private func activity(
    _ id: String,
    on date: Date,
    type: String = "RUN",
    duration: Int? = 3600,
    linkedTo plannedId: String? = nil
) -> V1ActivityListItem {
    var fields = [
        "\"id\": \"\(id)\"",
        "\"type\": \"\(type)\"",
        "\"date\": \"\(ISO8601DateFormatter().string(from: date))\"",
        "\"title\": \"Réalisé \(id)\"",
    ]
    if let duration { fields.append("\"duration\": \(duration)") }
    if let plannedId {
        fields.append("\"plannedSession\": { \"id\": \"\(plannedId)\", \"title\": \"Prévu\", \"analysis\": null }")
    }
    let json = "{ \(fields.joined(separator: ", ")) }"
    do {
        return try JSONDecoder().decode(V1ActivityListItem.self, from: Data(json.utf8))
    } catch {
        fatalError("fixture does not match V1ActivityListItem: \(error)")
    }
}

// MARK: - Candidates

@Test func candidatesAreTheUnlinkedActivitiesWithinADay() {
    let reference = at("2026-09-20")
    let candidates = SessionLinkCandidate.candidates(
        from: [
            activity("same-day", on: at("2026-09-20", hour: 18)),
            activity("already-linked", on: at("2026-09-20"), linkedTo: "other"),
            activity("two-days-before", on: at("2026-09-18")),
            activity("day-before", on: at("2026-09-19")),
            activity("day-after", on: at("2026-09-21")),
            activity("week-after", on: at("2026-09-27")),
        ],
        around: reference,
        calendar: calendar
    )
    #expect(Set(candidates.map(\.id)) == ["same-day", "day-before", "day-after"])
}

@Test func candidatesPutTheSameDayFirstThenTheMostRecent() {
    let candidates = SessionLinkCandidate.candidates(
        from: [
            activity("day-before", on: at("2026-09-19")),
            activity("day-after", on: at("2026-09-21")),
            activity("morning", on: at("2026-09-20", hour: 7)),
            activity("evening", on: at("2026-09-20", hour: 19)),
        ],
        around: at("2026-09-20"),
        calendar: calendar
    )
    #expect(candidates.map(\.id) == ["evening", "morning", "day-after", "day-before"])
}

@Test func candidatesSayHowFarTheyAreFromThePrescription() {
    let candidates = SessionLinkCandidate.candidates(
        from: [
            activity("same-day", on: at("2026-09-20")),
            activity("day-before", on: at("2026-09-19")),
            activity("day-after", on: at("2026-09-21")),
        ],
        around: at("2026-09-20"),
        calendar: calendar
    )
    let labels = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.dayLabel) })
    #expect(labels == ["same-day": "Même jour", "day-before": "J−1", "day-after": "J+1"])
}

@Test func candidateDescribesTheActivity() {
    let candidates = SessionLinkCandidate.candidates(
        from: [activity("swim", on: at("2026-09-20"), type: "SWIM", duration: 3900)],
        around: at("2026-09-20"),
        calendar: calendar
    )
    #expect(candidates.first?.sport == "Natation")
    #expect(candidates.first?.durationLabel == "1 h 5 min")
}

@Test func anActivityWithoutADurationHasNoDurationLabel() {
    let candidates = SessionLinkCandidate.candidates(
        from: [activity("no-duration", on: at("2026-09-20"), duration: nil)],
        around: at("2026-09-20"),
        calendar: calendar
    )
    #expect(candidates.first?.durationLabel == nil)
}

// MARK: - Store

private actor Calls {
    private(set) var links: [String] = []
    private(set) var invalidations = 0

    func recordLink(_ text: String) { links.append(text) }
    func recordInvalidation() { invalidations += 1 }
}

private struct StubActivities: ActivityServing {
    var list: [V1ActivityListItem] = []
    var listError: SharpitAPIError?
    let calls: Calls

    func activities(token: String) async throws -> [V1ActivityListItem] {
        if let listError { throw listError }
        return list
    }

    func invalidateActivities() async { await calls.recordInvalidation() }

    func activity(id: String, token: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload { throw SharpitAPIError.server }
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {}
}

private struct StubLinker: PlannedSessionLinking {
    var error: SharpitAPIError?
    let calls: Calls

    func link(sessionId: String, activityId: String?, token: String) async throws {
        if let error { throw error }
        await calls.recordLink("\(sessionId)->\(activityId ?? "nil")")
    }
}

@MainActor
private func store(
    list: [V1ActivityListItem] = [activity("run-1", on: at("2026-09-20"))],
    listError: SharpitAPIError? = nil,
    linkError: SharpitAPIError? = nil,
    calls: Calls = Calls()
) -> SessionLinkStore {
    SessionLinkStore(
        sessionId: "session-1",
        referenceDate: at("2026-09-20"),
        activities: StubActivities(list: list, listError: listError, calls: calls),
        linker: StubLinker(error: linkError, calls: calls),
        tokenProvider: { "token" },
        calendar: calendar
    )
}

@MainActor
@Test func storeLoadsTheCandidatesAroundTheSession() async {
    let store = store()
    await store.load()
    #expect(store.phase == .ready)
    #expect(store.candidates.map(\.id) == ["run-1"])
}

@MainActor
@Test func storeReportsWhenTheActivitiesCannotBeLoaded() async {
    let store = store(listError: .transport)
    await store.load()
    #expect(store.phase == .failed("Tes séances réalisées n'ont pas pu être chargées."))
}

@MainActor
@Test func storeLinksThePickedActivityAndForgetsTheStaleList() async {
    let calls = Calls()
    let store = store(calls: calls)
    await store.load()

    let linked = await store.link(store.candidates[0])

    #expect(linked)
    #expect(await calls.links == ["session-1->run-1"])
    #expect(await calls.invalidations == 1)
    #expect(store.phase == .ready)
}

@MainActor
@Test func aFailedLinkKeepsTheListAndAllowsAnotherTry() async {
    let calls = Calls()
    let store = store(
        list: [activity("run-1", on: at("2026-09-20")), activity("run-2", on: at("2026-09-20", hour: 18))],
        linkError: .server,
        calls: calls
    )
    await store.load()

    let linked = await store.link(store.candidates[0])

    #expect(!linked)
    #expect(store.phase == .failed("La liaison n'a pas abouti. Réessaie."))
    #expect(store.candidates.count == 2)
    #expect(await calls.invalidations == 0)
    // The failed phase must not lock the list: a second candidate can still be tried.
    #expect(await store.link(store.candidates[1]) == false)
}

@MainActor
@Test func anExpiredSessionSaysSo() async {
    let store = store(linkError: .unauthorized)
    await store.load()
    _ = await store.link(store.candidates[0])
    #expect(store.phase == .failed("Session expirée. Reconnecte-toi."))
}

// MARK: - Client

private nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
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
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func linkingClient() -> PlannedSessionClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return PlannedSessionClient(
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://sharpit.example")!
    )
}

@Suite(.serialized)
struct PlannedSessionClientLinkTests {
    @Test func postsTheActivityToTheSessionsLinkRoute() async throws {
        StubURLProtocol.status = 200
        try await linkingClient().link(sessionId: "session-1", activityId: "run-1", token: "abc")

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://sharpit.example/api/v1/planned-sessions/session-1/link")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let body = try JSONSerialization.jsonObject(with: try #require(StubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["activityId"] as? String == "run-1")
    }

    @Test func sendsANullActivityToUnlink() async throws {
        StubURLProtocol.status = 200
        try await linkingClient().link(sessionId: "session-1", activityId: nil, token: "abc")

        let body = try JSONSerialization.jsonObject(with: try #require(StubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["activityId"] is NSNull)
    }

    @Test func mapsAnExpiredTokenAndServerFailures() async {
        StubURLProtocol.status = 401
        await #expect(throws: SharpitAPIError.unauthorized) {
            try await linkingClient().link(sessionId: "s", activityId: "a", token: "t")
        }
        StubURLProtocol.status = 404
        await #expect(throws: SharpitAPIError.server) {
            try await linkingClient().link(sessionId: "s", activityId: "a", token: "t")
        }
    }
}

// MARK: - Training day

@Test func aTrainingDayIdParsesToLocalMidnight() {
    let date = TrainingDayId.date("2026-09-20")
    let parts = date.map { Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour], from: $0) }
    #expect(parts?.year == 2026)
    #expect(parts?.month == 9)
    #expect(parts?.day == 20)
    #expect(parts?.hour == 0)
    #expect(TrainingDayId.date("not-a-day") == nil)
}

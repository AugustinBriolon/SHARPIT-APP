import Foundation
import Testing
@testable import Sharpit

// MARK: - Stub Protocol for Network Tests

private nonisolated final class WatchPushStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseData = Data("{}".utf8)
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

private func makeWatchClient() -> PlannedSessionClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WatchPushStubURLProtocol.self]
    return PlannedSessionClient(
        session: URLSession(configuration: configuration),
        baseURL: URL(string: "https://sharpit.example")!
    )
}

@Suite(.serialized)
struct PlannedSessionWatchPushTests {

    // MARK: - Model & Decoding Tests

    @Test func sessionDecodesGarminWorkoutFields() throws {
        let json = """
        {
            "id": "session-42",
            "date": "2026-09-22",
            "title": "Sortie longue seuil",
            "type": "RUN",
            "durationMin": 75,
            "garminWorkoutId": "gwk-999",
            "garminWorkoutScheduledDate": "2026-09-22",
            "garminWorkoutPushedAt": "2026-09-22T15:30:00.000Z"
        }
        """
        let session = try JSONDecoder().decode(V1PlannedSessionItem.self, from: Data(json.utf8))
        #expect(session.id == "session-42")
        #expect(session.garminWorkoutId == "gwk-999")
        #expect(session.garminWorkoutScheduledDate == "2026-09-22")
        #expect(session.garminWorkoutPushedAt != nil)
    }

    @Test func sessionDecodesIntegerGarminWorkoutIdResiliently() throws {
        let json = """
        {
            "id": "session-43",
            "date": "2026-09-23",
            "title": "PMA Vélo",
            "type": "BIKE",
            "garminWorkoutId": 8847291
        }
        """
        let session = try JSONDecoder().decode(V1PlannedSessionItem.self, from: Data(json.utf8))
        #expect(session.garminWorkoutId == "8847291")
    }

    @Test func withGarminPushUpdatesFieldsCorrectly() {
        let original = V1PlannedSessionItem(
            id: "s-1",
            date: Date(),
            title: "Natation",
            type: "SWIM"
        )
        #expect(original.garminWorkoutId == nil)

        let pushed = original.withGarminPush(
            workoutId: "gwk-123",
            scheduledDate: "2026-09-24",
            pushedAt: Date()
        )
        #expect(pushed.garminWorkoutId == "gwk-123")
        #expect(pushed.garminWorkoutScheduledDate == "2026-09-24")
        #expect(pushed.garminWorkoutPushedAt != nil)
    }

    @Test func plannedSessionPreviewCarriesWatchFields() {
        let now = Date()
        let session = V1PlannedSessionItem(
            id: "s-2",
            date: now,
            title: "Footing",
            type: "RUN",
            garminWorkoutId: "gwk-555",
            garminWorkoutScheduledDate: "2026-09-25",
            garminWorkoutPushedAt: now
        )
        let preview = PlannedSessionPreview(session: session)
        #expect(preview.garminWorkoutId == "gwk-555")
        #expect(preview.garminWorkoutScheduledDate == "2026-09-25")
        #expect(preview.garminWorkoutPushedAt == now)
    }

    // MARK: - Client Push Tests

    @Test func pushToWatchSendsPostRequestAndReturnsResult() async throws {
        WatchPushStubURLProtocol.status = 200
        WatchPushStubURLProtocol.responseData = Data("""
        {
            "workoutId": 7654321,
            "workoutName": "SharpIt - Sortie longue",
            "sport": "RUN",
            "stepCount": 6,
            "scheduledDate": "2026-09-22",
            "pushedAt": "2026-09-22T16:00:00.000Z"
        }
        """.utf8)

        let client = makeWatchClient()
        let result = try await client.pushToWatch(sessionId: "session-1", force: false, token: "test-token")

        let request = try #require(WatchPushStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/garmin/workouts/from-planned-session")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

        let body = try JSONSerialization.jsonObject(with: try #require(WatchPushStubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["plannedSessionId"] as? String == "session-1")
        #expect(body?["schedule"] as? Bool == true)
        #expect(body?["force"] as? Bool == false)

        #expect(result.workoutId == "7654321")
        #expect(result.workoutName == "SharpIt - Sortie longue")
        #expect(result.scheduledDate == "2026-09-22")
        #expect(result.alreadyPushed == false)
    }

    @Test func pushToWatchThrowsAlreadyPushedOn409Conflict() async {
        WatchPushStubURLProtocol.status = 409
        WatchPushStubURLProtocol.responseData = Data("""
        {
            "error": "Cette séance est déjà sur Garmin.",
            "alreadyPushed": true,
            "receipt": {
                "workoutId": "gwk-999",
                "scheduledDate": "2026-09-22"
            }
        }
        """.utf8)

        let client = makeWatchClient()
        do {
            _ = try await client.pushToWatch(sessionId: "session-1", force: false, token: "test-token")
            Issue.record("Expected alreadyPushed error")
        } catch let error as PlannedSessionWatchPushError {
            #expect(error == .alreadyPushed(message: "Cette séance est déjà sur Garmin.", scheduledDate: "2026-09-22"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func pushToWatchThrowsNotConnectedOn404() async {
        WatchPushStubURLProtocol.status = 404
        WatchPushStubURLProtocol.responseData = Data("""
        {
            "error": "Compte Garmin non connecté"
        }
        """.utf8)

        let client = makeWatchClient()
        do {
            _ = try await client.pushToWatch(sessionId: "session-1", force: false, token: "test-token")
            Issue.record("Expected notConnected error")
        } catch let error as PlannedSessionWatchPushError {
            #expect(error == .notConnected("Compte Garmin non connecté"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func pushToWatchWithForceSendsForceTrue() async throws {
        WatchPushStubURLProtocol.status = 200
        WatchPushStubURLProtocol.responseData = Data("""
        {
            "workoutId": "gwk-forced",
            "workoutName": "Remplacement PMA",
            "scheduledDate": "2026-09-22"
        }
        """.utf8)

        let client = makeWatchClient()
        let result = try await client.pushToWatch(sessionId: "session-force", force: true, token: "token-abc")

        let body = try JSONSerialization.jsonObject(with: try #require(WatchPushStubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["force"] as? Bool == true)
        #expect(result.workoutId == "gwk-forced")
    }
}

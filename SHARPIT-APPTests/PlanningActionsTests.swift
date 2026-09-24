import Foundation
import Testing
@testable import Sharpit

// MARK: - Stub Protocol for Network Tests

private nonisolated final class PlanningStubURLProtocol: URLProtocol, @unchecked Sendable {
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

private func makeStubURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PlanningStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

@Suite(.serialized)
struct PlanningActionsTests {

    // MARK: - Macro Training Plan Tests

    @Test func trainingPlanDecodesProperly() throws {
        let json = """
        {
            "id": "plan-123",
            "goalId": "goal-456",
            "raceDate": "2026-12-01",
            "startDate": "2026-09-01",
            "baselineCtl": 45.0,
            "summary": "Objectif Marathon 3h15",
            "status": "ACTIVE",
            "weeks": [
                {
                    "id": "w-1",
                    "weekStart": "2026-09-01",
                    "weekIndex": 1,
                    "phase": "BUILD",
                    "targetLoad": 450.0,
                    "targetHours": 6.5,
                    "focus": "Volume modéré et tempo",
                    "isDeload": false
                },
                {
                    "id": "w-4",
                    "weekStart": "2026-09-22",
                    "weekIndex": 4,
                    "phase": "BUILD",
                    "targetLoad": 300.0,
                    "targetHours": 4.0,
                    "focus": "Semaine d'assimilation",
                    "isDeload": true
                }
            ]
        }
        """
        let plan = try JSONDecoder().decode(V1TrainingPlan.self, from: Data(json.utf8))
        #expect(plan.id == "plan-123")
        #expect(plan.goalId == "goal-456")
        #expect(plan.summary == "Objectif Marathon 3h15")
        #expect(plan.weeks.count == 2)
        #expect(plan.weeks[0].phase == .build)
        #expect(plan.weeks[0].weekIndex == 1)
        #expect(plan.weeks[0].targetLoad == 450.0)
        #expect(plan.weeks[1].isDeload == true)
    }

    @Test func trainingPlanClientFetchesActivePlan() async throws {
        PlanningStubURLProtocol.status = 200
        PlanningStubURLProtocol.responseData = Data("""
        {
            "id": "plan-abc",
            "goalId": "goal-789",
            "raceDate": "2026-11-15",
            "startDate": "2026-09-01",
            "status": "ACTIVE",
            "weeks": []
        }
        """.utf8)

        let client = TrainingPlanClient(session: makeStubURLSession(), baseURL: URL(string: "https://sharpit.example")!)
        let plan = try await client.fetchActivePlan(token: "tok-test")

        let request = try #require(PlanningStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/v1/training-plans")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-test")
        #expect(plan?.id == "plan-abc")
    }

    @Test func trainingPlanClientArchivesPlan() async throws {
        PlanningStubURLProtocol.status = 200
        PlanningStubURLProtocol.responseData = Data("{}".utf8)

        let client = TrainingPlanClient(session: makeStubURLSession(), baseURL: URL(string: "https://sharpit.example")!)
        try await client.archivePlan(id: "plan-to-archive", token: "tok-arch")

        let request = try #require(PlanningStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/training-plans/plan-to-archive")
    }

    // MARK: - Coach Plan Generator Tests

    @Test func generatedPlanDecodesProperly() throws {
        let json = """
        {
            "summary": "Plan de 7 jours axé sur le foncier",
            "sessions": [
                {
                    "date": "2026-09-24",
                    "startTime": "08:00",
                    "title": "Footing endurance fondamentale",
                    "type": "RUN",
                    "durationMin": 45,
                    "load": 42,
                    "intensity": "EASY",
                    "description": "Courir en aisance respiratoire à 70% FCmax",
                    "rationale": "Maintien de la base aérobie sans fatigue excessive",
                    "decisionId": "dec-001"
                }
            ]
        }
        """
        let plan = try JSONDecoder().decode(V1GeneratedPlan.self, from: Data(json.utf8))
        #expect(plan.summary == "Plan de 7 jours axé sur le foncier")
        #expect(plan.sessions.count == 1)
        let s = plan.sessions[0]
        #expect(s.date == "2026-09-24")
        #expect(s.type == .run)
        #expect(s.durationMin == 45)
        #expect(s.load == 42)
        #expect(s.decisionId == "dec-001")
    }

    // MARK: - Coach Adapt Plan Tests

    @Test func adaptPlanResultDecodesProperly() throws {
        let json = """
        {
            "summary": "Allègement suite à une fatigue accrue",
            "changes": [
                {
                    "action": "MODIFY",
                    "sessionId": "s-old-1",
                    "date": "2026-09-25",
                    "title": "Séance allégée",
                    "type": "RUN",
                    "durationMin": 30,
                    "load": 25,
                    "intensity": "EASY",
                    "description": "Réduction du volume",
                    "reason": "VFC basse détectée",
                    "decisionId": "dec-adapt-1"
                },
                {
                    "action": "REMOVE",
                    "sessionId": "s-old-2",
                    "title": "Fractionné court",
                    "reason": "Trop intense pour la récupération"
                },
                {
                    "action": "ADD",
                    "date": "2026-09-27",
                    "title": "Mobilité & Récupération",
                    "type": "OTHER",
                    "durationMin": 20,
                    "load": 10,
                    "intensity": "RECOVERY",
                    "reason": "Favoriser la régénération"
                }
            ]
        }
        """
        let result = try JSONDecoder().decode(V1AdaptPlanResult.self, from: Data(json.utf8))
        #expect(result.summary == "Allègement suite à une fatigue accrue")
        #expect(result.changes.count == 3)

        #expect(result.changes[0].action == .modify)
        #expect(result.changes[0].sessionId == "s-old-1")
        #expect(result.changes[0].type == .run)

        #expect(result.changes[1].action == .remove)
        #expect(result.changes[1].sessionId == "s-old-2")

        #expect(result.changes[2].action == .add)
        #expect(result.changes[2].type == .other)
    }

    // MARK: - PlannedSessionClient Mutations

    @Test func createPlannedSessionSendsCorrectPayload() async throws {
        PlanningStubURLProtocol.status = 200
        PlanningStubURLProtocol.responseData = Data("""
        {
            "id": "new-session-id",
            "date": "2026-09-24T12:00:00Z",
            "title": "Sortie vélo",
            "type": "BIKE",
            "durationMin": 90,
            "load": 80
        }
        """.utf8)

        let client = PlannedSessionClient(session: makeStubURLSession(), baseURL: URL(string: "https://sharpit.example")!)
        let payload = CreatePlannedSessionPayload(
            type: "BIKE",
            date: "2026-09-24T12:00:00Z",
            startTime: "09:30",
            title: "Sortie vélo",
            description: "Zone 2",
            durationMin: 90,
            load: 80,
            intensity: "MODERATE",
            goalId: "goal-1",
            decisionId: "dec-1"
        )
        let item = try await client.createSession(payload, token: "tok-create")

        let request = try #require(PlanningStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/planned-sessions")
        #expect(item.id == "new-session-id")
        #expect(item.type == "BIKE")

        let body = try JSONSerialization.jsonObject(with: try #require(PlanningStubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["type"] as? String == "BIKE")
        #expect(body?["title"] as? String == "Sortie vélo")
        #expect(body?["durationMin"] as? Double == 90)
        #expect(body?["goalId"] as? String == "goal-1")
    }

    @Test func updatePlannedSessionSendsPatch() async throws {
        PlanningStubURLProtocol.status = 200
        PlanningStubURLProtocol.responseData = Data("""
        {
            "id": "session-to-update",
            "date": "2026-09-25T12:00:00Z",
            "title": "Sortie modifiée",
            "type": "RUN"
        }
        """.utf8)

        let client = PlannedSessionClient(session: makeStubURLSession(), baseURL: URL(string: "https://sharpit.example")!)
        let patch = UpdatePlannedSessionPayload(
            type: "RUN",
            title: "Sortie modifiée",
            durationMin: 45
        )
        let updated = try await client.updateSession(id: "session-to-update", patch: patch, token: "tok-up")

        let request = try #require(PlanningStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/v1/planned-sessions/session-to-update")
        #expect(updated.title == "Sortie modifiée")

        let body = try JSONSerialization.jsonObject(with: try #require(PlanningStubURLProtocol.lastBody)) as? [String: Any]
        #expect(body?["title"] as? String == "Sortie modifiée")
        #expect(body?["durationMin"] as? Double == 45)
    }

    @Test func deletePlannedSessionSendsDelete() async throws {
        PlanningStubURLProtocol.status = 200
        PlanningStubURLProtocol.responseData = Data("{}".utf8)

        let client = PlannedSessionClient(session: makeStubURLSession(), baseURL: URL(string: "https://sharpit.example")!)
        try await client.deleteSession(id: "session-del-42", token: "tok-del")

        let request = try #require(PlanningStubURLProtocol.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/api/v1/planned-sessions/session-del-42")
    }
}

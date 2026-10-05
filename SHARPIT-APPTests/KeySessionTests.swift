import Foundation
import Testing
@testable import Sharpit

/// Keeps the patches it was sent, or refuses as told.
@MainActor
private final class SessionPatcher: PlannedSessionMutating {
    private(set) var patches: [(id: String, isKey: Bool?)] = []
    let refusal: SharpitAPIError?

    init(refusal: SharpitAPIError? = nil) { self.refusal = refusal }

    func createSession(_: PlannedSessionFields, token _: String) async throws -> V1PlannedSessionItem {
        throw SharpitAPIError.badRequest
    }

    func updateSession(id: String, fields: PlannedSessionFields, token _: String) async throws -> V1PlannedSessionItem {
        if let refusal { throw refusal }
        var isKey: Bool?
        if case .bool(let value)? = fields["isKey"] { isKey = value }
        patches.append((id, isKey))
        return V1PlannedSessionItem(id: id, date: .now, isKey: isKey ?? false)
    }

    func deleteSession(id _: String, token _: String) async throws {}
}

@Test func aPlannedSessionReadsWhetherItIsKey() throws {
    let key = try JSONDecoder().decode(
        V1PlannedSessionItem.self,
        from: Data(#"{"id":"s1","date":"2026-10-06T00:00:00.000Z","isKey":true}"#.utf8)
    )
    let older = try JSONDecoder().decode(
        V1PlannedSessionItem.self,
        from: Data(#"{"id":"s2","date":"2026-10-06T00:00:00.000Z"}"#.utf8)
    )
    #expect(key.isKey)
    #expect(!older.isKey)
}

@Test func aProposedSessionReadsTheKeyTheServerMarked() throws {
    let json = #"{"dayOffset":1,"date":"2026-10-06","type":"RUN","intensity":"THRESHOLD","title":"Seuil","description":"","durationMin":50,"load":70,"key":true}"#
    let session = try JSONDecoder().decode(V1GeneratedSession.self, from: Data(json.utf8))
    #expect(session.isKey)
}

@Test func aBrickIsKeyWhenALegIs() {
    let legs = [
        V1PlannedSessionItem(id: "l1", date: .now, type: "BIKE", brickGroupId: "b1", brickOrder: 0, isKey: true),
        V1PlannedSessionItem(id: "l2", date: .now, type: "RUN", brickGroupId: "b1", brickOrder: 1),
    ]
    #expect(PlanEntryBuilder.entries(planned: legs, activities: []).contains { entry in
        if case .brick(let brick) = entry { return brick.isKey }
        return false
    })
}

@MainActor
@Test func markingASessionKeyWritesItAndTellsThePlan() async {
    let patcher = SessionPatcher()
    var changed = 0
    let store = SessionKeyStore(
        sessionId: "s1",
        isKey: false,
        context: SessionKeyContext(mutator: patcher, tokenProvider: { "t" }, onChanged: { changed += 1 })
    )

    await store.set(true)

    #expect(store.isKey)
    #expect(patcher.patches.map(\.isKey) == [true])
    #expect(changed == 1)
}

@MainActor
@Test func aRefusedMarkComesBackAndSaysSo() async {
    let store = SessionKeyStore(
        sessionId: "s1",
        isKey: true,
        context: SessionKeyContext(mutator: SessionPatcher(refusal: .badRequest), tokenProvider: { "t" }, onChanged: {})
    )

    await store.set(false)

    #expect(store.isKey)
    #expect(SharpitWriteFailures.shared.latest?.message == SessionKeyStore.failureMessage)
}

import Foundation
import Testing
@testable import Sharpit

// MARK: - Stored messages

private func stored(_ json: String) -> JSONValue {
    do {
        return try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    } catch {
        fatalError("fixture is not JSON: \(error)")
    }
}

@Test func aStoredTurnIsReadFromItsTextParts() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "assistant", "parts": [
        { "type": "text", "text": "Première" },
        { "type": "tool-plan", "state": "output-available" },
        { "type": "text", "text": "Seconde" }
    ] }
    """))
    #expect(message?.role == .assistant)
    #expect(message?.text == "Première\n\nSeconde")
}

@Test func aTurnWithAnUnknownRoleIsLeftOut() {
    #expect(CoachMessage(stored: stored(#"{ "id": "m1", "role": "system", "parts": [] }"#)) == nil)
}

@Test func aStoredSubjectComesBackAsAChip() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "user", "parts": [{ "type": "text", "text": "Et ça ?" }],
      "metadata": { "discussKind": "planned-session", "sessionId": "s-1" } }
    """))
    #expect(message?.context?.target == .plannedSession(sessionId: "s-1"))
}

@Test func aSubjectTheAppCannotReachReadsAsAnOrdinaryTurn() {
    let message = CoachMessage(stored: stored("""
    { "id": "m1", "role": "user", "parts": [{ "type": "text", "text": "Et ça ?" }],
      "metadata": { "discussKind": "goal", "goalId": "g-1" } }
    """))
    #expect(message?.context == nil)
}

@Test(arguments: [
    (#"{ "discussKind": "planning", "horizonDays": 7 }"#, 7),
    (#"{ "discussKind": "planning", "horizonDays": "7" }"#, 7),
])
func aPlanningHorizonIsReadWhetherTheWebOrTheAppWroteIt(json: String, days: Int) {
    #expect(CoachDiscussContext(storedMetadata: stored(json))?.target == .planning(horizonDays: days))
}

@Test func savingSendsAStoredTurnBackAsItCame() throws {
    let toolPart = #"{ "type": "tool-plan", "state": "output-available" }"#
    let original = try #require(CoachMessage(stored: stored("""
    { "id": "m1", "role": "assistant", "parts": [
        { "type": "text", "text": "Voilà" }, \(toolPart)
    ] }
    """)))

    let body = try CoachConversationClient.body(for: [original])
    let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let parts = ((sent?["messages"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]

    #expect(parts?.count == 2)
    #expect(parts?.last?["type"] as? String == "tool-plan")
}

@Test func savingSendsATurnWrittenHereAsTheChatRouteReadsIt() throws {
    let body = try CoachConversationClient.body(for: [CoachMessage(id: "m1", role: .user, text: "Bonjour")])
    let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let first = (sent?["messages"] as? [[String: Any]])?.first

    #expect(first?["id"] as? String == "m1")
    #expect(first?["role"] as? String == "user")
    #expect(((first?["parts"] as? [[String: Any]])?.first?["text"]) as? String == "Bonjour")
}

// MARK: - Store

private actor Saved {
    private(set) var created: [[CoachMessage]] = []
    private(set) var saved: [(id: String, messages: [CoachMessage])] = []
    private(set) var deleted: [String] = []

    func recordCreate(_ messages: [CoachMessage]) { created.append(messages) }
    func recordSave(_ id: String, _ messages: [CoachMessage]) { saved.append((id, messages)) }
    func recordDelete(_ id: String) { deleted.append(id) }
}

private struct StubConversations: CoachConversationServing {
    var list: [CoachConversationSummary] = []
    var opened: CoachConversation?
    var failing = false
    let saved: Saved

    func conversations(token: String) async throws -> [CoachConversationSummary] {
        if failing { throw SharpitAPIError.transport }
        return list
    }

    func conversation(id: String, token: String) async throws -> CoachConversation {
        guard let opened, !failing else { throw SharpitAPIError.server }
        return opened
    }

    func create(messages: [CoachMessage], token: String) async throws -> String {
        if failing { throw SharpitAPIError.transport }
        await saved.recordCreate(messages)
        return "conversation-1"
    }

    func save(id: String, messages: [CoachMessage], token: String) async throws {
        if failing { throw SharpitAPIError.transport }
        await saved.recordSave(id, messages)
    }

    func delete(id: String, token: String) async throws {
        if failing { throw SharpitAPIError.server }
        await saved.recordDelete(id)
    }
}

@MainActor
private func coachStore(
    opened: CoachConversation? = nil,
    failing: Bool = false,
    saved: Saved = Saved()
) -> CoachStore {
    CoachStore(
        client: StubCoachClient(deltas: ["Oui"]),
        conversations: StubConversations(opened: opened, failing: failing, saved: saved),
        tokenProvider: { "token" }
    )
}

@MainActor
private func ask(_ store: CoachStore, _ text: String = "Bonjour") async {
    store.draft = text
    await store.send()
}

@MainActor
@Test func theFirstExchangeCreatesTheConversation() async {
    let saved = Saved()
    let store = coachStore(saved: saved)

    await ask(store)

    #expect(store.conversationId == "conversation-1")
    #expect(await saved.created.count == 1)
    #expect(await saved.created.first?.map(\.role) == [.user, .assistant])
    #expect(await saved.saved.isEmpty)
}

@MainActor
@Test func laterExchangesReplaceTheWholeThread() async {
    let saved = Saved()
    let store = coachStore(saved: saved)
    await ask(store, "Une")
    await ask(store, "Deux")

    #expect(await saved.created.count == 1)
    #expect(await saved.saved.count == 1)
    #expect(await saved.saved.first?.id == "conversation-1")
    #expect(await saved.saved.first?.messages.count == 4)
}

@MainActor
@Test func aFailedSaveDoesNotHideTheAnswer() async {
    let store = coachStore(failing: true)

    await ask(store)

    #expect(store.messages.map(\.role) == [.user, .assistant])
    #expect(store.failure == nil)
    #expect(store.conversationId == nil)
}

@MainActor
@Test func aNewConversationStartsEmptyAndIsCreatedAgain() async {
    let saved = Saved()
    let store = coachStore(saved: saved)
    await ask(store)

    store.startNewConversation()
    #expect(store.isEmpty)
    #expect(store.conversationId == nil)

    await ask(store, "Autre sujet")
    #expect(await saved.created.count == 2)
}

@MainActor
@Test func openingAConversationReplacesTheThreadAndContinuesIt() async {
    let saved = Saved()
    let past = CoachConversation(
        id: "past-1",
        messages: [CoachMessage(id: "a", role: .user, text: "Hier"), CoachMessage(id: "b", role: .assistant, text: "Oui")]
    )
    let store = coachStore(opened: past, saved: saved)
    await ask(store, "Brouillon")

    let opened = await store.open(conversationId: "past-1")
    #expect(opened)
    #expect(store.messages.map(\.id) == ["a", "b"])
    #expect(store.conversationId == "past-1")

    await ask(store, "Suite")
    #expect(await saved.saved.last?.id == "past-1")
    #expect(await saved.saved.last?.messages.count == 4)
}

@MainActor
@Test func aConversationThatCannotBeOpenedLeavesTheThreadAlone() async {
    let store = coachStore(opened: nil)
    await ask(store)

    let opened = await store.open(conversationId: "missing")

    #expect(!opened)
    #expect(store.messages.count == 2)
    #expect(store.failure == "Cette conversation n'a pas pu être ouverte.")
}

@MainActor
@Test func deletingTheOpenConversationClearsTheThread() async {
    let store = coachStore()
    await ask(store)

    store.forget(conversationId: "another")
    #expect(!store.isEmpty)

    store.forget(conversationId: "conversation-1")
    #expect(store.isEmpty)
    #expect(store.conversationId == nil)
}

// MARK: - History

private func summary(_ id: String) -> CoachConversationSummary {
    CoachConversationSummary(id: id, title: "Titre \(id)", updatedAt: Date(timeIntervalSince1970: 1_789_000_000))
}

@MainActor
private func history(
    list: [CoachConversationSummary],
    failing: Bool = false,
    saved: Saved = Saved(),
    onDeleted: @escaping (String) -> Void = { _ in }
) -> CoachHistoryStore {
    CoachHistoryStore(
        conversations: StubConversations(list: list, failing: failing, saved: saved),
        tokenProvider: { "token" },
        onDeleted: onDeleted
    )
}

@MainActor
@Test func historyListsTheConversations() async {
    let store = history(list: [summary("a"), summary("b")])
    await store.load()
    #expect(store.phase == .loaded([summary("a"), summary("b")]))
}

@MainActor
@Test func historyReportsWhenItCannotLoad() async {
    let store = history(list: [], failing: true)
    await store.load()
    #expect(store.phase == .failed("L'historique n'a pas pu être chargé."))
}

@MainActor
@Test func deletingRemovesTheRowAndTellsTheThread() async {
    let saved = Saved()
    var told: [String] = []
    let store = history(list: [summary("a"), summary("b")], saved: saved, onDeleted: { told.append($0) })
    await store.load()

    await store.delete(summary("a"))

    #expect(store.phase == .loaded([summary("b")]))
    #expect(await saved.deleted == ["a"])
    #expect(told == ["a"])
}

@MainActor
@Test func aRefusedDeletionBringsTheRowBack() async {
    // The list loads through a stub that works, then the delete goes through a failing one.
    let store = CoachHistoryStore(
        conversations: FailingDeletes(list: [summary("a")]),
        tokenProvider: { "token" },
        onDeleted: { _ in Issue.record("must not announce a deletion that failed") }
    )
    await store.load()

    await store.delete(summary("a"))

    #expect(store.phase == .loaded([summary("a")]))
    #expect(store.deletionFailure == "La conversation n'a pas pu être supprimée.")
}

private struct FailingDeletes: CoachConversationServing {
    let list: [CoachConversationSummary]

    func conversations(token: String) async throws -> [CoachConversationSummary] { list }
    func conversation(id: String, token: String) async throws -> CoachConversation { throw SharpitAPIError.server }
    func create(messages: [CoachMessage], token: String) async throws -> String { "x" }
    func save(id: String, messages: [CoachMessage], token: String) async throws {}
    func delete(id: String, token: String) async throws { throw SharpitAPIError.server }
}

// MARK: - Wire

@Test func summariesDecodeTheServersTimestamps() throws {
    let json = """
    [{ "id": "c1", "title": "Ma semaine", "createdAt": "2026-09-19T08:00:00.000Z", "updatedAt": "2026-09-20T09:30:00.123Z" },
     { "id": "c2", "title": "Sans fraction", "createdAt": "2026-09-19T08:00:00Z", "updatedAt": "2026-09-20T09:30:00Z" }]
    """
    let list = try JSONDecoder().decode([CoachConversationSummary].self, from: Data(json.utf8))
    #expect(list.map(\.title) == ["Ma semaine", "Sans fraction"])
    #expect(list[0].updatedAt > list[1].updatedAt)
}

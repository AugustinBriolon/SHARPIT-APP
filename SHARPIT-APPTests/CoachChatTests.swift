import Foundation
import Testing
@testable import Sharpit

// MARK: - Stream parsing

// The route answers with the AI SDK's UI-message stream. Unknown event types are skipped
// rather than rejected, so a new one on the server cannot blank an installed app.

@Test func aTextDeltaIsReadFromItsEventLine() {
    let line = #"data: {"type":"text-delta","delta":"Bon"}"#

    #expect(CoachChatClient.textDelta(inEventLine: line) == "Bon")
}

@Test func theOlderFieldNameIsStillRead() {
    let line = #"data: {"type":"text-delta","textDelta":"Bon"}"#

    #expect(CoachChatClient.textDelta(inEventLine: line) == "Bon")
}

@Test func everyOtherEventTypeIsSkipped() {
    for line in [
        #"data: {"type":"start"}"#,
        #"data: {"type":"tool-call","toolName":"plan"}"#,
        #"data: {"type":"finish"}"#,
    ] {
        #expect(CoachChatClient.textDelta(inEventLine: line) == nil)
    }
}

@Test func streamBookkeepingLinesAreSkipped() {
    #expect(CoachChatClient.textDelta(inEventLine: "data: [DONE]") == nil)
    #expect(CoachChatClient.textDelta(inEventLine: "") == nil)
    #expect(CoachChatClient.textDelta(inEventLine: ": keep-alive") == nil)
    #expect(CoachChatClient.textDelta(inEventLine: "event: message") == nil)
}

@Test func aMalformedPayloadIsSkippedRatherThanCrashing() {
    #expect(CoachChatClient.textDelta(inEventLine: "data: {not json") == nil)
}

@Test func whitespaceInsideADeltaSurvives() {
    // Trimming the payload must not trim the text — a lost leading space glues words.
    let line = #"data: {"type":"text-delta","delta":" ton allure"}"#

    #expect(CoachChatClient.textDelta(inEventLine: line) == " ton allure")
}

// MARK: - Wire shape

@Test func aQuestionTravelsAsAUIMessageWithTextParts() {
    let wire = CoachChatClient.wireMessage(CoachMessage(id: "m1", role: .user, text: "Et demain ?"))

    #expect(wire["id"] as? String == "m1")
    #expect(wire["role"] as? String == "user")
    let parts = wire["parts"] as? [[String: String]]
    #expect(parts == [["type": "text", "text": "Et demain ?"]])
}

@Test func theSubjectTravelsAsMetadataNotAsProse() {
    // The athlete's words stay theirs; the server is told what they were looking at.
    let context = CoachDiscuss.describe(.activity(activityId: "a-1"), name: "Sortie longue")
    let wire = CoachChatClient.wireMessage(CoachMessage(role: .user, text: "Alors ?", context: context))

    let metadata = wire["metadata"] as? [String: String]
    #expect(metadata?["discussKind"] == "activity")
    #expect(metadata?["activityId"] == "a-1")
    let parts = wire["parts"] as? [[String: String]]
    #expect(parts?.first?["text"] == "Alors ?")
}

@Test func aMessageWithoutASubjectCarriesNoMetadata() {
    let wire = CoachChatClient.wireMessage(CoachMessage(role: .user, text: "Salut"))

    #expect(wire["metadata"] == nil)
}

// MARK: - Store

private struct StubCoachClient: CoachChatServing {
    var deltas: [String] = []
    var failure: (any Error)?

    func reply(to messages: [CoachMessage], token: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            deltas.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

@MainActor
private func store(_ client: StubCoachClient = StubCoachClient(deltas: ["Oui"])) -> CoachStore {
    CoachStore(client: client, tokenProvider: { "token" })
}

@MainActor
@Test func sendingAppendsTheQuestionThenTheAnswer() async {
    let coach = store(StubCoachClient(deltas: ["Tu ", "peux ", "y aller."]))
    coach.draft = "Je pousse demain ?"

    await coach.send()

    #expect(coach.messages.count == 2)
    #expect(coach.messages[0].role == .user)
    #expect(coach.messages[0].text == "Je pousse demain ?")
    #expect(coach.messages[1].role == .assistant)
    #expect(coach.messages[1].text == "Tu peux y aller.")
    #expect(coach.draft.isEmpty)
}

@MainActor
@Test func theAttachedSubjectTravelsWithThatTurnAndIsThenReleased() async {
    let coach = store()
    coach.attach(CoachDiscuss.describe(.today))
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.messages.first?.context?.kind == "today")
    // Released, so the next question is not silently about the same thing.
    #expect(coach.pendingContext == nil)
}

@MainActor
@Test func theAthleteCanDropTheSubjectBeforeSending() {
    let coach = store()
    coach.attach(CoachDiscuss.describe(.today))

    coach.dropContext()

    #expect(coach.pendingContext == nil)
}

@MainActor
@Test func anEmptyDraftCannotBeSent() async {
    let coach = store()
    coach.draft = "   "

    #expect(coach.canSend == false)
    await coach.send()
    #expect(coach.messages.isEmpty)
}

@MainActor
@Test func anAnswerThatNeverArrivesLeavesNoEmptyBubble() async {
    let coach = store(StubCoachClient(deltas: []))
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.messages.count == 1)
    #expect(coach.messages[0].role == .user)
    #expect(coach.failure != nil)
}

@MainActor
@Test func aFailedStreamKeepsTheQuestionAndReportsIt() async {
    let coach = store(StubCoachClient(failure: SharpitAPIError.transport))
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.messages.map(\.role) == [.user])
    #expect(coach.failure != nil)
}

@MainActor
@Test func anExpiredSessionSaysSoRatherThanFailingSilently() async {
    let coach = store(StubCoachClient(failure: SharpitAPIError.unauthorized))
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.failure?.contains("Reconnecte") == true)
}

@MainActor
@Test func withoutATokenTheQuestionIsKeptAndTheReasonGiven() async {
    let coach = CoachStore(client: StubCoachClient(deltas: ["Oui"]), tokenProvider: nil)
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.messages.map(\.role) == [.user])
    #expect(coach.failure != nil)
}

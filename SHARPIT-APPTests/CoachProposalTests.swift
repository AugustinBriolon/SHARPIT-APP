import Foundation
import Testing
@testable import Sharpit

// MARK: - Stream → UI message parts

/// What the route streams for "move my Thursday run": a sentence, then an update awaiting approval.
private let proposalStream: [JSONValue] = [
    chunk(#"{"type":"start"}"#),
    chunk(#"{"type":"start-step"}"#),
    chunk(#"{"type":"text-start","id":"0"}"#),
    chunk(#"{"type":"text-delta","id":"0","delta":"Je décale "}"#),
    chunk(#"{"type":"text-delta","id":"0","delta":"ta séance."}"#),
    chunk(#"{"type":"text-end","id":"0"}"#),
    chunk(#"{"type":"tool-input-start","toolCallId":"c1","toolName":"updatePlannedSession"}"#),
    chunk(#"{"type":"tool-input-delta","toolCallId":"c1","inputTextDelta":"{\"id\""}"#),
    chunk(#"{"type":"tool-input-available","toolCallId":"c1","toolName":"updatePlannedSession","input":{"id":"s1","title":"Footing","date":"2026-09-26","type":"RUN","durationMin":45,"intensity":"ENDURANCE"},"providerMetadata":{"google":{"thoughtSignature":"sig"}}}"#),
    chunk(#"{"type":"tool-approval-request","approvalId":"a1","toolCallId":"c1","signature":"hmac"}"#),
    chunk(#"{"type":"finish-step"}"#),
    chunk(#"{"type":"finish","finishReason":"tool-calls"}"#),
]

private func assembled(_ chunks: [JSONValue]) -> [JSONValue] {
    var assembler = CoachUIMessageAssembler()
    chunks.forEach { assembler.apply($0) }
    return assembler.parts
}

@Test func theStreamBuildsTheTurnTheWebWouldHave() throws {
    let parts = assembled(proposalStream)

    #expect(parts.map { $0["type"]?.string } == ["step-start", "text", "tool-updatePlannedSession"])
    #expect(parts[1]["text"]?.string == "Je décale ta séance.")
    #expect(parts[1]["state"]?.string == "done")
    let tool = parts[2]
    #expect(tool["state"]?.string == "approval-requested")
    #expect(tool["approval"]?["id"]?.string == "a1")
    // What the server needs to accept the answer and replay the call.
    #expect(tool["approval"]?["signature"]?.string == "hmac")
    #expect(tool["callProviderMetadata"]?["google"]?["thoughtSignature"]?.string == "sig")
    #expect(tool["input"]?["id"]?.string == "s1")
}

@Test func anAnswerCompletesTheStepOnlyOnceEveryProposalHasOne() {
    let two = assembled(Array(proposalStream.dropLast(2)) + [
        chunk(#"{"type":"tool-input-available","toolCallId":"c2","toolName":"deletePlannedSession","input":{"id":"s2"}}"#),
        chunk(#"{"type":"tool-approval-request","approvalId":"a2","toolCallId":"c2"}"#),
    ])

    let first = CoachUIParts.responding(two, approvalId: "a1", approved: true)
    #expect(!CoachUIParts.isCompleteWithApprovalResponses(first))

    let both = CoachUIParts.responding(first, approvalId: "a2", approved: false)
    #expect(CoachUIParts.isCompleteWithApprovalResponses(both))
    #expect(CoachUIParts.approvalFingerprint(both) == "a1|a2")
    #expect(both[2]["approval"]?["reason"]?.string == CoachUIParts.approvedReason)
    #expect(both[2]["approval"]?["signature"]?.string == "hmac")
}

@Test func theContinuationFinishesTheSameCall() {
    var assembler = CoachUIMessageAssembler(parts: CoachUIParts.responding(assembled(proposalStream), approvalId: "a1", approved: true))
    [
        chunk(#"{"type":"start"}"#),
        chunk(#"{"type":"start-step"}"#),
        chunk(#"{"type":"tool-output-available","toolCallId":"c1","output":{"ok":true,"title":"Footing"}}"#),
        chunk(#"{"type":"finish-step"}"#),
        chunk(#"{"type":"start-step"}"#),
        chunk(#"{"type":"text-start","id":"1"}"#),
        chunk(#"{"type":"text-delta","id":"1","delta":"C'est fait."}"#),
        chunk(#"{"type":"text-end","id":"1"}"#),
    ].forEach { assembler.apply($0) }

    let tool = assembler.parts[2]
    #expect(tool["state"]?.string == "output-available")
    #expect(tool["approval"]?["approved"] == .bool(true))
    #expect(tool["input"]?["id"]?.string == "s1")
    #expect(assembler.text == "Je décale ta séance.\n\nC'est fait.")
    #expect(CoachUIParts.appliedChanges(assembler.parts) == 1)
}

@Test func aNewQuestionRefusesTheOpenProposal() {
    let dismissed = CoachUIParts.dismissingUnresolved(assembled(proposalStream))

    #expect(dismissed[2]["state"]?.string == "output-denied")
    #expect(dismissed[2]["approval"]?["approved"] == .bool(false))
    #expect(dismissed[2]["approval"]?["reason"]?.string == CoachUIParts.dismissedReason)
}

@Test func aCoachTurnGoesBackWithItsParts() {
    let message = CoachMessage(role: .assistant, text: "Je décale ta séance.", parts: assembled(proposalStream))

    let wire = CoachChatClient.wireMessage(message)
    let parts = wire["parts"] as? [[String: Any]]

    #expect(parts?.count == 3)
    #expect(parts?.last?["type"] as? String == "tool-updatePlannedSession")
    #expect((parts?.last?["approval"] as? [String: Any])?["signature"] as? String == "hmac")
}

// MARK: - Cards

@Test func aProposalReadsLikeTheWebsCard() throws {
    let proposal = try #require(CoachProposal(part: assembled(proposalStream)[2]))

    #expect(proposal.status == .awaiting(approvalId: "a1"))
    #expect(proposal.headline == "Footing")
    #expect(proposal.proposal == "Modifier une séance")
    #expect(proposal.intentLine == "Course · 45 min · Endurance")
    #expect(proposal.date == CoachProposal.formattedDate("2026-09-26"))
}

@Test func aProposalSaysHowItEnded() throws {
    let failed = chunk(#"{"type":"tool-createPlannedSession","toolCallId":"c","state":"output-available","input":{"title":"Seuil"},"output":{"ok":false,"error":"Créneau déjà pris"}}"#)
    let refused = chunk(#"{"type":"tool-deletePlannedSession","toolCallId":"d","state":"output-denied","input":{"id":"s"}}"#)

    #expect(CoachProposal(part: failed)?.status == .failed("Créneau déjà pris"))
    #expect(CoachProposal(part: refused)?.status == .refused)
    #expect(CoachProposal(part: refused)?.headline == "Séance ciblée")
    #expect(CoachProposal(part: chunk(#"{"type":"tool-listPlannedSessions","state":"output-available"}"#)) == nil)
}

@Test func anEnduranceBlockReadsAsItsSteps() throws {
    let part = chunk(#"{"type":"tool-createPlannedSession","toolCallId":"c","state":"approval-requested","approval":{"id":"a"},"input":{"title":"VMA","endurancePrescription":{"blocks":[{"steps":[{"kind":"warmup","minutes":15,"effort":"ENDURANCE"}]},{"times":6,"steps":[{"kind":"interval","meters":400,"effort":"VO2MAX"},{"kind":"recovery","minutes":1}]}]}}}"#)

    let proposal = try #require(CoachProposal(part: part))

    #expect(proposal.steps == [
        "Échauffement · 15 min · Endurance",
        "6× Travail · 400 m · VO2max + Récup · 1 min",
    ])
}

// MARK: - Store

/// Answers each request with the next response, and keeps what it was sent.
private final class SequencedCoachClient: CoachChatServing, @unchecked Sendable {
    private var responses: [[JSONValue]]
    private(set) var requests: [[CoachMessage]] = []

    init(_ responses: [[JSONValue]]) {
        self.responses = responses
    }

    func reply(to messages: [CoachMessage], token: String) -> AsyncThrowingStream<JSONValue, Error> {
        requests.append(messages)
        let next = responses.isEmpty ? [] : responses.removeFirst()
        return AsyncThrowingStream { continuation in
            next.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

@MainActor
@Test func approvingSendsTheTurnBackAndReloadsThePlan() async {
    let client = SequencedCoachClient([
        proposalStream,
        [
            chunk(#"{"type":"start-step"}"#),
            chunk(#"{"type":"tool-output-available","toolCallId":"c1","output":{"ok":true}}"#),
            chunk(#"{"type":"text-start","id":"1"}"#),
            chunk(#"{"type":"text-delta","id":"1","delta":"C'est fait."}"#),
            chunk(#"{"type":"text-end","id":"1"}"#),
        ],
    ])
    let coach = CoachStore(client: client, tokenProvider: { "t" })
    var calendarChanges = 0
    coach.onCalendarChanged = { calendarChanges += 1 }
    coach.draft = "Décale jeudi"

    await coach.send()
    #expect(coach.hasPendingApproval)
    #expect(calendarChanges == 0)

    await coach.respond(to: "a1", approved: true)

    // The same turn went back, answered, and was continued in place.
    #expect(client.requests.count == 2)
    #expect(client.requests[1].last?.parts?[2]["state"]?.string == "approval-responded")
    #expect(coach.messages.count == 2)
    #expect(!coach.hasPendingApproval)
    #expect(coach.messages[1].text.hasSuffix("C'est fait."))
    #expect(calendarChanges == 1)

    // An answer already sent is not sent again.
    await coach.respond(to: "a1", approved: true)
    #expect(client.requests.count == 2)
}

@MainActor
@Test func aProposalAloneIsAnAnswer() async {
    let onlyTool = proposalStream.filter { !($0["type"]?.string?.hasPrefix("text") ?? false) }
    let coach = CoachStore(client: SequencedCoachClient([onlyTool]), tokenProvider: { "t" })
    coach.draft = "Décale jeudi"

    await coach.send()

    #expect(coach.messages.count == 2)
    #expect(coach.failure == nil)
    #expect(coach.hasPendingApproval)
}

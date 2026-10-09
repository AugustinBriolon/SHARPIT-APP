import Foundation
import Testing
@testable import Sharpit

/// Sample `tool-logFoods` part. The root object must always close — a missing `}`
/// makes `chunk` return `.null` and used to crash the suite via force-unwrap.
private func foodPart(
    state: String = "approval-requested",
    meal: String = "LUNCH",
    grams: Double = 200,
    outputJSON: String? = nil,
    errorText: String? = nil
) -> JSONValue {
    // Single-line body: a missing final `}` makes JSONDecoder return .null.
    var body =
        "{\"type\":\"tool-logFoods\",\"toolCallId\":\"f1\",\"state\":\"\(state)\",\"approval\":{\"id\":\"af1\"},\"input\":{\"date\":\"2026-10-08\",\"meal\":\"\(meal)\",\"items\":[{\"name\":\"Frites\",\"grams\":\(grams),\"kcalPer100g\":300,\"proteinPer100g\":4,\"carbsPer100g\":40,\"fatPer100g\":15}]}}"
    if let outputJSON {
        body.removeLast()
        body += ",\"output\":\(outputJSON)}"
    }
    if let errorText {
        body.removeLast()
        body += ",\"errorText\":\"\(errorText)\"}"
    }
    return chunk(body)
}

private func foodProposal(in message: CoachMessage) -> CoachFoodLogProposal? {
    message.parts?.compactMap { CoachFoodLogProposal(part: $0) }.first
}

@Test func coachFoodLogProposalParsesMealAndItems() throws {
    let proposal = try #require(CoachFoodLogProposal(part: foodPart()))
    #expect(proposal.meal == .lunch)
    #expect(proposal.items.count == 1)
    #expect(proposal.items[0].name == "Frites")
    #expect(proposal.items[0].grams == 200)
    #expect(proposal.approvalId == "af1")
    if case .awaiting(let id) = proposal.status {
        #expect(id == "af1")
    } else {
        Issue.record("expected awaiting")
    }
}

@Test func coachFoodLogKeepsApprovalIdAfterFailure() throws {
    let proposal = try #require(CoachFoodLogProposal(part: foodPart(
        state: "output-error",
        errorText: "Timeout"
    )))
    #expect(proposal.approvalId == "af1")
    if case .failed(let hint) = proposal.status {
        #expect(hint == "Timeout")
    } else {
        Issue.record("expected failed")
    }
}

@Test func coachFoodLogPatchedInputKeepsMacrosAndUpdatesGrams() throws {
    let proposal = try #require(CoachFoodLogProposal(part: foodPart()))
    var item = proposal.items[0]
    item.grams = 150
    let patched = proposal.patchedInput(meal: .dinner, items: [item])
    #expect(patched["meal"]?.string == "DINNER")
    #expect(patched["items"]?.array?.first?["grams"]?.number == 150)
    #expect(patched["items"]?.array?.first?["kcalPer100g"]?.number == 300)
    #expect(patched["date"]?.string == "2026-10-08")
}

@Test func coachFoodLogReadyItemsParsesValidGrams() throws {
    let item = try #require(CoachFoodLogProposal(part: foodPart())?.items.first)
    let ready = CoachFoodLogProposal.readyItems(from: [("150", item)])
    #expect(ready?.count == 1)
    #expect(ready?[0].grams == 150)
}

@Test func coachFoodLogReadyItemsAcceptsFrenchDecimal() throws {
    let item = try #require(CoachFoodLogProposal(part: foodPart())?.items.first)
    let ready = CoachFoodLogProposal.readyItems(from: [("12,5", item)])
    #expect(ready?[0].grams == 12.5)
}

@Test func coachFoodLogReadyItemsRejectsEmptyOrInvalid() throws {
    let item = try #require(CoachFoodLogProposal(part: foodPart())?.items.first)
    #expect(CoachFoodLogProposal.readyItems(from: [("", item)]) == nil)
    #expect(CoachFoodLogProposal.readyItems(from: [("0", item)]) == nil)
    #expect(CoachFoodLogProposal.readyItems(from: [("abc", item)]) == nil)
    #expect(CoachFoodLogProposal.readyItems(from: [("9000", item)]) == nil)
}

@Test func coachFoodLogGramPresetsLeadWithPortionWhenDistinct() {
    let presets = CoachFoodLogProposal.gramPresets(proposedGrams: 175)
    #expect(presets.map(\.grams) == [175, 100, 200])
    let plain = CoachFoodLogProposal.gramPresets(proposedGrams: 100)
    #expect(plain.map(\.grams) == [100, 200])
}

@Test func respondingReplacesInputWhenApprovingFoodLog() throws {
    let parts = [foodPart()]
    let proposal = try #require(CoachFoodLogProposal(part: parts[0]))
    var item = try #require(proposal.items.first)
    item.grams = 120
    let input = proposal.patchedInput(meal: .snacks, items: [item])
    let answered = CoachUIParts.responding(parts, approvalId: "af1", approved: true, replacingInput: input)
    #expect(answered[0]["state"]?.string == "approval-responded")
    #expect(answered[0]["input"]?["meal"]?.string == "SNACKS")
    #expect(answered[0]["input"]?["items"]?.array?.first?["grams"]?.number == 120)
}

@Test func reopeningFailedFoodLogRestoresApprovalRequested() {
    let failed = foodPart(state: "output-error", errorText: "Timeout")
    let reopened = CoachUIParts.reopening([failed], approvalId: "af1")
    #expect(reopened[0]["state"]?.string == "approval-requested")
    #expect(reopened[0]["approval"]?["id"]?.string == "af1")
    #expect(reopened[0]["errorText"] == nil)
    #expect(reopened[0]["output"] == nil)
}

@Test func markingFailedApprovalsTurnsRespondedIntoError() {
    let answered = CoachUIParts.responding([foodPart()], approvalId: "af1", approved: true)
    let marked = CoachUIParts.markingFailedApprovals(answered, message: "Coupure réseau")
    #expect(marked[0]["state"]?.string == "output-error")
    #expect(marked[0]["errorText"]?.string == "Coupure réseau")
}

@Test func coachSegmentPrefersFoodLogCardOverGenericProposal() throws {
    let message = CoachMessage(
        role: .assistant,
        text: "",
        parts: [foodPart()]
    )
    let segments = CoachSegment.segments(of: message)
    #expect(segments.count == 1)
    if case .foodLog(let proposal) = segments[0] {
        #expect(proposal.items.first?.name == "Frites")
    } else {
        Issue.record("expected foodLog segment")
    }
}

// MARK: - Store retry

/// Yields each scripted reply in order; a `nil` script throws.
private final class FoodLogCoachClient: CoachChatServing, @unchecked Sendable {
    private var scripts: [[JSONValue]?]
    private(set) var requestCount = 0

    init(_ scripts: [[JSONValue]?]) {
        self.scripts = scripts
    }

    func reply(to request: CoachChatRequest, token: String) -> AsyncThrowingStream<JSONValue, Error> {
        requestCount += 1
        let next = scripts.isEmpty ? [] as [JSONValue]? : scripts.removeFirst()
        return AsyncThrowingStream { continuation in
            guard let next else {
                continuation.finish(throwing: CoachChatError.refused(status: 500, message: "boom"))
                return
            }
            next.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private let foodLogStream: [JSONValue] = [
    chunk(#"{"type":"start"}"#),
    chunk(#"{"type":"start-step"}"#),
    chunk(#"{"type":"text-start","id":"0"}"#),
    chunk(#"{"type":"text-delta","id":"0","delta":"J'ajoute les frites."}"#),
    chunk(#"{"type":"text-end","id":"0"}"#),
    chunk(#"{"type":"tool-input-available","toolCallId":"f1","toolName":"logFoods","input":{"date":"2026-10-08","meal":"LUNCH","items":[{"name":"Frites","grams":200,"kcalPer100g":300,"proteinPer100g":4,"carbsPer100g":40,"fatPer100g":15}]}}"#),
    chunk(#"{"type":"tool-approval-request","approvalId":"af1","toolCallId":"f1"}"#),
    chunk(#"{"type":"finish-step"}"#),
    chunk(#"{"type":"finish","finishReason":"tool-calls"}"#),
]

private let foodLogApplied: [JSONValue] = [
    chunk(#"{"type":"start-step"}"#),
    chunk(#"{"type":"tool-output-available","toolCallId":"f1","output":{"ok":true}}"#),
    chunk(#"{"type":"text-start","id":"1"}"#),
    chunk(#"{"type":"text-delta","id":"1","delta":"C'est noté."}"#),
    chunk(#"{"type":"text-end","id":"1"}"#),
]

@MainActor
@Test func foodLogRetryAfterStreamFailureSendsOnceMore() async throws {
    let client = FoodLogCoachClient([foodLogStream, nil, foodLogApplied])
    let coach = CoachStore(client: client, tokenProvider: { "t" })
    coach.draft = "Ajoute les frites"

    await coach.send()
    #expect(coach.hasPendingApproval)
    #expect(client.requestCount == 1)

    await coach.respond(to: "af1", approved: true)
    #expect(client.requestCount == 2)
    let afterFail = try #require(foodProposal(in: coach.messages[1]))
    if case .failed = afterFail.status {
        // expected
    } else {
        Issue.record("expected failed food-log after stream error, got \(String(describing: afterFail.status))")
    }

    await coach.retry(approvalId: "af1")
    #expect(client.requestCount == 3)
    let afterRetry = try #require(foodProposal(in: coach.messages[1]))
    if case .applied = afterRetry.status {
        // expected
    } else {
        Issue.record("expected applied after retry, got \(String(describing: afterRetry.status))")
    }
    #expect(coach.messages[1].text.contains("C'est noté."))
}

@MainActor
@Test func foodLogRespondIsDedupedWithoutRetry() async throws {
    let client = FoodLogCoachClient([
        foodLogStream,
        [
            chunk(#"{"type":"start-step"}"#),
            chunk(#"{"type":"tool-output-available","toolCallId":"f1","output":{"ok":false,"error":"Déjà loggé"}}"#),
        ],
        foodLogApplied,
    ])
    let coach = CoachStore(client: client, tokenProvider: { "t" })
    coach.draft = "Ajoute"

    await coach.send()
    await coach.respond(to: "af1", approved: true)
    #expect(client.requestCount == 2)

    // Same fingerprint without clearing — no second send.
    await coach.respond(to: "af1", approved: true)
    #expect(client.requestCount == 2)

    // Explicit retry reopens and sends again.
    await coach.retry(approvalId: "af1")
    #expect(client.requestCount == 3)
    let afterRetry = try #require(foodProposal(in: coach.messages[1]))
    if case .applied = afterRetry.status {
        // expected
    } else {
        Issue.record("expected applied after retry, got \(String(describing: afterRetry.status))")
    }
}

import Foundation
import Testing
@testable import Sharpit

private func foodPart(
    state: String = "approval-requested",
    meal: String = "LUNCH",
    grams: Double = 200
) -> JSONValue {
    chunk("""
    {"type":"tool-logFoods","toolCallId":"f1","state":"\(state)","approval":{"id":"af1"},"input":{"date":"2026-10-08","meal":"\(meal)","items":[{"name":"Frites","grams":\(grams),"kcalPer100g":300,"proteinPer100g":4,"carbsPer100g":40,"fatPer100g":15}]}}
    """)
}

@Test func coachFoodLogProposalParsesMealAndItems() throws {
    let proposal = try #require(CoachFoodLogProposal(part: foodPart()))
    #expect(proposal.meal == .lunch)
    #expect(proposal.items.count == 1)
    #expect(proposal.items[0].name == "Frites")
    #expect(proposal.items[0].grams == 200)
    if case .awaiting(let id) = proposal.status {
        #expect(id == "af1")
    } else {
        Issue.record("expected awaiting")
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

@Test func respondingReplacesInputWhenApprovingFoodLog() {
    let parts = [foodPart()]
    var item = CoachFoodLogProposal(part: parts[0])!.items[0]
    item.grams = 120
    let input = CoachFoodLogProposal(part: parts[0])!.patchedInput(meal: .snacks, items: [item])
    let answered = CoachUIParts.responding(parts, approvalId: "af1", approved: true, replacingInput: input)
    #expect(answered[0]["state"]?.string == "approval-responded")
    #expect(answered[0]["input"]?["meal"]?.string == "SNACKS")
    #expect(answered[0]["input"]?["items"]?.array?.first?["grams"]?.number == 120)
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

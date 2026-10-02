import Foundation
import Testing
@testable import Sharpit

private let proposal = V1TodayMorningProposal(
    decisionId: "d1",
    sessionId: "s1",
    direction: .down,
    changeSummary: "Seuil 40 min → Endurance 35 min",
    why: "Nuit courte et VFC sous ta plage",
    from: .init(intensityLabel: "Seuil", durationMin: 40, description: "3×10 min au seuil"),
    to: .init(intensityLabel: "Endurance", durationMin: 35, description: nil)
)

/// Serves the fixture day, with the proposal until the athlete answered it.
@MainActor
private final class ProposalDay: TodayServing, MorningProposalServing {
    private var pending = true
    private(set) var answers: [(decisionId: String, accept: Bool)] = []
    let refusal: SharpitAPIError?

    init(refusal: SharpitAPIError? = nil) { self.refusal = refusal }

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        var day = try await FixtureTodayClient().today(trainingDayId: trainingDayId, token: token)
        day.morningProposal = pending ? proposal : nil
        return day
    }

    func respondToMorningProposal(decisionId: String, accept: Bool, token _: String) async throws {
        if let refusal { throw refusal }
        answers.append((decisionId, accept))
        pending = false
    }

    func answerCount() -> Int { answers.count }
    func lastAnswer() -> (decisionId: String, accept: Bool)? { answers.last }
}

@MainActor
private func loadedProposal(_ store: TodayStore) -> V1TodayMorningProposal? {
    guard case .loaded(let fold) = store.phase else { return nil }
    return fold.morningProposal
}

@Test func theProposalDecodesFromTheTodayContract() throws {
    let json = """
    { "decisionId": "d1", "sessionId": "s1", "direction": "DOWN",
      "changeSummary": "Seuil → Endurance", "why": "Nuit courte",
      "from": { "intensityLabel": "Seuil", "durationMin": 40, "description": null },
      "to": { "intensityLabel": "Endurance", "durationMin": 35, "description": "Footing" } }
    """
    let decoded = try JSONDecoder().decode(V1TodayMorningProposal.self, from: Data(json.utf8))
    #expect(decoded.direction == .down)
    #expect(decoded.to.durationMin == 35)
}

@MainActor
@Test func acceptingTheProposalSendsItAndReadsTheDayAgain() async {
    let day = ProposalDay()
    let store = TodayStore(client: day, proposals: day, tokenProvider: { "t" })
    await store.load(resetToLoading: true)
    #expect(loadedProposal(store) == proposal)

    let changed = await store.respondToMorningProposal(accept: true)

    #expect(changed)
    #expect(day.lastAnswer()?.decisionId == "d1")
    #expect(day.lastAnswer()?.accept == true)
    #expect(loadedProposal(store) == nil)
}

@MainActor
@Test func keepingThePlanChangesNothing() async {
    let day = ProposalDay()
    let store = TodayStore(client: day, proposals: day, tokenProvider: { "t" })
    await store.load(resetToLoading: true)

    let changed = await store.respondToMorningProposal(accept: false)

    #expect(!changed)
    #expect(day.lastAnswer()?.accept == false)
    #expect(loadedProposal(store) == nil)
}

@MainActor
@Test func aRefusedAnswerPutsTheProposalBackAndSaysWhy() async {
    let day = ProposalDay(refusal: .message("Cette proposition n’est plus en attente"))
    let store = TodayStore(client: day, proposals: day, tokenProvider: { "t" })
    await store.load(resetToLoading: true)

    let changed = await store.respondToMorningProposal(accept: true)

    #expect(!changed)
    #expect(loadedProposal(store) == proposal)
    #expect(SharpitWriteFailures.shared.latest?.message == "Cette proposition n’est plus en attente")
}

@Test func eachSideReadsAsIntensityAndDuration() {
    #expect(MorningProposalReadout.headline(proposal.from) == "Seuil · 40 min")
    #expect(MorningProposalReadout.headline(.init(intensityLabel: nil, durationMin: nil, description: nil)) == "Séance")
}

@Test func aProposalReadFromTheNightAloneSaysTheCheckInIsToDo() throws {
    let json = """
    { "checkInDone": false, "decisionId": "d1", "sessionId": "s1", "direction": "DOWN",
      "changeSummary": "Endurance → Récupération", "why": "RECOVER",
      "from": { "intensityLabel": "Endurance", "durationMin": 60, "description": null },
      "to": { "intensityLabel": "Récupération", "durationMin": 45, "description": null } }
    """
    let decoded = try JSONDecoder().decode(V1TodayMorningProposal.self, from: Data(json.utf8))
    #expect(decoded.checkInDone == false)
    #expect(proposal.checkInDone == nil)
}

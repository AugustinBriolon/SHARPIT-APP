import Foundation
import Testing
@testable import Sharpit

private func quota(
    isPro: Bool = false,
    remaining: Int,
    usedRatio: Double,
    retryAfter: Int? = nil
) -> V1CoachQuota {
    V1CoachQuota(
        isPro: isPro,
        dailyQuestions: isPro ? 62 : 6,
        remainingQuestions: remaining,
        usedRatio: usedRatio,
        retryAfterSeconds: retryAfter
    )
}

@Test func theGaugeStaysHiddenWhileMoreThanHalfIsLeft() {
    #expect(CoachQuotaReadout.line(quota(remaining: 4, usedRatio: 0.3)) == nil)
    #expect(!CoachQuotaReadout.offersPro(quota(remaining: 4, usedRatio: 0.3)))
}

@Test func pastHalfTheGaugeCountsTheQuestionsLeft() {
    #expect(CoachQuotaReadout.line(quota(remaining: 2, usedRatio: 0.6)) == "Environ 2 échanges restants sur 24 h")
    #expect(CoachQuotaReadout.line(quota(remaining: 1, usedRatio: 0.9)) == "Environ 1 échange restant sur 24 h")
    #expect(CoachQuotaReadout.line(quota(remaining: 0, usedRatio: 0.95)) == "Moins d'un échange restant sur 24 h")
}

@Test func aSpentBudgetSaysWhenItComesBack() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(
        CoachQuotaReadout.line(quota(remaining: 0, usedRatio: 1, retryAfter: 600), now: now)
            == "Plus d'échange pour l'instant · de nouveau dans 10 min"
    )
    #expect(CoachQuotaReadout.eta(30, now: now) == "dans 1 min")
    #expect(CoachQuotaReadout.eta(7200, now: now).hasPrefix("à "))
}

@Test func onlyFreeAthletesAreOfferedPro() {
    #expect(CoachQuotaReadout.offersPro(quota(remaining: 1, usedRatio: 0.9)))
    #expect(!CoachQuotaReadout.offersPro(quota(isPro: true, remaining: 10, usedRatio: 0.9)))
}

@Test func theQuotaDecodesAsTheWebSendsIt() throws {
    let json = #"{"isPro":true,"dailyQuestions":62,"remainingQuestions":50,"usedRatio":0.2,"retryAfterSeconds":null}"#
    let decoded = try JSONDecoder().decode(V1CoachQuota.self, from: Data(json.utf8))
    #expect(decoded == quota(isPro: true, remaining: 50, usedRatio: 0.2))
}

private struct StubQuota: CoachQuotaServing {
    let answer: V1CoachQuota
    func quota(token: String) async throws -> V1CoachQuota { answer }
}

@MainActor
@Test func theQuotaIsReadAgainAfterEachAnswer() async {
    let coach = CoachStore(
        client: StubCoachClient(deltas: ["Oui"]),
        quota: StubQuota(answer: quota(remaining: 3, usedRatio: 0.5)),
        tokenProvider: { "token" }
    )
    coach.draft = "Je pousse demain ?"

    await coach.send()

    #expect(coach.quota?.remainingQuestions == 3)
}

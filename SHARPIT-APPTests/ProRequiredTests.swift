import Foundation
import Testing
@testable import Sharpit

/// Coaching is SharpIt Pro (SHARPIT ADR-097): the server's refusal reads as `.proRequired`, which a
/// screen turns into `SharpitProTeaser`, never into « session expirée ».
@Test func theServersProRefusalIsRead() {
    #expect(SharpitAPIError.isProRequired(Data(#"{"error":"pro_required"}"#.utf8)))
    #expect(!SharpitAPIError.isProRequired(Data(#"{"error":"Consentement requis","code":"ai_processing_consent_required"}"#.utf8)))
    #expect(!SharpitAPIError.isProRequired(Data("not json".utf8)))
}

@Test func aLockedAnalysisAndAProRefusalAreProNotASignOut() {
    #expect(throws: SharpitAPIError.proRequired) {
        try ActivityClient.mapReadStatus(402, body: Data(#"{"error":"locked"}"#.utf8))
    }
    #expect(throws: SharpitAPIError.proRequired) {
        try ActivityClient.mapReadStatus(403, body: Data(#"{"error":"pro_required"}"#.utf8))
    }
    #expect(throws: SharpitAPIError.unauthorized) {
        try ActivityClient.mapReadStatus(403, body: Data(#"{"error":"Interdit"}"#.utf8))
    }
}

private struct FreeQuota: CoachQuotaServing {
    var isPro = false
    func quota(token _: String) async throws -> V1CoachQuota {
        V1CoachQuota(isPro: isPro, dailyQuestions: isPro ? 62 : 0, remainingQuestions: isPro ? 62 : 0, usedRatio: isPro ? 0 : 1, retryAfterSeconds: nil)
    }
}

@MainActor
@Test func aFreeAthleteSeesTheTeaserWhereTheComposerWas() async {
    let coach = CoachStore(client: StubCoachClient(deltas: ["Oui"]), quota: FreeQuota(), tokenProvider: { "token" })
    coach.draft = "Je pousse demain ?"

    await coach.refreshQuota()

    #expect(coach.needsPro)
    #expect(!coach.canSend)
}

@MainActor
@Test func aProAthleteKeepsTheComposer() async {
    let coach = CoachStore(client: StubCoachClient(deltas: ["Oui"]), quota: FreeQuota(isPro: true), tokenProvider: { "token" })
    coach.draft = "Je pousse demain ?"

    await coach.refreshQuota()

    #expect(!coach.needsPro)
    #expect(coach.canSend)
}

@MainActor
@Test func aProRefusalOnSendOffersProRatherThanAnError() async {
    let coach = CoachStore(client: StubCoachClient(failure: SharpitAPIError.proRequired), tokenProvider: { "token" })
    coach.draft = "Alors ?"

    await coach.send()

    #expect(coach.needsPro)
    #expect(coach.failure == nil)
    #expect(coach.messages.first?.role == .user)
}

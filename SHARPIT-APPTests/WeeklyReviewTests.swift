import Foundation
import Testing
@testable import Sharpit

private actor StubReviewClient: WeeklyReviewServing {
    var latest: V1WeeklyReview?
    var error: Error?
    private(set) var writes = 0

    init(latest: V1WeeklyReview? = nil, error: Error? = nil) {
        self.latest = latest
        self.error = error
    }

    func latestReview(token _: String) async throws -> V1WeeklyReview? {
        if let error { throw error }
        return latest
    }

    func generateReview(token _: String) async throws -> V1WeeklyReview {
        writes += 1
        if let error { throw error }
        return V1WeeklyReview(id: "r2", weekStart: "2026-09-28", content: "## Bilan")
    }
}

@Test func theReviewEnvelopeDecodes() throws {
    let json = Data(#"""
    { "review": {
        "id": "r1", "athleteId": "a", "weekStart": "2026-09-21T00:00:00.000Z",
        "content": "## Bilan\nBonne semaine.", "generatedAt": "2026-09-27T20:12:44.120Z",
        "stats": { "sessionsDone": 4, "sessionsPlanned": 5, "totalLoad": 312.4, "prevTotalLoad": 280,
                   "totalDurationMin": 290, "sleep": { "avgDurationMin": 431, "avgScore": null },
                   "recovery": { "avgReadiness": 68, "avgHrv": 55 }, "byType": [] }
    } }
    """#.utf8)

    struct Envelope: Decodable { let review: V1WeeklyReview? }
    let review = try #require(try JSONDecoder().decode(Envelope.self, from: json).review)

    #expect(review.weekStart == "2026-09-21")
    #expect(review.stats?.sessionsDone == 4)
    #expect(review.stats?.sleep?.avgDurationMin == 431)
    #expect(review.generatedAt != nil)
}

@MainActor
@Test func noReviewYetOffersToWriteOne() async {
    let store = WeeklyReviewStore(client: StubReviewClient(), tokenProvider: { "t" })

    await store.load()
    #expect(store.phase == .empty)

    await store.write()
    #expect(store.phase == .loaded(V1WeeklyReview(id: "r2", weekStart: "2026-09-28", content: "## Bilan")))
}

@MainActor
@Test func belowProTheReviewIsATeaser() async {
    let store = WeeklyReviewStore(client: StubReviewClient(error: WeeklyReviewError.proRequired), tokenProvider: { "t" })

    await store.load()

    #expect(store.phase == .proRequired)
}

@MainActor
@Test func aRateLimitedWriteKeepsTheReviewOnScreen() async {
    let existing = V1WeeklyReview(id: "r1", weekStart: "2026-09-21", content: "## Bilan")
    let client = StubReviewClient(latest: existing)
    let store = WeeklyReviewStore(client: client, tokenProvider: { "t" })
    await store.load()

    await client.fail(with: SharpitAPIError.rateLimited)
    await store.write()

    #expect(store.phase == .loaded(existing))
    #expect(store.writeError == "Tu as demandé plusieurs bilans d'affilée. Réessaie dans une heure.")
}

private extension StubReviewClient {
    func fail(with error: Error) { self.error = error }
}

@Test func onlyASubscriptionThatBillsAgainWarnsBeforeDeletion() {
    #expect(ProStore.renews(V1ProSubscription(status: "active", source: "apple", willRenew: true)))
    #expect(ProStore.renews(V1ProSubscription(status: "billing_retry", source: "apple", willRenew: true)))
    #expect(!ProStore.renews(V1ProSubscription(status: "active", source: "apple", willRenew: false)))
    #expect(!ProStore.renews(V1ProSubscription(status: "expired", source: "apple", willRenew: true)))
    #expect(!ProStore.renews(nil))
}

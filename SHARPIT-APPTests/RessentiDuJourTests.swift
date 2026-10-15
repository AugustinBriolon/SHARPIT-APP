import Foundation
import Testing
@testable import Sharpit

@Test func wellnessStatusDecodesCodesOnly() throws {
    let data = try #require(#"{"localDate":"2026-10-15","completed":false}"#.data(using: .utf8))
    let status = try JSONDecoder().decode(V1WellnessCheckinStatus.self, from: data)
    #expect(status.localDate == "2026-10-15")
    #expect(!status.completed)
}

@Test func wellnessSubmitResponseDecodesAdditiveVerdict() throws {
    let json = """
    {
      "trainingDayId": "2026-10-15",
      "completed": true,
      "alreadyCompleted": false,
      "verdict": {
        "overallVerdict": "TRAIN_EASY",
        "limitingFactorSystem": "RECOVERY",
        "limitingFactorCode": "reasoning.limitingFactor.recovery.deficit",
        "limiter": "subjective"
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let response = try JSONDecoder().decode(V1WellnessSubmitResponse.self, from: data)
    #expect(response.completed == true)
    #expect(response.verdict?.overallVerdict == .trainEasy)
    #expect(response.verdict?.limiter == "subjective")
}

@Test func localStoreDismissesPerAthleteAndDay() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-local-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = WellnessCheckInLocalStore(fileURL: url)

    #expect(!store.isDismissed(athleteId: "a1", localDate: "2026-10-15"))
    store.dismiss(athleteId: "a1", localDate: "2026-10-15")
    #expect(store.isDismissed(athleteId: "a1", localDate: "2026-10-15"))
    #expect(!store.isDismissed(athleteId: "a1", localDate: "2026-10-16"))
    #expect(!store.isDismissed(athleteId: "a2", localDate: "2026-10-15"))
}

@Test func localStoreDraftClearsAfterErase() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-draft-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = WellnessCheckInLocalStore(fileURL: url)

    store.saveDraft(
        WellnessCheckInLocalStore.Draft(feeling: 4, energy: 3, soreness: nil, stress: nil, notes: "ok", detailsExpanded: true),
        athleteId: "a1",
        localDate: "2026-10-15"
    )
    #expect(store.draft(athleteId: "a1", localDate: "2026-10-15")?.feeling == 4)
    store.clearDraft(athleteId: "a1")
    #expect(store.draft(athleteId: "a1", localDate: "2026-10-15") == nil)
    store.erase()
    #expect(store.load() == nil)
}

@MainActor
@Test func ressentiSubmitMapsFeelingToMoodAndReturnsVerdict() async throws {
    let client = StubWellnessForRessenti(
        verdict: V1WellnessVerdictSummary(
            overallVerdict: .caution,
            limitingFactorSystem: "RECOVERY",
            limitingFactorCode: nil,
            limiter: "subjective"
        )
    )
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-ressenti-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let local = WellnessCheckInLocalStore(fileURL: url)

    let store = RessentiDuJourStore(
        client: client,
        tokenProvider: { "token" },
        athleteId: "a1",
        trainingDayId: "2026-10-15",
        local: local
    )
    #expect(!store.canSubmit)
    store.feeling = .good
    #expect(store.canSubmit)

    let entry = try #require(store.makeEntry())
    #expect(entry.mood == 4)
    #expect(entry.energyLevel == 3)

    let verdict = await store.submit()
    #expect(verdict?.overallVerdict == .caution)
    #expect(store.didSave)
    #expect(local.draft(athleteId: "a1", localDate: "2026-10-15") == nil)
    let sent = await client.recorded()
    #expect(sent.count == 1)
    #expect(sent.first?.mood == 4)
}

/// Local stub — kept here so Ressenti tests do not depend on WellnessTests internals.
private actor StubWellnessForRessenti: WellnessServing {
    private let verdict: V1WellnessVerdictSummary?
    private(set) var submitted: [V1WellnessEntry] = []

    init(verdict: V1WellnessVerdictSummary?) {
        self.verdict = verdict
    }

    func wellnessCheckin(trainingDayId _: String, token _: String) async throws -> V1WellnessCheckin {
        V1WellnessCheckin(completed: false, entry: nil)
    }

    func wellnessCheckinStatus(token _: String) async throws -> V1WellnessCheckinStatus {
        V1WellnessCheckinStatus(localDate: "2026-10-15", completed: false)
    }

    func submitWellnessCheckin(
        _ entry: V1WellnessEntry,
        trainingDayId: String,
        token _: String
    ) async throws -> V1WellnessSubmitResponse {
        submitted.append(entry)
        return V1WellnessSubmitResponse(
            trainingDayId: trainingDayId,
            completed: true,
            alreadyCompleted: false,
            verdict: verdict
        )
    }

    func recorded() -> [V1WellnessEntry] { submitted }
}

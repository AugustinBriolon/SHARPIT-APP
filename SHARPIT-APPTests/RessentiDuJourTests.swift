import CoreGraphics
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

    #expect(!store.isDismissed(athleteId: "lea", localDate: "2026-10-15"))
    store.dismiss(athleteId: "lea", localDate: "2026-10-15")
    #expect(store.isDismissed(athleteId: "lea", localDate: "2026-10-15"))
    #expect(!store.isDismissed(athleteId: "lea", localDate: "2026-10-16"))
    #expect(!store.isDismissed(athleteId: "a2", localDate: "2026-10-15"))
}

@Test func localStoreDraftClearsAfterErase() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-draft-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = WellnessCheckInLocalStore(fileURL: url)

    store.saveDraft(
        WellnessCheckInLocalStore.Draft(feeling: 4, energy: 3, soreness: nil, stress: nil, notes: "ok", detailsExpanded: true),
        athleteId: "lea",
        localDate: "2026-10-15"
    )
    #expect(store.draft(athleteId: "lea", localDate: "2026-10-15")?.feeling == 4)
    store.clearDraft(athleteId: "lea")
    #expect(store.draft(athleteId: "lea", localDate: "2026-10-15") == nil)
    store.erase()
    #expect(store.load() == nil)
}

/// Drafts live in the protected Application Support file from #17 — never UserDefaults.
@Test func ressentiDraftStorageIsProtectedFileNotUserDefaults() throws {
    let sharedURL = WellnessCheckInLocalStore.shared.fileURL
    #expect(sharedURL.lastPathComponent == "WellnessCheckInLocal.json")
    #expect(sharedURL.path.contains("Application Support") || sharedURL.path.contains("Application%20Support"))

    let defaults = UserDefaults.standard
    let before = defaults.dictionaryRepresentation().keys.filter { $0.localizedCaseInsensitiveContains("wellness") || $0.localizedCaseInsensitiveContains("ressenti") }

    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-storage-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let local = WellnessCheckInLocalStore(fileURL: url)
    // Demo athlete Léa — no real health values.
    local.saveDraft(
        WellnessCheckInLocalStore.Draft(
            feeling: 4,
            energy: 3,
            soreness: 2,
            stress: 2,
            notes: "Léa — matin démo",
            detailsExpanded: false
        ),
        athleteId: "lea",
        localDate: "2026-10-15"
    )
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(local.draft(athleteId: "lea", localDate: "2026-10-15")?.notes == "Léa — matin démo")

    let after = defaults.dictionaryRepresentation().keys.filter { $0.localizedCaseInsensitiveContains("wellness") || $0.localizedCaseInsensitiveContains("ressenti") }
    #expect(Set(after) == Set(before))
}

@MainActor
@Test func ressentiOptimisticSuccessClearsDraftAfterConfirm() async throws {
    let client = StubWellnessForRessenti(
        verdict: V1WellnessVerdictSummary(
            overallVerdict: .caution,
            limitingFactorSystem: "RECOVERY",
            limitingFactorCode: nil,
            limiter: "subjective"
        )
    )
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-ressenti-ok-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let local = WellnessCheckInLocalStore(fileURL: url)

    let store = RessentiDuJourStore(
        client: client,
        tokenProvider: { "token" },
        athleteId: "lea",
        trainingDayId: "2026-10-15",
        local: local
    )
    store.feeling = .good
    store.notes = "Léa — prêt"

    var confirmedVerdict: V1WellnessVerdictSummary?
    var failed = false
    #expect(store.submitOptimistic(
        onConfirmed: { confirmedVerdict = $0 },
        onFailed: { failed = true }
    ))
    // Optimistic: UI may close immediately with didSave already true.
    #expect(store.didSave)
    #expect(local.draft(athleteId: "lea", localDate: "2026-10-15")?.feeling == 4)

    await store.settle()
    #expect(!failed)
    #expect(confirmedVerdict?.overallVerdict == .caution)
    #expect(local.draft(athleteId: "lea", localDate: "2026-10-15") == nil)
    let sent = await client.recorded()
    #expect(sent.count == 1)
    #expect(sent.first?.mood == 4)
}

@MainActor
@Test func ressentiOptimisticFailureKeepsDraftAndReportsMessage() async throws {
    let client = StubWellnessForRessenti(verdict: nil, shouldFail: true)
    let url = FileManager.default.temporaryDirectory
        .appending(path: "wellness-ressenti-fail-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let local = WellnessCheckInLocalStore(fileURL: url)

    let store = RessentiDuJourStore(
        client: client,
        tokenProvider: { "token" },
        athleteId: "lea",
        trainingDayId: "2026-10-15",
        local: local
    )
    store.feeling = .okay
    store.energy = .four
    store.notes = "Léa — note à garder"

    var confirmed = false
    var failed = false
    #expect(store.submitOptimistic(
        onConfirmed: { _ in confirmed = true },
        onFailed: { failed = true }
    ))
    #expect(store.didSave)

    await store.settle()
    #expect(failed)
    #expect(!confirmed)
    // Input never lost silently — still in the protected file.
    let draft = try #require(local.draft(athleteId: "lea", localDate: "2026-10-15"))
    #expect(draft.feeling == SessionFeeling.okay.rawValue)
    #expect(draft.energy == WellnessScore.four.rawValue)
    #expect(draft.notes == "Léa — note à garder")
    #expect(RessentiDuJourStore.saveFailureMessage == "Pas enregistré, réessaie")

    // Reopen path: a new store restores the draft and can show the failure copy.
    let reopened = RessentiDuJourStore(
        client: client,
        tokenProvider: { "token" },
        athleteId: "lea",
        trainingDayId: "2026-10-15",
        local: local,
        initialFailureMessage: RessentiDuJourStore.saveFailureMessage
    )
    #expect(reopened.feeling == .okay)
    #expect(reopened.notes == "Léa — note à garder")
    #expect(reopened.phase == .failed(RessentiDuJourStore.saveFailureMessage))
}

@MainActor
@Test func morningFeelBadgeClearsOptimisticallyAndRestoresOnFailure() {
    var count = 3
    let badge = MorningFeelBadge(
        readCount: { count },
        writeCount: { count = $0 }
    )
    #expect(!badge.isAwaitingConfirmation)
    badge.clearOptimistically()
    #expect(count == 0)
    #expect(badge.isAwaitingConfirmation)

    badge.restore()
    #expect(count == 3)
    #expect(!badge.isAwaitingConfirmation)

    count = 2
    badge.clearOptimistically()
    #expect(count == 0)
    badge.confirmCleared()
    #expect(count == 0)
    #expect(!badge.isAwaitingConfirmation)
}

@Test func bannerDismissCommitsPastFortyPercentOrFastFlick() {
    let height: CGFloat = 100
    #expect(SharpitBannerDismiss.shouldDismiss(height: height, translationY: -40, velocityY: 0))
    #expect(!SharpitBannerDismiss.shouldDismiss(height: height, translationY: -20, velocityY: 0))
    #expect(SharpitBannerDismiss.shouldDismiss(height: height, translationY: -10, velocityY: -1000))
    // Downward rubber band stays positive and never dismisses.
    #expect(SharpitBannerDismiss.offset(translationY: 40, height: height) > 0)
    #expect(SharpitBannerDismiss.offset(translationY: 40, height: height) < 40)
    #expect(!SharpitBannerDismiss.shouldDismiss(height: height, translationY: 40, velocityY: 200))
    // Up follows the finger 1:1.
    #expect(SharpitBannerDismiss.offset(translationY: -30, height: height) == -30)
}

/// Local stub — kept here so Ressenti tests do not depend on WellnessTests internals.
/// Demo athlete data only (Léa); never real user health values.
private actor StubWellnessForRessenti: WellnessServing {
    private let verdict: V1WellnessVerdictSummary?
    private let shouldFail: Bool
    private(set) var submitted: [V1WellnessEntry] = []

    init(verdict: V1WellnessVerdictSummary?, shouldFail: Bool = false) {
        self.verdict = verdict
        self.shouldFail = shouldFail
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
        if shouldFail { throw SharpitAPIError.server }
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

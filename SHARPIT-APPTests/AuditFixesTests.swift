import Foundation
import SwiftData
import Testing
@testable import Sharpit

private final class RecordingHealthWriter: HealthWriting, @unchecked Sendable {
    private(set) var bodyMassWrites: [(kg: Double, at: Date)] = []

    func saveNutritionDay(day: String, kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) async throws {}
    func saveBodyMass(kg: Double, at date: Date) async throws {
        bodyMassWrites.append((kg, date))
    }
}

private struct StubBodyOverview: BodyServing {
    func bodyOverview(token: String) async throws -> V1BodyOverview {
        V1BodyOverview(metrics: [])
    }

    func bodySeries(metric: CorpsMetricKey, range: CorpsRange, token: String) async throws -> V1BodySeries {
        throw SharpitAPIError.server
    }
}

private struct StubCorpsProfile: AthleteProfileServing {
    func athleteProfile(token: String) async throws -> V1AthleteProfile { V1AthleteProfile() }
    func patchAthleteProfile(_ patch: AthleteProfilePatch, token: String) async throws -> V1AthleteProfile {
        V1AthleteProfile()
    }
    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] { [] }
}

private struct StubCorpsBody: BodyCompositionServing {
    let measurements: [V1BodyMeasurement]
    func bodyComposition(days: Int, token: String) async throws -> [V1BodyMeasurement] { measurements }
}

private struct StubCorpsRecovery: RecoveryServing {
    func recovery(trainingDayId: String, token: String) async throws -> V1RecoveryResponse {
        throw SharpitAPIError.server
    }
}

private actor StubProClient: ProServing {
    /// Stored account UUID — not named `token` to avoid shadowing the Bearer `token` param.
    var accountToken: UUID?
    var tokenError: Error?
    private(set) var tokenFetches = 0

    func setAccountToken(_ value: UUID?) { accountToken = value }
    func setTokenError(_ value: Error?) { tokenError = value }

    func pro(token: String) async throws -> V1Pro { V1Pro(tier: "FREE") }

    func appAccountToken(token: String) async throws -> UUID {
        tokenFetches += 1
        if let tokenError { throw tokenError }
        guard let accountToken else { throw SharpitAPIError.server }
        return accountToken
    }

    func verify(signedTransaction: String, signedRenewalInfo: String?, token: String) async throws -> V1Pro {
        V1Pro(tier: "PRO")
    }
}

private final class TokenCapturingToday: TodayServing, MorningProposalServing, @unchecked Sendable {
    private(set) var todayTokens: [String] = []
    private(set) var proposalTokens: [String] = []

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        todayTokens.append(token)
        return try await FixtureTodayClient().today(trainingDayId: trainingDayId, token: token)
    }

    func respondToMorningProposal(decisionId: String, accept: Bool, token: String) async throws {
        proposalTokens.append(token)
    }
}

/// Regression coverage for the must-fix from the iOS security/quality audit.
@Suite struct AuditFixesTests {
    // MARK: Body-mass idempotency

    @Test func sameMeasuredAtAndKgIsAlreadyMirrored() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BodyMassMirror.alreadyMirrored(kg: 72.4, at: at, existingOwn: [(72.4, at)]))
        #expect(BodyMassMirror.alreadyMirrored(kg: 72.41, at: at, existingOwn: [(72.4, at)]))
        #expect(!BodyMassMirror.alreadyMirrored(kg: 73.0, at: at, existingOwn: [(72.4, at)]))
        #expect(!BodyMassMirror.alreadyMirrored(
            kg: 72.4,
            at: at.addingTimeInterval(10),
            existingOwn: [(72.4, at)]
        ))
    }

    @Test func ownSamplesAtTheSameTimestampAreReplaced() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let ids = BodyMassMirror.ownSamplesToReplace(
            at: at,
            existingOwn: [
                (id: "a", kg: 72.0, at: at),
                (id: "b", kg: 71.0, at: at.addingTimeInterval(60)),
            ]
        )
        #expect(ids == ["a"])
    }

    @MainActor
    @Test func corpsLoadDoesNotMirrorTheSameWeighInTwice() async {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = RecordingHealthWriter()
        let store = CorpsStore(
            overviewClient: StubBodyOverview(),
            profileClient: StubCorpsProfile(),
            bodyClient: StubCorpsBody(measurements: [
                V1BodyMeasurement(id: "w1", measuredAt: at, source: "WITHINGS", weightKg: 72.4),
            ]),
            recoveryClient: StubCorpsRecovery(),
            tokenProvider: { "t" },
            healthWriter: writer
        )

        await store.load()
        await store.load()

        #expect(writer.bodyMassWrites.count == 1)
        #expect(writer.bodyMassWrites.first?.kg == 72.4)
    }

    // MARK: Pro token gating

    @MainActor
    @Test func proCannotPurchaseUntilAppAccountTokenIsKnown() async {
        let client = StubProClient()
        await client.setAccountToken(nil)
        let store = ProStore(client: client, tokenProvider: { "t" })
        #expect(!store.canPurchase)

        await client.setAccountToken(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        await store.ensureAppAccountToken()
        #expect(store.canPurchase)
        #expect(store.appAccountToken != nil)
    }

    @MainActor
    @Test func proRetriesAccountTokenAfterAMiss() async {
        let client = StubProClient()
        await client.setTokenError(SharpitAPIError.transport)
        let store = ProStore(client: client, tokenProvider: { "t" })
        await store.ensureAppAccountToken()
        #expect(!store.canPurchase)

        await client.setTokenError(nil)
        await client.setAccountToken(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        await store.ensureAppAccountToken()
        #expect(store.canPurchase)
    }

    // MARK: 401 / 403 mapping

    @Test func activityClientMaps401And403AsUnauthorized() {
        #expect(throws: SharpitAPIError.unauthorized) {
            try ActivityClient.mapReadStatus(401)
        }
        #expect(throws: SharpitAPIError.unauthorized) {
            try ActivityClient.mapReadStatus(403)
        }
        #expect(throws: ActivityClientError.self) {
            try ActivityClient.mapReadStatus(500, body: Data("boom".utf8))
        }
    }

    @Test func plannedSessionClientMaps403AsUnauthorized() {
        #expect(throws: SharpitAPIError.unauthorized) {
            try PlannedSessionClient.mapListStatus(401)
        }
        #expect(throws: SharpitAPIError.unauthorized) {
            try PlannedSessionClient.mapListStatus(403)
        }
        #expect(throws: SharpitAPIError.server) {
            try PlannedSessionClient.mapListStatus(500)
        }
    }

    @Test func sharpitHTTPStatusTreats401And403Alike() throws {
        #expect(throws: SharpitAPIError.unauthorized) {
            try SharpitHTTPStatus.throwIfUnauthorized(401)
        }
        #expect(throws: SharpitAPIError.unauthorized) {
            try SharpitHTTPStatus.throwIfUnauthorized(403)
        }
        // Non-auth statuses are left to the caller.
        try SharpitHTTPStatus.throwIfUnauthorized(200)
    }

    // MARK: Sign-out wipe (LocalAccountData.erase)

    @MainActor
    @Test func signOutWipeErasesSwiftDataAndDiskLikeAccountDelete() throws {
        let container = try SharpitPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let defaults = try #require(UserDefaults(suiteName: "SignOutWipe-\(UUID().uuidString)"))
        let disk = ActivityDiskCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))

        LocalAccountData.claim(userId: "user_a", context: context, defaults: defaults, disk: disk)
        context.insert(CachedResponse(key: "today", payloadJSON: Data("{}".utf8)))
        try context.save()
        disk.write(Data("{}".utf8), .detail, id: "act-1")

        // Same call sign-out and account delete share.
        LocalAccountData.erase(context: context, defaults: defaults, disk: disk)

        #expect(try context.fetchCount(FetchDescriptor<CachedResponse>()) == 0)
        #expect(disk.read(.detail, id: "act-1") == nil)
        #expect(defaults.string(forKey: LocalAccountData.ownerKey) == nil)
    }

    // MARK: TodayStore empty bearer

    @MainActor
    @Test func todayStoreWithoutTokenProviderStaysFixtureOnly() async {
        let client = TokenCapturingToday()
        let store = TodayStore(client: client, proposals: client, tokenProvider: nil)
        await store.load(resetToLoading: true)
        #expect(client.todayTokens == ["fixture"])
        #expect(!client.todayTokens.contains(""))
        #expect(await store.respondToMorningProposal(accept: true) == false)
        #expect(client.proposalTokens.isEmpty)
    }
}

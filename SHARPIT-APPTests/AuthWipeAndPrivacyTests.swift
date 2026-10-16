import Foundation
import SwiftData
import Testing
@testable import Sharpit

@Suite(.serialized)
struct AuthWipeAndPrivacyTests {
    @MainActor
    private func makeContext() throws -> (ModelContext, UserDefaults, ActivityDiskCache) {
        let container = try SharpitPersistence.makeContainer(inMemory: true)
        let suite = "AuthWipe-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let disk = ActivityDiskCache(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        return (ModelContext(container), defaults, disk)
    }

    @MainActor
    private func leaFold(dayId: String) -> TodayFold {
        TodayFold(
            trainingDayId: dayId,
            plate: InkPlateModel(
                statusLabel: "Léger",
                headline: "",
                actionLine: nil,
                limitingCause: nil,
                confidencePct: 80,
                confidenceLabel: "ok",
                packTier: nil,
                estimationGaps: [],
                posture: .steady,
                instruction: "Sortie facile",
                limiterSignals: [.sleepShort],
                showHeadline: false,
                stateCode: .trainEasy
            ),
            sessions: [],
            gauges: [],
            consistency: nil,
            weather: nil
        )
    }

    // MARK: 401 recovery

    @MainActor
    @Test func unauthorizedThenSuccessfulRefreshDoesNotPurge() async throws {
        let (context, defaults, disk) = try makeContext()
        AuthSession.shared.resetForTests()
        AuthSession.shared.bind(context: context, defaults: defaults, disk: disk)
        LocalAccountData.claim(userId: "user_lea", context: context, defaults: defaults, disk: disk)
        disk.write(Data("{}".utf8), .detail, id: "act-1")

        var refreshCalls = 0
        AuthSession.shared.refreshToken = {
            refreshCalls += 1
            return "fresh-token"
        }
        var signedOut = 0
        AuthSession.shared.performSignOut = { signedOut += 1 }

        let token = await AuthSession.shared.refreshTokenOnce()
        #expect(token == "fresh-token")
        #expect(refreshCalls == 1)
        #expect(signedOut == 0)
        #expect(defaults.string(forKey: LocalAccountData.ownerKey) == "user_lea")
        #expect(disk.read(.detail, id: "act-1") != nil)
        #expect(!AuthSession.shared.expiredNotice)

        AuthSession.shared.resetForTests()
    }

    @MainActor
    @Test func repeatedUnauthorizedPurgesAndSignsOutOnce() async throws {
        let (context, defaults, disk) = try makeContext()
        AuthSession.shared.resetForTests()
        AuthSession.shared.bind(context: context, defaults: defaults, disk: disk)
        LocalAccountData.claim(userId: "user_lea", context: context, defaults: defaults, disk: disk)
        disk.write(Data("{}".utf8), .detail, id: "act-1")
        GuidedHeartRatePreference.setEnabled(true)

        AuthSession.shared.refreshToken = { nil }
        var signedOut = 0
        AuthSession.shared.performSignOut = { signedOut += 1 }

        async let a: Void = AuthSession.shared.expireSession()
        async let b: Void = AuthSession.shared.expireSession()
        _ = await (a, b)
        // Client + store both call expire after a hard 401 — still one sign-out.
        await AuthSession.shared.expireSession()

        #expect(signedOut == 1)
        #expect(AuthSession.shared.expiredNotice)
        #expect(defaults.string(forKey: LocalAccountData.ownerKey) == nil)
        #expect(disk.read(.detail, id: "act-1") == nil)
        #expect(!GuidedHeartRatePreference.isEnabled)

        AuthSession.shared.resetForTests()
    }

    // MARK: Wipe contents

    @MainActor
    @Test func eraseClearsAllListedStores() throws {
        let (context, defaults, disk) = try makeContext()
        LocalAccountData.claim(userId: "user_lea", context: context, defaults: defaults, disk: disk)

        try TodaySnapshotRepository.save(leaFold(dayId: TrainingDayId.today()), context: context)
        context.insert(CachedResponse(key: "health", payloadJSON: Data("{}".utf8)))
        try context.save()
        disk.write(Data("{}".utf8), .stream, id: "w1")
        WellnessCheckInLocalStore.shared.saveDraft(
            .init(feeling: 3, energy: 3, soreness: nil, stress: nil, notes: nil, detailsExpanded: nil),
            athleteId: "user_lea",
            localDate: TrainingDayId.today()
        )
        GuidedHeartRatePreference.setEnabled(true)
        GuidedHeartRatePreference.lastPeripheralUUID = UUID()

        LocalAccountData.erase(context: context, defaults: defaults, disk: disk)

        #expect(try TodaySnapshotRepository.load(trainingDayId: TrainingDayId.today(), context: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<CachedResponse>()) == 0)
        #expect(disk.read(.stream, id: "w1") == nil)
        #expect(WellnessCheckInLocalStore.shared.load() == nil)
        #expect(!GuidedHeartRatePreference.isEnabled)
        #expect(GuidedHeartRatePreference.lastPeripheralUUID == nil)
        #expect(defaults.string(forKey: LocalAccountData.ownerKey) == nil)
    }

    @MainActor
    @Test func accountSwitchWipesPreviousAthlete() throws {
        let (context, defaults, disk) = try makeContext()
        LocalAccountData.claim(userId: "user_lea", context: context, defaults: defaults, disk: disk)
        disk.write(Data("lea".utf8), .detail, id: "act-lea")

        LocalAccountData.claim(userId: "user_other", context: context, defaults: defaults, disk: disk)

        #expect(disk.read(.detail, id: "act-lea") == nil)
        #expect(defaults.string(forKey: LocalAccountData.ownerKey) == "user_other")
    }

    // MARK: Snapshot day gate

    @MainActor
    @Test func yesterdaySnapshotIsNotShown() throws {
        let (context, _, _) = try makeContext()
        let yesterday = "2020-01-01"
        try TodaySnapshotRepository.save(leaFold(dayId: yesterday), context: context)
        #expect(try TodaySnapshotRepository.load(trainingDayId: yesterday, context: context) == nil)
        #expect(try TodaySnapshotRepository.load(trainingDayId: TrainingDayId.today(), context: context) == nil)
    }

    @MainActor
    @Test func todaysSnapshotIsShown() throws {
        let (context, _, _) = try makeContext()
        let today = TrainingDayId.today()
        try TodaySnapshotRepository.save(leaFold(dayId: today), context: context)
        let cached = try #require(try TodaySnapshotRepository.load(trainingDayId: today, context: context))
        #expect(cached.statusLabel == "Léger")
        #expect(cached.instruction == "Sortie facile")
        #expect(cached.limiterSignalCodes == ["sleep_short"])
        #expect(cached.stateCode == "TRAIN_EASY")
        let raw = try #require(try context.fetch(FetchDescriptor<TodayDaySnapshot>()).first?.payloadJSON)
        #expect(String(data: raw, encoding: .utf8)?.contains("\"sessions\"") != true)
    }

    // MARK: Push URL host allowlist

    @Test func pushUrlWithForeignHostIsIgnored() {
        let info: [AnyHashable: Any] = [
            "url": "https://evil.example/plan",
        ]
        #expect(PushNotificationManager.destination(for: info) == nil)
    }

    @Test func pushUrlOnSharpitHostIsAccepted() {
        let info: [AnyHashable: Any] = [
            "url": "https://sharpit.app/plan",
        ]
        #expect(PushNotificationManager.destination(for: info) == .tab(.plan))
    }

    @Test func pushUrlHttpSchemeIsIgnored() {
        let info: [AnyHashable: Any] = [
            "url": "http://sharpit.app/plan",
        ]
        #expect(PushNotificationManager.destination(for: info) == nil)
    }
}

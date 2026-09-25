import Foundation
import Testing
@testable import Sharpit

// MARK: - Stubs

private actor RecordingProfileClient: AthleteProfileServing {
    private(set) var patches: [AthleteProfilePatch] = []
    private var profile: V1AthleteProfile
    private let failsPatch: Bool
    private let failsRead: Bool

    init(_ profile: V1AthleteProfile = V1AthleteProfile(), failsPatch: Bool = false, failsRead: Bool = false) {
        self.profile = profile
        self.failsPatch = failsPatch
        self.failsRead = failsRead
    }

    func athleteProfile(token _: String) async throws -> V1AthleteProfile {
        if failsRead { throw SharpitAPIError.transport }
        return profile
    }

    func patchAthleteProfile(_ patch: AthleteProfilePatch, token _: String) async throws -> V1AthleteProfile {
        if failsPatch { throw SharpitAPIError.server }
        patches.append(patch)
        return profile
    }

    func thresholdHistory(token _: String) async throws -> [V1ThresholdSnapshot] { [] }
}

private actor RecordingGoalClient: GoalServing {
    private(set) var created: [CreateGoalInput] = []

    func goals(token _: String) async throws -> [V1Goal] { [] }

    func createGoal(_ input: CreateGoalInput, token _: String) async throws -> V1Goal {
        created.append(input)
        return V1Goal(title: input.title, kind: input.kind)
    }

    func toggleAchieved(id _: String, achieved _: Bool, token _: String) async throws -> V1Goal {
        throw SharpitAPIError.server
    }

    func deleteGoal(id _: String, token _: String) async throws {}
}

private actor RecordingOnboardingClient: OnboardingServing {
    private(set) var completions = 0
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func completeOnboarding(token _: String) async throws {
        if fails { throw SharpitAPIError.server }
        completions += 1
    }
}

@MainActor
private func makeStore(
    profile: RecordingProfileClient = RecordingProfileClient(),
    goals: RecordingGoalClient = RecordingGoalClient(),
    onboarding: RecordingOnboardingClient = RecordingOnboardingClient()
) -> OnboardingStore {
    OnboardingStore(
        profileClient: profile,
        goalClient: goals,
        onboardingClient: onboarding,
        tokenProvider: { "t" }
    )
}

// MARK: - Profile contract

@Test func aNullCompletionStampMeansTheWizardIsOwed() throws {
    let json = Data(#"{ "displayMode": "essential", "onboardingCompletedAt": null }"#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(profile.needsOnboarding)
    #expect(profile.onboardingCompletedAt == nil)
}

@Test func aStampedProfileIsDone() throws {
    let json = Data(#"{ "onboardingCompletedAt": "2026-09-20T08:12:44.120Z" }"#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(!profile.needsOnboarding)
    #expect(profile.onboardingCompletedAt != nil)
}

/// The web's fallback payload for an athlete with no row carries no stamp at all — as on the
/// web, that never traps anyone in the wizard.
@Test func aPayloadWithoutTheStampIsNotOwedTheWizard() throws {
    let json = Data(#"{ "id": "a1", "displayMode": "essential", "tier": "FREE" }"#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(!profile.needsOnboarding)
}

@Test func theOwedWizardSurvivesTheCache() throws {
    let owed = V1AthleteProfile(needsOnboarding: true)

    let decoded = try JSONDecoder().decode(V1AthleteProfile.self, from: JSONEncoder().encode(owed))

    #expect(decoded.needsOnboarding)
}

@Test func theTrainingWeekDecodesMondayFirst() throws {
    let json = Data(#"""
    { "trainingAvailability": { "version": 1, "targetSessionsPerWeek": 3, "availableWeekdays": [0, 2, 4, 2, 9] } }
    """#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(profile.trainingAvailability?.availableWeekdays == [2, 4, 0])
    #expect(profile.trainingAvailability?.targetSessionsPerWeek == 3)
}

@Test func theTrainingWeekPatchCarriesTheWebShape() {
    var patch = AthleteProfilePatch()

    patch.setTrainingAvailability(V1TrainingAvailability(availableWeekdays: [6, 2, 4]))

    #expect(patch.fields["trainingAvailability"] == .object([
        "version": .number(1),
        "targetSessionsPerWeek": .number(3),
        "availableWeekdays": .array([.number(2), .number(4), .number(6)]),
    ]))
}

@Test func anEmptyWeekIsDeclaredEmptyNotCleared() {
    var patch = AthleteProfilePatch()

    patch.setTrainingAvailability(V1TrainingAvailability())

    #expect(patch.fields["trainingAvailability"] == .object([
        "version": .number(1),
        "targetSessionsPerWeek": .null,
        "availableWeekdays": .array([]),
    ]))
}

// MARK: - Steps

@Test func theStepsFollowTheWebOrder() {
    #expect(OnboardingStep.allCases.map(\.label) == [
        "Sports", "Équipement", "Disponibilités", "Intention", "Sources",
    ])
    #expect(OnboardingStep.sports.previous == nil)
    #expect(OnboardingStep.sources.next == nil)
    #expect(OnboardingStep.availability.position == 3)
}

@Test func onlyTheConstraintStepsAndTheGoalCanBeSkipped() {
    #expect(OnboardingStep.allCases.filter(\.allowsSkip) == [.equipment, .availability, .intention])
}

@Test func theWeekReadsAsSessionsThenDays() {
    #expect(OnboardingWeekday.reading(V1TrainingAvailability()) == nil)
    #expect(OnboardingWeekday.reading(V1TrainingAvailability(availableWeekdays: [3])) == "1 séance possible · Mercredi")
    #expect(
        OnboardingWeekday.reading(V1TrainingAvailability(availableWeekdays: [0, 2]))
            == "2 séances possibles · Mardi, Dimanche"
    )
}

// MARK: - Intention

@Test func aRaceBecomesTheSeasonsAGoal() {
    var draft = OnboardingIntentionDraft()
    draft.raceTitle = "  Marathon de Paris "
    draft.raceLocation = " "

    let input = draft.goalInput

    #expect(input?.title == "Marathon de Paris")
    #expect(input?.kind == .race)
    #expect(input?.priority == .a)
    #expect(input?.targetDate == draft.raceDate)
    #expect(input?.location == nil)
}

@Test func aMetricNeedsATitleAPositiveTargetAndAUnit() {
    var draft = OnboardingIntentionDraft()
    draft.kind = .metric
    draft.metricTitle = "FTP"
    draft.metricTargetText = "0"
    draft.metricUnit = "W"
    #expect(!draft.isValid)

    draft.metricTargetText = "280,5"
    #expect(draft.goalInput?.targetValue == 280.5)
    #expect(draft.goalInput?.unit == "W")
    #expect(draft.goalInput?.priority == nil)

    draft.metricUnit = " "
    #expect(draft.goalInput == nil)
}

// MARK: - Store

@MainActor
@Test func sportsRefuseAComplementOnly() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await store.load()

    store.toggleSport("strength")
    await store.advance()

    #expect(store.step == .sports)
    #expect(store.error == "Choisis au moins un sport d'endurance pour continuer.")
    #expect(await profile.patches.isEmpty)
}

@MainActor
@Test func sportsAreSavedInCatalogOrderBeforeMovingOn() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await store.load()

    store.toggleSport("strength")
    store.toggleSport("run")
    await store.advance()

    #expect(store.step == .equipment)
    let patches = await profile.patches
    #expect(patches.first?.fields["practicedSports"] == .object([
        "version": .number(1),
        "sports": .array([.string("run"), .string("strength")]),
    ]))
}

@MainActor
@Test func aFailedSaveKeepsTheAthleteOnTheStep() async {
    let store = makeStore(profile: RecordingProfileClient(failsPatch: true))
    await store.load()

    store.toggleSport("bike")
    await store.advance()

    #expect(store.step == .sports)
    #expect(store.error == "Impossible d'enregistrer tes sports — réessaie.")
    #expect(!store.isBusy)
}

@MainActor
@Test func untouchedEquipmentIsNotWritten() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await store.load()
    store.toggleSport("run")
    await store.advance()

    await store.skip()

    #expect(store.step == .availability)
    #expect(await profile.patches.count == 1)
}

@MainActor
@Test func skippingTheWeekStillDeclaresItEmpty() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await store.load()
    store.toggleSport("run")
    await store.advance()
    await store.skip()

    await store.skip()

    #expect(store.step == .intention)
    #expect(await profile.patches.last?.fields.keys.contains("trainingAvailability") == true)
}

@MainActor
@Test func theGoalIsCreatedThenTheWizardFinishesServerSide() async {
    let goals = RecordingGoalClient()
    let onboarding = RecordingOnboardingClient()
    let store = makeStore(goals: goals, onboarding: onboarding)
    await store.load()
    store.toggleSport("swim")
    await store.advance()
    await store.skip()
    await store.skip()

    store.intention.raceTitle = "Triathlon de Nice"
    await store.advance()
    #expect(store.step == .sources)
    #expect(await goals.created.map(\.title) == ["Triathlon de Nice"])

    await store.advance()
    #expect(store.phase == .bootstrap)
    #expect(await onboarding.completions == 1)
}

@MainActor
@Test func aFailedCompletionStaysOnSources() async {
    let store = makeStore(onboarding: RecordingOnboardingClient(fails: true))
    await store.load()
    store.toggleSport("run")
    await store.advance()
    await store.skip()
    await store.skip()
    await store.skip()

    await store.advance()

    #expect(store.step == .sources)
    #expect(store.phase == .steps)
    #expect(store.error == "Impossible de terminer l'onboarding — réessaie.")
}

@MainActor
@Test func aReopenedWizardStartsFromWhatWasSaved() async {
    let saved = V1AthleteProfile(
        equipment: V1AthleteEquipment(strengthVenue: "gym", owned: ["bike_home_trainer"]),
        practicedSports: V1AthletePracticedSports(sports: ["strength", "bike"]),
        trainingAvailability: V1TrainingAvailability(availableWeekdays: [1, 3])
    )
    let store = makeStore(profile: RecordingProfileClient(saved))

    await store.load()

    #expect(store.phase == .steps)
    #expect(store.sports == ["bike", "strength"])
    #expect(store.strengthVenue == .gym)
    #expect(store.ownedEquipment == ["bike_home_trainer"])
    #expect(store.availability.availableWeekdays == [1, 3])
}

@MainActor
@Test func aFailedProfileReadStillOpensTheWizard() async {
    let store = makeStore(profile: RecordingProfileClient(failsRead: true))

    await store.load()

    #expect(store.phase == .steps)
    #expect(store.sports.isEmpty)
}

// MARK: - Gate

private actor StubConsentClient: PrivacyConsentServing {
    private var current: V1PrivacyConsents
    private let fails: Bool
    private(set) var updates: [PrivacyConsentUpdate] = []

    init(_ consents: V1PrivacyConsents = .accepted, fails: Bool = false) {
        current = consents
        self.fails = fails
    }

    func consents(token _: String) async throws -> V1PrivacyConsents {
        if fails { throw SharpitAPIError.transport }
        return current
    }

    func updateConsents(_ update: PrivacyConsentUpdate, token _: String) async throws -> V1PrivacyConsents {
        updates.append(update)
        return current
    }
}

extension V1PrivacyConsents {
    nonisolated static let accepted = V1PrivacyConsents(
        termsAcceptedAt: Date(timeIntervalSince1970: 1_800_000_000),
        privacyAcceptedAt: Date(timeIntervalSince1970: 1_800_000_000),
        privacyVersion: "v0-2026-09",
        healthDataConsentAt: Date(timeIntervalSince1970: 1_800_000_000),
        currentPrivacyVersion: "v0-2026-09"
    )
}

private func freshDefaults(_ name: String) throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Test func theGateOpensTheWizardForAnOwedAthlete() async throws {
    let defaults = try freshDefaults("account-gate-owed")
    let gate = AccountGateModel(
        consentClient: StubConsentClient(),
        profileClient: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)),
        defaults: defaults
    )

    await gate.resolve(userId: "user_1") { "t" }
    #expect(gate.status == .onboarding)

    gate.onboardingFinished()
    #expect(gate.status == .ready)

    // Remembered: a later launch goes straight to the tabs, even offline.
    let relaunch = AccountGateModel(
        consentClient: StubConsentClient(fails: true),
        profileClient: RecordingProfileClient(failsRead: true),
        defaults: defaults
    )
    await relaunch.resolve(userId: "user_1") { "t" }
    #expect(relaunch.status == .ready)
}

@MainActor
@Test func aFailedReadLetsTheAthleteInWithoutRememberingIt() async throws {
    let defaults = try freshDefaults("account-gate-offline")
    let offline = AccountGateModel(
        consentClient: StubConsentClient(fails: true),
        profileClient: RecordingProfileClient(failsRead: true),
        defaults: defaults
    )

    await offline.resolve(userId: "user_2") { "t" }
    #expect(offline.status == .ready)

    let online = AccountGateModel(
        consentClient: StubConsentClient(),
        profileClient: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)),
        defaults: defaults
    )
    await online.resolve(userId: "user_2") { "t" }
    #expect(online.status == .onboarding)
}

/// The web's order: the wall comes before the wizard.
@MainActor
@Test func theWallStandsBeforeTheWizard() async throws {
    let gate = AccountGateModel(
        consentClient: StubConsentClient(V1PrivacyConsents(currentPrivacyVersion: "v0-2026-09")),
        profileClient: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)),
        defaults: try freshDefaults("account-gate-wall")
    )

    await gate.resolve(userId: "user_3") { "t" }

    #expect(gate.status == .consent(.documents))
}

/// A finished athlete still meets the wall when the documents move to a new version.
@MainActor
@Test func aNewDocumentVersionBringsTheWallBack() async throws {
    let defaults = try freshDefaults("account-gate-version")
    defaults.set(true, forKey: "sharpit.onboarding.completed.user_4")
    var outdated = V1PrivacyConsents.accepted
    outdated.currentPrivacyVersion = "v1-2027-01"
    let gate = AccountGateModel(
        consentClient: StubConsentClient(outdated),
        profileClient: RecordingProfileClient(),
        defaults: defaults
    )

    await gate.resolve(userId: "user_4") { "t" }

    #expect(gate.status == .consent(.documents))
}

@MainActor
@Test func withdrawingHealthPutsTheWallBack() async throws {
    let gate = AccountGateModel(
        consentClient: StubConsentClient(),
        profileClient: RecordingProfileClient(),
        defaults: try freshDefaults("account-gate-withdraw")
    )
    await gate.resolve(userId: "user_5") { "t" }
    #expect(gate.status == .ready)

    var withdrawn = V1PrivacyConsents.accepted
    withdrawn.healthDataConsentAt = nil
    gate.consentsChanged(withdrawn)

    #expect(gate.status == .consent(.healthWithdrawn))
}

// MARK: - Consents

@Test func theWallReasonMirrorsTheWeb() {
    #expect(V1PrivacyConsents.accepted.wallReason == nil)
    #expect(V1PrivacyConsents(currentPrivacyVersion: "v0-2026-09").wallReason == .documents)

    var noHealth = V1PrivacyConsents.accepted
    noHealth.healthDataConsentAt = nil
    #expect(noHealth.wallReason == .healthWithdrawn)

    var onlyTerms = V1PrivacyConsents.accepted
    onlyTerms.privacyAcceptedAt = nil
    #expect(onlyTerms.wallReason == .documents)
}

@Test func theWallSendsHealthWithTheDocumentsAndLeavesUntickedOptionsAbsent() {
    #expect(PrivacyConsentUpdate.wall(ai: false, unofficialProviders: false).body == [
        "acceptLegal": true,
        "healthDataConsent": true,
    ])
    #expect(PrivacyConsentUpdate.wall(ai: true, unofficialProviders: true).body == [
        "acceptLegal": true,
        "healthDataConsent": true,
        "aiProcessingConsent": true,
        "unofficialProvidersAck": true,
    ])
}

@Test func aWithdrawalIsAnExplicitFalse() {
    var update = PrivacyConsentUpdate()
    update.healthDataConsent = false

    #expect(update.body == ["healthDataConsent": false])
}

@Test func theConsentEnvelopeDecodes() throws {
    let json = Data(#"""
    {
      "termsAcceptedAt": "2026-09-20T08:12:44.120Z",
      "privacyAcceptedAt": "2026-09-20T08:12:44.120Z",
      "privacyVersion": "v0-2026-09",
      "healthDataConsentAt": null,
      "aiProcessingConsentAt": "2026-09-20T08:12:44.120Z",
      "unofficialProvidersAckAt": null,
      "currentPrivacyVersion": "v0-2026-09"
    }
    """#.utf8)

    let consents = try JSONDecoder().decode(V1PrivacyConsents.self, from: json)

    #expect(consents.hasAIConsent)
    #expect(!consents.hasUnofficialProvidersAck)
    #expect(consents.wallReason == .healthWithdrawn)
}

@MainActor
@Test func aSettingsChangeAdoptsWhatTheServerSaved() async {
    let client = StubConsentClient()
    let store = PrivacySettingsStore(client: client, tokenProvider: { "t" })
    await store.load()
    #expect(store.phase == .loaded)

    var update = PrivacyConsentUpdate()
    update.aiProcessingConsent = true
    let saved = await store.update(update)

    #expect(saved == .accepted)
    #expect(await client.updates == [update])
}

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
private final class RecordingPlanClient: CoachPlanServing {
    private(set) var requestedGoalIds: [String?] = []
    private(set) var inserted: [(sessions: [V1GeneratedSession], goalId: String?)] = []
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func generateWeek(
        days _: Int,
        goalId: String?,
        focus _: String?,
        startDate _: Date?,
        token _: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1GeneratedPlan {
        requestedGoalIds.append(goalId)
        if fails { throw SharpitAPIError.server }
        onReasoning("…")
        return V1GeneratedPlan(summary: "Installation", sessions: [
            V1GeneratedSession(date: "2026-09-28", type: .run, intensity: "ENDURANCE", title: "Footing", description: "", durationMin: 45, load: 40),
            V1GeneratedSession(date: "2026-09-30", type: .run, intensity: "THRESHOLD", title: "Seuil", description: "", durationMin: 55, load: 62),
        ])
    }

    func adaptPlan(days _: Int, focus _: String?, token _: String, onReasoning _: @escaping @Sendable (String) -> Void) async throws -> V1AdaptPlanResult {
        V1AdaptPlanResult(summary: "", changes: [])
    }

    func insertWeek(_ sessions: [V1GeneratedSession], goalId: String?, token _: String) async throws {
        inserted.append((sessions, goalId))
    }
}

private actor NoteRecorder: PhysicalNoteCreating {
    private(set) var notes: [CreatePhysicalNoteInput] = []

    func createNote(_ input: CreatePhysicalNoteInput, token _: String) async throws { notes.append(input) }
}

private actor NameRecorder {
    private(set) var names: [String] = []

    func save(_ name: String) { names.append(name) }
}

/// Fails its first `failures` completions, then succeeds.
private actor FlakyOnboardingClient: OnboardingServing {
    private(set) var completions = 0
    private var failures: Int

    init(failures: Int) { self.failures = failures }

    func completeOnboarding(token _: String) async throws {
        if failures > 0 {
            failures -= 1
            throw SharpitAPIError.server
        }
        completions += 1
    }
}

@MainActor
private func makeStore(
    profile: RecordingProfileClient = RecordingProfileClient(),
    goals: RecordingGoalClient = RecordingGoalClient(),
    onboarding: any OnboardingServing = RecordingOnboardingClient(),
    consents: StubConsentClient = StubConsentClient(),
    plan: RecordingPlanClient = RecordingPlanClient(),
    notes: NoteRecorder = NoteRecorder(),
    names: NameRecorder = NameRecorder(),
    consentsOwed: Bool = false,
    currentConsents: V1PrivacyConsents? = nil,
    stepMemory: OnboardingStepMemory? = nil
) -> OnboardingStore {
    OnboardingStore(
        services: OnboardingServices(
            profile: profile,
            goals: goals,
            onboarding: onboarding,
            consents: consents,
            plan: plan,
            physicalNotes: notes,
            saveFirstName: { await names.save($0) }
        ),
        consentsOwed: consentsOwed,
        currentConsents: currentConsents,
        stepMemory: stepMemory,
        tokenProvider: { "t" }
    )
}

/// Loads the wizard and walks past the identity and an endurance sport, both saved.
@MainActor
private func storeOnEquipment(_ store: OnboardingStore) async {
    await store.load()
    store.identity.firstName = "Zoé"
    await store.advance()
    store.toggleSport("run")
    await store.advance()
}

/// The first week is generated in a task of its own; this waits for it to settle.
@MainActor
private func settledFirstWeek(_ store: OnboardingStore) async -> OnboardingStore.FirstWeek {
    for _ in 0..<500 where store.firstWeek == .generating {
        try? await Task.sleep(for: .milliseconds(2))
    }
    return store.firstWeek
}

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

@Test func theWizardBuildsTheCoachThenPlansItsWeek() {
    #expect(OnboardingStep.allCases == [
        .identity, .sports, .equipment, .week, .goal, .injuries, .privacy, .sources, .firstWeek,
    ])
}

@Test func onlyTheKitTheWeekAndTheGoalCanBeSkipped() {
    #expect(OnboardingStep.allCases.filter(\.allowsSkip) == [.equipment, .week, .goal, .injuries])
}

@MainActor
@Test func theConsentsAreAStepOnlyWhenOwed() {
    #expect(!makeStore().path.contains(.privacy))
    #expect(makeStore(consentsOwed: true).path == OnboardingStep.allCases)
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
    store.identity.firstName = "Zoé"
    await store.advance()

    store.toggleSport("strength")
    await store.advance()

    #expect(store.step == .sports)
    #expect(!store.canAdvance)
    #expect(await profile.patches.isEmpty)
}

@MainActor
@Test func sportsAreSavedInCatalogOrderBeforeMovingOn() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await store.load()
    store.identity.firstName = "Zoé"
    await store.advance()

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
    store.identity.firstName = "Zoé"
    await store.advance()

    store.toggleSport("bike")
    await store.advance()

    #expect(store.step == .sports)
    #expect(store.error == "Impossible d'enregistrer tes sports. Réessaie.")
    #expect(!store.isBusy)
}

@MainActor
@Test func untouchedEquipmentIsNotWritten() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await storeOnEquipment(store)

    await store.skip()

    #expect(store.step == .week)
    #expect(await profile.patches.count == 1)
}

/// A step with nothing to save moves at once; the same tap delivered again must not skip the
/// step it lands on.
@MainActor
@Test func aTapFromAStepAlreadyLeftIsDropped() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await storeOnEquipment(store)

    await store.advance(from: .equipment)
    await store.advance(from: .equipment)
    await store.skip(from: .equipment)

    #expect(store.step == .week)
    #expect(await profile.patches.count == 1)
}

@MainActor
@Test func skippingTheWeekStillDeclaresItEmpty() async {
    let profile = RecordingProfileClient()
    let store = makeStore(profile: profile)
    await storeOnEquipment(store)
    await store.skip()

    await store.skip()

    #expect(store.step == .goal)
    #expect(await profile.patches.last?.fields.keys.contains("trainingAvailability") == true)
}

@MainActor
@Test func paintingADayTwiceKeepsItOnce() {
    let store = makeStore()

    store.setWeekday(2, available: true)
    store.setWeekday(2, available: true)
    store.setWeekday(4, available: true)
    store.toggleWeekday(2)

    #expect(store.availability.availableWeekdays == [4])
}

/// The whole path of a new account: goal, consents with AI, the week generated towards the
/// goal while the sources are linked, then added to the plan and the wizard closed.
@MainActor
@Test func theFirstWeekIsPlannedTowardsTheGoalThenAdded() async {
    let goals = RecordingGoalClient()
    let consents = StubConsentClient()
    let plan = RecordingPlanClient()
    let notes = NoteRecorder()
    let onboarding = RecordingOnboardingClient()
    let store = makeStore(goals: goals, onboarding: onboarding, consents: consents, plan: plan, notes: notes, consentsOwed: true)
    await storeOnEquipment(store)
    await store.skip()
    await store.skip()

    store.intention.raceTitle = "Triathlon de Nice"
    await store.advance()
    #expect(store.step == .injuries)
    #expect(await goals.created.map(\.title) == ["Triathlon de Nice"])

    var knee = OnboardingInjuryDraft(bodyPart: "Genou")
    knee.kind = .pain
    knee.side = .right
    knee.level = .moderate
    store.saveInjury(knee)
    await store.advance()
    #expect(store.step == .privacy)
    #expect(await notes.notes.isEmpty)

    await store.advance()
    #expect(store.step == .privacy)

    store.consents.acceptAll()
    await store.advance()
    #expect(store.step == .sources)
    #expect(await consents.updates == [.wall(ai: true, unofficialProviders: true)])
    #expect(await notes.notes.map(\.title) == ["Douleur genou droit"])

    guard case .ready(_, let week) = await settledFirstWeek(store) else {
        Issue.record("The first week was not generated")
        return
    }
    #expect(week.count == 2)
    #expect(plan.requestedGoalIds.count == 1)
    #expect(plan.requestedGoalIds.first != nil)

    await store.advance()
    #expect(store.step == .firstWeek)
    await store.advance()

    #expect(plan.inserted.count == 1)
    #expect(plan.inserted.first?.sessions.map(\.title) == ["Footing", "Seuil"])
    #expect(plan.inserted.first?.goalId != nil)
    #expect(await onboarding.completions == 1)
    #expect(store.phase == .bootstrap)
}

@MainActor
@Test func withoutTheAIConsentNoWeekIsGenerated() async {
    let plan = RecordingPlanClient()
    let onboarding = RecordingOnboardingClient()
    let store = makeStore(onboarding: onboarding, plan: plan, consentsOwed: true)
    await storeOnEquipment(store)
    await store.skip()
    await store.skip()
    await store.skip()
    await store.skip()

    store.consents.terms = true
    store.consents.privacy = true
    store.consents.health = true
    await store.advance()
    await store.advance()

    #expect(store.step == .firstWeek)
    #expect(store.firstWeek == .unavailable)
    #expect(plan.requestedGoalIds.isEmpty)

    await store.advance()
    #expect(store.phase == .bootstrap)
    #expect(await onboarding.completions == 1)
}

/// An athlete who already consented walks no privacy step: the week starts from the sources.
@MainActor
@Test func consentsAlreadyGivenSkipThePrivacyStep() async {
    var consented = V1PrivacyConsents.accepted
    consented.aiProcessingConsentAt = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeStore(currentConsents: consented)
    await storeOnEquipment(store)
    await store.skip()
    await store.skip()
    await store.skip()
    await store.skip()
    #expect(store.step == .sources)

    await store.advance()

    #expect(store.step == .firstWeek)
    if case .ready = await settledFirstWeek(store) {} else {
        Issue.record("The first week was not generated")
    }
}

@MainActor
@Test func aFailedGenerationCanBeRetried() async {
    var consented = V1PrivacyConsents.accepted
    consented.aiProcessingConsentAt = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = RecordingPlanClient(fails: true)
    let store = makeStore(plan: plan, currentConsents: consented)

    store.startFirstWeek()
    guard case .failed = await settledFirstWeek(store) else {
        Issue.record("The generation should have failed")
        return
    }
    store.startFirstWeek()
    _ = await settledFirstWeek(store)

    #expect(plan.requestedGoalIds.count == 2)
}

/// The week is in the plan once: a completion that failed and is tried again adds nothing more.
@MainActor
@Test func aRetriedFinishNeverAddsTheWeekTwice() async {
    var consented = V1PrivacyConsents.accepted
    consented.aiProcessingConsentAt = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = RecordingPlanClient()
    let onboarding = FlakyOnboardingClient(failures: 1)
    let store = makeStore(onboarding: onboarding, plan: plan, currentConsents: consented)
    await storeOnEquipment(store)
    await store.skip()
    await store.skip()
    await store.skip()
    await store.skip()
    await store.advance()
    _ = await settledFirstWeek(store)

    await store.advance()
    #expect(store.error == "Impossible de terminer l'onboarding. Réessaie.")
    #expect(store.phase == .steps)

    await store.advance()
    #expect(plan.inserted.count == 1)
    #expect(await onboarding.completions == 1)
    #expect(store.phase == .bootstrap)
}

@MainActor
@Test func theIdentityNeedsAFirstNameThenSavesItAndTheBody() async {
    let profile = RecordingProfileClient()
    let names = NameRecorder()
    let store = makeStore(profile: profile, names: names)
    await store.load()
    #expect(!store.canAdvance)

    store.identity.firstName = "  Zoé "
    store.identity.sex = .female
    store.identity.heightCm = 168
    await store.advance()

    #expect(store.step == .sports)
    #expect(await names.names == ["Zoé"])
    let patch = await profile.patches.first
    #expect(patch?.fields["sex"] == .string("female"))
    #expect(patch?.fields["heightCm"] == .number(168))
    #expect(patch?.fields.keys.contains("birthDate") == false)
}

/// Consents already given: the injuries are written as the step is left.
@Test func anInjuryIsCompleteOnlyOnceEachQuestionIsAnswered() {
    var knee = OnboardingInjuryDraft(bodyPart: "Genou")
    #expect(!knee.isComplete)
    knee.kind = .pain
    knee.level = .light
    #expect(!knee.isComplete)
    knee.side = .both
    #expect(knee.isComplete)
    #expect(knee.title == "Douleur genou des deux côtés")

    var back = OnboardingInjuryDraft(bodyPart: "Dos")
    back.kind = .injury
    back.level = .moderate
    #expect(back.isComplete)
    #expect(back.note.side == "NA")
}

@MainActor
@Test func injuriesAreWrittenAtOnceWhenNoConsentIsOwed() async {
    let notes = NoteRecorder()
    let store = makeStore(notes: notes)
    await storeOnEquipment(store)
    await store.skip()
    await store.skip()
    await store.skip()

    var back = OnboardingInjuryDraft(bodyPart: "Dos")
    back.kind = .pain
    back.level = .light
    store.saveInjury(back)
    var ankle = OnboardingInjuryDraft(bodyPart: "Cheville")
    ankle.kind = .injury
    ankle.level = .strong
    store.saveInjury(ankle)
    #expect(store.injuries.count == 1)
    ankle.side = .left
    store.saveInjury(ankle)
    store.removeInjury("Dos")
    await store.advance()

    #expect(store.step == .sources)
    let written = await notes.notes
    #expect(written.map(\.title) == ["Blessure cheville gauche"])
    #expect(written.first?.category == "INJURY")
    #expect(written.first?.side == "LEFT")
    #expect(written.first?.severity == 8)
}

@MainActor
@Test func aReopenedWizardStartsFromWhatWasSaved() async throws {
    let saved = V1AthleteProfile(
        equipment: V1AthleteEquipment(strengthVenue: "gym", owned: ["bike_home_trainer"]),
        practicedSports: V1AthletePracticedSports(sports: ["strength", "bike"]),
        trainingAvailability: V1TrainingAvailability(availableWeekdays: [1, 3])
    )
    let memory = OnboardingStepMemory(userId: "user_reopen", defaults: try freshDefaults("onboarding-reopen"))
    memory.step = .week
    let store = makeStore(profile: RecordingProfileClient(saved), stepMemory: memory)

    await store.load()

    #expect(store.phase == .steps)
    #expect(store.step == .week)
    #expect(store.sports == ["bike", "strength"])
    #expect(store.strengthVenue == .gym)
    #expect(store.ownedEquipment == ["bike_home_trainer"])
    #expect(store.availability.availableWeekdays == [1, 3])
}

@MainActor
@Test func aFinishedWizardForgetsTheStep() async throws {
    let memory = OnboardingStepMemory(userId: "user_done", defaults: try freshDefaults("onboarding-done"))
    let store = makeStore(stepMemory: memory)
    await storeOnEquipment(store)
    #expect(memory.step == .equipment)

    await store.finishWithoutFirstWeek()

    #expect(memory.step == nil)
    #expect(store.phase == .bootstrap)
}

@MainActor
@Test func aFailedProfileReadStillOpensTheWizard() async {
    let store = makeStore(profile: RecordingProfileClient(failsRead: true))

    await store.load()

    #expect(store.phase == .steps)
    #expect(store.step == .identity)
    #expect(store.sports.isEmpty)
}

// MARK: - Gate

@MainActor
private func makeGate(
    consents: StubConsentClient = StubConsentClient(),
    profile: RecordingProfileClient = RecordingProfileClient(),
    defaults: UserDefaults,
    onStore: @escaping @MainActor (Bool) -> Void = { _ in }
) -> AccountGateModel {
    AccountGateModel(consentClient: consents, profileClient: profile, defaults: defaults) { owed, current, _ in
        onStore(owed)
        return makeStore(consentsOwed: owed, currentConsents: current)
    }
}

@MainActor
@Test func theGateOpensTheWizardForAnOwedAthlete() async throws {
    let defaults = try freshDefaults("account-gate-owed")
    let gate = makeGate(profile: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)), defaults: defaults)

    await gate.resolve(userId: "user_1") { "t" }
    #expect(gate.status == .onboarding)
    #expect(gate.onboardingStore != nil)

    gate.onboardingFinished()
    #expect(gate.status == .ready)
    #expect(gate.onboardingStore == nil)

    // Remembered: a later launch goes straight to the tabs, even offline.
    let relaunch = makeGate(
        consents: StubConsentClient(fails: true),
        profile: RecordingProfileClient(failsRead: true),
        defaults: defaults
    )
    await relaunch.resolve(userId: "user_1") { "t" }
    #expect(relaunch.status == .ready)
}

/// A session refresh resolves the gate again; the open wizard must survive it untouched.
@MainActor
@Test func resolvingAgainKeepsTheOpenWizard() async throws {
    let gate = makeGate(
        profile: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)),
        defaults: try freshDefaults("account-gate-reresolve")
    )
    await gate.resolve(userId: "user_6") { "t" }
    let wizard = try #require(gate.onboardingStore)

    await gate.resolve(userId: "user_6") { "t" }

    #expect(gate.status == .onboarding)
    #expect(gate.onboardingStore === wizard)
}

@MainActor
@Test func aFailedReadLetsTheAthleteInWithoutRememberingIt() async throws {
    let defaults = try freshDefaults("account-gate-offline")
    let offline = makeGate(
        consents: StubConsentClient(fails: true),
        profile: RecordingProfileClient(failsRead: true),
        defaults: defaults
    )

    await offline.resolve(userId: "user_2") { "t" }
    #expect(offline.status == .ready)

    let online = makeGate(profile: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)), defaults: defaults)
    await online.resolve(userId: "user_2") { "t" }
    #expect(online.status == .onboarding)
}

/// A new account meets the consents inside the wizard, just before its sources — not a wall
/// in front of it.
@MainActor
@Test func aNewAccountConsentsInsideTheWizard() async throws {
    var owed: Bool?
    let gate = makeGate(
        consents: StubConsentClient(V1PrivacyConsents(currentPrivacyVersion: "v0-2026-09")),
        profile: RecordingProfileClient(V1AthleteProfile(needsOnboarding: true)),
        defaults: try freshDefaults("account-gate-wall")
    ) { owed = $0 }

    await gate.resolve(userId: "user_3") { "t" }

    #expect(gate.status == .onboarding)
    #expect(owed == true)
    #expect(gate.onboardingStore?.path.contains(.privacy) == true)
}

/// A finished athlete still meets the wall when the documents move to a new version.
@MainActor
@Test func aNewDocumentVersionBringsTheWallBack() async throws {
    let defaults = try freshDefaults("account-gate-version")
    defaults.set(true, forKey: "sharpit.onboarding.completed.user_4")
    var outdated = V1PrivacyConsents.accepted
    outdated.currentPrivacyVersion = "v1-2027-01"
    let gate = makeGate(consents: StubConsentClient(outdated), defaults: defaults)

    await gate.resolve(userId: "user_4") { "t" }

    #expect(gate.status == .consent(.documents))
}

@MainActor
@Test func withdrawingHealthPutsTheWallBack() async throws {
    let gate = makeGate(defaults: try freshDefaults("account-gate-withdraw"))
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

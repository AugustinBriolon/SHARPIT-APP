import Foundation
import Observation

/// The first-login wizard: what the athlete picked on each step, the write that leaves it, and
/// the first week the coach plans at the end.
///
/// Each step is saved as the athlete leaves it, so quitting half-way keeps what was answered;
/// the step reached is remembered too (`stepMemory`), so a relaunch reopens where it was. The
/// consents are a step of their own, just before the sources, when they are owed. Once they
/// allow AI, the first week is generated in the background while the athlete links their
/// sources, and it waits for them on the last step. The wizard is finished only by
/// `/api/v1/onboarding/complete` — never by the app deciding it.
@MainActor
@Observable
final class OnboardingStore {
    enum Phase: Equatable {
        /// Reading the profile, so a wizard reopened after a quit starts from what was saved.
        case loading
        case steps
        /// Finished server-side: the short beat before Résumé.
        case bootstrap
    }

    /// The first week, generated in the background once the consents allow AI.
    enum FirstWeek: Equatable {
        case idle
        /// No AI consent: nothing is generated, and the step says so.
        case unavailable
        case generating
        case ready(summary: String, sessions: [V1GeneratedSession])
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var step: OnboardingStep = .identity
    /// Which way the last move went, so a step slides in from the side the athlete is heading.
    private(set) var isMovingForward = true
    /// Set while a write is in flight, so the actions refuse a second tap.
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var firstWeek: FirstWeek = .idle
    /// The sessions the coach has written so far, shown as they arrive.
    private(set) var firstWeekDrafts: [V1GeneratedSession] = []

    var identity = OnboardingIdentityDraft()
    /// Catalog order, as the web stores it.
    var sports: [String] = []
    var ownedEquipment: Set<String> = []
    var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    var availability = V1TrainingAvailability()
    var intention = OnboardingIntentionDraft()
    var consents = OnboardingConsents()
    /// One per zone, in the order the athlete touched them.
    private(set) var injuries: [OnboardingInjuryDraft] = []

    /// The steps this athlete walks: the privacy one only when the consents are owed.
    let path: [OnboardingStep]

    /// Equipment is written only when the athlete touched it — the web's `flush` does the same.
    private var equipmentIsDirty = false
    private var createdGoalId: String?
    /// Set once the week is in the plan, so a retried finish never adds it twice.
    private var addedFirstWeek = false
    private var hasAIConsent: Bool
    private var generation: Task<Void, Never>?
    /// Injuries are health data: with the consents still owed they wait on the phone and are
    /// written once the privacy step is accepted, before the first week is planned.
    private var injuriesAwaitingConsent: [OnboardingInjuryDraft] = []

    private let services: OnboardingServices
    private let tokenProvider: () async throws -> String
    private let stepMemory: OnboardingStepMemory?

    init(
        services: OnboardingServices,
        consentsOwed: Bool = false,
        currentConsents: V1PrivacyConsents? = nil,
        stepMemory: OnboardingStepMemory? = nil,
        firstName: String? = nil,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.services = services
        self.tokenProvider = tokenProvider
        self.stepMemory = stepMemory
        path = OnboardingStep.allCases.filter { $0 != .privacy || consentsOwed }
        hasAIConsent = currentConsents?.hasAIConsent ?? false
        consents.ai = currentConsents?.hasAIConsent ?? false
        consents.unofficialProviders = currentConsents?.hasUnofficialProvidersAck ?? false
        identity.firstName = firstName ?? ""
    }

    var canContinueFromSports: Bool { PracticedSportCatalog.hasEnduranceSport(sports) }

    var equipmentSports: [EquipmentSport] {
        PracticedSportCatalog.equipmentSports(for: Set(sports))
    }

    /// 0…1, for the header's dial.
    var progress: Double {
        guard let index = path.firstIndex(of: step), path.count > 1 else { return 0 }
        return Double(index) / Double(path.count - 1)
    }

    var position: Int { (path.firstIndex(of: step) ?? 0) + 1 }
    var canGoBack: Bool { previous != nil && step != .firstWeek }

    /// Whether the step's primary action can run now.
    var canAdvance: Bool {
        switch step {
        case .identity: identity.isValid
        case .sports: canContinueFromSports
        case .goal: intention.isValid
        case .privacy: consents.requiredAccepted
        case .firstWeek: firstWeek != .generating
        case .equipment, .week, .injuries, .sources: true
        }
    }

    private var next: OnboardingStep? {
        guard let index = path.firstIndex(of: step), index + 1 < path.count else { return nil }
        return path[index + 1]
    }

    private var previous: OnboardingStep? {
        guard let index = path.firstIndex(of: step), index > 0 else { return nil }
        return path[index - 1]
    }

    // MARK: - Loading

    /// Pre-fills the steps from the profile and reopens the step reached before a quit. A failed
    /// read still opens the wizard, empty: every step writes what it holds.
    func load() async {
        guard phase == .loading else { return }
        defer { phase = .steps }
        if let remembered = stepMemory?.step, path.contains(remembered), remembered != .firstWeek {
            step = remembered
        }
        guard
            let token = try? await tokenProvider(),
            let profile = try? await services.profile.athleteProfile(token: token)
        else { return }
        adopt(profile)
    }

    private func adopt(_ profile: V1AthleteProfile) {
        identity.sex = profile.sex
        identity.heightCm = profile.heightCm
        identity.birthDate = profile.birthDate
        if let practiced = profile.practicedSports?.sports {
            sports = PracticedSportCatalog.ordered(practiced)
        }
        if let equipment = profile.equipment {
            ownedEquipment = Set(equipment.owned)
            if let raw = equipment.strengthVenue, let venue = V1AthleteEquipment.StrengthVenue(rawValue: raw) {
                strengthVenue = venue
            }
        }
        if let declared = profile.trainingAvailability {
            availability = declared
        }
    }

    // MARK: - Editing

    func toggleSport(_ id: String) {
        var next = Set(sports)
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        sports = PracticedSportCatalog.ordered(next)
        if canContinueFromSports, error != nil { error = nil }
    }

    /// Adds a complete declaration, or replaces the one for the same zone.
    func saveInjury(_ injury: OnboardingInjuryDraft) {
        guard injury.isComplete else { return }
        if let index = injuries.firstIndex(where: { $0.id == injury.id }) {
            injuries[index] = injury
        } else {
            injuries.append(injury)
        }
    }

    func removeInjury(_ bodyPart: String) {
        injuries.removeAll { $0.bodyPart == bodyPart }
    }

    func toggleEquipment(_ id: String) {
        if ownedEquipment.contains(id) { ownedEquipment.remove(id) } else { ownedEquipment.insert(id) }
        equipmentIsDirty = true
    }

    func setStrengthVenue(_ venue: V1AthleteEquipment.StrengthVenue) {
        strengthVenue = venue
        equipmentIsDirty = true
    }

    /// N days ⇒ N possible sessions, derived rather than asked.
    func setWeekday(_ day: Int, available: Bool) {
        var days = availability.availableWeekdays
        let has = days.contains(day)
        guard has != available else { return }
        if available { days.append(day) } else { days.removeAll { $0 == day } }
        availability = V1TrainingAvailability(availableWeekdays: days)
    }

    func toggleWeekday(_ day: Int) {
        setWeekday(day, available: !availability.availableWeekdays.contains(day))
    }

    // MARK: - Navigation

    func goBack() {
        guard !isBusy, canGoBack, let previous else { return }
        move(to: previous)
    }

    /// The step's primary action: saves what it holds, then moves on. `origin` is the step the
    /// tap was made on: a tap delivered again after the page already moved (a step with nothing
    /// to save moves at once) is dropped instead of skipping the next step.
    func advance(from origin: OnboardingStep? = nil) async {
        guard !isBusy, canAdvance, origin == nil || origin == step else { return }
        switch step {
        case .identity: leaveIdentity()
        case .sports: leaveSports()
        case .equipment: leaveEquipment()
        case .week: leaveWeek()
        case .goal: submitGoal()
        case .injuries: leaveInjuries()
        case .privacy: leavePrivacy()
        case .sources: leaveSources()
        case .firstWeek: await addFirstWeekAndFinish()
        }
    }

    /// The step's Passer. Equipment and the week still save: skipping the week declares it
    /// empty, and the coach then falls back to the days it observes.
    func skip(from origin: OnboardingStep? = nil) async {
        guard !isBusy, step.allowsSkip, origin == nil || origin == step else { return }
        switch step {
        case .equipment: leaveEquipment()
        case .week: leaveWeek()
        case .goal: moveNext()
        case .injuries:
            injuries = []
            leaveInjuries()
        default: break
        }
    }

    /// Finishes without the generated week: it stays unplanned, the coach can plan it later.
    func finishWithoutFirstWeek() async {
        guard !isBusy else { return }
        generation?.cancel()
        await finish()
    }

    private func moveNext() {
        guard let next else { return }
        move(to: next)
    }

    private func leaveIdentity() {
        let draft = identity
        enqueue(failure: "Impossible d'enregistrer ton profil.") { token in
            try await self.services.saveFirstName(draft.trimmedFirstName)
            let patch = draft.profilePatch
            if !patch.fields.isEmpty {
                _ = try await self.services.profile.patchAthleteProfile(patch, token: token)
            }
        }
        moveNext()
    }

    private func leaveSports() {
        var patch = AthleteProfilePatch()
        patch.setPracticedSports(V1AthletePracticedSports(sports: sports))
        enqueue(patch, failure: "Impossible d'enregistrer tes sports.")
        moveNext()
    }

    private func leaveEquipment() {
        if equipmentIsDirty {
            var patch = AthleteProfilePatch()
            patch.setEquipment(V1AthleteEquipment(
                strengthVenue: strengthVenue.rawValue,
                owned: ownedEquipment.sorted()
            ))
            enqueue(patch, failure: "Impossible d'enregistrer ton matériel.")
            equipmentIsDirty = false
        }
        moveNext()
    }

    private func leaveWeek() {
        var patch = AthleteProfilePatch()
        patch.setTrainingAvailability(availability)
        enqueue(patch, failure: "Impossible d'enregistrer ta semaine.")
        moveNext()
    }

    private func submitGoal() {
        guard let input = intention.goalInput else { return }
        enqueue(failure: "Impossible de créer l'objectif.") { token in
            let goal = try await self.services.goals.createGoal(input, token: token)
            self.createdGoalId = goal.id
        }
        moveNext()
    }

    private func leaveInjuries() {
        let declared = injuries
        if path.contains(.privacy) {
            injuriesAwaitingConsent = declared
        } else if !declared.isEmpty {
            enqueue(failure: "Impossible d'enregistrer tes blessures.") { token in
                try await self.write(declared, token: token)
            }
        }
        moveNext()
    }

    private func write(_ declared: [OnboardingInjuryDraft], token: String) async throws {
        for injury in declared {
            try await services.physicalNotes.createNote(injury.note, token: token)
        }
    }

    /// The consents go first in the queue, then the injuries they allow; the first week is
    /// generated once both are in (`startFirstWeek` waits for the queue).
    private func leavePrivacy() {
        let waiting = injuriesAwaitingConsent
        let update = PrivacyConsentUpdate.wall(ai: consents.ai, unofficialProviders: consents.unofficialProviders)
        enqueue(failure: "Impossible d'enregistrer tes choix de confidentialité.") { token in
            _ = try await self.services.consents.updateConsents(update, token: token)
            try await self.write(waiting, token: token)
        }
        injuriesAwaitingConsent = []
        hasAIConsent = consents.ai
        // Generated while the athlete links their sources, so it is waiting at the end.
        startFirstWeek()
        moveNext()
    }

    private func leaveSources() {
        startFirstWeek()
        moveNext()
    }

    // MARK: - Background writes

    /// A write a step queued, kept to be tried again when it failed.
    private struct QueuedWrite {
        let failure: String
        let work: (String) async throws -> Void
    }

    /// Writes run behind the athlete, in the order the steps were left: a step moves on at
    /// once instead of waiting on the network.
    private var writeQueue: Task<Void, Never>?
    private var failedWrites: [QueuedWrite] = []

    private func enqueue(_ patch: AthleteProfilePatch, failure: String) {
        enqueue(failure: failure) { token in
            _ = try await self.services.profile.patchAthleteProfile(patch, token: token)
        }
    }

    private func enqueue(failure: String, _ work: @escaping (String) async throws -> Void) {
        let write = QueuedWrite(failure: failure, work: work)
        let previous = writeQueue
        writeQueue = Task { [weak self] in
            await previous?.value
            await self?.run(write)
        }
    }

    private func run(_ write: QueuedWrite) async {
        do {
            try await write.work(try await tokenProvider())
        } catch {
            failedWrites.append(write)
            self.error = message(for: error, failure: "\(write.failure) On réessaie avant de continuer.")
        }
    }

    /// Waits for every queued write and tries the failed ones once more — before anything
    /// depends on them. True when everything the athlete answered is saved.
    @discardableResult
    func flushWrites() async -> Bool {
        await writeQueue?.value
        guard !failedWrites.isEmpty else { return true }
        let retrying = failedWrites
        failedWrites = []
        for write in retrying {
            await run(write)
        }
        if failedWrites.isEmpty { error = nil }
        return failedWrites.isEmpty
    }

    // MARK: - First week

    /// Once, and only with the AI consent: the plan generator is an AI route.
    func startFirstWeek() {
        guard firstWeek == .idle || isRetryable else { return }
        guard hasAIConsent else {
            firstWeek = .unavailable
            return
        }
        firstWeek = .generating
        firstWeekDrafts = []
        generation = Task { [weak self] in
            guard let self else { return }
            // The consents, the goal and the injuries must be in before the coach reads them.
            guard await self.flushWrites() else {
                self.firstWeek = .failed(self.error ?? "Tes réponses ne sont pas encore enregistrées. Réessaie.")
                return
            }
            let goalId = self.createdGoalId
            do {
                let token = try await self.tokenProvider()
                let plan = try await self.services.plan.generateWeek(
                    days: 7,
                    goalId: goalId,
                    focus: nil,
                    startDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                    token: token
                ) { [weak self] drafts in
                    Task { @MainActor in self?.noteDrafts(drafts) }
                }
                guard !Task.isCancelled else { return }
                self.firstWeek = plan.sessions.isEmpty
                    ? .failed("Le coach n'a proposé aucune séance. Tu pourras lui demander ta semaine depuis le Plan.")
                    : .ready(summary: plan.summary, sessions: plan.sessions)
            } catch is CancellationError {
            } catch {
                self.firstWeek = .failed(SharpitErrorGuidance.message(for: error, subject: "Ta première semaine"))
            }
        }
    }

    private var isRetryable: Bool {
        if case .failed = firstWeek { return true }
        return false
    }

    private func noteDrafts(_ drafts: [V1GeneratedSession]) {
        guard firstWeek == .generating else { return }
        firstWeekDrafts = drafts
    }

    /// Puts the week in the plan, then finishes. A failed insert stays on the step, the week
    /// still on screen, so the athlete can try again or finish without it.
    private func addFirstWeekAndFinish() async {
        guard case .ready(_, let sessions) = firstWeek, !addedFirstWeek else {
            await finish()
            return
        }
        let goalId = createdGoalId
        var added = false
        await perform(failure: "Impossible d'ajouter ta semaine au plan. Réessaie.") { token in
            try await self.services.plan.insertWeek(sessions, goalId: goalId, token: token)
        } onSuccess: {
            added = true
        }
        guard added else { return }
        addedFirstWeek = true
        await finish()
    }

    private func finish() async {
        isBusy = true
        let saved = await flushWrites()
        isBusy = false
        guard saved else { return }
        await perform(failure: "Impossible de terminer l'onboarding. Réessaie.") { token in
            try await self.services.onboarding.completeOnboarding(token: token)
        } onSuccess: {
            self.stepMemory?.step = nil
            self.phase = .bootstrap
        }
    }

    // MARK: - Writes

    private func move(to target: OnboardingStep) {
        error = nil
        isMovingForward = (path.firstIndex(of: target) ?? 0) > (path.firstIndex(of: step) ?? 0)
        step = target
        stepMemory?.step = target
    }

    private func perform(
        failure: String,
        _ work: (String) async throws -> Void,
        onSuccess: () -> Void
    ) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let token = try await tokenProvider()
            try await work(token)
            onSuccess()
        } catch {
            self.error = message(for: error, failure: failure)
        }
    }

    private func message(for error: Error, failure: String) -> String {
        switch error as? SharpitAPIError {
        case .unauthorized: "Session expirée. Reconnecte-toi."
        case .transport: "Pas de connexion internet. Vérifie ton réseau, puis réessaie."
        default: failure
        }
    }
}

/// What the wizard talks to, in one place so the gate, the demo and the tests hand it over
/// together.
struct OnboardingServices {
    let profile: any AthleteProfileServing
    let goals: any GoalServing
    let onboarding: any OnboardingServing
    let consents: any PrivacyConsentServing
    let plan: any CoachPlanServing
    let physicalNotes: any PhysicalNoteCreating
    /// The first name lives on the Clerk account, not the profile.
    let saveFirstName: @Sendable (String) async throws -> Void
}

/// The consents the privacy step asks for: the two documents and health, required together
/// (the server refuses one without the others); AI and the unofficial-providers notice optional.
struct OnboardingConsents: Equatable {
    var terms = false
    var privacy = false
    var health = false
    var ai = false
    var unofficialProviders = false

    var requiredAccepted: Bool { terms && privacy && health }

    /// The page's « Tout accepter »: every box, the optional ones included, since the first
    /// week needs the AI one.
    mutating func acceptAll() {
        terms = true
        privacy = true
        health = true
        ai = true
        unofficialProviders = true
    }
}

/// Where the wizard was, per athlete, so a relaunch reopens the same step.
final class OnboardingStepMemory {
    private let defaults: UserDefaults
    private let key: String

    init(userId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "sharpit.onboarding.step.\(userId)"
    }

    var step: OnboardingStep? {
        get { defaults.object(forKey: key) == nil ? nil : OnboardingStep(rawValue: defaults.integer(forKey: key)) }
        set {
            if let newValue { defaults.set(newValue.rawValue, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}

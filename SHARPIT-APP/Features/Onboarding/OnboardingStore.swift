import Foundation
import Observation

/// The first-login wizard: what the athlete picked on each step, and the write that leaves it.
///
/// Each step is saved as the athlete leaves it, as on the web, so quitting half-way keeps what
/// was already answered and the next launch reopens the wizard pre-filled from the profile.
/// The wizard is finished only by `/api/v1/onboarding/complete` — never by the app deciding it.
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

    private(set) var phase: Phase = .loading
    private(set) var step: OnboardingStep = .sports
    /// Which way the last move went, so a step slides in from the side the athlete is heading.
    private(set) var isMovingForward = true
    /// Set while a write is in flight, so the actions refuse a second tap.
    private(set) var isBusy = false
    private(set) var error: String?

    /// Catalog order, as the web stores it.
    var sports: [String] = []
    var ownedEquipment: Set<String> = []
    var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    var availability = V1TrainingAvailability()
    var intention = OnboardingIntentionDraft()

    /// Equipment is written only when the athlete touched it — the web's `flush` does the same.
    private var equipmentIsDirty = false

    private let profileClient: any AthleteProfileServing
    private let goalClient: any GoalServing
    private let onboardingClient: any OnboardingServing
    private let tokenProvider: () async throws -> String

    init(
        profileClient: any AthleteProfileServing,
        goalClient: any GoalServing,
        onboardingClient: any OnboardingServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.profileClient = profileClient
        self.goalClient = goalClient
        self.onboardingClient = onboardingClient
        self.tokenProvider = tokenProvider
    }

    var canContinueFromSports: Bool { PracticedSportCatalog.hasEnduranceSport(sports) }

    var equipmentSports: [EquipmentSport] {
        PracticedSportCatalog.equipmentSports(for: Set(sports))
    }

    // MARK: - Loading

    /// Pre-fills the steps from the profile. A failed read still opens the wizard, empty:
    /// every step writes what it holds, so nothing is lost by starting blank.
    func load() async {
        guard phase == .loading else { return }
        defer { SharpitMotion.run { phase = .steps } }
        guard
            let token = try? await tokenProvider(),
            let profile = try? await profileClient.athleteProfile(token: token)
        else { return }
        adopt(profile)
    }

    private func adopt(_ profile: V1AthleteProfile) {
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

    func toggleEquipment(_ id: String) {
        if ownedEquipment.contains(id) { ownedEquipment.remove(id) } else { ownedEquipment.insert(id) }
        equipmentIsDirty = true
    }

    func setStrengthVenue(_ venue: V1AthleteEquipment.StrengthVenue) {
        strengthVenue = venue
        equipmentIsDirty = true
    }

    /// N days ⇒ N possible sessions, derived rather than asked.
    func toggleWeekday(_ day: Int) {
        var days = availability.availableWeekdays
        if let index = days.firstIndex(of: day) { days.remove(at: index) } else { days.append(day) }
        availability = V1TrainingAvailability(availableWeekdays: days)
    }

    // MARK: - Navigation

    func goBack() {
        guard !isBusy, let previous = step.previous else { return }
        move(to: previous)
    }

    /// The step's primary action: saves what it holds, then moves on.
    func advance() async {
        guard !isBusy else { return }
        switch step {
        case .sports: await leaveSports()
        case .equipment: await leaveEquipment()
        case .availability: await leaveAvailability()
        case .intention: await submitIntention()
        case .sources: await finish()
        }
    }

    /// The step's Passer. Equipment and availability still save, as the web's do: skipping the
    /// week declares it empty, and the coach then falls back to the days it observes.
    func skip() async {
        guard !isBusy, step.allowsSkip else { return }
        switch step {
        case .equipment: await leaveEquipment()
        case .availability: await leaveAvailability()
        case .intention: move(to: .sources)
        case .sports, .sources: break
        }
    }

    private func leaveSports() async {
        guard canContinueFromSports else {
            error = "Choisis au moins un sport d'endurance pour continuer."
            return
        }
        var patch = AthleteProfilePatch()
        patch.setPracticedSports(V1AthletePracticedSports(sports: sports))
        if await save(patch, failure: "Impossible d'enregistrer tes sports — réessaie.") {
            move(to: .equipment)
        }
    }

    private func leaveEquipment() async {
        guard equipmentIsDirty else {
            move(to: .availability)
            return
        }
        var patch = AthleteProfilePatch()
        patch.setEquipment(V1AthleteEquipment(
            strengthVenue: strengthVenue.rawValue,
            owned: ownedEquipment.sorted()
        ))
        if await save(patch, failure: "Impossible d'enregistrer ton matériel — réessaie.") {
            equipmentIsDirty = false
            move(to: .availability)
        }
    }

    private func leaveAvailability() async {
        var patch = AthleteProfilePatch()
        patch.setTrainingAvailability(availability)
        if await save(patch, failure: "Impossible d'enregistrer ta semaine — réessaie.") {
            move(to: .intention)
        }
    }

    private func submitIntention() async {
        guard let input = intention.goalInput else {
            error = "Complète l'objectif, ou passe cette étape."
            return
        }
        await perform(failure: "Impossible de créer l'objectif — réessaie.") { token in
            _ = try await self.goalClient.createGoal(input, token: token)
        } onSuccess: {
            self.move(to: .sources)
        }
    }

    private func finish() async {
        await perform(failure: "Impossible de terminer l'onboarding — réessaie.") { token in
            try await self.onboardingClient.completeOnboarding(token: token)
        } onSuccess: {
            SharpitMotion.run { self.phase = .bootstrap }
        }
    }

    // MARK: - Writes

    private func move(to target: OnboardingStep) {
        error = nil
        isMovingForward = target.rawValue > step.rawValue
        SharpitMotion.run { step = target }
    }

    private func save(_ patch: AthleteProfilePatch, failure: String) async -> Bool {
        var saved = false
        await perform(failure: failure) { token in
            _ = try await self.profileClient.patchAthleteProfile(patch, token: token)
        } onSuccess: {
            saved = true
        }
        return saved
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
        } catch SharpitAPIError.unauthorized {
            self.error = "Session expirée. Reconnecte-toi."
        } catch {
            self.error = failure
        }
    }
}

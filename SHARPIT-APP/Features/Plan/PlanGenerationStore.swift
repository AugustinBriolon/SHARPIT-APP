import Foundation
import Observation

/// Plan's « Remplir ma semaine »: the request, the week the coach writes, the sessions kept.
///
/// Owned by Plan, not by its sheet, so closing the sheet mid-generation loses nothing: the
/// generation runs on, and reopening the sheet shows it where it is — still writing, or ready.
@MainActor
@Observable
final class PlanGenerationStore {
    enum Phase {
        case idle
        /// Streaming: the sessions written so far.
        case generating(drafts: [V1GeneratedSession])
        case ready(plan: V1GeneratedPlan, selected: Set<Int>)
        case inserting(plan: V1GeneratedPlan, selected: Set<Int>)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Why the last « Ajouter » failed; the week stays on screen to try again.
    private(set) var insertError: String?
    var days = 7
    /// nil for no goal.
    var goalId: String?
    var focus = ""
    private(set) var goals: [V1Goal] = []

    private let plan: any CoachPlanServing
    private let goalClient: any GoalServing
    private let tokenProvider: () async throws -> String
    private var generation: Task<Void, Never>?

    init(
        plan: any CoachPlanServing = CoachPlanClient(),
        goalClient: any GoalServing = GoalClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.plan = plan
        self.goalClient = goalClient
        self.tokenProvider = tokenProvider
    }

    var isGenerating: Bool {
        if case .generating = phase { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Dated goals still ahead, the ones a week can be built towards.
    func loadGoals(now: Date = .now) async {
        guard let token = try? await tokenProvider(),
              let all = try? await goalClient.goals(token: token)
        else { return }
        goals = all.filter { !$0.achieved && ($0.targetDate ?? .distantPast) >= now }
    }

    func start() {
        generation?.cancel()
        phase = .generating(drafts: [])
        let request = (days: days, goalId: goalId, focus: focus)
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await self.tokenProvider()
                let week = try await self.plan.generateWeek(
                    days: request.days,
                    goalId: request.goalId,
                    focus: request.focus,
                    startDate: .now,
                    token: token
                ) { [weak self] drafts in
                    Task { @MainActor in self?.showDrafts(drafts) }
                }
                guard !Task.isCancelled else { return }
                self.phase = week.sessions.isEmpty
                    ? .failed("Le coach n'a proposé aucune séance. Précise ta demande et réessaie.")
                    : .ready(plan: week, selected: Set(week.sessions.indices))
                SharpitHaptics.play(week.sessions.isEmpty ? .soft : .success)
            } catch is CancellationError {
            } catch {
                self.phase = .failed(SharpitErrorGuidance.message(for: error, subject: "La génération"))
            }
        }
    }

    /// A draft never replaces a finished week, and only ever grows what is shown.
    private func showDrafts(_ drafts: [V1GeneratedSession]) {
        guard case .generating = phase else { return }
        phase = .generating(drafts: drafts)
    }

    func toggle(_ index: Int) {
        guard case .ready(let plan, var selected) = phase else { return }
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        phase = .ready(plan: plan, selected: selected)
    }

    /// Back to the request, keeping it filled in.
    func reset() {
        generation?.cancel()
        phase = .idle
    }

    /// Adds the kept sessions; returns how many went in, or nil when it failed.
    func insert() async -> Int? {
        guard case .ready(let week, let selected) = phase, !selected.isEmpty else { return nil }
        phase = .inserting(plan: week, selected: selected)
        insertError = nil
        let sessions = selected.sorted().filter { $0 < week.sessions.count }.map { week.sessions[$0] }
        do {
            try await plan.insertWeek(sessions, goalId: goalId, token: try await tokenProvider())
            phase = .idle
            return sessions.count
        } catch {
            insertError = SharpitErrorGuidance.message(for: error, subject: "L'ajout au plan")
            phase = .ready(plan: week, selected: selected)
            return nil
        }
    }
}

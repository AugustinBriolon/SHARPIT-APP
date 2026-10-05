import Foundation
import Observation

/// Plan's « Remplir ma semaine »: the request, the week the coach writes, the sessions kept.
///
/// The week is generated on the server in the background (`PlanJobServing`): the app starts it,
/// follows it while in front, and picks it back up on its return — the server pushes « Ta
/// semaine est prête » when it is done, app open or not. Owned by Plan, not by its sheet.
@MainActor
@Observable
final class PlanGenerationStore {
    enum Phase {
        case idle
        /// Generating: the sessions written so far.
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
    private let jobs: any PlanJobServing
    private let goalClient: any GoalServing
    private let tokenProvider: () async throws -> String
    private let defaults: UserDefaults
    private let pollInterval: Duration
    private var jobId: String?
    private var polling: Task<Void, Never>?

    /// The last generation added or dismissed, so a relaunch does not offer it again.
    static let handledJobKey = "sharpit.planGeneration.handledJob"

    init(
        plan: any CoachPlanServing & PlanJobServing = CoachPlanClient(),
        goalClient: any GoalServing = GoalClient(),
        defaults: UserDefaults = .standard,
        pollInterval: Duration = .milliseconds(1500),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.plan = plan
        jobs = plan
        self.goalClient = goalClient
        self.defaults = defaults
        self.pollInterval = pollInterval
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
        polling?.cancel()
        phase = .generating(drafts: [])
        insertError = nil
        let request = (days: days, goalId: goalId, focus: focus)
        polling = Task { [weak self] in
            guard let self else { return }
            do {
                let job = try await self.jobs.startWeekJob(
                    days: request.days,
                    goalId: request.goalId,
                    focus: request.focus,
                    startDate: .now,
                    token: try await self.tokenProvider()
                )
                self.jobId = job.id
                await self.follow(job.id)
            } catch is CancellationError {
            } catch {
                self.phase = .failed(Self.message(for: error, subject: "La génération"))
            }
        }
    }

    /// Picks the generation back up when Plan shows or the app returns: follows one still
    /// running, and shows one finished while the athlete was away.
    func resume() async {
        if case .generating = phase, let jobId {
            guard polling == nil else { return }
            polling = Task { [weak self] in await self?.follow(jobId) }
            return
        }
        guard case .idle = phase,
              let token = try? await tokenProvider(),
              let job = try? await jobs.latestPlanJob(token: token),
              job.id != defaults.string(forKey: Self.handledJobKey)
        else { return }
        jobId = job.id
        apply(job)
        if job.status == "running", polling == nil {
            polling = Task { [weak self] in await self?.follow(job.id) }
        }
    }

    /// Reads the job until it is no longer running — while the app is in front.
    private func follow(_ id: String) async {
        defer { polling = nil }
        while !Task.isCancelled {
            guard let token = try? await tokenProvider() else { return }
            if let job = try? await jobs.planJob(id: id, token: token) {
                apply(job)
                if job.status != "running" { return }
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func apply(_ job: V1PlanJob) {
        switch job.status {
        case "ready":
            guard let week = job.plan, !week.sessions.isEmpty else {
                phase = .failed("Le coach n'a proposé aucune séance. Précise ta demande et réessaie.")
                return
            }
            if case .ready = phase { return }
            phase = .ready(plan: week, selected: week.insertableIndices)
        case "failed":
            phase = .failed(job.error ?? "La génération a échoué. Réessaie dans un instant.")
        default:
            phase = .generating(drafts: job.drafts)
        }
    }

    func toggle(_ index: Int) {
        guard case .ready(let plan, var selected) = phase, plan.insertableIndices.contains(index) else { return }
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        phase = .ready(plan: plan, selected: selected)
    }

    /// Back to the request, keeping it filled in; the week shown is not offered again.
    func reset() {
        polling?.cancel()
        polling = nil
        markHandled()
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
            markHandled()
            phase = .idle
            return sessions.count
        } catch {
            insertError = Self.message(for: error, subject: "L'ajout au plan")
            phase = .ready(plan: week, selected: selected)
            return nil
        }
    }

    private func markHandled() {
        guard let jobId else { return }
        defaults.set(jobId, forKey: Self.handledJobKey)
        self.jobId = nil
    }

    private static func message(for error: Error, subject: String) -> String {
        (error as? CoachPlanError)?.errorDescription ?? SharpitErrorGuidance.message(for: error, subject: subject)
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class GoalStore {
    /// Every change reaches the « Prochain objectif » widget: a race added, done or deleted.
    private(set) var goals: [V1Goal] = [] {
        didSet { if goals != oldValue { WidgetSnapshotPublisher.publish(goals) } }
    }
    private(set) var sessions: [V1PlannedSessionItem] = []
    private(set) var activities: [V1ActivityListItem] = []
    private(set) var profile: V1AthleteProfile?
    /// Each time a goal was reached, newest first — « Réalisations récentes », at the foot of Objectifs.
    private(set) var achievements: [V1GoalAchievement] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: any GoalServing
    private let plannedSessionClient: (any PlannedSessionServing)?
    private let profileClient: (any AthleteProfileServing)?
    private let activityClient: (any ActivityServing)?
    let tokenProvider: () async throws -> String

    /// What an achievement's session opens with, pushed in the Objectifs stack.
    var sessionReader: (any ActivityServing)? { activityClient }

    /// How many achievements the page lists, as the web's history does.
    static let achievementsLimit = 15

    init(
        client: any GoalServing,
        plannedSessionClient: (any PlannedSessionServing)? = PlannedSessionClient(),
        profileClient: (any AthleteProfileServing)? = AthleteProfileClient(),
        activityClient: (any ActivityServing)? = ActivityClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.plannedSessionClient = plannedSessionClient
        self.profileClient = profileClient
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
    }

    var activeGoals: [V1Goal] {
        goals.filter { !$0.achieved }
    }

    var completedGoals: [V1Goal] {
        goals.filter(\.achieved)
    }

    /// The race the season is built toward: the nearest upcoming A race, else the nearest
    /// upcoming race of any priority. Nil when no race lies ahead.
    var nextRace: V1Goal? {
        GoalOrdering.nextRace(in: goals)
    }

    /// Active goals in the order an athlete reads them: dated ones soonest first, then the
    /// undated, each group by title.
    var activeGoalsOrdered: [V1Goal] {
        GoalOrdering.active(activeGoals)
    }

    func goal(id: String) -> V1Goal? {
        goals.first { $0.id == id }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await tokenProvider()
            goals = try await client.goals(token: token)

            // Concurrently load sessions, profile, and activities to supply accurate goal analytics
            async let fetchedSessions = fetchSessions(token: token)
            async let fetchedProfile = fetchProfile(token: token)
            async let fetchedActivities = fetchActivities(token: token)
            async let fetchedAchievements = fetchAchievements(token: token)

            let (s, p, a) = await (fetchedSessions, fetchedProfile, fetchedActivities)
            self.sessions = s
            self.profile = p
            self.activities = a
            // A history that failed to read keeps what was shown: it is never the page's error.
            if let reached = await fetchedAchievements { self.achievements = reached }
        } catch SharpitAPIError.unauthorized {
            errorMessage = "Session expirée"
        } catch {
            errorMessage = "Impossible de charger les objectifs"
        }
    }

    private func fetchSessions(token: String) async -> [V1PlannedSessionItem] {
        guard let client = plannedSessionClient else { return [] }
        let now = Date()
        let from = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let to = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        return (try? await client.plannedSessions(from: from, to: to, token: token)) ?? []
    }

    func refreshAchievements() async {
        guard let token = try? await tokenProvider() else { return }
        if let reached = await fetchAchievements(token: token) { achievements = reached }
    }

    private func fetchAchievements(token: String) async -> [V1GoalAchievement]? {
        try? await client.achievements(limit: Self.achievementsLimit, token: token)
    }

    private func fetchProfile(token: String) async -> V1AthleteProfile? {
        guard let client = profileClient else { return nil }
        return try? await client.athleteProfile(token: token)
    }

    private func fetchActivities(token: String) async -> [V1ActivityListItem] {
        guard let client = activityClient else { return [] }
        return (try? await client.activities(token: token)) ?? []
    }

    func volumeStats(for goal: V1Goal) -> GoalVolumeStats {
        GoalAnalyticsEngine.computeVolumeStats(goal: goal, sessions: sessions, activities: activities)
    }

    func raceProjection(for goal: V1Goal) -> GoalRaceProjectionResult? {
        GoalAnalyticsEngine.computeRaceProjection(goal: goal, profile: profile, activities: activities)
    }

    @discardableResult
    func create(_ input: CreateGoalInput) async -> Bool {
        do {
            let newGoal = try await SharpitRetry.run {
                try await client.createGoal(input, token: try await tokenProvider())
            }
            goals.append(newGoal)
            return true
        } catch {
            errorMessage = "Impossible de créer l'objectif"
            return false
        }
    }

    /// Shown on the tap and sent behind; a refusal puts the goal back and says why.
    func update(_ goal: V1Goal, with draft: GoalDraft, from original: GoalDraft) {
        let fields = draft.changes(from: original)
        guard !fields.isEmpty, let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        let previous = goals[index]
        goals[index] = previous.applying(draft)
        Task {
            do {
                let updated = try await SharpitRetry.run {
                    try await client.updateGoal(id: goal.id, fields: fields, token: try await tokenProvider())
                }
                if let idx = goals.firstIndex(where: { $0.id == updated.id }) { goals[idx] = updated }
            } catch {
                if let idx = goals.firstIndex(where: { $0.id == goal.id }) { goals[idx] = previous }
                if case SharpitAPIError.message(let reason) = error {
                    SharpitWriteFailures.shared.report("Objectif non modifié : \(reason)")
                } else {
                    SharpitWriteFailures.shared.report("Objectif non modifié.")
                }
            }
        }
    }

    func toggleAchieved(_ goal: V1Goal) async {
        let newAchieved = !goal.achieved
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].achieved = newAchieved
        do {
            let updated = try await SharpitRetry.run {
                try await client.toggleAchieved(id: goal.id, achieved: newAchieved, token: try await tokenProvider())
            }
            if let idx = goals.firstIndex(where: { $0.id == updated.id }) {
                goals[idx] = updated
            }
            // Marking a goal reached writes an achievement server-side.
            await refreshAchievements()
        } catch {
            // Revert on error
            if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[idx].achieved = !newAchieved
            }
            errorMessage = "Mise à jour impossible"
        }
    }

    func delete(id: String) async {
        let backup = goals
        goals.removeAll { $0.id == id }
        do {
            try await SharpitRetry.run {
                try await client.deleteGoal(id: id, token: try await tokenProvider())
            }
        } catch {
            goals = backup
            errorMessage = "Suppression impossible"
        }
    }
}

nonisolated enum GoalOrdering {
    static func nextRace(in goals: [V1Goal], now: Date = Date(), calendar: Calendar = .current) -> V1Goal? {
        let today = calendar.startOfDay(for: now)
        let upcoming = goals
            .filter { !$0.achieved && $0.kind == .race }
            .compactMap { goal -> (V1Goal, Date)? in
                guard let date = goal.targetDate, calendar.startOfDay(for: date) >= today else { return nil }
                return (goal, date)
            }
            .sorted { $0.1 < $1.1 }
        return (upcoming.first { $0.0.priority == .a } ?? upcoming.first)?.0
    }

    static func active(_ goals: [V1Goal]) -> [V1Goal] {
        goals.sorted { lhs, rhs in
            switch (lhs.targetDate, rhs.targetDate) {
            case let (l?, r?): l < r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

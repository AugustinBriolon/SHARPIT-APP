import Foundation
import Observation

@MainActor
@Observable
final class GoalStore {
    private(set) var goals: [V1Goal] = []
    private(set) var sessions: [V1PlannedSessionItem] = []
    private(set) var activities: [V1ActivityListItem] = []
    private(set) var profile: V1AthleteProfile?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: any GoalServing
    private let plannedSessionClient: (any PlannedSessionServing)?
    private let profileClient: (any AthleteProfileServing)?
    private let activityClient: (any ActivityServing)?
    private let tokenProvider: () async throws -> String

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

            let (s, p, a) = await (fetchedSessions, fetchedProfile, fetchedActivities)
            self.sessions = s
            self.profile = p
            self.activities = a
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
            let token = try await tokenProvider()
            let newGoal = try await client.createGoal(input, token: token)
            goals.append(newGoal)
            return true
        } catch {
            errorMessage = "Impossible de créer l'objectif"
            return false
        }
    }

    func toggleAchieved(_ goal: V1Goal) async {
        let newAchieved = !goal.achieved
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].achieved = newAchieved
        do {
            let token = try await tokenProvider()
            let updated = try await client.toggleAchieved(id: goal.id, achieved: newAchieved, token: token)
            if let idx = goals.firstIndex(where: { $0.id == updated.id }) {
                goals[idx] = updated
            }
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
            let token = try await tokenProvider()
            try await client.deleteGoal(id: id, token: token)
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

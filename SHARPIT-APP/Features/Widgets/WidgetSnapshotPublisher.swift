import ClerkKit
import Foundation
import WidgetKit

extension WidgetSnapshot.Day {
    /// Résumé's day as the widgets show it — the fold already mapped for the screen, so the
    /// widgets say what Résumé says.
    init(fold: TodayFold) {
        let sleep = fold.gauges.first { $0.key == .sleep }
        let recovery = fold.gauges.first { $0.key == .recovery }
        self.init(
            trainingDayId: fold.trainingDayId,
            verdict: WidgetSnapshot.Verdict(
                status: fold.plate.statusLabel,
                headline: fold.plate.headline,
                action: fold.plate.actionLine,
                posture: fold.plate.posture
            ),
            sessions: fold.sessions.map { card in
                WidgetSnapshot.Session(
                    id: card.id,
                    isDone: card.kind == .done,
                    title: card.brickChain ?? card.title,
                    sport: V1ActivityType(sportLabel: card.sport ?? ""),
                    plannedSessionId: card.plannedSessionId,
                    figures: card.metrics.prefix(2).map {
                        WidgetSnapshot.Figure(value: $0.value, unit: $0.unit.isEmpty ? $0.label.lowercased() : $0.unit)
                    }
                )
            },
            sleep: sleep.map { WidgetSnapshot.Sleep(score: Int($0.score), caption: $0.caption) },
            recovery: recovery.map { WidgetSnapshot.Sleep(score: Int($0.score), caption: $0.caption) }
        )
    }
}

extension WidgetSnapshot.Nutrition {
    /// The food log as its Résumé card reads it: the server's goal and remainder, never recomputed.
    init(response: V1NutritionResponse) {
        let day = response.day
        let goals = day?.goals
        self.init(
            trainingDayId: response.trainingDayId,
            isConnected: response.connected,
            calories: day?.calories,
            calorieGoal: goals?.calorieBudget,
            remaining: goals?.calories.remaining,
            macros: day.map { day in
                [
                    WidgetSnapshot.Macro(kind: .protein, grams: day.protein, goalGrams: goals?.protein.goal),
                    WidgetSnapshot.Macro(kind: .carbohydrates, grams: day.carbohydrates, goalGrams: goals?.carbohydrates.goal),
                    WidgetSnapshot.Macro(kind: .fat, grams: day.fat, goalGrams: goals?.fat.goal),
                ]
            } ?? []
        )
    }
}

extension WidgetSnapshot.Weight {
    /// The weigh-in from the web's body overview — the value Corps leads with — and the target.
    init?(overview: V1BodyOverview, targetKilograms: Double?) {
        guard let weight = overview.metrics.first(where: { $0.key == .weight }) else { return nil }
        self.init(
            kilograms: weight.value,
            measuredAt: weight.measuredAt,
            previousKilograms: weight.previous,
            changeWindowDays: weight.deltaWindowDays,
            targetKilograms: targetKilograms
        )
    }
}

extension WidgetSnapshot.Regularity {
    /// Résumé's strip, as the server counts it.
    init?(consistency: V1TodayConsistency?, trainingDayId: String) {
        guard let consistency, !consistency.days.isEmpty else { return nil }
        self.init(
            trainingDayId: trainingDayId,
            days: consistency.days.map {
                WidgetSnapshot.RegularityDay(
                    date: $0.date, weekdayLabel: $0.weekdayLabel, dayOfMonth: $0.dayOfMonth,
                    hasActivity: $0.hasActivity, isToday: $0.isToday, isFuture: $0.isFuture
                )
            },
            weekSessionCount: consistency.thisWeekSessionCount
        )
    }
}

extension WidgetSnapshot.Training {
    /// The last two weeks of the activity list — enough for this week and last week's same point.
    init(activities: [V1ActivityListItem], now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? now
        self.init(sessions: activities
            .filter { $0.date >= start }
            .map {
                WidgetSnapshot.TrainedSession(
                    dayId: WidgetSnapshot.dayId($0.date, calendar: calendar),
                    sport: $0.type,
                    distanceMeters: $0.distanceM,
                    durationSeconds: $0.duration
                )
            })
    }
}

extension WidgetSnapshot.LatestActivity {
    /// The session as the widget reads it: how far first, else how long; then the time and the
    /// pace (a ride's speed, a swim's pace per 100 m), or the load when nothing was measured.
    init(activity: V1ActivityListItem, route: [[Double]]?) {
        var figures: [WidgetSnapshot.Figure] = []
        let meters = activity.distanceM.flatMap { $0 > 0 ? $0 : nil }
        let seconds = activity.duration.flatMap { $0 > 0 ? $0 : nil }
        if let meters {
            figures.append(meters >= 1_000
                ? .init(value: SharpitFigureFormat.kilometers(meters / 1_000), unit: "km")
                : .init(value: "\(Int(meters.rounded()))", unit: "m"))
        }
        if let seconds { figures.append(.init(value: SharpitFigureFormat.duration(seconds: seconds), unit: "")) }
        if let meters, let seconds, meters >= 100 {
            switch activity.type {
            case .bike: figures.append(.init(value: ActivityFormat.speedKmh(distanceM: meters, duration: seconds), unit: "km/h"))
            case .swim: figures.append(.init(value: ActivityFormat.paceClock(seconds / (meters / 100)), unit: "/100 m"))
            default: figures.append(.init(value: ActivityFormat.paceClock(seconds / (meters / 1_000)), unit: "/km"))
            }
        } else if let load = activity.load, load > 0, let whole = Int(exactly: load.rounded()) {
            figures.append(.init(value: "\(whole)", unit: String(localized: "charge")))
        }
        self.init(
            id: activity.id, title: activity.title ?? activity.type.label, sport: activity.type,
            date: activity.date, figures: figures, route: route
        )
    }
}

extension WidgetSnapshot.Goal {
    /// The race Objectifs puts first: the nearest A race ahead, else the nearest race.
    init?(goals: [V1Goal], now: Date = .now) {
        guard let race = GoalOrdering.nextRace(in: goals, now: now), let date = race.targetDate else { return nil }
        self.init(
            id: race.id, title: race.title, date: date, location: race.location,
            format: race.raceFormat, targetPerformance: race.targetPerformance
        )
    }
}

/// Writes the widgets' sections and asks WidgetKit to redraw them when one changed.
enum WidgetSnapshotPublisher {
    /// Only today's fold reaches the home screen.
    static func publish(_ fold: TodayFold, now: Date = .now) {
        guard fold.trainingDayId == TrainingDayId.today(now: now) else { return }
        update {
            $0.day = WidgetSnapshot.Day(fold: fold)
            $0.regularity = WidgetSnapshot.Regularity(consistency: fold.consistency, trainingDayId: fold.trainingDayId)
        }
    }

    static func publish(_ activities: [V1ActivityListItem]) {
        update { $0.training = WidgetSnapshot.Training(activities: activities) }
    }

    /// The session recorded last, for « Dernière activité ». Its route is read once per session:
    /// the one already published is kept, and a read that fails publishes the session without it
    /// rather than leave the previous session on the Home Screen.
    static func publishLatestActivity(from activities: [V1ActivityListItem], client: any ActivityServing, token: String) async {
        guard let latest = activities.max(by: { $0.date < $1.date }), !latest.id.isEmpty else { return }
        let published = WidgetSnapshotStore.read()?.latestActivity
        var route = published?.id == latest.id ? published?.route : nil
        if route == nil, let stream = try? await client.activityStream(id: latest.id, token: token) {
            route = WidgetRoute.fit((stream.path ?? []))
        }
        let next = WidgetSnapshot.LatestActivity(activity: latest, route: route)
        update { $0.latestActivity = next }
    }

    /// Nil clears it: a race done or deleted leaves no countdown behind.
    static func publish(_ goals: [V1Goal]) {
        update { $0.goal = WidgetSnapshot.Goal(goals: goals) }
    }

    static func publish(_ nutrition: V1NutritionResponse, now: Date = .now) {
        guard nutrition.trainingDayId == TrainingDayId.today(now: now) else { return }
        update { $0.nutrition = WidgetSnapshot.Nutrition(response: nutrition) }
    }

    static func publish(_ overview: V1BodyOverview, targetKilograms: Double?) {
        guard let weight = WidgetSnapshot.Weight(overview: overview, targetKilograms: targetKilograms) else { return }
        update { $0.weight = weight }
    }

    static func erase() {
        WidgetSnapshotStore.erase()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func update(_ change: (inout WidgetSnapshot) -> Void) {
        if WidgetSnapshotStore.update(change) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Reads every section in the background — a silent push after a server sync — and
    /// publishes what came back. Returns whether anything was read.
    @MainActor
    static func refreshInBackground(
        today: any TodayServing = SharpitClient(),
        nutrition: any NutritionServing = SharpitClient(),
        body: any BodyServing = BodyClient(),
        profile: any AthleteProfileServing = AthleteProfileClient(),
        activities: any ActivityServing = ActivityClient(),
        goals: any GoalServing = GoalClient()
    ) async -> Bool {
        guard let token = try? await Clerk.shared.auth.getToken() else { return false }
        let dayId = TrainingDayId.today()
        async let todayRead = try? today.today(trainingDayId: dayId, token: token)
        async let nutritionRead = try? nutrition.nutrition(trainingDayId: dayId, token: token)
        async let overviewRead = try? body.bodyOverview(token: token)
        async let profileRead = try? profile.athleteProfile(token: token)
        // The newest page holds the fortnight Training reads.
        async let activitiesRead = try? activities.activityPage(before: nil, limit: 60, token: token)
        async let goalsRead = try? goals.goals(token: token)
        let (payload, food, overview, athlete) = await (todayRead, nutritionRead, overviewRead, profileRead)
        let (recorded, races) = await (activitiesRead, goalsRead)

        if let payload, case .loaded(let response) = TodayModel.state(from: payload) {
            publish(TodayFoldMapper.map(response))
        }
        if let food { publish(food) }
        if let overview { publish(overview, targetKilograms: athlete?.targetWeightKg) }
        if let recorded {
            publish(recorded)
            await publishLatestActivity(from: recorded, client: activities, token: token)
        }
        if let races { publish(races) }
        return payload != nil || food != nil || overview != nil || recorded != nil || races != nil
    }
}

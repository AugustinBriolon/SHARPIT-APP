import ClerkKit
import Foundation
import WidgetKit

extension WidgetSnapshot.Day {
    /// Résumé's day as the widgets show it — the fold already mapped for the screen, so the
    /// widgets say what Résumé says.
    init(fold: TodayFold) {
        let sleep = fold.gauges.first { $0.key == .sleep }
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
            sleep: sleep.map { WidgetSnapshot.Sleep(score: Int($0.score), caption: $0.caption) }
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

/// Writes the widgets' sections and asks WidgetKit to redraw them when one changed.
enum WidgetSnapshotPublisher {
    /// Only today's fold reaches the home screen.
    static func publish(_ fold: TodayFold, now: Date = .now) {
        guard fold.trainingDayId == TrainingDayId.today(now: now) else { return }
        update { $0.day = WidgetSnapshot.Day(fold: fold) }
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
        profile: any AthleteProfileServing = AthleteProfileClient()
    ) async -> Bool {
        guard let token = try? await Clerk.shared.auth.getToken() else { return false }
        let dayId = TrainingDayId.today()
        async let todayRead = try? today.today(trainingDayId: dayId, token: token)
        async let nutritionRead = try? nutrition.nutrition(trainingDayId: dayId, token: token)
        async let overviewRead = try? body.bodyOverview(token: token)
        async let profileRead = try? profile.athleteProfile(token: token)
        let (payload, food, overview, athlete) = await (todayRead, nutritionRead, overviewRead, profileRead)

        if let payload, case .loaded(let response) = TodayModel.state(from: payload) {
            publish(TodayFoldMapper.map(response))
        }
        if let food { publish(food) }
        if let overview { publish(overview, targetKilograms: athlete?.targetWeightKg) }
        return payload != nil || food != nil || overview != nil
    }
}

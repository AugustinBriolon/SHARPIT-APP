import Foundation
import Testing
@testable import Sharpit

private func fold(day: String = "2026-09-28", sessions: [SessionCardModel]) -> TodayFold {
    TodayFold(
        trainingDayId: day,
        plate: InkPlateModel(
            statusLabel: "Feu vert",
            headline: "Séance clé possible",
            actionLine: "Tiens le seuil.",
            limitingCause: nil,
            confidencePct: 80,
            confidenceLabel: nil,
            packTier: .full,
            estimationGaps: [],
            posture: .push
        ),
        sessions: sessions,
        gauges: [],
        consistency: nil,
        weather: nil
    )
}

private func card(_ id: String, _ kind: V1TodaySessionKind, sport: String = "Course") -> SessionCardModel {
    SessionCardModel(
        id: id,
        kind: kind,
        title: "Seuil \(id)",
        subtitle: nil,
        metrics: [
            V1TodayMetric(label: "Durée", value: "55", unit: "min"),
            V1TodayMetric(label: "Charge", value: "62", unit: ""),
            V1TodayMetric(label: "Intensité", value: "Seuil", unit: ""),
        ],
        sport: sport,
        priority: false
    )
}

/// The widgets say what Résumé says: its verdict, its sessions, their first figures, the night.
@Test func theWidgetsShowRésuméDay() {
    var folded = fold(sessions: [card("a", .done, sport: "Vélo"), card("b", .planned)])
    folded.gauges = [OvernightGaugeModel(key: .sleep, score: "82", caption: "7 h 12")]
    let day = WidgetSnapshot.Day(fold: folded)

    #expect(day.verdict?.status == "Feu vert")
    #expect(day.verdict?.posture == .push)
    #expect(day.sessions.map(\.isDone) == [true, false])
    #expect(day.sessions.first?.sport == .bike)
    #expect(day.sessions.first?.figures == [.init(value: "55", unit: "min"), .init(value: "62", unit: "charge")])
    #expect(day.sleep == WidgetSnapshot.Sleep(score: 82, caption: "7 h 12"))
    // The session still to do comes first; once all are done, the last one.
    #expect(day.leadSession?.id == "b")
}

@Test func onceEverythingIsDoneTheLastSessionLeads() {
    let day = WidgetSnapshot.Day(fold: fold(sessions: [card("a", .done), card("b", .done)]))
    #expect(day.leadSession?.id == "b")
}

/// Yesterday's day and food log are never shown as today's; a weigh-in holds until the next.
@Test func aSectionBelongsToItsDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let snapshot = WidgetSnapshot(
        day: WidgetSnapshot.Day(fold: fold(sessions: [])),
        nutrition: .init(trainingDayId: "2026-09-28", isConnected: true, calories: 1200, calorieGoal: 2000, remaining: 800, macros: [])
    )
    let sameDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23))!
    let nextDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 0, minute: 5))!

    #expect(snapshot.day(on: sameDay, calendar: calendar) != nil)
    #expect(snapshot.nutrition(on: sameDay, calendar: calendar) != nil)
    #expect(snapshot.day(on: nextDay, calendar: calendar) == nil)
    #expect(snapshot.nutrition(on: nextDay, calendar: calendar) == nil)
}

/// Reading the food log does not erase the day: each section is merged into what is there.
@Test func sectionsAreMergedNotReplaced() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let day = WidgetSnapshot.Day(fold: fold(sessions: [card("a", .planned)]))

    #expect(WidgetSnapshotStore.update(in: directory) { $0.day = day })
    #expect(WidgetSnapshotStore.update(in: directory) {
        $0.weight = .init(kilograms: 72.4, measuredAt: Date(timeIntervalSince1970: 1_790_000_000), targetKilograms: 70)
    })
    // The same write twice changes nothing, so the widgets are not reloaded for nothing.
    #expect(!WidgetSnapshotStore.update(in: directory) { $0.day = day })

    let read = try #require(WidgetSnapshotStore.read(from: directory))
    #expect(read.day == day)
    #expect(read.weight?.kilograms == 72.4)

    WidgetSnapshotStore.erase(in: directory)
    #expect(WidgetSnapshotStore.read(from: directory) == nil)
}

/// The food log as its card reads it: the server's budget and remainder, the three macros.
@Test func theFoodLogKeepsTheServersGoals() throws {
    let json = Data(#"""
    { "apiVersion": 1, "trainingDayId": "2026-09-28", "connected": true, "emptyState": null,
      "day": { "calories": 1480, "protein": 112, "carbohydrates": 165, "fat": 48, "fiber": null, "sugar": null,
               "complete": false, "fuelDensity": null, "meals": [],
               "goals": { "calories": { "consumed": 1480, "goal": 2310, "remaining": 830, "pct": 64 },
                          "protein": { "consumed": 112, "goal": 140, "remaining": 28, "pct": 80 },
                          "carbohydrates": { "consumed": 165, "goal": 290, "remaining": 125, "pct": 57 },
                          "fat": { "consumed": 48, "goal": 75, "remaining": 27, "pct": 64 },
                          "exerciseCalories": 310, "calorieBudget": 2310 } } }
    """#.utf8)
    let response = try JSONDecoder().decode(V1NutritionResponse.self, from: json)
    let nutrition = WidgetSnapshot.Nutrition(response: response)

    #expect(nutrition.remaining == 830)
    #expect(nutrition.calorieGoal == 2310)
    #expect(nutrition.macros.map(\.kind) == [.protein, .carbohydrates, .fat])
    #expect(nutrition.macros.first?.goalGrams == 140)
}

@Test func theDialSaysWhatIsLeftOrHowFarPast() {
    var nutrition = WidgetSnapshot.Nutrition(trainingDayId: "2026-09-28", isConnected: true, calories: 1480, calorieGoal: 2310, remaining: 830, macros: [])
    #expect(nutrition.dialFigure == "830")
    #expect(nutrition.dialCaption == "kcal restantes")
    #expect(nutrition.dialScore.map { Int($0.rounded()) } == 64)

    nutrition.calories = 2520
    nutrition.remaining = -210
    #expect(nutrition.dialFigure == "210")
    #expect(nutrition.dialCaption == "kcal au-delà")
    #expect(nutrition.dialScore == 100)
}

/// A change is coloured only against a target: towards it, or not at all.
@Test func aWeighInReadsAgainstItsTarget() {
    let losing = WidgetSnapshot.Weight(kilograms: 72.4, measuredAt: .now, previousKilograms: 73.0, changeWindowDays: 30, targetKilograms: 70)
    #expect(losing.changeLine == "−0,6 kg · 30 j")
    #expect(losing.movesTowardsTarget == true)
    #expect(losing.targetLine == "Encore 2,4 kg · objectif 70 kg")

    let gaining = WidgetSnapshot.Weight(kilograms: 73.6, measuredAt: .now, previousKilograms: 73.0, changeWindowDays: 30, targetKilograms: 70)
    #expect(gaining.movesTowardsTarget == false)

    let noTarget = WidgetSnapshot.Weight(kilograms: 72.4, measuredAt: .now, previousKilograms: 73.0)
    #expect(noTarget.movesTowardsTarget == nil)
    #expect(noTarget.targetLine == nil)
}

// MARK: - Phase 3: volume, regularity, next race

private var parisCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

/// Wednesday 30 September 2026, noon in Paris.
private let wednesday = parisCalendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!

private func trained(_ day: String, _ sport: V1ActivityType, km: Double, minutes: Double) -> WidgetSnapshot.TrainedSession {
    WidgetSnapshot.TrainedSession(dayId: day, sport: sport, distanceMeters: km * 1000, durationSeconds: minutes * 60)
}

@Test func theWeeksVolumeCountsItsSportFromMondayAndComparesWithLastWeekSoFar() {
    let training = WidgetSnapshot.Training(sessions: [
        trained("2026-09-22", .run, km: 8, minutes: 45),   // last Tuesday: counted in last week so far
        trained("2026-09-25", .run, km: 20, minutes: 110), // last Friday: after this weekday, left out
        trained("2026-09-28", .run, km: 10, minutes: 50),  // Monday
        trained("2026-09-28", .bike, km: 40, minutes: 80),
        trained("2026-09-30", .run, km: 12.4, minutes: 60), // today
    ])

    let run = training.week(of: wednesday, sport: .run, calendar: parisCalendar)
    #expect(run.readsInDistance)
    #expect(run.sessionCount == 2)
    #expect(abs(run.distanceKilometers - 22.4) < 0.001)
    #expect(run.lastWeekSoFar == 8)
    #expect(run.days.map(\.initial) == ["L", "M", "M", "J", "V", "S", "D"])
    #expect(run.days[2].isToday)
    #expect(run.days[3].isFuture)
    #expect(run.figureText == "22,4")
    #expect(run.detailLine == "2 séances · 1 h 50")

    // Every sport together reads in time: kilometres of cycling and running add up to nothing.
    let all = training.week(of: wednesday, sport: nil, calendar: parisCalendar)
    #expect(!all.readsInDistance)
    #expect(all.sessionCount == 3)
    #expect(all.figureText == "3 h 10")
}

@Test func theNextRaceIsTheNearestARaceAheadAndCountsDown() {
    let goals = [
        V1Goal(id: "b", title: "10 km", kind: .race, targetDate: wednesday.addingTimeInterval(10 * 86_400), priority: .b),
        V1Goal(id: "a", title: "Ironman 70.3 Nice", kind: .race, targetDate: wednesday.addingTimeInterval(42 * 86_400),
               location: "Nice", priority: .a, raceFormat: "70.3", targetPerformance: "5 h 15"),
        V1Goal(id: "old", title: "Semi", kind: .race, targetDate: wednesday.addingTimeInterval(-5 * 86_400), priority: .a),
    ]
    let goal = WidgetSnapshot.Goal(goals: goals, now: wednesday)

    #expect(goal?.id == "a")
    #expect(goal?.daysLeft(from: wednesday, calendar: parisCalendar) == 42)
    #expect(goal?.countdownCaption(from: wednesday, calendar: parisCalendar) == "42 jours · 6 sem.")
    #expect(goal?.contextLine == "70.3 · Nice · visé 5 h 15")
    #expect(WidgetSnapshot.Goal(goals: [], now: wednesday) == nil)
}

@Test func aRacePassedLeavesTheWidgetEmpty() {
    let snapshot = WidgetSnapshot(goal: WidgetSnapshot.Goal(id: "g", title: "Semi", date: wednesday))

    #expect(snapshot.goal(on: wednesday) != nil)
    #expect(snapshot.goal(on: wednesday.addingTimeInterval(86_400)) == nil)
}

@Test func regularityFollowsResumesStripAndIsTodaysOnly() {
    var consistencyFold = fold(day: "2026-09-28", sessions: [])
    consistencyFold.consistency = V1TodayConsistency(
        days: [V1TodayConsistencyDay(date: "2026-09-28", weekdayLabel: "lun.", dayOfMonth: 28, hasActivity: true, isToday: true, isFuture: false)],
        thisWeekSessionCount: 3
    )
    let regularity = WidgetSnapshot.Regularity(consistency: consistencyFold.consistency, trainingDayId: consistencyFold.trainingDayId)

    #expect(regularity?.weekSessionCount == 3)
    #expect(regularity?.days.first?.hasActivity == true)
    #expect(WidgetSnapshot.Regularity(consistency: nil, trainingDayId: "2026-09-28") == nil)
}

@Test func durationsReadInHoursAndMinutes() {
    #expect(SharpitFigureFormat.duration(minutes: 45) == "45 min")
    #expect(SharpitFigureFormat.duration(minutes: 120) == "2 h")
    #expect(SharpitFigureFormat.duration(minutes: 185) == "3 h 05")
    #expect(SharpitFigureFormat.kilometers(128.4) == "128")
}

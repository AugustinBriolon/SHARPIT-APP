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

/// A strength session done says its work — kilos lifted, exercises — before its time.
@Test func aStrengthSessionShowsItsKilosAndExercises() {
    let done = [
        V1TodayMetric(label: "Durée", value: "45:00", unit: "min"),
        V1TodayMetric(label: "Volume", value: "2160", unit: "kg"),
        V1TodayMetric(label: "Exercices", value: "6", unit: "exos"),
    ]
    #expect(WidgetSnapshot.Day.figures(done, sport: .strength) == [.init(value: "2160", unit: "kg"), .init(value: "6", unit: "exos")])
    // No load recorded, or another sport: the card's first two figures, as before.
    #expect(WidgetSnapshot.Day.figures(Array(done.prefix(1)) + [done[2]], sport: .strength).map(\.unit) == ["min", "exos"])
    #expect(WidgetSnapshot.Day.figures(done, sport: .run).map(\.unit) == ["min", "kg"])
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

    let mapURL = directory.appending(path: WidgetSnapshotStore.lastActivityMapFileName)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: mapURL)
    #expect(FileManager.default.fileExists(atPath: mapURL.path))

    WidgetSnapshotStore.erase(in: directory)
    #expect(WidgetSnapshotStore.read(from: directory) == nil)
    #expect(!FileManager.default.fileExists(atPath: mapURL.path))
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

@Test func aSportRecordedWithoutDistancesReadsInTime() {
    // Rides come without a distance: « 0,0 km » beside 1 h 15 said nothing true.
    let training = WidgetSnapshot.Training(sessions: [
        WidgetSnapshot.TrainedSession(dayId: "2026-09-29", sport: .bike, distanceMeters: nil, durationSeconds: 75 * 60),
    ])
    let bike = training.week(of: wednesday, sport: .bike, calendar: parisCalendar)

    #expect(!bike.readsInDistance)
    #expect(bike.figureText == "1 h 15")
    #expect(bike.days[1].value == 75)
}

@Test func aDialFigureShrinksFromThreeDigits() {
    #expect(DialFigureScale.factor(for: "7") == 1)
    #expect(DialFigureScale.factor(for: "84") == 1)
    #expect(DialFigureScale.factor(for: "100") < 1)
    #expect(DialFigureScale.factor(for: "1 250") < DialFigureScale.factor(for: "100"))
    #expect(DialFigureScale.factor(for: "—") == 1)
}

@Test func theWidgetsCarryTheMorningsRecovery() {
    var folded = fold(sessions: [])
    folded.gauges = [
        OvernightGaugeModel(key: .sleep, score: "82", caption: "7 h 12"),
        OvernightGaugeModel(key: .recovery, score: "71", caption: nil),
    ]
    let day = WidgetSnapshot.Day(fold: folded)
    #expect(day.recovery == WidgetSnapshot.Sleep(score: 71, caption: nil))
    #expect(WidgetSnapshot.Day(fold: fold(sessions: [])).recovery == nil)
}

@Test func theResumeWidgetDrawsOnlyTheRingsTheAthleteKeeps() {
    var day = WidgetSnapshot.Day(fold: fold(sessions: []))
    day.sleep = WidgetSnapshot.Sleep(score: 82, caption: nil)
    day.recovery = WidgetSnapshot.Sleep(score: 140, caption: nil)
    let nutrition = WidgetSnapshot.Nutrition(trainingDayId: "2026-09-28", isConnected: true, calories: 1_155, calorieGoal: 2_310, remaining: 1_155, macros: [])
    let regularity = WidgetSnapshot.Regularity(
        trainingDayId: "2026-09-28",
        days: [
            .init(date: "2026-09-27", weekdayLabel: "dim.", dayOfMonth: 27, hasActivity: true, isToday: false, isFuture: false),
            .init(date: "2026-09-28", weekdayLabel: "lun.", dayOfMonth: 28, hasActivity: false, isToday: true, isFuture: false),
        ],
        weekSessionCount: 1
    )

    let all = WidgetResumeRing.rings(day: day, nutrition: nutrition, regularity: regularity, features: V1FeaturePrefs())
    #expect(all.map(\.kind) == [.sleep, .recovery, .nutrition, .regularity])
    #expect(all.map(\.value) == ["82", "140", "50 %", "1/2"])
    #expect(all.map(\.fraction) == [0.82, 1, 0.5, 0.5])

    var hidden = V1FeaturePrefs()
    hidden.set(.nutrition, false)
    hidden.set(.regularity, false)
    let kept = WidgetResumeRing.rings(day: nil, nutrition: nil, regularity: nil, features: hidden)
    #expect(kept.map(\.kind) == [.sleep, .recovery])
    #expect(kept.map(\.value) == ["—", "—"])
    #expect(kept.allSatisfy { $0.fraction == nil })
}

@Test func theLockScreenReadsTheNightAndTheRecoveryUnderTheVerdict() {
    var day = WidgetSnapshot.Day(fold: fold(sessions: []))
    day.sleep = WidgetSnapshot.Sleep(score: 78, caption: nil)
    day.recovery = WidgetSnapshot.Sleep(score: 61, caption: nil)
    #expect(WidgetResumeRing.lockScreenLine(day: day) == "Sommeil 78 · Récup. 61")
    // A figure not known yet is left out, never shown as a dash on the Lock Screen.
    day.recovery = nil
    #expect(WidgetResumeRing.lockScreenLine(day: day) == "Sommeil 78")
    day.sleep = nil
    #expect(WidgetResumeRing.lockScreenLine(day: day) == nil)
    #expect(WidgetResumeRing.lockScreenLine(day: nil) == nil)
}

// MARK: - Dernière activité

@Test func aRouteIsFittedToAUnitSquareNorthUpWithItsProportions() throws {
    // Twice as tall as wide once longitude is shrunk by the latitude (cos 60° = 0.5).
    let fitted = try #require(WidgetRoute.fit([[60.0, 10.0], [60.2, 10.0], [60.2, 10.2]]))
    #expect(fitted.count == 3)
    // South-west start: bottom of the square; the route is centred across its narrow side.
    #expect(abs(fitted[0][1] - 1) < 1e-9)
    #expect(abs(fitted[1][1]) < 1e-9)
    #expect(abs(fitted[0][0] - 0.25) < 0.01)
    #expect(abs(fitted[2][0] - 0.75) < 0.01)
    #expect(fitted.allSatisfy { (0...1).contains($0[0]) && (0...1).contains($0[1]) })
}

@Test func aRouteWithNothingToDrawIsNoRoute() {
    #expect(WidgetRoute.fit([]) == nil)
    #expect(WidgetRoute.fit([[48.1, 2.3]]) == nil)
    // A session that never left its start, and coordinates that are not ones.
    #expect(WidgetRoute.fit([[48.1, 2.3], [48.1, 2.3]]) == nil)
    #expect(WidgetRoute.fit([[480, 2.3], [48.1, 900], [48.1]]) == nil)
}

@Test func aLongRouteIsThinnedAndKeepsItsEnd() throws {
    let long = (0..<1_000).map { [48.0 + Double($0) / 10_000, 2.0 + Double($0) / 20_000] }
    let fitted = try #require(WidgetRoute.fit(long, maxPoints: 100))
    #expect(fitted.count <= 101)
    #expect(abs(fitted[fitted.count - 1][1]) < 1e-9)
}

@Test func theLatestActivityNamesDistanceTimeThenPaceOrLoad() throws {
    let run = WidgetSnapshot.LatestActivity(
        activity: V1ActivityListItem(id: "a1", type: .run, date: .now, title: "Footing", duration: 3_000, distanceM: 10_000),
        route: nil
    )
    #expect(run.stats == [
        .init(label: "Distance", value: "10,0", unit: "km"),
        .init(label: "Durée", value: "50:00", unit: "min"),
        .init(label: "Allure", value: "5:00", unit: "/km"),
    ])
    #expect(run.link.path == "/activity/a1")

    let ride = WidgetSnapshot.LatestActivity(activity: V1ActivityListItem(type: .bike, date: .now, duration: 3_600, distanceM: 30_000), route: nil)
    #expect(ride.stats.last == .init(label: "Vitesse", value: "30,0", unit: "km/h"))
    #expect(ride.title == V1ActivityType.bike.label)

    // Strength: no distance, so the time leads and the load follows.
    let strength = WidgetSnapshot.LatestActivity(activity: V1ActivityListItem(type: .strength, date: .now, duration: 2_700, load: 41.6), route: nil)
    #expect(strength.stats == [.init(label: "Durée", value: "45:00", unit: "min"), .init(label: "Charge", value: "42", unit: "")])

    // Past the hour the clock gains its hours and says so.
    // Strength with its sets: the kilos lifted and the exercises take the load's place.
    let lifted = try JSONDecoder().decode(V1ActivityListItem.self, from: Data(#"""
    {"id":"s","type":"STRENGTH","date":"2026-11-16T18:00:00.000Z","duration":2700,"load":41.6,
     "strengthSets":[{"exercise":"Squat","sets":3,"reps":10,"weightKg":60},{"exercise":"Squat","sets":1,"reps":5,"weightKg":null},
                     {"exercise":"Press","sets":2,"reps":8,"weightKg":22.5}]}
    """#.utf8))
    #expect(WidgetSnapshot.LatestActivity(activity: lifted, route: nil).stats.map(\.label) == ["Durée", "Volume", "Exercices"])
    #expect(WidgetSnapshot.LatestActivity(activity: lifted, route: nil).stats.map(\.unit) == ["min", "kg", ""])
    #expect(WidgetSnapshot.LatestActivity(activity: lifted, route: nil).stats.last?.value == "2")
    let long = WidgetSnapshot.LatestActivity(activity: V1ActivityListItem(type: .run, date: .now, duration: 5_530, distanceM: 18_400), route: nil)
    #expect(long.stats[1] == .init(label: "Durée", value: "1:32:10", unit: "h"))
}

@Test func aMapIsShownOnlyForTheSessionItWasDrawnFor() throws {
    var activity = WidgetSnapshot.LatestActivity(id: "new", title: "t", sport: .run, date: .now, stats: [], route: nil)
    #expect(!activity.hasMap)
    // The maps on disk are still the previous session's.
    activity.mapActivityId = "old"
    #expect(!activity.hasMap)
    activity.mapActivityId = "new"
    #expect(activity.hasMap)

    // Signing out takes the maps with the snapshot: they say where the athlete trains.
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let urls = WidgetSnapshotStore.LatestActivityMap.allCases.flatMap { map in
        [false, true].compactMap { WidgetSnapshotStore.latestActivityMapURL(map, dark: $0, in: directory) }
    }
    #expect(Set(urls).count == 4)
    for url in urls { try Data([0x89]).write(to: url) }
    WidgetSnapshotStore.erase(in: directory)
    #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
}

@Test func theLatestActivitySaysItsDayAndSport() {
    let calendar = Calendar.current
    let now = Date.now
    func eyebrow(daysAgo: Int) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return LatestActivityReadout.eyebrow(
            WidgetSnapshot.LatestActivity(id: "a", title: "t", sport: .run, date: date, stats: [], route: nil), now: now
        )
    }
    #expect(eyebrow(daysAgo: 0) == "Aujourd'hui · \(V1ActivityType.run.label)")
    #expect(eyebrow(daysAgo: 1) == "Hier · \(V1ActivityType.run.label)")
    #expect(!eyebrow(daysAgo: 3).hasPrefix("Hier"))
}

@Test func aSnapshotAnOlderBuildWroteStillDecodesWithItsOldLastActivity() throws {
    // « lastActivity » had another shape: it must stay an unknown key, not blank every widget.
    let old = #"{"lastActivity":{"id":"x","distanceValue":"5,2"},"isPro":true}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(old.utf8))
    #expect(snapshot.latestActivity == nil)
    #expect(snapshot.isPro == true)
}

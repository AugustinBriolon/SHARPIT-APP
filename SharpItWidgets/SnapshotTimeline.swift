import WidgetKit

/// One entry: what the app last wrote, read as of `date`.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Today's day, or nil when the one on disk is another day's: yesterday is never today.
    var day: WidgetSnapshot.Day? { snapshot?.day(on: date) }
    /// Today's food log, under the same rule.
    var nutrition: WidgetSnapshot.Nutrition? { snapshot?.nutrition(on: date) }
    /// The latest weigh-in, whatever its day — a weight holds until the next one.
    var weight: WidgetSnapshot.Weight? { snapshot?.weight }
    /// Résumé's regularity strip, today's only.
    var regularity: WidgetSnapshot.Regularity? { snapshot?.regularity(on: date) }
    /// The last two weeks recorded, read for whatever week `date` falls in.
    var training: WidgetSnapshot.Training? { snapshot?.training }
    /// The next race while it is ahead.
    var goal: WidgetSnapshot.Goal? { snapshot?.goal(on: date) }
    /// The parts of SharpIt the athlete uses — all on until the app said otherwise.
    var features: V1FeaturePrefs { snapshot?.features ?? V1FeaturePrefs() }
    /// Whether the extra widgets show; true until the app said otherwise.
    var unlocksExtraWidgets: Bool { snapshot?.isPro ?? true }

    /// A free widget's tap: its page, or Pages et widgets when its feature is hidden.
    func link(_ path: String, feature: SharpitFeature? = nil) -> URL {
        WidgetSnapshot.link(path, feature: feature, features: features)
    }

    /// An extra (Pro) widget's tap: its page, else SharpIt Pro while it shows its lock.
    func extraLink(_ path: String, feature: SharpitFeature? = nil) -> URL {
        WidgetSnapshot.link(path, unlocked: unlocksExtraWidgets, feature: feature, features: features)
    }
}

/// Reads the snapshot the app wrote. The app reloads the timelines when it writes a new one;
/// the only change the widget makes on its own is the day turning, at midnight.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshotStore.read()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.read()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        completion(Timeline(
            entries: [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)],
            policy: .after(midnight)
        ))
    }
}

extension WidgetSnapshot {
    /// The gallery's example.
    static let preview = WidgetSnapshot(
        day: Day(
            trainingDayId: dayId(.now),
            verdict: Verdict(status: "Feu vert", headline: "Séance clé possible", action: "Tiens le seuil, pas plus.", posture: .push),
            sessions: [
                Session(id: "a1", isDone: true, title: "Renfo gainage", sport: .strength, figures: [Figure(value: "30", unit: "min")]),
                Session(id: "p1", isDone: false, title: "Seuil 3 × 8 min", sport: .run, plannedSessionId: "p1",
                        figures: [Figure(value: "55", unit: "min"), Figure(value: "62", unit: "charge")]),
            ],
            sleep: Sleep(score: 82, caption: "7 h 12")
        ),
        nutrition: Nutrition(
            trainingDayId: dayId(.now),
            isConnected: true,
            calories: 1_480,
            calorieGoal: 2_310,
            remaining: 830,
            macros: [
                Macro(kind: .protein, grams: 112, goalGrams: 140),
                Macro(kind: .carbohydrates, grams: 165, goalGrams: 290),
                Macro(kind: .fat, grams: 48, goalGrams: 75),
            ]
        ),
        weight: Weight(kilograms: 72.4, measuredAt: .now, previousKilograms: 73.0, changeWindowDays: 30, targetKilograms: 70),
        regularity: Regularity(
            trainingDayId: dayId(.now),
            days: (-6...1).map { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                return RegularityDay(
                    date: dayId(day),
                    weekdayLabel: day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "fr_FR"))),
                    dayOfMonth: Calendar.current.component(.day, from: day),
                    hasActivity: [-6, -5, -3, -1, 0].contains(offset),
                    isToday: offset == 0,
                    isFuture: offset > 0
                )
            },
            weekSessionCount: 4
        ),
        training: Training(sessions: [(-9, 8_200.0, 2_700.0), (-7, 12_400, 4_100), (-3, 10_000, 3_300), (-2, 6_100, 2_100), (0, 14_300, 4_500)]
            .map { offset, meters, seconds in
                TrainedSession(
                    dayId: dayId(Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now),
                    sport: .run, distanceMeters: meters, durationSeconds: seconds
                )
            }),
        goal: Goal(
            id: "g1", title: "Ironman 70.3 Nice", date: Calendar.current.date(byAdding: .day, value: 42, to: .now) ?? .now,
            location: "Nice", format: "70.3", targetPerformance: "5 h 15"
        )
    )
}

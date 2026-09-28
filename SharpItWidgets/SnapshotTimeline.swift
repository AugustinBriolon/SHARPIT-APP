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
        weight: Weight(kilograms: 72.4, measuredAt: .now, previousKilograms: 73.0, changeWindowDays: 30, targetKilograms: 70)
    )
}

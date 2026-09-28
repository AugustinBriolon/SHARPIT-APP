import WidgetKit

/// One entry: the day the app last wrote, read as of `date`.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Today's snapshot, or nil when the one on disk is another day's: yesterday's session is
    /// never shown as today's.
    var today: WidgetSnapshot? {
        guard let snapshot, snapshot.isFor(day: date) else { return nil }
        return snapshot
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
        trainingDayId: dayId(.now),
        writtenAt: .now,
        verdict: Verdict(status: "Feu vert", headline: "Séance clé possible", action: "Tiens le seuil, pas plus.", posture: .push),
        sessions: [Session(id: "preview", isDone: false, title: "Seuil 3 × 8 min", sport: .run, figures: ["55 min", "62 charge"])]
    )
}

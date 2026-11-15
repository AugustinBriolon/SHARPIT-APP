import Foundation

/// The session being logged by hand, kept on the iPhone while its form is closed without
/// saving: reopened, the form is where the athlete left it. One draft at a time, for a new
/// session only — an edit of a recorded one starts from the record.
///
/// In Application Support, protected and out of backups like the morning check-in's draft:
/// it holds training data. Cleared once saved and on sign-out (`LocalAccountData.erase`).
nonisolated struct ActivityDraftLocalStore: Sendable {
    struct Exercise: Codable, Equatable, Sendable {
        var name: String
        var sets: Int
        var reps: Int
        var weightKg: Double?
        var durationSec: Int?
        var notes: String?
    }

    struct Snapshot: Codable, Equatable, Sendable {
        var sport: String
        var date: Date
        var title: String
        var durationMin: Int?
        var distanceText: String
        var elevationText: String
        var avgHrText: String
        var rpe: Int?
        var feeling: Int?
        var notes: String
        var exercises: [Exercise]
    }

    let fileURL: URL

    static let shared = ActivityDraftLocalStore(
        fileURL: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appending(path: "ActivityDraftLocal.json")
    )

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = fileURL
        try? url.setResourceValues(values)
    }

    func erase() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension ActivityDraft {
    /// The draft as it is kept between two openings of the form.
    @MainActor
    var snapshot: ActivityDraftLocalStore.Snapshot {
        ActivityDraftLocalStore.Snapshot(
            sport: sport.rawValue, date: date, title: title, durationMin: durationMin,
            distanceText: distanceText, elevationText: elevationText, avgHrText: avgHrText,
            rpe: rpe, feeling: feeling?.rawValue, notes: notes,
            exercises: exercises.filter(\.isNamed).map {
                .init(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg, durationSec: $0.durationSec, notes: $0.notes)
            }
        )
    }

    /// A kept draft back in the form; nil when its sport is no longer one logged by hand.
    @MainActor
    init?(snapshot: ActivityDraftLocalStore.Snapshot) {
        guard let sport = V1ActivityType(rawValue: snapshot.sport), Self.sports.contains(sport) else { return nil }
        self.init(date: snapshot.date)
        self.sport = sport
        title = snapshot.title
        durationMin = snapshot.durationMin
        distanceText = snapshot.distanceText
        elevationText = snapshot.elevationText
        avgHrText = snapshot.avgHrText
        rpe = snapshot.rpe
        feeling = snapshot.feeling.flatMap(SessionFeeling.init(rawValue:))
        notes = snapshot.notes
        exercises = snapshot.exercises.map {
            StrengthExerciseDraft(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg, durationSec: $0.durationSec, notes: $0.notes)
        }
    }
}

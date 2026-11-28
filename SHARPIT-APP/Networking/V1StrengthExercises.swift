import Foundation
import Observation

/// `/api/v1/strength-exercises` — every exercise the athlete has logged, with what they last
/// did on it and their best. Read from the sets the server already keeps: the app proposes them
/// as a new set's defaults and as the first results of its exercise search.
nonisolated struct V1StrengthExercise: Decodable, Equatable, Sendable, Identifiable {
    struct Last: Decodable, Equatable, Sendable {
        let date: String
        let sets: Int
        let reps: Int
        let weightKg: Double?
        let durationSec: Int?
    }

    struct Best: Decodable, Equatable, Sendable {
        var weightKg: Double? = nil
        var reps: Int? = nil
        var durationSec: Int? = nil
    }

    let name: String
    var catalogId: String? = nil
    /// The note last written on it — for an exercise of the athlete's own, the zone it works.
    var note: String? = nil
    /// The standing note the athlete keeps on it (SHARPIT ADR-146), shown each time it comes back.
    var athleteNote: String? = nil
    var sessions: Int = 1
    let last: Last
    var best = Best()

    var id: String { StrengthExerciseKey.of(name) }
}

nonisolated enum StrengthExerciseKey {
    /// « Développé couché » and « developpe  couche » are one exercise, as the server reads them.
    static func of(_ name: String) -> String { ExerciseMediaCatalog.normalize(name) }
}

nonisolated struct V1StrengthExercisesResponse: Decodable, Sendable {
    let exercises: [V1StrengthExercise]
}

/// `/api/v1/strength-exercises/progression?name=` — one day an exercise was done.
nonisolated struct V1ExerciseSession: Decodable, Equatable, Sendable, Identifiable {
    struct Block: Decodable, Equatable, Sendable {
        let sets: Int
        let reps: Int
        let weightKg: Double?
        let durationSec: Int?
    }

    /// `yyyy-MM-dd`, the day it was done.
    let date: String
    let blocks: [Block]
    let bestWeightKg: Double?
    let bestDurationSec: Int?
    let volumeKg: Double

    var id: String { date }
}

nonisolated struct V1ExerciseProgressionResponse: Decodable, Sendable {
    let sessions: [V1ExerciseSession]
}

nonisolated protocol StrengthExerciseServing: Sendable {
    func exercises(token: String) async throws -> [V1StrengthExercise]
    func saveNote(name: String, note: String, token: String) async throws
    func progression(name: String, token: String) async throws -> [V1ExerciseSession]
}

actor StrengthExerciseClient: StrengthExerciseServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func exercises(token: String) async throws -> [V1StrengthExercise] {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/strength-exercises"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.sharpitData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
        return try JSONDecoder().decode(V1StrengthExercisesResponse.self, from: data).exercises
    }

    func progression(name: String, token: String) async throws -> [V1ExerciseSession] {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/strength-exercises/progression"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components?.url else { throw SharpitAPIError.server }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.sharpitData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
        return try JSONDecoder().decode(V1ExerciseProgressionResponse.self, from: data).sessions
    }

    /// Writes the standing note on one exercise; an empty note removes it.
    func saveNote(name: String, note: String, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/strength-exercises"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "note": note])
        let (_, response) = try await session.sharpitData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
    }
}

/// The athlete's exercises, read once and kept for the launch: a session that starts and the
/// exercise search both ask for them, and a save reads them again.
@Observable
@MainActor
final class StrengthLibraryStore {
    static let shared = StrengthLibraryStore()

    private(set) var exercises: [V1StrengthExercise] = []
    /// Standing notes by exercise key — also those on an exercise not saved yet, written this launch.
    private(set) var athleteNotes: [String: String] = [:]
    private var isLoaded = false
    private let client: any StrengthExerciseServing

    init(client: any StrengthExerciseServing = StrengthExerciseClient()) {
        self.client = client
    }

    /// The exercises as last read; asks the server the first time, and again when `fresh`.
    /// A failed read keeps what was known: defaults are a comfort, never a blocking state.
    @discardableResult
    func load(tokenProvider: () async throws -> String, fresh: Bool = false) async -> [V1StrengthExercise] {
        guard fresh || !isLoaded else { return exercises }
        if let token = try? await tokenProvider(), let read = try? await client.exercises(token: token) {
            exercises = read
            for exercise in read { athleteNotes[exercise.id] = exercise.athleteNote }
            isLoaded = true
        }
        return exercises
    }

    func history(of name: String) -> V1StrengthExercise? {
        let key = StrengthExerciseKey.of(name)
        return exercises.first { $0.id == key }
    }

    func athleteNote(of name: String) -> String? {
        athleteNotes[StrengthExerciseKey.of(name)]
    }

    /// The days one exercise was done, oldest first; a failure is thrown for the page to say.
    ///
    /// The server reads the days under the name exactly as folded on its side, which keeps
    /// punctuation: « Traction (lestée) » and « Traction lestée » are two exercises there and one
    /// here. The page showed nothing for an exercise whose « Dernière fois » it had just shown
    /// (the athlete's remark, 2026-11-28), so it asks under every name the history gathers here.
    func progression(of name: String, tokenProvider: () async throws -> String) async throws -> [V1ExerciseSession] {
        let token = try await tokenProvider()
        var sessions: [V1ExerciseSession] = []
        for spelling in StrengthProgressionMerge.spellings(of: name, in: exercises) {
            sessions += try await client.progression(name: spelling, token: token)
        }
        return StrengthProgressionMerge.merged(sessions)
    }

    /// Saves the note, then keeps it here so the page shows it at once; a failure is thrown.
    func saveNote(name: String, note: String, tokenProvider: () async throws -> String) async throws {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.saveNote(name: name, note: text, token: try await tokenProvider())
        let key = StrengthExerciseKey.of(name)
        athleteNotes[key] = text.isEmpty ? nil : text
        if let index = exercises.firstIndex(where: { $0.id == key }) {
            exercises[index].athleteNote = athleteNotes[key]
        }
    }
}

/// One exercise's days read under each of its spellings, folded back into one list.
enum StrengthProgressionMerge {
    /// The name asked first, then every other name the athlete logged that folds to the same key.
    static func spellings(of name: String, in library: [V1StrengthExercise]) -> [String] {
        let key = StrengthExerciseKey.of(name)
        var seen = Set([serverKey(name)])
        var names = [name]
        for exercise in library where exercise.id == key && seen.insert(serverKey(exercise.name)).inserted {
            names.append(exercise.name)
        }
        return names
    }

    /// The server's `exerciseKey`: accents and case folded, spaces collapsed, punctuation kept.
    static func serverKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// One session a day, oldest first: the blocks side by side, the best kept, the volume added.
    static func merged(_ sessions: [V1ExerciseSession]) -> [V1ExerciseSession] {
        var byDay: [String: V1ExerciseSession] = [:]
        for session in sessions {
            guard let kept = byDay[session.date] else {
                byDay[session.date] = session
                continue
            }
            byDay[session.date] = V1ExerciseSession(
                date: session.date,
                blocks: kept.blocks + session.blocks,
                bestWeightKg: [kept.bestWeightKg, session.bestWeightKg].compactMap { $0 }.max(),
                bestDurationSec: [kept.bestDurationSec, session.bestDurationSec].compactMap { $0 }.max(),
                volumeKg: kept.volumeKg + session.volumeKg
            )
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}

/// How an exercise's history reads beside it.
enum StrengthHistoryReadout {
    /// « Dernière fois 4 × 8 · 60 kg », or « 3 × 45 s » for a hold.
    static func last(_ exercise: V1StrengthExercise) -> String {
        String(localized: "Dernière fois \(block(sets: exercise.last.sets, reps: exercise.last.reps, weightKg: exercise.last.weightKg, durationSec: exercise.last.durationSec))")
    }

    /// « Meilleur 70 kg × 5 », « Meilleur 1 min 30 s »; nil when nothing was ever loaded or timed.
    static func best(_ exercise: V1StrengthExercise) -> String? {
        bestFigure(exercise).map { String(localized: "Meilleur \($0)") }
    }

    /// The same without its name, for a column that carries it: « 3 × 12 · 8 kg ».
    static func lastFigure(_ exercise: V1StrengthExercise) -> String {
        block(sets: exercise.last.sets, reps: exercise.last.reps, weightKg: exercise.last.weightKg, durationSec: exercise.last.durationSec)
    }

    /// « 70 kg × 5 », « 1 min 30 s ».
    static func bestFigure(_ exercise: V1StrengthExercise) -> String? {
        if let kg = exercise.best.weightKg, kg > 0 {
            let reps = exercise.best.reps.map { " × \($0)" } ?? ""
            return "\(GuidedStrengthSetTarget.kilograms(kg))\(reps)"
        }
        if let seconds = exercise.best.durationSec, seconds > 0 {
            return PlannedSessionFormat.durationSeconds(seconds)
        }
        return nil
    }

    /// « Dernière fois 4 × 8 », the sets without their load: what a list of exercises says beside
    /// each one. The load belongs to the exercise's own sheet (the athlete's call, 2026-11-28).
    static func lastSets(_ exercise: V1StrengthExercise) -> String {
        let block = block(sets: exercise.last.sets, reps: exercise.last.reps, weightKg: nil, durationSec: exercise.last.durationSec)
        return String(localized: "Dernière fois \(block)")
    }

    static func line(_ exercise: V1StrengthExercise) -> String {
        [last(exercise), best(exercise)].compactMap { $0 }.joined(separator: " · ")
    }

    static func block(sets: Int, reps: Int, weightKg: Double?, durationSec: Int?) -> String {
        if let durationSec, durationSec > 0, reps <= 1 {
            return "\(sets) × \(PlannedSessionFormat.durationSeconds(durationSec))"
        }
        let base = "\(sets) × \(reps)"
        guard let weightKg, weightKg > 0 else { return base }
        return "\(base) · \(GuidedStrengthSetTarget.kilograms(weightKg))"
    }
}

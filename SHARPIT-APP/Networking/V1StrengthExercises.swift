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

nonisolated protocol StrengthExerciseServing: Sendable {
    func exercises(token: String) async throws -> [V1StrengthExercise]
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
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SharpitAPIError.unauthorized }
        guard (200...299).contains(status) else { throw SharpitAPIError.server }
        return try JSONDecoder().decode(V1StrengthExercisesResponse.self, from: data).exercises
    }
}

/// The athlete's exercises, read once and kept for the launch: a session that starts and the
/// exercise search both ask for them, and a save reads them again.
@Observable
@MainActor
final class StrengthLibraryStore {
    static let shared = StrengthLibraryStore()

    private(set) var exercises: [V1StrengthExercise] = []
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
            isLoaded = true
        }
        return exercises
    }

    func history(of name: String) -> V1StrengthExercise? {
        let key = StrengthExerciseKey.of(name)
        return exercises.first { $0.id == key }
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

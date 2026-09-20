import Foundation
import Observation

/// The morning check-in: four scales and an optional note, asked one at a time.
///
/// Mood is not a standalone field. The web asks the whole start-of-day ressenti in one
/// pass because the four dimensions are read together by recovery, and writes the mood's
/// label onto the day journal only as an echo of what was answered here.
@MainActor
@Observable
final class MorningWellnessStore {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var alreadyCompleted = false
    var step = 0
    var notes = ""
    private(set) var picks: [WellnessDimension: WellnessScore] = [:]

    private let client: any WellnessServing
    private let tokenProvider: () async throws -> String
    private let trainingDayId: String

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String = TrainingDayId.today()
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.trainingDayId = trainingDayId
    }

    /// Steps are the four scales plus the note.
    ///
    /// `nonisolated`, because a view body reads it and SwiftUI evaluates bodies on its
    /// own renderer thread: a main-actor static would assert the main queue the first
    /// time it is initialised there.
    nonisolated static let noteStep = WellnessDimension.allCases.count
    nonisolated var stepCount: Int { Self.noteStep + 1 }

    var dimension: WellnessDimension? {
        step < WellnessDimension.allCases.count ? WellnessDimension.allCases[step] : nil
    }

    var isOnNoteStep: Bool { step == Self.noteStep }

    /// The note is optional; every scale before it is not.
    var canGoForward: Bool {
        guard let dimension else { return true }
        return picks[dimension] != nil
    }

    var canSubmit: Bool {
        WellnessDimension.allCases.allSatisfy { picks[$0] != nil }
    }

    func pick(_ score: WellnessScore, for dimension: WellnessDimension) {
        picks[dimension] = score
        SharpitHaptics.play(.light)
    }

    func load() async {
        phase = .loading
        do {
            let token = try await tokenProvider()
            let checkin = try await client.wellnessCheckin(
                trainingDayId: trainingDayId,
                token: token
            )
            alreadyCompleted = checkin.completed
            if let entry = checkin.entry {
                hydrate(from: entry)
            }
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(Self.message(for: error, fallback: "Ton ressenti n'a pas pu être chargé."))
        }
    }

    private func hydrate(from entry: V1WellnessEntry) {
        picks[.mood] = WellnessScore(rawValue: entry.mood)
        picks[.energy] = WellnessScore(rawValue: entry.energyLevel)
        picks[.soreness] = WellnessSoreness.ui(fromDomain: entry.perceivedSoreness)
        picks[.stress] = WellnessScore(rawValue: entry.stressLevel)
        notes = entry.notes ?? ""
    }

    /// The mood's label on success, so the journal can echo it the way the web does.
    func submit() async -> String? {
        guard
            let mood = picks[.mood],
            let energy = picks[.energy],
            let soreness = picks[.soreness],
            let stress = picks[.stress]
        else { return nil }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = V1WellnessEntry(
            mood: mood.rawValue,
            energyLevel: energy.rawValue,
            perceivedSoreness: WellnessSoreness.domain(fromUI: soreness),
            stressLevel: stress.rawValue,
            notes: trimmed.isEmpty ? nil : String(trimmed.prefix(500))
        )

        phase = .saving
        do {
            let token = try await tokenProvider()
            try await client.submitWellnessCheckin(
                entry,
                trainingDayId: trainingDayId,
                token: token
            )
            phase = .ready
            alreadyCompleted = true
            SharpitHaptics.play(.success)
            return WellnessDimension.mood.label(for: mood)
        } catch {
            phase = .failed(Self.message(for: error, fallback: "Ton ressenti n'a pas pu être enregistré."))
            return nil
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return fallback
    }
}

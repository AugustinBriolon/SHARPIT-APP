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
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var alreadyCompleted = false
    var step = 0
    var notes = ""
    private(set) var picks: [WellnessDimension: WellnessScore] = [:]

    private let client: any WellnessServing
    private let tokenProvider: () async throws -> String
    @ObservationIgnored private var write: Task<Void, Never>?
    private let trainingDayId: String
    /// Once the server holds the check-in: it has read the night against today's session by then.
    private let onSaved: @MainActor () -> Void

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String = TrainingDayId.today(),
        onSaved: @escaping @MainActor () -> Void = {}
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.trainingDayId = trainingDayId
        self.onSaved = onSaved
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

    /// Waits for the check-in sent last — for a test.
    func settle() async {
        await write?.value
    }

    /// The mood's label once every dimension is picked, so the journal can echo it the way the
    /// web does. The write goes out behind it: the sheet never waits on the server.
    func submit() -> String? {
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

        alreadyCompleted = true
        // Sent behind the closing sheet, retried on a transient failure; the sheet is gone by
        // the time a write fails for good, so that is said in the app's toast.
        write = Task { [client, tokenProvider, trainingDayId, onSaved] in
            do {
                try await SharpitRetry.run {
                    try await client.submitWellnessCheckin(
                        entry,
                        trainingDayId: trainingDayId,
                        token: try await tokenProvider()
                    )
                }
                onSaved()
            } catch {
                SharpitWriteFailures.shared.report(
                    Self.message(for: error, fallback: "Ton ressenti n'a pas pu être enregistré.")
                )
            }
        }
        return WellnessDimension.mood.label(for: mood)
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let apiError = error as? SharpitAPIError, apiError == .unauthorized {
            return "Session expirée. Reconnecte-toi."
        }
        return fallback
    }
}

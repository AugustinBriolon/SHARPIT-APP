import Foundation
import Observation

/// Journal → Analyses: what the athlete's habits go with, read from `/api/v1/journal/analyses`.
///
/// Owned by `JournalView`, so reopening the page shows the last reading at once and refreshes it
/// quietly — a refresh that fails keeps what is on screen.
@MainActor
@Observable
final class JournalAnalysesStore {
    enum Phase: Equatable {
        case loading
        case loaded(V1JournalAnalyses)
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var isRefreshing = false

    private let client: any JournalAnalysesServing
    private let tokenProvider: () async throws -> String

    init(client: any JournalAnalysesServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var analyses: V1JournalAnalyses? {
        if case .loaded(let analyses) = phase { return analyses }
        return nil
    }

    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let token = try await tokenProvider()
            let fresh = try await client.journalAnalyses(token: token)
            if analyses != fresh { phase = .loaded(fresh) }
        } catch is CancellationError {
            return
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if analyses == nil {
                phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Les analyses du journal"))
            }
        }
    }
}

/// How the analyses read where the server sends numbers rather than words.
nonisolated enum JournalAnalysesReadout {
    /// « 4 / 7 jours · encore 3 », as the web's progress line.
    static func progress(_ analyses: V1JournalAnalyses) -> String {
        let count = "\(min(analyses.daysWithSignal, analyses.minDays)) / \(analyses.minDays) jours"
        return analyses.remainingDays > 0 ? "\(count) · encore \(analyses.remainingDays)" : count
    }

    /// « 7 jours avec · 22 sans ».
    static func sample(_ row: V1JournalAnalysesRow) -> String {
        "\(days(row.nYes)) avec · \(row.nNo) sans"
    }

    static func days(_ count: Int) -> String {
        count == 1 ? "1 jour" : "\(count) jours"
    }
}

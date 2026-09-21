import Foundation
import Observation

/// The weigh-ins behind Corps: the latest one, and what it moved from.
@MainActor
@Observable
final class BodyCompositionStore {
    enum Phase: Equatable {
        case idle
        case loading
        /// Loaded and empty — no scale has ever written. Distinct from a failure, because
        /// there is nothing to retry.
        case empty
        case loaded
        case failed(String)
        case unauthorized
    }

    /// Ninety days: long enough for a trend to mean something, short enough that a phone
    /// renders the list without paging.
    static let windowDays = 90

    private(set) var phase: Phase = .idle
    private(set) var measurements: [V1BodyMeasurement] = []

    private let client: any BodyCompositionServing
    private let tokenProvider: () async throws -> String

    init(client: any BodyCompositionServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    /// Newest first, as the server orders them.
    var latest: V1BodyMeasurement? { measurements.first }

    /// The weigh-in a week or more before the latest, to read the current one against.
    ///
    /// Not simply the previous row: two weigh-ins on consecutive mornings differ by water,
    /// not by composition, and calling that a trend would invent a signal.
    var reference: V1BodyMeasurement? {
        guard let latest else { return nil }
        let cutoff = latest.measuredAt.addingTimeInterval(-7 * 24 * 3600)
        return measurements.first { $0.measuredAt <= cutoff }
    }

    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let token = try await tokenProvider()
            measurements = try await client.bodyComposition(days: Self.windowDays, token: token)
            phase = measurements.isEmpty ? .empty : .loaded
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            phase = .failed("Lecture de tes mesures impossible.")
        }
    }
}

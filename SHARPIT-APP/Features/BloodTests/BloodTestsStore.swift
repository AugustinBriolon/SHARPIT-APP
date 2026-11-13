import Foundation
import Observation

/// The athlete's blood tests, read from `/api/v1/blood-tests`: the history, each test, each marker.
@MainActor
@Observable
final class BloodTestsStore {
    enum Phase: Equatable {
        case loading, loaded, failed(String), unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var tests: [V1BloodTest] = []

    private let client: any BloodTestServing
    private let tokenProvider: () async throws -> String

    init(client: any BloodTestServing = BloodTestClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        do {
            let fresh = try await SharpitRetry.run {
                try await client.bloodTests(token: try await tokenProvider())
            }
            tests = fresh
            phase = .loaded
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if phase == .loaded {
                SharpitWriteFailures.shared.reportStaleRead(String(localized: "Analyses non actualisées."))
            } else {
                phase = .failed(String(localized: "Lecture de tes analyses impossible."))
            }
        }
    }

    func test(_ id: String) -> V1BloodTest? {
        tests.first { $0.id == id }
    }

    var followedMarkers: [BloodMarkerHistory] {
        BloodMarkerHistory.followed(in: tests)
    }

    func history(of markerKey: String) -> BloodMarkerHistory {
        BloodMarkerHistory(markerKey: markerKey, tests: tests)
    }

    /// Gone on the tap; put back and said when the server refuses for good.
    func delete(_ id: String) async {
        guard let index = tests.firstIndex(where: { $0.id == id }) else { return }
        let removed = tests.remove(at: index)
        do {
            try await SharpitRetry.run {
                try await client.deleteBloodTest(id: id, token: try await tokenProvider())
            }
        } catch {
            tests.insert(removed, at: min(index, tests.count))
            SharpitWriteFailures.shared.report(String(localized: "Suppression de l'analyse impossible."))
        }
    }
}

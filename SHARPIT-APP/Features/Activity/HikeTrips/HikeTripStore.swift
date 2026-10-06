import Foundation
import Observation

/// The athlete's séjours and the hikes they can still gather — Activité › Séjours, the web's
/// `/activite/sejours`.
///
/// A creation and an added stage wait for the server: the new trip needs its id, and a stage's
/// figures come back with it. A rename, a removed stage and a deletion show on the tap and go out
/// behind through `SharpitRetry`; one refused for good is put back and said in the app's toast
/// (`SharpitWriteFailures`), since the page may be gone by then.
@MainActor
@Observable
final class HikeTripStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var trips: [V1HikeTrip] = []
    /// Every hike in the history, newest first — the candidates for a séjour.
    private(set) var hikes: [V1ActivityListItem] = []
    private(set) var isSaving = false
    /// What a write that waited was refused for, said in the form that asked it.
    var saveError: String?

    private let client: any HikeTripServing
    private let activities: any ActivityServing
    private let tokenProvider: () async throws -> String

    init(
        client: any HikeTripServing = HikeTripClient(),
        activities: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.activities = activities
        self.tokenProvider = tokenProvider
    }

    func load() async {
        do {
            let token = try await tokenProvider()
            let loadedTrips = try await client.hikeTrips(token: token)
            let history = try await activities.activities(forceRefresh: false, token: token)
            trips = loadedTrips
            hikes = Self.hikes(in: history)
            phase = .loaded
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if phase != .loaded {
                phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Ton historique de séjours"))
            }
        }
    }

    func trip(id: String) -> V1HikeTrip? {
        trips.first { $0.id == id }
    }

    /// The séjour an activity belongs to, if any.
    func trip(containing activityId: String) -> V1HikeTrip? {
        trips.first { trip in trip.activities.contains { $0.id == activityId } }
    }

    /// Hikes not yet in a séjour — a hike belongs to one at most (the server's 409 otherwise).
    var availableHikes: [V1ActivityListItem] {
        Self.available(hikes: hikes, trips: trips)
    }

    nonisolated static func hikes(in history: [V1ActivityListItem]) -> [V1ActivityListItem] {
        history.filter { $0.type == .hike }.sorted { $0.date > $1.date }
    }

    nonisolated static func available(hikes: [V1ActivityListItem], trips: [V1HikeTrip]) -> [V1ActivityListItem] {
        let linked = Set(trips.flatMap { $0.activities.map(\.id) })
        return hikes.filter { !linked.contains($0.id) }
    }

    /// Creates the séjour and returns it once the server answered — retried on a transient failure.
    func create(name: String, activityIds: [String]) async -> V1HikeTrip? {
        guard !isSaving else { return nil }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let created = try await SharpitRetry.run {
                try await client.createHikeTrip(name: name, activityIds: activityIds, token: try await tokenProvider())
            }
            trips.removeAll { $0.id == created.id }
            trips.insert(created, at: 0)
            return created
        } catch {
            saveError = Self.refusal(error, fallback: "Création du séjour impossible. Réessaie.")
            return nil
        }
    }

    /// Adds stages and adopts the trip the server sends back, with their figures.
    func addSteps(_ activityIds: [String], to tripId: String) async -> Bool {
        guard !isSaving, !activityIds.isEmpty else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let patch = HikeTripPatch(addActivityIds: activityIds)
            let updated = try await SharpitRetry.run {
                try await client.updateHikeTrip(id: tripId, patch: patch, token: try await tokenProvider())
            }
            replace(updated)
            return true
        } catch {
            saveError = Self.refusal(error, fallback: "Ajout impossible. Réessaie.")
            return false
        }
    }

    func rename(_ tripId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = trips.firstIndex(where: { $0.id == tripId }), !trimmed.isEmpty,
              trimmed != trips[index].name else { return }
        let previous = trips
        trips[index].name = trimmed
        send(HikeTripPatch(name: trimmed), to: tripId, restoring: previous, failure: "Le séjour n'a pas pu être renommé.")
    }

    /// Takes a stage out; the hike stays in the history. The last one is never removed here —
    /// the server refuses it, the trip is deleted instead.
    func removeStep(_ activityId: String, from tripId: String) {
        guard let index = trips.firstIndex(where: { $0.id == tripId }),
              trips[index].activities.count > 1 else { return }
        let previous = trips
        trips[index].activities.removeAll { $0.id == activityId }
        send(
            HikeTripPatch(removeActivityIds: [activityId]),
            to: tripId,
            restoring: previous,
            failure: "L'étape n'a pas pu être retirée."
        )
    }

    /// Deletes the séjour; its hikes stay in the history, detached.
    func delete(_ tripId: String) {
        let previous = trips
        trips.removeAll { $0.id == tripId }
        Task {
            do {
                try await SharpitRetry.run {
                    try await client.deleteHikeTrip(id: tripId, token: try await tokenProvider())
                }
            } catch {
                trips = previous
                SharpitWriteFailures.shared.report(Self.refusal(error, fallback: "Le séjour n'a pas pu être supprimé."))
            }
        }
    }

    private func send(_ patch: HikeTripPatch, to tripId: String, restoring previous: [V1HikeTrip], failure: String) {
        Task {
            do {
                let updated = try await SharpitRetry.run {
                    try await client.updateHikeTrip(id: tripId, patch: patch, token: try await tokenProvider())
                }
                replace(updated)
            } catch {
                trips = previous
                SharpitWriteFailures.shared.report(Self.refusal(error, fallback: failure))
            }
        }
    }

    private func replace(_ trip: V1HikeTrip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.insert(trip, at: 0)
        }
    }

    /// The server's own reason when it gave one (« Une activité appartient déjà à un autre
    /// séjour »), else what to do.
    nonisolated static func refusal(_ error: any Error, fallback: String) -> String {
        switch error as? SharpitAPIError {
        case .message(let text)?: text
        case .transport?: "Pas de connexion internet. Vérifie ton réseau, puis réessaie."
        case .unauthorized?: "Ta session a expiré. Reconnecte-toi, puis réessaie."
        default: fallback
        }
    }
}

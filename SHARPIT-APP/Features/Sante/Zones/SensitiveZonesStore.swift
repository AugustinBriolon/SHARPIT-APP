import Foundation
import Observation
import SwiftData

/// The athlete's declared zones (`/api/v1/sensitive-zones`), kept whole so the page paints at
/// once, even offline, and every change reloads them from the web, which decides what each zone
/// now does to the plan.
@MainActor
@Observable
final class SensitiveZonesStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var zones: V1SensitiveZones?
    /// A change is on its way: the actions wait for it.
    private(set) var isSaving = false
    /// The last change the web refused, for the page to say so.
    var saveError: String?

    private let client: any SensitiveZoneServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    init(
        client: any SensitiveZoneServing = PhysicalNoteClient(),
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        if let cached = ResponseCache.read(V1SensitiveZones.self, key: ResponseCacheKey.sensitiveZones, context: modelContext) {
            zones = cached
            phase = .loaded
        }
    }

    func zone(_ id: String) -> V1SensitiveZone? {
        zones?.zones.first { $0.id == id }
    }

    func load() async {
        do {
            let data = try await SharpitRetry.run {
                try await client.sensitiveZonesData(token: try await tokenProvider())
            }
            let fresh = try JSONDecoder().decode(V1SensitiveZones.self, from: data)
            ResponseCache.write(data: data, key: ResponseCacheKey.sensitiveZones, context: modelContext)
            SharpitMotion.run {
                zones = fresh
                phase = .loaded
            }
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            if zones == nil {
                phase = .failed("Lecture de tes zones impossible.")
            }
        }
    }

    @discardableResult
    func declare(_ draft: SensitiveZoneDraft) async -> Bool {
        let input = draft.createInput
        return await perform("La zone n'a pas pu être enregistrée.") { client, token in
            try await client.createNote(input, token: token)
        }
    }

    @discardableResult
    func update(_ zone: V1SensitiveZone, with draft: SensitiveZoneDraft) async -> Bool {
        let patch = draft.patch(from: zone)
        guard patch != PhysicalNotePatch() else { return true }
        let id = zone.id
        return await perform("La modification n'a pas pu être enregistrée.") { client, token in
            try await client.updateNote(id: id, patch: patch, token: token)
        }
    }

    @discardableResult
    func setStatus(_ zone: V1SensitiveZone, to status: String) async -> Bool {
        let id = zone.id
        return await perform("Le statut n'a pas pu être changé.") { client, token in
            try await client.updateNote(id: id, patch: PhysicalNotePatch(status: status), token: token)
        }
    }

    @discardableResult
    func checkin(_ zone: V1SensitiveZone, _ draft: ZoneCheckinDraft) async -> Bool {
        guard let input = draft.input else { return false }
        let id = zone.id
        return await perform("Le point n'a pas pu être enregistré.") { client, token in
            try await client.addCheckin(noteId: id, input: input, token: token)
        }
    }

    /// The change takes the client and a token as parameters rather than capturing them, and
    /// `isSaving` is reset on each path: Xcode 26.6's compiler crashed on the earlier shape (a
    /// non-escaping async closure called inside the retry's closure, under a `defer`).
    private func perform(
        _ failure: String,
        _ change: @escaping @Sendable (any SensitiveZoneServing, String) async throws -> Void
    ) async -> Bool {
        isSaving = true
        let client = client
        do {
            // A dropped connection or a 5xx is tried again; a refusal is not.
            try await SharpitRetry.run {
                try await change(client, try await tokenProvider())
            }
            saveError = nil
            await load()
            isSaving = false
            return true
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
            isSaving = false
            return false
        } catch {
            saveError = failure
            isSaving = false
            return false
        }
    }
}

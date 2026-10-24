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
    /// The body drawn under the zones, from the sex declared in the profile.
    private(set) var figure: SensitiveZoneFigure = .male
    /// The last change the web refused, for the page to say so.
    var saveError: String?

    private let client: any SensitiveZoneServing
    private let profileClient: any AthleteProfileServing
    private let tokenProvider: () async throws -> String
    private let modelContext: ModelContext?

    init(
        client: any SensitiveZoneServing = PhysicalNoteClient(),
        profileClient: any AthleteProfileServing = AthleteProfileClient(),
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.client = client
        self.profileClient = profileClient
        self.tokenProvider = tokenProvider
        self.modelContext = modelContext
        if let cached = ResponseCache.read(V1SensitiveZones.self, key: ResponseCacheKey.sensitiveZones, context: modelContext) {
            zones = cached
            phase = .loaded
        }
        // The profile Settings last read, so the right body paints before the network answers.
        if let profile = ResponseCache.read(V1AthleteProfile.self, key: ResponseCacheKey.athleteProfile, context: modelContext) {
            figure = SensitiveZoneFigure(sex: profile.sex)
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
                phase = .failed(String(localized: "Lecture de tes zones impossible."))
            }
        }
        await refreshFigure()
    }

    /// The sex may have changed in Settings since; a failed read keeps the figure shown.
    private func refreshFigure() async {
        guard let profile = try? await profileClient.athleteProfile(token: try await tokenProvider()) else { return }
        figure = SensitiveZoneFigure(sex: profile.sex)
    }

    @discardableResult
    func declare(_ draft: SensitiveZoneDraft) async -> Bool {
        await perform(String(localized: "La zone n'a pas pu être enregistrée.")) { token in
            try await client.createNote(draft.createInput, token: token)
        }
    }

    @discardableResult
    func update(_ zone: V1SensitiveZone, with draft: SensitiveZoneDraft) async -> Bool {
        let patch = draft.patch(from: zone)
        guard patch != PhysicalNotePatch() else { return true }
        return await perform(String(localized: "La modification n'a pas pu être enregistrée.")) { token in
            try await client.updateNote(id: zone.id, patch: patch, token: token)
        }
    }

    /// The status shows on the tap; a refusal puts the zone back and says so on the page.
    @discardableResult
    func setStatus(_ zone: V1SensitiveZone, to status: String) async -> Bool {
        let before = zones
        saveError = nil
        setLocalStatus(zone.id, status)
        do {
            try await SharpitRetry.run {
                try await client.updateNote(id: zone.id, patch: PhysicalNotePatch(status: status), token: try await tokenProvider())
            }
        } catch SharpitAPIError.unauthorized {
            zones = before
            phase = .unauthorized
            return false
        } catch {
            zones = before
            let message = String(localized: "Statut non enregistré.")
            saveError = message
            SharpitWriteFailures.shared.report(message)
            return false
        }
        await load()
        return true
    }

    @discardableResult
    func checkin(_ zone: V1SensitiveZone, _ draft: ZoneCheckinDraft) async -> Bool {
        guard let input = draft.input else { return false }
        return await perform(String(localized: "Le point n'a pas pu être enregistré.")) { token in
            try await client.addCheckin(noteId: zone.id, input: input, token: token)
        }
    }

    private func setLocalStatus(_ id: String, _ status: String) {
        guard let current = zones else { return }
        let updated = current.zones.map { zone -> V1SensitiveZone in
            guard zone.id == id else { return zone }
            var changed = zone
            changed.status = status
            return changed
        }
        zones = V1SensitiveZones(zones: updated, bodyParts: current.bodyParts)
    }

    private func perform(_ failure: String, _ change: (String) async throws -> Void) async -> Bool {
        do {
            // A dropped connection or a 5xx is tried again; a refusal is not.
            try await SharpitRetry.run { try await change(try await tokenProvider()) }
            saveError = nil
            await load()
            return true
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
            return false
        } catch {
            saveError = failure
            return false
        }
    }
}

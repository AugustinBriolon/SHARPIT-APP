import Foundation
import Observation

@MainActor
@Observable
final class CoachMemoryStore {
    private(set) var snapshot = CoachMemorySnapshot()
    var profileContextText: String = ""
    private(set) var isSavingContext = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastSavedContext: String = ""

    private let client: any CoachMemoryServing
    private let tokenProvider: () async throws -> String

    init(client: any CoachMemoryServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var isContextDirty: Bool {
        profileContextText.trimmingCharacters(in: .whitespacesAndNewlines) != lastSavedContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var entries: [CoachMemoryEntry] {
        snapshot.entries
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let token = try await tokenProvider()
            let snap = try await client.snapshot(token: token)
            snapshot = snap
            profileContextText = snap.profileContext
            lastSavedContext = snap.profileContext
        } catch SharpitAPIError.unauthorized {
            errorMessage = "Session expirée"
        } catch {
            errorMessage = "Impossible de charger la mémoire du coach"
        }
    }

    @discardableResult
    func saveContext() async -> Bool {
        guard !isSavingContext else { return false }
        isSavingContext = true
        errorMessage = nil
        defer { isSavingContext = false }
        do {
            let token = try await tokenProvider()
            try await client.saveProfileContext(profileContextText, token: token)
            lastSavedContext = profileContextText
            return true
        } catch {
            errorMessage = "Impossible d'enregistrer le contexte"
            return false
        }
    }

    @discardableResult
    func createEntry(_ input: CreateCoachMemoryInput) async -> Bool {
        do {
            let token = try await tokenProvider()
            let newEntry = try await client.createEntry(input, token: token)
            var current = snapshot
            current.entries.removeAll { $0.id == newEntry.id }
            current.entries.insert(newEntry, at: 0)
            self.snapshot = current
            await self.load()
            return true
        } catch {
            await self.load()
            if let first = snapshot.entries.first, first.type == input.type {
                return true
            }
            errorMessage = "Impossible d'ajouter la contrainte"
            return false
        }
    }

    func deleteEntry(id: String) async {
        var current = snapshot
        current.entries.removeAll { $0.id == id }
        self.snapshot = current
        do {
            let token = try await tokenProvider()
            try await client.deleteEntry(id: id, token: token)
            await self.load()
        } catch {
            await self.load()
            errorMessage = "Suppression impossible"
        }
    }
}

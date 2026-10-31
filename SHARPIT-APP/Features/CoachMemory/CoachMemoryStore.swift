import Foundation
import Observation

@MainActor
@Observable
final class CoachMemoryStore {
    private(set) var snapshot = CoachMemorySnapshot()
    var profileContextText: String = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastSavedContext: String = ""

    private let client: any CoachMemoryServing
    private let tokenProvider: () async throws -> String
    private let failures: SharpitWriteFailures

    init(
        client: any CoachMemoryServing,
        tokenProvider: @escaping () async throws -> String,
        failures: SharpitWriteFailures = .shared
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.failures = failures
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
            errorMessage = String(localized: "Session expirée")
        } catch {
            errorMessage = String(localized: "Impossible de charger la mémoire du coach")
        }
    }

    /// Counts as saved on the tap and goes out behind; a write that fails for good makes the
    /// text dirty again and is said in the app's toast.
    func saveContext() async {
        let text = profileContextText
        let previous = lastSavedContext
        lastSavedContext = text
        do {
            try await SharpitRetry.run {
                try await client.saveProfileContext(text, token: try await tokenProvider())
            }
        } catch {
            if lastSavedContext == text { lastSavedContext = previous }
            failures.report(String(localized: "Contexte non enregistré. Réessaie dans un instant."))
        }
    }

    @discardableResult
    func createEntry(_ input: CreateCoachMemoryInput) async -> Bool {
        do {
            let newEntry = try await SharpitRetry.run {
                try await client.createEntry(input, token: try await tokenProvider())
            }
            var current = snapshot
            current.entries.removeAll { $0.id == newEntry.id }
            current.entries.insert(newEntry, at: 0)
            self.snapshot = current
            await self.load()
            return true
        } catch {
            let reason = Self.reason(for: error, fallback: String(localized: "Impossible d'ajouter cette entrée. Réessaie dans un instant."))
            await self.load()
            // The answer may have been lost after the server wrote it; only the same entry proves it.
            if !isRefusal(error), snapshot.entries.contains(where: { input.describes($0) }) {
                return true
            }
            errorMessage = reason
            return false
        }
    }

    @discardableResult
    func updateEntry(id: String, _ input: CreateCoachMemoryInput) async -> Bool {
        do {
            let updated = try await SharpitRetry.run {
                try await client.updateEntry(id: id, input, token: try await tokenProvider())
            }
            var current = snapshot
            if let index = current.entries.firstIndex(where: { $0.id == id }) {
                current.entries[index] = updated
            }
            self.snapshot = current
            await self.load()
            return true
        } catch {
            let reason = Self.reason(for: error, fallback: String(localized: "Modification impossible. Réessaie dans un instant."))
            await self.load()
            errorMessage = reason
            return false
        }
    }

    private func isRefusal(_ error: any Error) -> Bool {
        if case SharpitAPIError.message = error { return true }
        return false
    }

    private static func reason(for error: any Error, fallback: String) -> String {
        if case SharpitAPIError.message(let reason) = error { return reason }
        return fallback
    }

    func deleteEntry(id: String) async {
        var current = snapshot
        current.entries.removeAll { $0.id == id }
        self.snapshot = current
        do {
            try await SharpitRetry.run {
                try await client.deleteEntry(id: id, token: try await tokenProvider())
            }
            await self.load()
        } catch {
            await self.load()
            errorMessage = String(localized: "Suppression impossible")
        }
    }
}

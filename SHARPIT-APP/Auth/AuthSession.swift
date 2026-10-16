import ClerkKit
import Foundation
import SwiftData

/// Single place for 401 recovery: one Clerk token refresh, then purge + sign-out at most once.
@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    /// Shown on the login screen after a hard session expiry — one line, no error codes.
    private(set) var expiredNotice = false

    private var modelContext: ModelContext?
    private var defaults: UserDefaults = .standard
    private var disk: ActivityDiskCache = .shared
    private var signOutTask: Task<Void, Never>?

    /// Injectable for tests.
    var refreshToken: () async throws -> String? = {
        try await Clerk.shared.auth.getToken(.init(skipCache: true))
    }
    var performSignOut: () async throws -> Void = {
        try await Clerk.shared.auth.signOut()
    }

    func bind(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        disk: ActivityDiskCache = .shared
    ) {
        modelContext = context
        self.defaults = defaults
        self.disk = disk
    }

    /// Soft recovery: ask Clerk for a fresh JWT. Does not purge.
    func refreshTokenOnce() async -> String? {
        guard let token = try? await refreshToken(), !token.isEmpty else { return nil }
        return token
    }

    /// Hard expiry: purge local data, then sign out. Concurrent callers share one task;
    /// a second hard 401 after we're already expired is a no-op (client + store both call).
    func expireSession() async {
        if let signOutTask {
            await signOutTask.value
            return
        }
        guard !expiredNotice else { return }
        let task = Task { @MainActor in
            self.expiredNotice = true
            if let context = self.modelContext {
                LocalAccountData.erase(context: context, defaults: self.defaults, disk: self.disk)
            } else {
                LocalAccountData.eraseWithoutSwiftData(defaults: self.defaults, disk: self.disk)
            }
            try? await self.performSignOut()
        }
        signOutTask = task
        await task.value
        signOutTask = nil
    }

    func clearExpiredNotice() {
        expiredNotice = false
    }

    /// For tests: reset injectable state.
    func resetForTests() {
        signOutTask = nil
        expiredNotice = false
        modelContext = nil
        defaults = .standard
        disk = .shared
        refreshToken = {
            try await Clerk.shared.auth.getToken(.init(skipCache: true))
        }
        performSignOut = {
            try await Clerk.shared.auth.signOut()
        }
    }
}

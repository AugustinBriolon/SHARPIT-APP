import ClerkKit
import Foundation
import Observation
import SwiftUI

/// Decides, once per signed-in athlete, whether the first-login wizard stands before the tabs.
///
/// The server decides — `onboardingCompletedAt` on the profile, as the web's `OnboardingGate`
/// reads it — and the phone only remembers the answer once it is "done", so a finished athlete
/// never waits on a profile read to see Résumé again. A read that fails lets the athlete in
/// without remembering anything: the app works offline, and the next launch asks again.
@MainActor
@Observable
final class OnboardingGateModel {
    enum Status: Equatable {
        case checking
        case needed
        case ready
    }

    private(set) var status: Status = .checking

    private let client: any AthleteProfileServing
    private let defaults: UserDefaults

    init(client: any AthleteProfileServing, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func resolve(userId: String?, tokenProvider: () async throws -> String) async {
        guard let userId else {
            status = .ready
            return
        }
        guard !isRemembered(userId) else {
            status = .ready
            return
        }
        status = .checking
        do {
            let token = try await tokenProvider()
            let profile = try await client.athleteProfile(token: token)
            if profile.needsOnboarding {
                status = .needed
            } else {
                remember(userId)
                status = .ready
            }
        } catch {
            status = .ready
        }
    }

    /// The wizard closed server-side: remembered here so it never reopens on this phone.
    func finish(userId: String?) {
        if let userId { remember(userId) }
        SharpitMotion.run { status = .ready }
    }

    private static func key(_ userId: String) -> String { "sharpit.onboarding.completed.\(userId)" }

    private func isRemembered(_ userId: String) -> Bool {
        defaults.bool(forKey: Self.key(userId))
    }

    private func remember(_ userId: String) {
        defaults.set(true, forKey: Self.key(userId))
    }
}

/// Stands between sign-in and the tabs: the wizard for an athlete who has not finished it,
/// the app for everyone else.
struct OnboardingGate<Content: View>: View {
    @Environment(Clerk.self) private var clerk
    @State private var model = OnboardingGateModel(client: AthleteProfileClient())
    /// Held here rather than built in `body`, so the Sources step keeps observing one source.
    /// Its switch is stored in UserDefaults, so the tabs' own instance reads what was chosen.
    @State private var appleHealth = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            switch model.status {
            case .checking:
                ZStack {
                    SharpitCanvasBackground()
                    SharpitLoadingInstrument()
                }
            case .needed:
                OnboardingView(
                    store: OnboardingStore(
                        profileClient: AthleteProfileClient(),
                        goalClient: GoalClient(),
                        onboardingClient: OnboardingClient(),
                        tokenProvider: liveToken
                    ),
                    appleHealth: appleHealth,
                    syncClient: SharpitClient(),
                    tokenProvider: liveToken
                ) {
                    model.finish(userId: clerk.user?.id)
                }
                .transition(.opacity)
            case .ready:
                content()
                    .transition(.opacity)
            }
        }
        // Keyed by the athlete, so signing out and in as someone else asks again.
        .task(id: clerk.user?.id) {
            await model.resolve(userId: clerk.user?.id, tokenProvider: liveToken)
        }
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    @MainActor
    private func liveToken() async throws -> String {
        guard let token = try await clerk.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
    }
}

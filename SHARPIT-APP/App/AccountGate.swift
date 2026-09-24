import ClerkKit
import Foundation
import Observation
import SwiftUI

/// What stands between sign-in and the tabs, in the web's order (`(app)/layout.tsx`): the
/// legal wall first, then the first-login wizard, then the app.
///
/// The server decides both. The phone only remembers that the wizard is done, per Clerk user,
/// so a finished athlete sees Résumé at once while the consents are re-read behind it — a new
/// version of the documents, or a health consent withdrawn on the web, still brings the wall
/// back. A read that fails lets the athlete in without remembering anything: the app works
/// offline, and every data route enforces the consents server-side anyway.
@MainActor
@Observable
final class AccountGateModel {
    enum Status: Equatable {
        case checking
        case consent(V1PrivacyConsents.WallReason)
        case onboarding
        case ready
    }

    private(set) var status: Status = .checking
    /// The last consents read — the wall pre-fills the optional ones from it.
    private(set) var consents: V1PrivacyConsents?

    private let consentClient: any PrivacyConsentServing
    private let profileClient: any AthleteProfileServing
    private let defaults: UserDefaults
    private var userId: String?

    init(
        consentClient: any PrivacyConsentServing,
        profileClient: any AthleteProfileServing,
        defaults: UserDefaults = .standard
    ) {
        self.consentClient = consentClient
        self.profileClient = profileClient
        self.defaults = defaults
    }

    func resolve(userId: String?, tokenProvider: () async throws -> String) async {
        self.userId = userId
        guard let userId else {
            status = .ready
            return
        }
        let onboarded = isRemembered(userId)
        // A finished athlete is painted straight away; the check below can still send them
        // to the wall.
        if onboarded { status = .ready } else if status != .ready { status = .checking }

        do {
            let token = try await tokenProvider()
            let consents = try await consentClient.consents(token: token)
            self.consents = consents
            if let reason = consents.wallReason {
                move(to: .consent(reason))
                return
            }
            guard !onboarded else {
                move(to: .ready)
                return
            }
            let profile = try await profileClient.athleteProfile(token: token)
            if profile.needsOnboarding {
                move(to: .onboarding)
            } else {
                remember(userId)
                move(to: .ready)
            }
        } catch {
            move(to: .ready)
        }
    }

    /// The wall was accepted: carry on to the wizard, or to the app.
    func consentAccepted(_ consents: V1PrivacyConsents, tokenProvider: () async throws -> String) async {
        self.consents = consents
        await resolve(userId: userId, tokenProvider: tokenProvider)
    }

    /// The health consent was withdrawn from Moi: the wall stands again at once, as on the web.
    func consentsChanged(_ consents: V1PrivacyConsents) {
        self.consents = consents
        if let reason = consents.wallReason {
            move(to: .consent(reason))
        }
    }

    /// The wizard closed server-side: remembered here so it never reopens on this phone.
    func onboardingFinished() {
        if let userId { remember(userId) }
        move(to: .ready)
    }

    private func move(to target: Status) {
        guard status != target else { return }
        SharpitMotion.run { status = target }
    }

    private static func key(_ userId: String) -> String { "sharpit.onboarding.completed.\(userId)" }

    private func isRemembered(_ userId: String) -> Bool {
        defaults.bool(forKey: Self.key(userId))
    }

    private func remember(_ userId: String) {
        defaults.set(true, forKey: Self.key(userId))
    }
}

/// Shows the wall, the wizard or the app, whichever the athlete owes next.
struct AccountGate<Content: View>: View {
    @Environment(Clerk.self) private var clerk
    @State private var model = AccountGateModel(
        consentClient: PrivacyConsentClient(),
        profileClient: AthleteProfileClient()
    )
    /// Held here rather than built in `body`, so the Sources step keeps observing one source.
    /// Its switch is stored in UserDefaults, so the tabs' own instance reads what was chosen.
    @State private var appleHealth = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            switch model.status {
            case .checking:
                ZStack {
                    SharpitCanvasBackground()
                    SharpitLoadingInstrument()
                }
                .transition(.opacity)
            case .consent(let reason):
                PrivacyConsentWallView(
                    reason: reason,
                    initial: model.consents,
                    client: PrivacyConsentClient(),
                    tokenProvider: liveToken
                ) { consents in
                    await model.consentAccepted(consents, tokenProvider: liveToken)
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 1.02))))
            case .onboarding:
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
                    model.onboardingFinished()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 24)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
            case .ready:
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        // Keyed by the athlete, so signing out and in as someone else asks again.
        .task(id: clerk.user?.id) {
            await model.resolve(userId: clerk.user?.id, tokenProvider: liveToken)
        }
        // Moi → Confidentialité reports a withdrawn health consent through this.
        .environment(model)
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

import ClerkKit
import Foundation
import Observation
import SwiftUI

/// What stands between sign-in and the tabs: the first-login wizard for a new account — its
/// consents are a step of it, just before the sources — or the legal wall alone for an athlete
/// already onboarded whose consents are owed again (a new document version, health withdrawn).
///
/// The wizard's store is owned here, so a re-render or a second resolve never rebuilds it and
/// never sends the athlete back to the first step; once the wizard is open, resolving leaves it
/// alone until it finishes.
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
        /// A new account whose first read failed for good: never let in without the wizard,
        /// which nothing would reopen. Says why, with a retry.
        case unreachable(String)
    }

    private(set) var status: Status = .checking
    /// The last consents read — the wall pre-fills the optional ones from it.
    private(set) var consents: V1PrivacyConsents?
    /// The open wizard, kept across renders and resolves.
    private(set) var onboardingStore: OnboardingStore?
    private let makeOnboardingStore: @MainActor (_ consentsOwed: Bool, _ consents: V1PrivacyConsents?, _ userId: String) -> OnboardingStore

    private let consentClient: any PrivacyConsentServing
    private let profileClient: any AthleteProfileServing
    private let defaults: UserDefaults
    /// The wizard answered before sign-up: dropped when the account turns out to be onboarded.
    private let onboardingDraft: OnboardingDraftFile?
    private var userId: String?

    init(
        consentClient: any PrivacyConsentServing,
        profileClient: any AthleteProfileServing,
        defaults: UserDefaults = .standard,
        onboardingDraft: OnboardingDraftFile? = nil,
        makeOnboardingStore: @escaping @MainActor (_ consentsOwed: Bool, _ consents: V1PrivacyConsents?, _ userId: String) -> OnboardingStore
    ) {
        self.consentClient = consentClient
        self.profileClient = profileClient
        self.defaults = defaults
        self.onboardingDraft = onboardingDraft
        self.makeOnboardingStore = makeOnboardingStore
    }

    func resolve(userId: String?, tokenProvider: () async throws -> String) async {
        self.userId = userId
        guard let userId else {
            status = .ready
            return
        }
        // The wizard is open: nothing here may rebuild it or pull the athlete out of it.
        guard status != .onboarding else { return }
        let onboarded = isRemembered(userId)
        // A finished athlete is painted straight away; the check below can still send them
        // to the wall. Never back to `checking` from a screen already shown.
        if onboarded { status = .ready }

        do {
            // Right after sign-up Clerk can hand out no token, or one the server does not take
            // yet: a refusal is tried again here, unlike a write.
            let (consents, profile) = try await SharpitRetry.run(retryingOn: Self.isWorthRetrying) {
                let token = try await tokenProvider()
                async let consentsRead = consentClient.consents(token: token)
                // Read even when remembered: the server is the truth. A new account's very first
                // read can come before its row exists, and the phone once remembered « done » from it.
                async let profileRead = profileClient.athleteProfile(token: token)
                return try await (consentsRead, profileRead)
            }
            self.consents = consents
            if profile.needsOnboarding {
                onboardingStore = makeOnboardingStore(consents.wallReason != nil, consents, userId)
                move(to: .onboarding)
                return
            }
            // « J'ai déjà un compte » after starting the wizard: that account has its answers.
            onboardingDraft?.clear()
            if let reason = consents.wallReason {
                move(to: .consent(reason))
                return
            }
            // Remembered only once the server says so: a profile without the field (no row yet,
            // an older server) lets the athlete in, but decides nothing for next time.
            if profile.onboardingCompletedAt != nil { remember(userId) }
            move(to: .ready)
        } catch {
            // A finished athlete works offline; a new one would land in empty tabs for good.
            move(to: onboarded ? .ready : .unreachable(Self.message(for: error)))
        }
    }

    /// « Réessayer » from the unreachable screen.
    func retry(tokenProvider: () async throws -> String) async {
        move(to: .checking)
        await resolve(userId: userId, tokenProvider: tokenProvider)
    }

    nonisolated static func isWorthRetrying(_ error: any Error) -> Bool {
        SharpitRetry.isTransient(error) || (error as? SharpitAPIError) == .unauthorized
    }

    nonisolated static func message(for error: any Error) -> String {
        if (error as? SharpitAPIError) == .unauthorized {
            return String(localized: "Ta session n'est pas encore prête. Réessaie, ou reconnecte-toi.")
        }
        return SharpitErrorGuidance.message(for: error, subject: String(localized: "Ton profil"))
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
        onboardingStore = nil
        move(to: .ready)
    }

    private func move(to target: Status) {
        guard status != target else { return }
        #if DEBUG
        print("[gate] \(status) → \(target)")
        #endif
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
        profileClient: AthleteProfileClient(),
        onboardingDraft: .shared,
        makeOnboardingStore: AccountGate.liveOnboardingStore
    )
    /// Held here rather than built in `body`, so the Sources step keeps observing one source.
    /// Its switch is stored in UserDefaults, so the tabs' own instance reads what was chosen.
    @State private var appleHealth = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
    @State private var appleCalendar = AppleCalendarSource(client: SharpitClient())
    /// Available during onboarding so the first-week Pro teaser can open the paywall.
    @State private var pro = ProStore(tokenProvider: {
        guard let token = try await Clerk.shared.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
    })
    @Environment(LaunchCurtain.self) private var launchCurtain: LaunchCurtain?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            SharpitCanvasBackground()
            switch model.status {
            case .checking:
                // A neutral mark, never a screen's skeleton: where the athlete lands is not
                // known yet.
                ZStack {
                    SharpitCanvasBackground()
                    SharpitLaunchMark()
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
                if let store = model.onboardingStore {
                    OnboardingView(
                        store: store,
                        appleHealth: appleHealth,
                        appleCalendar: appleCalendar,
                        tokenProvider: liveToken
                    ) {
                        model.onboardingFinished()
                    }
                    .transition(.opacity)
                }
            case .unreachable(let message):
                SharpitStateMessage.failed(message) {
                    Task { await model.retry(tokenProvider: liveToken) }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Se déconnecter") {
                        Task { try? await clerk.auth.signOut() }
                    }
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.bottom, SharpitSpacing.lg)
                }
                .transition(.opacity)
            case .ready:
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        // The wall, the wizard or a failure is the screen: the splash may go. Ready waits on Résumé.
        .onChange(of: model.status, initial: true) { _, status in
            switch status {
            case .consent, .onboarding, .unreachable: launchCurtain?.markReady()
            case .checking, .ready: break
            }
        }
        // Keyed by the athlete, so signing out and in as someone else asks again.
        .task(id: clerk.user?.id) {
            appleHealth.bind(userId: clerk.user?.id)
            appleCalendar.bind(userId: clerk.user?.id)
            await model.resolve(userId: clerk.user?.id, tokenProvider: liveToken)
        }
        .task(id: clerk.user?.id) {
            await pro.load()
        }
        // Moi → Confidentialité reports a withdrawn health consent through this.
        .environment(model)
        .environment(pro)
        .environment(\.locale, AppLanguage.locale)
        // Every switch from the consent wall on, the tabs and their sheets included, is lime.
        .toggleStyle(.sharpitSwitch)
    }

    /// The wizard on the live services. Its token comes from Clerk's shared instance, as the
    /// gate's own does.
    @MainActor
    static func liveOnboardingStore(consentsOwed: Bool, consents: V1PrivacyConsents?, userId: String) -> OnboardingStore {
        return OnboardingStore(
            services: liveOnboardingServices,
            consentsOwed: consentsOwed,
            currentConsents: consents,
            stepMemory: OnboardingStepMemory(userId: userId),
            firstName: Clerk.shared.user?.firstName,
            draftFile: .shared,
            onExit: {
                Task {
                    try? await Clerk.shared.auth.signOut()
                }
            },
            tokenProvider: {
                guard let token = try await Clerk.shared.auth.getToken() else { throw SharpitAPIError.unauthorized }
                return token
            }
        )
    }

    /// What the wizard writes to — before sign-up too, where nothing is called.
    @MainActor
    static var liveOnboardingServices: OnboardingServices {
        OnboardingServices(
            profile: AthleteProfileClient(),
            goals: GoalClient(),
            onboarding: OnboardingClient(),
            consents: PrivacyConsentClient(),
            plan: CoachPlanClient(),
            physicalNotes: PhysicalNoteClient(),
            saveFirstName: { firstName in
                guard let user = await Clerk.shared.user, user.firstName != firstName else { return }
                _ = try await user.update(.init(firstName: firstName))
            }
        )
    }

    @MainActor
    private func liveToken() async throws -> String {
        guard let token = try await clerk.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
    }
}

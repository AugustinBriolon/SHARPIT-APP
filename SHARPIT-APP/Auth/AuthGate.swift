import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

/// The app's authentication gate.
///
/// Signed out it shows the welcome (`SignInWelcome`), the pre-account wizard, or the line that a
/// session expired; signed in, the app.
struct AuthGate<SignedIn: View>: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var authIsPresented = false
    /// Why the sign-up is asked for, when the wizard asks for it.
    @State private var authHeadline: String?
    @State private var authSession = AuthSession.shared
    /// The wizard before an account (SHARPIT ADR-097): the profile steps, kept on the phone.
    @State private var preAccountWizard: OnboardingStore?
    /// True when the welcome → wizard push is forward; false when the back chevron pops it.
    @State private var wizardEntryForward = true
    /// The wizard never reaches Sources without an account; OnboardingView still takes one.
    @State private var appleHealth = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
    @Environment(LaunchCurtain.self) private var launchCurtain: LaunchCurtain?
    var signedIn: () -> SignedIn

    var body: some View {
        Group {
            if clerk.user != nil {
                signedIn()
            } else if authSession.expiredNotice {
                SessionExpiredSignIn(onSignIn: { signIn() })
            } else if let preAccountWizard {
                OnboardingView(
                    store: preAccountWizard,
                    appleHealth: appleHealth,
                    tokenProvider: { throw SharpitAPIError.unauthorized },
                    onFinished: {}
                )
                .transition(OnboardingStepSlide(direction: { wizardEntryForward }))
            } else {
                SignInWelcome(
                    onStart: { startWizard() },
                    onSignIn: { signIn() }
                )
                .transition(OnboardingStepSlide(direction: { wizardEntryForward }))
            }
        }
        .sheet(isPresented: $authIsPresented) {
            SharpitAuthDrawer(headline: authHeadline)
        }
        .overlay {
            if scenePhase != .active {
                PrivacyMaskView()
            }
        }
        .task {
            // Signed out: the welcome screen is drawn at once, and plays its own entrance.
            if clerk.user == nil { launchCurtain?.markReady() }
            AuthSession.shared.bind(context: modelContext)
            if let userId = clerk.user?.id {
                AuthSession.shared.clearExpiredNotice()
                LocalAccountData.claim(userId: userId, context: modelContext)
                CrashReporting.identify(userId: userId)
            }
        }
        .onChange(of: clerk.user?.id) { previous, current in
            if let userId = current {
                // The account's own wizard takes over, from the draft.
                preAccountWizard = nil
                AuthSession.shared.clearExpiredNotice()
                LocalAccountData.claim(userId: userId, context: modelContext)
                CrashReporting.identify(userId: userId)
            } else if previous != nil {
                // Became nil — purge local data (manual sign-out or hard 401 expiry).
                LocalAccountData.erase(context: modelContext)
                CrashReporting.identify(userId: nil)
            }
        }
    }

    private func signIn() {
        authHeadline = nil
        authIsPresented = true
    }

    /// « Commencer »: the profile steps first, the account once they are answered — reopened
    /// where it was when a draft is on the phone.
    private func startWizard() {
        let store = OnboardingStore(
            services: AccountGate<EmptyView>.liveOnboardingServices,
            consentsOwed: true,
            hasAccount: false,
            draftFile: .shared,
            onAccountNeeded: {
                authHeadline = String(localized: "Crée ton compte pour brancher tes appareils et générer ton plan.")
                authIsPresented = true
            },
            onExit: { leaveWizard() },
            tokenProvider: { throw SharpitAPIError.unauthorized }
        )
        wizardEntryForward = true
        Task { @MainActor in
            await Task.yield()
            SharpitMotion.run {
                preAccountWizard = store
            }
        }
    }

    private func leaveWizard() {
        // Rebind the wizard's transition to pop before removing it (same bake as step slides).
        wizardEntryForward = false
        Task { @MainActor in
            await Task.yield()
            SharpitMotion.run {
                preAccountWizard = nil
            }
        }
    }
}

/// Hard session expiry — one line, no alert, no status codes.
private struct SessionExpiredSignIn: View {
    var onSignIn: () -> Void

    var body: some View {
        VStack(spacing: SharpitSpacing.lg) {
            Spacer()
            Text("Ta session a expiré, reconnecte-toi.")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SharpitSpacing.pageInset)
            Button("Se connecter", action: onSignIn)
                .buttonStyle(CliniqueButtonStyle(kind: .primary))
                .fixedSize()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitColor.card.ignoresSafeArea())
    }
}

// MARK: – Welcome

/// The signed-out welcome, in Clinique: one white sheet under the brand's wash, the mark and the
/// name, what SharpIt reads as four lines — a pillar's ring each — and the two ways in docked at
/// the foot. No gauge, no glow: the screen says what the app does, then gets out of the way.
private struct SignInWelcome: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    private struct Promise: Identifiable {
        let pillar: CliniquePillar
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let promises = [
        Promise(pillar: .sleep, symbol: "moon", title: String(localized: "Tes nuits, lues chaque matin"),
                detail: String(localized: "Sommeil, VFC et fréquence cardiaque, depuis ta montre.")),
        Promise(pillar: .recovery, symbol: "bolt", title: String(localized: "Une séance à ta mesure"),
                detail: String(localized: "Allégée après une nuit courte, tenue quand tu es prêt.")),
        Promise(pillar: .nutrition, symbol: "flame", title: String(localized: "Ce que tu manges compte"),
                detail: String(localized: "Ce qu'il te manque avant et après chaque séance.")),
        Promise(pillar: .coach, symbol: "bubble.left", title: String(localized: "Un coach qui te connaît"),
                detail: String(localized: "Il répond avec ta nuit, ta charge et ton plan.")),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "circle.hexagonpath.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(SharpitColor.brandMarkGradient)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "SharpIt")
                            .font(SharpitTypography.system(size: 34, weight: .semibold, relativeTo: .largeTitle))
                            .tracking(-0.7)
                            .foregroundStyle(SharpitColor.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Text("L'intelligence de ton entraînement.")
                            .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(promises.enumerated()), id: \.element.id) { index, promise in
                        HStack(spacing: SharpitSpacing.md) {
                            CliniqueRing(pillar: promise.pillar, fraction: 1, symbol: promise.symbol, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(promise.title)
                                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                                    .foregroundStyle(SharpitColor.foreground)
                                Text(promise.detail)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.slate)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                        if index < promises.count - 1 {
                            CliniqueDivider()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, SharpitSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button(action: onStart) {
                    Text("Commencer").frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                Button("J'ai déjà un compte", action: onSignIn)
                    .buttonStyle(CliniqueButtonStyle(kind: .plain))
            }
            .padding(.horizontal, SharpitSpacing.md)
            .padding(.bottom, SharpitSpacing.xs)
            .background(SharpitColor.card)
        }
        .cliniqueSheet(wash: .good, height: 320)
    }
}

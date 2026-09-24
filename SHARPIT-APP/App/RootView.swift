import ClerkKit
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.modelContext) private var modelContext

    /// Owned here so a surface can send the athlete to another tab — the regularity strip
    /// opening Plan, any "Discuter avec le coach" button opening Coach with its subject.
    @State private var router = ShellRouter()

    /// One client for reading the plan and for linking, so both share a session.
    private let plannedSessionClient = PlannedSessionClient()
    private let activityStatusClient = ActivityStatusClient()
    private let journalClient = JournalClient()
    private let wellnessClient = WellnessClient()
    private let sharpitClient = SharpitClient()
    /// One client for Profil, Seuils, Corps and the reading density, so they share a session.
    private let profileClient = AthleteProfileClient()
    /// Shared by Today, which sends on each sync, and Moi, where it is switched on.
    @State private var appleHealth = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
    /// The reading density, read once and handed to every surface through the environment.
    @State private var displayMode = DisplayModeStore(client: AthleteProfileClient())
    /// The app's one toast slot — a sync starting or failing, wherever the athlete is.
    @State private var toastCenter = SharpitToastCenter()
    /// Push notification manager for Moment 1 (Wake / Morning verdict) APNs registration and routing.
    @State private var pushManager = PushNotificationManager.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Résumé", systemImage: "sun.max", value: ShellTab.today) {
                TodayView(
                    client: SharpitClient(),
                    tokenProvider: liveToken,
                    modelContext: modelContext,
                    activityStatusClient: activityStatusClient,
                    journalClient: journalClient,
                    wellnessClient: wellnessClient,
                    signalClient: sharpitClient,
                    syncClient: sharpitClient,
                    appleHealth: appleHealth
                )
            }
            Tab(
                ShellDestination.plan.title,
                systemImage: ShellDestination.plan.systemImage,
                value: ShellTab.plan
            ) {
                PlanView(
                    client: plannedSessionClient,
                    linker: plannedSessionClient,
                    activityClient: ActivityClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.coach.title,
                systemImage: ShellDestination.coach.systemImage,
                value: ShellTab.coach
            ) {
                CoachView(
                    client: CoachChatClient(),
                    conversations: CoachConversationClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.activity.title,
                systemImage: ShellDestination.activity.systemImage,
                value: ShellTab.activity
            ) {
                ActivityView(
                    client: ActivityClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.me.title,
                systemImage: ShellDestination.me.systemImage,
                value: ShellTab.me
            ) {
                MeView(
                    appleHealth: appleHealth,
                    syncClient: sharpitClient,
                    profileClient: profileClient,
                    displayMode: displayMode,
                    tokenProvider: liveToken,
                    modelContext: modelContext
                ) {
                    AccountHeader()
                }
            }
        }
        .background(SharpitCanvasBackground())
        .overlay(alignment: .top) { SharpitToastHost(center: toastCenter) }
        .tint(SharpitColor.primary)
        .environment(router)
        .environment(toastCenter)
        // Read once for the whole app: every surface that shows a technical figure asks this
        // rather than the profile (ADR 0006).
        .environment(\.displayMode, displayMode)
        .task {
            async let modeLoad: () = displayMode.load(tokenProvider: liveToken)
            async let pushSetup: () = {
                _ = await pushManager.requestAuthorization()
                await pushManager.syncDeviceTokenIfNeeded(tokenProvider: liveToken, client: sharpitClient)
            }()
            _ = await (modeLoad, pushSetup)

            if let tab = pushManager.consumePendingNavigation() {
                router.select(tab)
            }
        }
        .onChange(of: pushManager.deviceToken) { _, newToken in
            if newToken != nil {
                Task {
                    await pushManager.syncDeviceTokenIfNeeded(tokenProvider: liveToken, client: sharpitClient)
                }
            }
        }
        .onChange(of: pushManager.pendingTabSelection) { _, newTab in
            if let tab = pushManager.consumePendingNavigation() {
                router.select(tab)
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        // Every string in this app is French, and so is the web's. Left to the device
        // locale the date strips rendered "M T W T F S S" under French copy.
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .modifier(LiquidTabBarModifier())
    }

    @MainActor
    private func liveToken() async throws -> String {
        guard let token = try await clerk.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
    }

    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        // 1. Garmin handoff callback (ADR-040, Direction A)
        if components.path == "/connect/garmin/callback" {
            let status = components.queryItems?.first(where: { $0.name == "garmin" })?.value
            handleGarminCallback(status: status)
            return
        }

        // 2. Direct tab routing (e.g. /today, /plan, /coach, /activities, /me)
        switch components.path {
        case "/today":
            router.select(.today)
        case "/plan":
            router.select(.plan)
        case "/coach":
            router.select(.coach)
        case "/activity", "/activities":
            router.select(.activity)
        case "/me", "/profile", "/settings":
            router.select(.me)
        default:
            break
        }
    }

    private func handleGarminCallback(status: String?) {
        switch status {
        case "connected":
            toastCenter.show(
                "Garmin connecté — synchronisation en cours…",
                symbol: "checkmark.circle.fill",
                tone: .success,
                autoDismissAfter: 4
            )
            Task {
                if let token = try? await liveToken() {
                    _ = try? await sharpitClient.sync(token: token)
                }
            }
        case "already_connected":
            toastCenter.show(
                "Garmin est déjà connecté",
                symbol: "checkmark.circle.fill",
                tone: .success,
                autoDismissAfter: 3
            )
        case "cancelled":
            toastCenter.show(
                "Connexion Garmin annulée",
                symbol: "xmark.circle",
                tone: .syncing,
                autoDismissAfter: 3
            )
        case "consent_required":
            toastCenter.show(
                "Autorisation requise pour Garmin",
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        case "invalid_state":
            toastCenter.show(
                "Session Garmin expirée",
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        case "denied":
            toastCenter.show(
                "Connexion Garmin refusée",
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        default:
            toastCenter.show(
                "Connexion Garmin impossible",
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 4
            )
        }
    }
}

private struct LiquidTabBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
                .toolbarBackground(.thinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

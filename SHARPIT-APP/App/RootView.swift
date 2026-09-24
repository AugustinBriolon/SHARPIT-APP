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
    /// Brings in every Garmin activity once — the regular pull only reaches back so far.
    @State private var historyImport = GarminHistoryImport(client: SharpitClient(), statusClient: SharpitClient())
    @State private var historyToast: UUID?
    @Environment(\.scenePhase) private var scenePhase

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
                ShellDestination.body.title,
                systemImage: ShellDestination.body.systemImage,
                value: ShellTab.body
            ) {
                CorpsView(
                    profileClient: profileClient,
                    recoveryClient: sharpitClient,
                    tokenProvider: liveToken,
                    modelContext: modelContext
                )
            }
        }
        .background(SharpitCanvasBackground())
        // Paramètres is a sheet over whichever tab is showing, opened from the avatar.
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsView(
                appleHealth: appleHealth,
                syncClient: sharpitClient,
                profileClient: profileClient,
                displayMode: displayMode,
                tokenProvider: liveToken,
                modelContext: modelContext
            )
        }
        .overlay(alignment: .top) { SharpitToastHost(center: toastCenter) }
        .tint(SharpitColor.primary)
        .environment(router)
        .environment(toastCenter)
        // Read once for the whole app: every surface that shows a technical figure asks this
        // rather than the profile (ADR 0006).
        .environment(\.displayMode, displayMode)
        .environment(historyImport)
        // Once per athlete; a run cut off is picked up again on the next foreground.
        .task(id: clerk.user?.id) { await runHistoryImport() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await runHistoryImport() } }
        }
        .onChange(of: historyImport.state) { _, state in showHistoryToast(for: state) }
        .task {
            async let modeLoad: () = displayMode.load(tokenProvider: liveToken)
            async let pushSetup: () = {
                // Only while the athlete has not switched SharpIt's notifications off.
                guard pushManager.isEnabledByAthlete else { return }
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

    private func runHistoryImport() async {
        await historyImport.runIfNeeded(userId: clerk.user?.id, tokenProvider: liveToken)
    }

    private func showHistoryToast(for state: GarminHistoryImport.State) {
        if let historyToast { toastCenter.dismiss(historyToast) }
        historyToast = nil
        switch state {
        case .importing:
            historyToast = toastCenter.show(
                "Import de tout ton historique Garmin…",
                symbol: "clock.arrow.circlepath",
                autoDismissAfter: nil
            )
        case .finished(let imported):
            historyToast = toastCenter.show(
                imported == 0
                    ? "Historique Garmin à jour"
                    : "Historique importé · \(imported) activité\(imported > 1 ? "s" : "")",
                symbol: "checkmark.circle.fill",
                tone: .success,
                autoDismissAfter: 4
            )
        case .failed:
            historyToast = toastCenter.show(
                "Import de l'historique interrompu — reprise au prochain lancement",
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 5
            )
        case .idle:
            break
        }
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
        case "/body", "/corps", "/me", "/profile":
            router.select(.body)
        case "/settings":
            router.openSettings()
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
                // A new connection brings its whole history, not just recent weeks.
                await runHistoryImport()
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

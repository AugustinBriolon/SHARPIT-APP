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
    @State private var appleCalendar = AppleCalendarSource(client: SharpitClient())
    /// The reading density, read once and handed to every surface through the environment.
    @State private var displayMode = DisplayModeStore(client: AthleteProfileClient())
    /// The parts of SharpIt the athlete uses: a feature off has no tab, card or widget.
    @State private var features = FeatureStore(client: AthleteProfileClient())
    /// The app's one toast slot — a sync starting or failing, wherever the athlete is.
    @State private var toastCenter = SharpitToastCenter()
    /// Push notification manager for Moment 1 (Wake / Morning verdict) APNs registration and routing.
    @State private var pushManager = PushNotificationManager.shared
    /// SharpIt Pro: the tier as the web states it, and every App Store transaction handed to
    /// the web to verify — listened to for as long as the app runs.
    @State private var pro: ProStore?
    @Environment(\.scenePhase) private var scenePhase
    /// Nil in previews and demo hosts, which open no links.
    @Environment(IncomingLinkInbox.self) private var linkInbox: IncomingLinkInbox?
    @Environment(LaunchCurtain.self) private var launchCurtain: LaunchCurtain?

    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.tabBarSelected($0) })) {
            Tab("Résumé", systemImage: "sun.max", value: ShellTab.today) {
                TodayView(
                    client: SharpitClient(),
                    tokenProvider: liveToken,
                    modelContext: modelContext,
                    activityStatusClient: activityStatusClient,
                    journalClient: journalClient,
                    wellnessClient: wellnessClient,
                    signalClient: sharpitClient,
                    nutritionClient: sharpitClient,
                    syncClient: sharpitClient,
                    appleHealth: appleHealth
                )
                .sharpitRegularColumn()
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
                .sharpitRegularColumn()
            }
            Tab(
                ShellDestination.coach.title,
                systemImage: ShellDestination.coach.systemImage,
                value: ShellTab.coach
            ) {
                CoachView(
                    client: CoachChatClient(),
                    conversations: CoachConversationClient(),
                    quota: CoachQuotaClient(),
                    tokenProvider: liveToken
                )
                .sharpitRegularColumn()
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
                .sharpitRegularColumn()
            }
            if features.isOn(.health) {
                Tab(
                    ShellDestination.body.title,
                    systemImage: ShellDestination.body.systemImage,
                    value: ShellTab.body
                ) {
                    SanteView(
                        profileClient: profileClient,
                        recoveryClient: sharpitClient,
                        tokenProvider: liveToken,
                        modelContext: modelContext
                    )
                    .sharpitRegularColumn()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // A tab turned off while showing, or a link to it, lands on Résumé.
        .onChange(of: router.selectedTab, initial: true) { _, tab in
            if tab == .body, !features.isOn(.health) { router.select(.today) }
            // A link or a notification opened another tab: Résumé is not what the splash waits on.
            if tab != .today { launchCurtain?.markReady() }
        }
        .onChange(of: features.prefs) { _, _ in
            if router.selectedTab == .body, !features.isOn(.health) { router.select(.today) }
        }
        .background(SharpitCanvasBackground())
        // Paramètres is a sheet over whichever tab is showing, opened from the avatar.
        // The sheet sits above this view's overlay, so the toast host is mounted again
        // inside it — otherwise sync / connect toasts hide behind Paramètres.
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsView(
                appleHealth: appleHealth,
                appleCalendar: appleCalendar,
                syncClient: sharpitClient,
                profileClient: profileClient,
                displayMode: displayMode,
                features: features,
                tokenProvider: liveToken,
                modelContext: modelContext,
                openingOn: router.settingsRoute
            )
            .environment(toastCenter)
            .overlay(alignment: .top) { SharpitToastHost(center: toastCenter) }
        }
        .overlay(alignment: .top) { SharpitToastHost(center: toastCenter) }
        // A write retried in the background and still refused: said once, wherever the athlete is.
        .onChange(of: SharpitWriteFailures.shared.latest) { _, failure in
            guard let failure else { return }
            toastCenter.show(failure.message, symbol: "exclamationmark.triangle.fill", tone: .error, autoDismissAfter: 4)
        }
        .tint(SharpitColor.primary)
        .environment(router)
        .environment(toastCenter)
        // Read once for the whole app: every surface that shows a technical figure asks this
        // rather than the profile (ADR 0006).
        .environment(\.displayMode, displayMode)
        .environment(\.features, features)
        .environment(pro)
        .task {
            let store = pro ?? ProStore(tokenProvider: liveToken)
            pro = store
            await store.load()
            await store.listenForTransactions()
        }
        .task(id: clerk.user?.id) {
            appleHealth.bind(userId: clerk.user?.id)
            appleCalendar.bind(userId: clerk.user?.id)
            if let token = try? await liveToken(),
               await AppleCalendarSync.shared.migrateLegacyPlanCalendarSync(
                   calendarLinker: sharpitClient,
                   token: token
               ) {
                appleCalendar.adoptLegacyMigration()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            pushManager.clearIconBadge()
            Task { await refreshSessionReminders() }
            Task { await refreshDayCheckIns() }
            Task { await pro?.drainUnfinished() }
        }
        .task {
            // Open a cold-launch tap before any network work — otherwise the athlete sits on
            // the default tab while prefs load and thinks the notification did nothing.
            openPendingNotificationIfNeeded()

            // Read here, on the main actor: the `async let` below runs off it.
            // Only while the athlete has not switched SharpIt's notifications off.
            let pushEnabled = pushManager.isEnabledByAthlete
            async let modeLoad: () = displayMode.load(tokenProvider: liveToken)
            async let featuresLoad: () = features.load(tokenProvider: liveToken)
            async let languageSync: () = AppLanguage.syncToProfile(client: AthleteProfileClient(), tokenProvider: liveToken)
            async let pushSetup: () = {
                guard pushEnabled else { return }
                _ = await pushManager.requestAuthorization()
                await pushManager.syncDeviceTokenIfNeeded(tokenProvider: liveToken, client: sharpitClient)
            }()
            _ = await (modeLoad, featuresLoad, languageSync, pushSetup)

            openPendingNotificationIfNeeded()
            await refreshSessionReminders()
            await refreshDayCheckIns()
        }
        // The plan changed elsewhere (a coach proposal carried out): the reminders follow it.
        .onChange(of: router.calendarRevision) { _, _ in Task { await refreshSessionReminders() } }
        // Just linked: the plan lands in the calendar now, not at the next return to the app.
        .onChange(of: appleCalendar.linkRevision) { _, _ in Task { await refreshAppleCalendar() } }
        .onChange(of: pushManager.deviceToken) { _, newToken in
            if newToken != nil {
                Task {
                    await pushManager.syncDeviceTokenIfNeeded(tokenProvider: liveToken, client: sharpitClient)
                }
            }
        }
        // Token, not destination: two identical taps (e.g. `/plan`) must each open again.
        .onChange(of: pushManager.pendingDeliveryToken, initial: true) { _, _ in
            openPendingNotificationIfNeeded()
        }
        // Heard by the app, so a link that arrived before the tabs did is still followed.
        .onChange(of: linkInbox?.pending, initial: true) { _, _ in
            if let url = linkInbox?.take() { handleIncomingURL(url) }
        }
        // Dates follow the app's language, not the device's: left to the device locale the
        // date strips rendered "M T W T F S S" under French copy.
        .environment(\.locale, AppLanguage.locale)
        .modifier(LiquidTabBarModifier())
    }

    @MainActor
    private func liveToken() async throws -> String {
        guard let token = try await clerk.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
    }

    /// Session reminders are local: rescheduled from the plan on launch, on each return and
    /// whenever the plan changes, so a session moved or done never rings.
    private func refreshSessionReminders() async {
        await SessionReminderScheduler.shared.refresh(
            isEnabledOnPhone: pushManager.isEnabledByAthlete,
            profiles: profileClient,
            plan: plannedSessionClient,
            tokenProvider: liveToken
        )
        await refreshAppleCalendar()
    }

    /// Apple Calendar: busy when enabled; plan sessions written as soon as it is linked (ADR 0016).
    private func refreshAppleCalendar() async {
        await AppleCalendarSync.shared.refresh(
            plan: plannedSessionClient,
            tokenProvider: liveToken,
            sourcePrefsClient: sharpitClient,
            sessionWriter: plannedSessionClient,
            busyClient: sharpitClient,
            calendarLinker: sharpitClient
        )
    }

    /// Callers: RootView. API: dayCheckIns prefs. User: fix all — P2 check-ins.
    private func refreshDayCheckIns() async {
        await DayCheckInReminderScheduler.shared.refresh(
            isEnabledOnPhone: pushManager.isEnabledByAthlete,
            profiles: profileClient,
            tokenProvider: liveToken
        )
    }

    private func openPendingNotificationIfNeeded() {
        if let destination = pushManager.consumePendingDestination() {
            router.open(destination)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        switch IncomingLink.parse(url) {
        case .oauthCallback(let provider, let status):
            handleOAuthCallback(provider: provider, status: status)
        case .tab(let tab):
            router.open(.tab(tab))
        case .settings(let route):
            router.openSettings(on: route)
        case .activity(let id):
            router.openActivity(id: id)
        case .plannedSession(let id):
            router.openPlannedSession(id: id)
        case .goals:
            router.open(.goals)
        case .today(let page):
            router.openToday(page)
        case nil:
            break
        }
    }

    /// Universal-link return when the OAuth sheet did not swallow the callback (Safari / cold open).
    private func handleOAuthCallback(provider: String, status: String?) {
        guard let source = DisconnectableSource(rawValue: provider), source.connectsViaOAuthHandoff else {
            return
        }
        let outcome = ProviderOAuthConnectOutcome(status: status)
        toastCenter.show(
            outcome.message(for: source),
            symbol: outcome.symbol,
            tone: outcome.tone,
            autoDismissAfter: outcome.toastDuration
        )
        guard outcome == .connected else { return }
        Task {
            do {
                let token = try await liveToken()
                _ = try await sharpitClient.sync(token: token)
            } catch {
                toastCenter.show(
                    SharpitErrorGuidance.message(for: error, subject: String(localized: "La synchronisation")),
                    symbol: "exclamationmark.triangle",
                    tone: .error,
                    autoDismissAfter: 4
                )
            }
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

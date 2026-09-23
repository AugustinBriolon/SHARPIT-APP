import SwiftData
import SwiftUI

struct TodayView: View {
    @State private var store: TodayStore
    @State private var weather = LocationWeatherService()
    /// Nil without a token or a client: a fixture-backed Today has nothing to pull.
    @State private var sync: ProviderSyncStore?
    private let appleHealth: AppleHealthSource?
    @Environment(\.scenePhase) private var scenePhase

    /// Kept so an activity opened from here can load itself. Nil in previews and
    /// fixtures, where a done session has nothing to fetch.
    private let tokenProvider: (() async throws -> String)?

    /// Nil without a token: the mode chip and the journal both write, and a control
    /// that cannot save is worse than no control.
    @State private var activityStatusStore: ActivityStatusStore?
    private let journalClient: (any JournalServing)?
    private let wellnessClient: (any WellnessServing)?
    private let signalClient: (any SleepServing & RecoveryServing)?
    /// Held as well as handed to the store, because the journal opened from here caches its
    /// own day and needs the same context.
    private let modelContext: ModelContext?

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil,
        modelContext: ModelContext? = nil,
        activityStatusClient: (any ActivityStatusServing)? = nil,
        journalClient: (any JournalServing)? = nil,
        wellnessClient: (any WellnessServing)? = nil,
        signalClient: (any SleepServing & RecoveryServing)? = nil,
        syncClient: (any SyncServing)? = nil,
        appleHealth: AppleHealthSource? = nil
    ) {
        self.appleHealth = tokenProvider == nil ? nil : appleHealth
        self.modelContext = modelContext
        _sync = State(initialValue: syncClient.flatMap { client in
            tokenProvider.map { ProviderSyncStore(client: client, tokenProvider: $0) }
        })
        self.signalClient = tokenProvider == nil ? nil : signalClient
        self.tokenProvider = tokenProvider
        self.journalClient = tokenProvider == nil ? nil : journalClient
        self.wellnessClient = tokenProvider == nil ? nil : wellnessClient
        _store = State(
            initialValue: TodayStore(
                client: client,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        )
        _activityStatusStore = State(
            initialValue: activityStatusClient.flatMap { client in
                tokenProvider.map { ActivityStatusStore(client: client, tokenProvider: $0) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch store.phase {
                case .loading:
                    SharpitLoadingInstrument()
                case .loaded(let fold):
                    TodayFoldView(
                        fold: fold,
                        hasCompletedArrival: store.hasCompletedArrival,
                        pulseScores: store.pulseScores,
                        sessionDoneCelebrations: store.sessionDoneCelebrations,
                        tokenProvider: tokenProvider,
                        signalClient: signalClient,
                        onArrival: { store.handleArrivalWins(fold: fold) },
                        onArrivalCompleted: { store.markArrivalCompleted() },
                        onSessionLinked: { Task { await store.refresh() } }
                    )
                case .empty(let empty):
                    TodayEmptyView(empty: empty)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Résumé indisponible", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") {
                            Task { await store.load(resetToLoading: true) }
                        }
                    }
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger le résumé.")
                    }
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle(store.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .sharpitSyncToast(sync)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let activityStatusStore {
                        ActivityStatusButton(store: activityStatusStore)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let journalClient, let wellnessClient, let tokenProvider {
                        NavigationLink {
                            JournalView(
                                client: journalClient,
                                wellness: wellnessClient,
                                tokenProvider: tokenProvider,
                                modelContext: modelContext
                            )
                        } label: {
                            Label("Journal", systemImage: "book.closed")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WeatherToolbarChip(service: weather)
                }
            }
            .refreshable {
                await store.refresh()
                weather.start()
                // The pull can take a minute; the gesture ends on what the server has now,
                // and the screen reloads once the providers have answered.
                Task { await pullProviders(force: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await pullProviders(force: false) }
            }
            .task {
                let shouldReset = !store.hasCompletedArrival && store.phase == .loading
                await store.load(resetToLoading: shouldReset)
                Task { await pullProviders(force: false) }
                weather.start()
            }
        }
    }
}

extension TodayView {
    /// Pulls the providers — always when asked, otherwise only when the last pull is stale —
    /// and reloads Today when fresh data came in.
    fileprivate func pullProviders(force: Bool) async {
        // Apple Health first: it is on the phone and answers in seconds, while the
        // provider pull can take a minute.
        if let appleHealth, let tokenProvider, await appleHealth.send(token: tokenProvider) {
            await store.refresh()
        }
        guard let sync else { return }
        let pulled = force ? await sync.syncNow() : await sync.syncIfStale()
        if pulled { await store.refresh() }
    }
}

private struct TodayFoldView: View {
    @Environment(ShellRouter.self) private var router
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    let fold: TodayFold
    var hasCompletedArrival: Bool = false
    var pulseScores: Bool = false
    var sessionDoneCelebrations: Set<String> = []
    var tokenProvider: (() async throws -> String)?
    var signalClient: (any SleepServing & RecoveryServing)?
    var onArrival: () -> Void = {}
    var onArrivalCompleted: () -> Void = {}
    /// Called once a prescription has been linked, so Today reloads and shows it as done.
    var onSessionLinked: () -> Void = {}

    @State private var selectedPreview: PlannedSessionPreview?
    @State private var openedSignal: V1TodaySignalKey?
    @State private var consecutiveWeeks: Int? = nil
    @State private var sleepOverrideCaption: String? = nil

    /// Arrival phase drives the staggered reveal of each section.
    @State private var phase: TodayArrivalPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        fold: TodayFold,
        hasCompletedArrival: Bool = false,
        pulseScores: Bool = false,
        sessionDoneCelebrations: Set<String> = [],
        tokenProvider: (() async throws -> String)? = nil,
        signalClient: (any SleepServing & RecoveryServing)? = nil,
        onArrival: @escaping () -> Void = {},
        onArrivalCompleted: @escaping () -> Void = {},
        onSessionLinked: @escaping () -> Void = {}
    ) {
        self.fold = fold
        self.hasCompletedArrival = hasCompletedArrival
        self.pulseScores = pulseScores
        self.sessionDoneCelebrations = sessionDoneCelebrations
        self.tokenProvider = tokenProvider
        self.signalClient = signalClient
        self.onArrival = onArrival
        self.onArrivalCompleted = onArrivalCompleted
        self.onSessionLinked = onSessionLinked
        _phase = State(initialValue: hasCompletedArrival ? .idle : .hidden)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                InkVerdictPlate(plate: fold.plate, revealed: phase.showsPlate)

                evidenceSection
                    .opacity(phase.showsSession ? 1 : 0)
                    .offset(y: phase.showsSession ? 0 : 18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.01)
                            : .spring(response: 0.40, dampingFraction: 0.80).delay(0.06),
                        value: phase.showsSession
                    )

                if !fold.gauges.isEmpty {
                    OvernightGaugePair(
                        gauges: fold.gauges,
                        sleepOverrideCaption: sleepOverrideCaption,
                        pulseScores: pulseScores,
                        animated: !hasCompletedArrival,
                        onSelect: signalClient == nil ? nil : { openedSignal = $0 }
                    )
                    .opacity(phase.showsGauges ? 1 : 0)
                    .offset(y: phase.showsGauges ? 0 : 18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.01)
                            : .spring(response: 0.40, dampingFraction: 0.80).delay(0.08),
                        value: phase.showsGauges
                    )
                }
                if let consistency = fold.consistency, !consistency.days.isEmpty {
                    ConsistencyStrip(
                        consistency: consistency,
                        consecutiveWeeks: consecutiveWeeks
                    ) {
                        router.select(.plan)
                    }
                    .opacity(phase.showsGauges ? 1 : 0)
                    .offset(y: phase.showsGauges ? 0 : 18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.01)
                            : .spring(response: 0.40, dampingFraction: 0.80).delay(0.14),
                        value: phase.showsGauges
                    )
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
            .containerRelativeFrame(.horizontal, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .modifier(ScrollUnderGlass())
        .navigationDestination(item: $openedSignal) { key in
            signalDetail(for: key)
        }
        .sheet(item: $selectedPreview) { preview in
            PlannedSessionDrawer(
                preview: preview,
                linking: linkContext,
                watchPush: watchPushContext,
                loadBreakdown: breakdownLoader(for: preview)
            ) { context in
                router.discussWithCoach(about: context)
            }
        }
        .task {
            if !hasCompletedArrival {
                onArrival()
                await TodayArrivalDirector.run(
                    reduceMotion: reduceMotion,
                    gaugeCount: fold.gauges.count
                ) { phase = $0 }
                onArrivalCompleted()
            } else {
                phase = .idle
            }
            await loadTelemetryEnrichments()
        }
    }

    private func loadTelemetryEnrichments() async {
        guard let tokenProvider else { return }
        guard let token = try? await tokenProvider() else { return }

        // 1. Calculate consecutive active weeks
        let activityClient = ActivityClient()
        if let activities = try? await activityClient.activities(forceRefresh: true, token: token) {
            let streak = ActivityStreakCalculator.consecutiveWeeksWithActivity(
                activities: activities,
                referenceDate: .now
            )
            consecutiveWeeks = streak
        }

        // 2. Calculate sleep target missing duration
        if let signalClient,
           let sleep = try? await signalClient.sleep(trainingDayId: fold.trainingDayId, token: token) {
            let delta = sleep.targetDeltaMin ?? (sleep.durationMin.map { $0 - sleep.targetMin })
            if let delta {
                if delta < -0.5 {
                    sleepOverrideCaption = "Manque · \(SleepReadout.duration(abs(delta)))"
                } else {
                    sleepOverrideCaption = "Objectif · Atteint"
                }
            }
        } else if let profile = try? await AthleteProfileClient().athleteProfile(token: token),
                  let targetMin = profile.sleepTargetMinutes, targetMin > 0,
                  let sleepGauge = fold.gauges.first(where: { $0.key == .sleep }),
                  let caption = sleepGauge.caption,
                  let durationMin = parseDurationMinutes(from: caption) {
            let delta = Double(durationMin - targetMin)
            if delta < -0.5 {
                sleepOverrideCaption = "Manque · \(SleepReadout.duration(abs(delta)))"
            } else {
                sleepOverrideCaption = "Objectif · Atteint"
            }
        }
    }

    private func parseDurationMinutes(from text: String) -> Int? {
        var totalMinutes = 0
        var foundAny = false

        if let hRange = text.range(of: #"\b(\d+)\s*h"#, options: .regularExpression) {
            let match = String(text[hRange])
            let digits = match.filter(\.isNumber)
            if let h = Int(digits) {
                totalMinutes += h * 60
                foundAny = true
            }
        }

        if let mRange = text.range(of: #"h\s*(\d+)"#, options: .regularExpression) {
            let match = String(text[mRange])
            let digits = match.filter(\.isNumber)
            if let m = Int(digits) {
                totalMinutes += m
                foundAny = true
            }
        } else if let minRange = text.range(of: #"\b(\d+)\s*min"#, options: .regularExpression) {
            let match = String(text[minRange])
            let digits = match.filter(\.isNumber)
            if let m = Int(digits) {
                totalMinutes += m
                foundAny = true
            }
        }

        return foundAny ? totalMinutes : nil
    }


    @ViewBuilder
    private func signalDetail(for key: V1TodaySignalKey) -> some View {
        if let signalClient, let tokenProvider {
            switch key {
            case .sleep:
                SleepView(client: signalClient, tokenProvider: tokenProvider)
            case .recovery:
                RecoveryView(client: signalClient, tokenProvider: tokenProvider)
            case .effort, .adaptation:
                EmptyView()
            }
        }
    }

    /// Reads the plan for the day to find what Today's line leaves out. Nil without a token
    /// or a session id — there is then nothing to look up.
    private func breakdownLoader(for preview: PlannedSessionPreview) -> (() async -> V1PlannedSessionBreakdown?)? {
        guard let tokenProvider, let sessionId = preview.sessionId else { return nil }
        let day = TrainingDayId.date(fold.trainingDayId) ?? .now
        return {
            guard let token = try? await tokenProvider(),
                  let sessions = try? await PlannedSessionClient().plannedSessions(from: day, to: day, token: token)
            else { return nil }
            return PlannedSessionPreview.breakdown(of: sessionId, in: sessions)
        }
    }

    /// Nil without a token: a fixture-backed Today has nothing to link against.
    private var linkContext: SessionLinkContext? {
        guard let tokenProvider else { return nil }
        return SessionLinkContext(
            referenceDate: TrainingDayId.date(fold.trainingDayId) ?? .now,
            activities: ActivityClient(),
            linker: PlannedSessionClient(),
            tokenProvider: tokenProvider,
            onLinked: {
                selectedPreview = nil
                toastCenter?.show(
                    "Séance liée avec succès",
                    symbol: "link",
                    tone: .success,
                    autoDismissAfter: 3.0
                )
                onSessionLinked()
            }
        )
    }

    private var watchPushContext: SessionWatchPushContext? {
        guard let tokenProvider else { return nil }
        return SessionWatchPushContext(
            pusher: PlannedSessionClient(),
            tokenProvider: tokenProvider
        )
    }

    @ViewBuilder
    private var evidenceSection: some View {
        if fold.sessions.isEmpty {
            RestDayPlate()
        } else {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                ForEach(fold.sessions) { session in
                    TodaySessionLink(
                        session: session,
                        showPriorityTag: SessionPriorityPolicy.showsTag(
                            sessionCount: fold.sessions.count,
                            priority: session.priority
                        ),
                        celebrateDone: sessionDoneCelebrations.contains(session.id),
                        tokenProvider: tokenProvider,
                        onOpenPreview: { selectedPreview = $0 }
                    )
                }
            }
        }
    }
}


/// Today's session line, made openable.
///
/// The same rule as the plan, because it is the same object seen from another screen: a
/// session that was done opens its own record, a prescription opens the drawer. Today
/// carries no activity payload, so the detail screen loads it from the id.
private struct TodaySessionLink: View {
    let session: SessionCardModel
    let showPriorityTag: Bool
    let celebrateDone: Bool
    let tokenProvider: (() async throws -> String)?
    let onOpenPreview: (PlannedSessionPreview) -> Void

    private var plate: some View {
        SessionPlate(
            session: session,
            showPriorityTag: showPriorityTag,
            celebrateDone: celebrateDone
        )
    }

    var body: some View {
        switch session.kind {
        case .done:
            // Only when the screen can actually fetch it. A fixture-backed Today has no
            // token, and a link that dead-ends is worse than a plate that does not move.
            if let tokenProvider {
                NavigationLink {
                    ActivityDetailView(
                        activity: session.id,
                        initialActivity: nil,
                        client: ActivityClient(),
                        tokenProvider: tokenProvider
                    )
                } label: {
                    plate
                }
                .buttonStyle(.sharpitPressable)
            } else {
                plate
            }
        case .planned:
            Button {
                onOpenPreview(PlannedSessionPreview(card: session))
            } label: {
                plate
            }
            .buttonStyle(.sharpitPressable)
        }
    }
}

private struct TodayEmptyView: View {
    let empty: V1TodayEmpty

    var body: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: "tray")
        } description: {
            if let message = empty.message {
                Text(message)
            }
        } actions: {
            if let url = URL(string: empty.webURL) {
                Link("Continuer sur le web", destination: url)
            }
        }
    }
}

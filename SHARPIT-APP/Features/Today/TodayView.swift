import SwiftData
import SwiftUI

struct TodayView: View {
    @State private var store: TodayStore
    @State private var weather = LocationWeatherService()
    /// Nil without a token or a client: a fixture-backed Today has nothing to pull.
    @State private var sync: ProviderSyncStore?
    private let appleHealth: AppleHealthSource?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ShellRouter.self) private var router
    @Environment(\.features) private var features
    @Environment(LaunchCurtain.self) private var launchCurtain: LaunchCurtain?

    /// Kept so an activity opened from here can load itself. Nil in previews and
    /// fixtures, where a done session has nothing to fetch.
    private let tokenProvider: (() async throws -> String)?

    /// Nil without a token: the mode chip and the journal both write, and a control
    /// that cannot save is worse than no control.
    @State private var activityStatusStore: ActivityStatusStore?
    private let journalClient: (any JournalServing)?
    private let wellnessClient: (any WellnessServing)?
    private let signalClient: (any SleepServing & RecoveryServing)?
    private let nutritionClient: (any NutritionServing)?
    /// Today's food log for the nutrition card. Nil without a token or a client.
    @State private var nutrition: NutritionTodayStore?
    @State private var showsCheckIn = false
    @State private var showsDayPicker = false
    /// Which past days hold a night or a session, marked in the calendar as on the day screens.
    @State private var dayMarks: DataDaysMarker?
    /// True while an optimistic Ressenti save waits on the server — blocks re-prompting.
    @State private var ressentiPendingConfirmation = false
    /// Shown when the sheet reopens after a failed optimistic save.
    @State private var ressentiFailureMessage: String?
    /// Bumped when a wellness save changed the morning verdict — fades the ink plate.
    /// Résumé's push stack — Journal from the chip or a day-check-in notification.
    @State private var path = NavigationPath()
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
        nutritionClient: (any NutritionServing)? = nil,
        syncClient: (any SyncServing)? = nil,
        appleHealth: AppleHealthSource? = nil,
        dataDaysClient: any DataDaysServing = SharpitClient()
    ) {
        self.appleHealth = tokenProvider == nil ? nil : appleHealth
        _dayMarks = State(initialValue: tokenProvider.map { tokenProvider in
            DataDaysMarker(tokenProvider: tokenProvider) { from, to, token in
                // A Résumé day holds data when it has a night or a session to read.
                async let nights = dataDaysClient.dataDays(domain: .sleep, from: from, to: to, token: token)
                async let sessions = dataDaysClient.dataDays(domain: .effort, from: from, to: to, token: token)
                return Array(Set(try await nights + sessions))
            }
        })
        self.modelContext = modelContext
        _sync = State(initialValue: syncClient.flatMap { client in
            tokenProvider.map { ProviderSyncStore(client: client, tokenProvider: $0) }
        })
        self.signalClient = tokenProvider == nil ? nil : signalClient
        self.nutritionClient = tokenProvider == nil ? nil : nutritionClient
        _nutrition = State(initialValue: nutritionClient.flatMap { client in
            tokenProvider.map { NutritionTodayStore(client: client, tokenProvider: $0, modelContext: modelContext) }
        })
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
        NavigationStack(path: $path) {
            ZStack {
                switch store.phase {
                case .loading:
                    SharpitLoadingInstrument()
                        .safeAreaInset(edge: .top) { pinnedDayTitle }
                case .loaded(let fold) where fold.trainingDayId != store.dayId:
                    // The day asked for is not read yet: its loading shape, under its own date.
                    SharpitLoadingInstrument()
                        .safeAreaInset(edge: .top) { pinnedDayTitle }
                case .loaded(let fold):
                    TodayFoldView(
                        fold: fold,
                        hasCompletedArrival: store.hasCompletedArrival,
                        pulseScores: store.pulseScores,
                        sessionDoneCelebrations: store.sessionDoneCelebrations,
                        tokenProvider: tokenProvider,
                        signalClient: signalClient,
                        nutrition: nutrition,
                        nutritionClient: nutritionClient,
                        onArrival: { store.handleArrivalWins(fold: fold) },
                        onArrivalCompleted: { store.markArrivalCompleted() },
                        onSessionLinked: { Task { await store.refresh() } },
                        onAnswerProposal: { accept in
                            Task {
                                if await store.respondToMorningProposal(accept: accept) {
                                    router.noteCalendarChanged()
                                }
                            }
                        },
                        onCheckIn: (wellnessClient != nil && tokenProvider != nil && store.isToday) ? { showsCheckIn = true } : nil,
                        controls: AnyView(controlsRow),
                        activityStatusStore: activityStatusStore
                    )
                    .id(fold.trainingDayId)
                case .empty(let empty):
                    TodayEmptyView(empty: empty)
                        .safeAreaInset(edge: .top) { pinnedDayTitle }
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
                    .safeAreaInset(edge: .top) { pinnedDayTitle }
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger le résumé.")
                    }
                }
            }
            // Right for the day before, left for the day after, never past today. A swipe that
            // starts on a card turns the day without opening it (`DaySwipe`).
            .daySwipe(day: TrainingDayId.date(store.dayId) ?? .now) { openDay($0) } neighbor: { day in
                neighborPage(day)
            }
            .background(SharpitCanvasBackground())
            // The date heads the page as a button (`dayTitle`): a toolbar large title takes no
            // touch on iOS 26. The bar keeps only the avatar; the name stays for VoiceOver.
            .navigationTitle(store.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsDayPicker) { dayPicker }
            .modifier(LiquidNavChrome())
            .sharpitSyncToast(sync)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountAvatarButton { router.openSettings() }
                }
            }
            .refreshable {
                async let refreshToday: Void = store.refresh()
                async let refreshNutrition: Void? = nutrition?.load(trainingDayId: store.dayId)
                async let refreshStatus: Void? = activityStatusStore?.load()
                _ = await (refreshToday, refreshNutrition, refreshStatus)
                weather.start()
                // The pull can take a minute; the gesture ends on what the server has now,
                // and the screen reloads once the providers have answered.
                Task { await pullProviders(force: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await pullProviders(force: false)
                    await evaluateRessentiPrompt()
                }
            }
            // The night syncs after the screen opened: its sleep may make the prompt due.
            .onChange(of: RessentiPromptTiming.hasLastNightSleep(overnightGauges)) { _, hasSleep in
                guard hasSleep else { return }
                Task { await evaluateRessentiPrompt() }
            }
            .onChange(of: router.calendarRevision) { _, _ in
                Task { await store.refresh() }
            }
            .onChange(of: router.checkInRevision) { _, _ in
                Task { await store.load(resetToLoading: false, force: true) }
            }
            .navigationDestination(for: TodayNav.self) { destination in
                switch destination {
                case .journal:
                    if let journalClient, let wellnessClient, let tokenProvider {
                        JournalView(
                            client: journalClient,
                            wellness: wellnessClient,
                            tokenProvider: tokenProvider,
                            modelContext: modelContext
                        )
                    }
                }
            }
            .onChange(of: router.pendingJournal, initial: true) { _, pending in
                guard pending else { return }
                router.pendingJournal = false
                guard features.isOn(.journal), journalClient != nil, wellnessClient != nil, tokenProvider != nil
                else { return }
                path.append(TodayNav.journal)
            }
            .sheet(isPresented: $showsCheckIn) {
                if let wellnessClient, let tokenProvider, let athleteId = localAthleteId {
                    RessentiDuJourSheet(
                        client: wellnessClient,
                        tokenProvider: tokenProvider,
                        athleteId: athleteId,
                        trainingDayId: TrainingDayId.today(),
                        initialFailureMessage: ressentiFailureMessage,
                        onOptimisticClose: {
                            ressentiPendingConfirmation = true
                            ressentiFailureMessage = nil
                            showsCheckIn = false
                            MorningFeelBadge.shared.clearOptimistically()
                        },
                        onSaved: { summary in
                            ressentiPendingConfirmation = false
                            ressentiFailureMessage = nil
                            MorningFeelBadge.shared.confirmCleared()
                            handleRessentiSaved(summary)
                        },
                        onSaveFailed: {
                            ressentiPendingConfirmation = false
                            ressentiFailureMessage = RessentiDuJourStore.saveFailureMessage
                            MorningFeelBadge.shared.restore()
                            // Let the optimistic dismiss settle before re-presenting with the draft.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                showsCheckIn = true
                            }
                        }
                    )
                }
            }
            .task {
                let shouldReset = !store.hasCompletedArrival && store.phase == .loading
                // The food log and activity status are read alongside today rather than once the fold
                // is drawn, so all fold cards arrive together without cascading layout shifts.
                async let statusRead: Void? = activityStatusStore?.loadIfNeeded()
                async let nutritionRead: Void? = nutrition?.loadIfNeeded(trainingDayId: store.dayId)
                await store.load(resetToLoading: shouldReset)
                // The server has answered, or refused: Résumé is drawn whole, and the splash may
                // go. The snapshot alone is the plate without its sessions, so it waits for the
                // curtain's ceiling instead.
                launchCurtain?.markReady()
                Task { await pullProviders(force: false) }
                weather.start()
                _ = await (statusRead, nutritionRead)
                await evaluateRessentiPrompt()
            }
        }
    }
}

private enum TodayNav: Hashable {
    case journal
}

extension TodayView {
    /// Mode, Journal and weather, as one row of glass chips.
    @ViewBuilder
    fileprivate var controlsRow: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            dayTitle
            chips
        }
    }

    /// The month calendar, each past day marked when it holds a night or a session.
    fileprivate var dayPicker: some View {
        let weeks = SharpitWeeks(offsets: SharpitWeeks.history)
        let shown = TrainingDayId.date(store.dayId) ?? .now
        let marks = SharpitCalendarMark.dataMarks(in: weeks) { day in
            dayMarks?[TrainingDayId.today(now: day)]
        }
        return SharpitCalendarSheet(
            title: String(localized: "Résumé"),
            initial: shown,
            weeks: weeks,
            range: weeks.selectableDates.lowerBound...Date.now,
            marks: marks,
            legend: [(.filled, String(localized: "Nuit ou séance")), (.muted, String(localized: "Aucune donnée"))],
            onPick: openDay,
            onToday: { openDay(.now) }
        )
        .task { await dayMarks?.ensure(around: shown) }
    }

    /// The day read, as the page's title: tapping it opens the calendar to read another one.
    fileprivate var dayTitle: some View {
        Button { showsDayPicker = true } label: {
            dayTitleLabel(store.navigationTitle)
                .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Choisir un autre jour, ou glisser pour la veille")
    }

    fileprivate func dayTitleLabel(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(title)
                .font(SharpitTypography.screenTitle)
                .tracking(SharpitTypography.screenTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
            Image(systemName: "chevron.down")
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }

    /// The day beside the page while a swipe moves it, laid out as it will be once it is the
    /// page: its fold if already read, its loading shape otherwise — always under its own date.
    @ViewBuilder
    fileprivate func neighborPage(_ day: Date) -> some View {
        let title = dayTitleLabel(TrainingDayId.displayName(TrainingDayId.today(now: day)))
        if let fold = store.knownFold(on: day) {
            TodayFoldView(
                fold: fold,
                hasCompletedArrival: true,
                controls: AnyView(VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    title
                    chips
                }),
                activityStatusStore: activityStatusStore
            )
        } else {
            SharpitLoadingInstrument()
                .safeAreaInset(edge: .top) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        title
                        chips
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SharpitSpacing.pageInset)
                        .padding(.vertical, SharpitSpacing.xs)
                }
        }
    }

    /// The date over a page that has no fold to carry it — loading, empty or failed — so the
    /// athlete can always pick another day.
    fileprivate var pinnedDayTitle: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            dayTitle
            chips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.vertical, SharpitSpacing.xs)
    }

    fileprivate var chips: some View {
        SharpitGlassGroup {
            HStack(spacing: SharpitSpacing.xs) {
                if let activityStatusStore {
                    ActivityStatusButton(store: activityStatusStore, showsLabel: true)
                }
                if features.isOn(.journal), let journalClient, let wellnessClient, let tokenProvider {
                    NavigationLink(value: TodayNav.journal) {
                        Label("Journal", systemImage: "book.closed")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(SharpitColor.foreground)
                            .sharpitGlassChip()
                    }
                    .buttonStyle(.sharpitPressable)
                }
                Spacer(minLength: 0)
                WeatherChip(service: weather)
            }
            .animation(SharpitMotion.reveal, value: weather.reading)
        }
    }

    /// Clerk user claimed into `LocalAccountData` — scopes draft / dismissal per athlete.
    fileprivate var localAthleteId: String? {
        UserDefaults.standard.string(forKey: LocalAccountData.ownerKey)
    }

    /// Server is the source of truth: present the half-sheet only when today's check-in
    /// is missing and the athlete has not dismissed it for this local day.
    fileprivate func openDay(_ day: Date) {
        showsDayPicker = false
        Task {
            await store.select(day: day)
            await nutrition?.load(trainingDayId: store.dayId)
        }
    }

    fileprivate var overnightGauges: [OvernightGaugeModel] {
        if case .loaded(let fold) = store.phase { return fold.gauges }
        return []
    }

    @MainActor
    fileprivate func evaluateRessentiPrompt() async {
        guard !showsCheckIn, !ressentiPendingConfirmation, store.isToday else { return }
        guard RessentiPromptTiming.isDue(now: .now, hasLastNightSleep: RessentiPromptTiming.hasLastNightSleep(overnightGauges)) else { return }
        guard let wellnessClient, let tokenProvider, let athleteId = localAthleteId else { return }
        do {
            let token = try await tokenProvider()
            let status = try await wellnessClient.wellnessCheckinStatus(token: token)
            guard !status.completed else { return }
            guard !WellnessCheckInLocalStore.shared.isDismissed(
                athleteId: athleteId,
                localDate: status.localDate
            ) else { return }
            showsCheckIn = true
        } catch {
            // Silent — never block Résumé on a status read; the athlete can still open it
            // from the morning proposal card.
        }
    }

    @MainActor
    /// The verdict cross-fades on its own when the reload brings a new one.
    fileprivate func handleRessentiSaved(_: V1WellnessVerdictSummary?) {
        router.noteMorningCheckIn()
        Task { await store.load(resetToLoading: false) }
    }

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
        if pulled {
            await store.refresh()
            // The food log came in with the pull: the nutrition card reads it only now.
            await nutrition?.load(trainingDayId: store.dayId)
        }
    }
}

private struct TodayFoldView: View {
    @Environment(ShellRouter.self) private var router
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @Environment(\.features) private var features

    let fold: TodayFold
    var hasCompletedArrival: Bool = false
    var pulseScores: Bool = false
    var sessionDoneCelebrations: Set<String> = []
    var tokenProvider: (() async throws -> String)?
    var signalClient: (any SleepServing & RecoveryServing)?
    var nutrition: NutritionTodayStore?
    var nutritionClient: (any NutritionServing)?
    var onArrival: () -> Void = {}
    var onArrivalCompleted: () -> Void = {}
    /// Called once a prescription has been linked, so Today reloads and shows it as done.
    var onSessionLinked: () -> Void = {}
    /// Answers the night's proposal for today's session; true accepts it.
    var onAnswerProposal: (Bool) -> Void = { _ in }
    /// Opens the morning check-in, which refines the proposal.
    var onCheckIn: (() -> Void)?
    /// Mode, Journal and weather — the fold's first row, scrolling away with the rest.
    var controls: AnyView?

    /// The athlete's training-mode store. When `current != .active`, an alert line is
    /// shown under the verdict plate. Not passed when there is no token.
    var activityStatusStore: ActivityStatusStore?

    @State private var selectedPreview: PlannedSessionPreview?
    @State private var selectedBrick: PlannedBrickPreview?
    @State private var selectedDoneBrick: DoneBrickPreview?
    @State private var openedSignal: V1TodaySignalKey?
    @State private var openedNutrition: NutritionDestination?
    @State private var consecutiveWeeks: Int? = nil
    @State private var sleepOverrideCaption: String? = nil

    /// Arrival phase drives the staggered reveal of each section.
    @State private var phase: TodayArrivalPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Up on a cold launch: the arrival waits for it, so it plays as the splash leaves.
    @Environment(LaunchCurtain.self) private var launchCurtain: LaunchCurtain?

    init(
        fold: TodayFold,
        hasCompletedArrival: Bool = false,
        pulseScores: Bool = false,
        sessionDoneCelebrations: Set<String> = [],
        tokenProvider: (() async throws -> String)? = nil,
        signalClient: (any SleepServing & RecoveryServing)? = nil,
        nutrition: NutritionTodayStore? = nil,
        nutritionClient: (any NutritionServing)? = nil,
        onArrival: @escaping () -> Void = {},
        onArrivalCompleted: @escaping () -> Void = {},
        onSessionLinked: @escaping () -> Void = {},
        onAnswerProposal: @escaping (Bool) -> Void = { _ in },
        onCheckIn: (() -> Void)? = nil,
        controls: AnyView? = nil,
        activityStatusStore: ActivityStatusStore? = nil
    ) {
        self.fold = fold
        self.hasCompletedArrival = hasCompletedArrival
        self.pulseScores = pulseScores
        self.sessionDoneCelebrations = sessionDoneCelebrations
        self.tokenProvider = tokenProvider
        self.signalClient = signalClient
        self.nutrition = nutrition
        self.nutritionClient = nutritionClient
        self.onArrival = onArrival
        self.onArrivalCompleted = onArrivalCompleted
        self.onSessionLinked = onSessionLinked
        self.onAnswerProposal = onAnswerProposal
        self.onCheckIn = onCheckIn
        self.controls = controls
        self.activityStatusStore = activityStatusStore
        _phase = State(initialValue: hasCompletedArrival ? .idle : .hidden)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let controls {
                    // Air under the date, then close to the verdict: the chips lead into the day.
                    controls
                        .padding(.top, SharpitSpacing.xxs)
                        .padding(.bottom, -SharpitSpacing.xs)
                }
                if let race = fold.race {
                    TodayRaceLink(race: race, tokenProvider: tokenProvider)
                        .opacity(phase.showsPlate ? 1 : 0)
                        .offset(y: phase.showsPlate ? 0 : 10)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.01)
                                : .spring(response: 0.38, dampingFraction: 0.78),
                            value: phase.showsPlate
                        )
                }
                InkVerdictPlate(plate: fold.plate, revealed: phase.showsPlate)

                if let store = activityStatusStore, store.current != .active, store.phase != .loading {
                    ActivityStatusAlertLine(status: store.current)
                        .opacity(phase.showsPlate ? 1 : 0)
                        .offset(y: phase.showsPlate ? 0 : 18)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.01)
                                : .spring(response: 0.40, dampingFraction: 0.80).delay(0.07),
                            value: phase.showsPlate
                        )
                }

                if let proposal = fold.morningProposal {
                    MorningProposalCard(proposal: proposal, onCheckIn: onCheckIn, onAnswer: onAnswerProposal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let horizon = fold.planHorizon {
                    PlanHorizonCard(horizon: horizon) { router.open(.planGenerator) }
                }

                evidenceSection
                    .opacity(phase.showsSession ? 1 : 0)
                    .offset(y: phase.showsSession ? 0 : 18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.01)
                            : .spring(response: 0.40, dampingFraction: 0.80).delay(0.06),
                        value: phase.showsSession
                    )

                if !fold.gauges.isEmpty || fold.isPlateOnly {
                    OvernightGaugePair(
                        gauges: fold.isPlateOnly ? OvernightGaugeModel.placeholders : fold.gauges,
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
                // Callers: TodayFoldView. API: timeline. User: fix all — P2 day timeline.
                TodayTimelineStrip(events: fold.timeline)
                .opacity(phase.showsGauges ? 1 : 0)
                .offset(y: phase.showsGauges ? 0 : 18)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.01)
                        : .spring(response: 0.40, dampingFraction: 0.80).delay(0.10),
                    value: phase.showsGauges
                )
                if features.isOn(.regularity), let consistency = fold.consistency, !consistency.days.isEmpty {
                    ConsistencyStrip(
                        consistency: consistency,
                        consecutiveWeeks: consecutiveWeeks
                    ) {
                        router.openPlan(on: foldDay)
                    }
                    .opacity(phase.showsGauges ? 1 : 0)
                    .offset(y: phase.showsGauges ? 0 : 18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.01)
                            : .spring(response: 0.40, dampingFraction: 0.80).delay(0.12),
                        value: phase.showsGauges
                    )
                }
                if features.isOn(.nutrition), let nutrition {
                    NutritionTodayCard(phase: nutrition.phase) { openNutrition(nutrition.phase) }
                        .opacity(phase.showsGauges ? 1 : 0)
                        .offset(y: phase.showsGauges ? 0 : 18)
                        .animation(
                            reduceMotion ? .easeOut(duration: 0.01)
                                : .spring(response: 0.40, dampingFraction: 0.80).delay(0.16),
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
        .navigationDestination(item: $openedNutrition) { destination in
            nutritionDetail(for: destination)
        }
        .task(id: fold.trainingDayId) {
            await nutrition?.loadIfNeeded(trainingDayId: fold.trainingDayId)
        }
        // Meals are logged on the Nutrition page: the card (and the widget) read the day again
        // when the athlete comes back from it.
        .onChange(of: openedNutrition) { _, destination in
            guard destination == nil else { return }
            Task { await nutrition?.load(trainingDayId: fold.trainingDayId) }
        }
        // A widget tapped: Résumé shows the page it stands for, over nothing else it had open.
        .onChange(of: router.pendingTodayPage, initial: true) { _, page in
            guard let page else { return }
            router.pendingTodayPage = nil
            show(page)
        }

        .sheet(item: $selectedPreview) { preview in
            TodayPlannedSessionSheet(
                preview: preview,
                day: TrainingDayId.date(fold.trainingDayId) ?? .now,
                tokenProvider: tokenProvider,
                linking: linkContext,
                guidedFinish: guidedFinishContext,
                loadBreakdown: breakdownLoader(for: preview),
                loadStrengthPrescription: strengthPrescriptionLoader(for: preview),
                storedBreakdown: storedBreakdown(for: preview)
            ) { context in
                router.discussWithCoach(about: context)
            }
        }
        .sheet(item: $selectedDoneBrick) { brick in
            DoneBrickDrawer(brick: brick, tokenProvider: tokenProvider)
        }
        .sheet(item: $selectedBrick) { brick in
            BrickSessionDrawer(
                brick: brick,
                linking: linkContext,
                guidedFinish: guidedFinishContext,
                loadLegs: brickLoader(for: brick)
            ) { context in
                router.discussWithCoach(about: context)
            }
        }
        .task(id: launchCurtain?.isUp ?? false) {
            guard launchCurtain?.isUp != true else { return }
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
        // shortcut: a streak is read over the last 53 weeks, so it tops out at a year; widen the window if streaks that long matter.
        let streakFrom = Calendar.current.date(byAdding: .weekOfYear, value: -53, to: .now)
        if let activities = try? await activityClient.activities(from: streakFrom, to: nil, token: token) {
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
                    sleepOverrideCaption = String(localized: "Manque · \(SleepReadout.duration(abs(delta)))")
                } else {
                    sleepOverrideCaption = String(localized: "Objectif · Atteint")
                }
            }
        } else if let profile = try? await AthleteProfileClient().athleteProfile(token: token),
                  let targetMin = profile.sleepTargetMinutes, targetMin > 0,
                  let sleepGauge = fold.gauges.first(where: { $0.key == .sleep }),
                  let caption = sleepGauge.caption,
                  let durationMin = parseDurationMinutes(from: caption) {
            let delta = Double(durationMin - targetMin)
            if delta < -0.5 {
                sleepOverrideCaption = String(localized: "Manque · \(SleepReadout.duration(abs(delta)))")
            } else {
                sleepOverrideCaption = String(localized: "Objectif · Atteint")
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


    private func show(_ page: TodayPage) {
        selectedPreview = nil
        selectedBrick = nil
        selectedDoneBrick = nil
        switch page {
        case .overview:
            openedSignal = nil
            openedNutrition = nil
        case .sleep:
            openedNutrition = nil
            openedSignal = signalClient == nil ? nil : .sleep
        case .nutrition, .foodScan:
            openedSignal = nil
            guard features.isOn(.nutrition) else {
                openedNutrition = nil
                return
            }
            openedNutrition = page == .foodScan ? .scan : .day
        }
    }

    private func openNutrition(_ phase: NutritionTodayStore.Phase) {
        switch phase {
        case .loaded, .empty, .failed: openedNutrition = .day
        case .loading: break
        }
    }

    private var foldDay: Date { TrainingDayId.date(fold.trainingDayId) ?? .now }

    @ViewBuilder
    private func nutritionDetail(for destination: NutritionDestination) -> some View {
        switch destination {
        case .day:
            if let nutritionClient, let tokenProvider {
                NutritionView(client: nutritionClient, tokenProvider: tokenProvider, day: foldDay)
            }
        case .scan:
            if let nutritionClient, let tokenProvider {
                NutritionView(client: nutritionClient, tokenProvider: tokenProvider, day: foldDay, opensScanner: true)
            }
        }
    }

    @ViewBuilder
    private func signalDetail(for key: V1TodaySignalKey) -> some View {
        if let signalClient, let tokenProvider {
            switch key {
            case .sleep:
                SleepView(client: signalClient, tokenProvider: tokenProvider, day: foldDay)
            case .recovery:
                RecoveryView(client: signalClient, tokenProvider: tokenProvider, day: foldDay)
            case .effort, .adaptation, .stress:
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
            let breakdown = PlannedSessionPreview.breakdown(of: sessionId, in: sessions)
            if let breakdown, let data = try? JSONEncoder().encode(breakdown) {
                ActivityDiskCache.shared.write(data, .plannedBreakdown, id: sessionId)
            } else {
                ActivityDiskCache.shared.remove(.plannedBreakdown, id: sessionId)
            }
            return breakdown
        }
    }

    /// Today's card has no prescription payload — load it from the plan so muscu can be followed.
    private func strengthPrescriptionLoader(for preview: PlannedSessionPreview) -> (() async -> JSONValue?)? {
        guard let tokenProvider, let sessionId = preview.sessionId, preview.strengthPrescription == nil else { return nil }
        let day = TrainingDayId.date(fold.trainingDayId) ?? .now
        return {
            guard let token = try? await tokenProvider(),
                  let sessions = try? await PlannedSessionClient().plannedSessions(from: day, to: day, token: token)
            else { return nil }
            return sessions.first(where: { $0.id == sessionId })?.strengthPrescription
        }
    }

    private var guidedFinishContext: GuidedStrengthFinishContext? {
        guard let tokenProvider else { return nil }
        return GuidedStrengthFinishContext(
            client: ActivityClient(),
            linker: PlannedSessionClient(),
            tokenProvider: tokenProvider,
            onFinished: { _ in
                selectedPreview = nil
                selectedBrick = nil
                toastCenter?.show(
                    String(localized: "Séance muscu enregistrée"),
                    symbol: "checkmark.circle.fill",
                    tone: .success,
                    autoDismissAfter: 3.0
                )
                // Résumé reads the day again from it, and Plan and Activité follow.
                router.noteActivitiesChanged()
            }
        )
    }

    /// The breakdown read the last time this session was opened, so the drawer opens on it.
    /// Today's line names the legs; their steps are in the plan.
    private func brickLoader(for brick: PlannedBrickPreview) -> (() async -> PlannedBrickPreview?)? {
        guard let tokenProvider else { return nil }
        let day = TrainingDayId.date(fold.trainingDayId) ?? .now
        return {
            guard let token = try? await tokenProvider(),
                  let sessions = try? await PlannedSessionClient().plannedSessions(from: day, to: day, token: token)
            else { return nil }
            return brick.refreshed(from: sessions)
        }
    }

    private func storedBreakdown(for preview: PlannedSessionPreview) -> V1PlannedSessionBreakdown? {
        guard let sessionId = preview.sessionId,
              let stored = ActivityDiskCache.shared.read(.plannedBreakdown, id: sessionId)
        else { return nil }
        return try? JSONDecoder().decode(V1PlannedSessionBreakdown.self, from: stored.data)
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
                    String(localized: "Séance liée avec succès"),
                    symbol: "link",
                    tone: .success,
                    autoDismissAfter: 3.0
                )
                onSessionLinked()
            }
        )
    }

    @ViewBuilder
    private var evidenceSection: some View {
        if fold.isPlateOnly {
            // Unknown yet, not a rest day: hold the session's place until the day arrives.
            SessionPlate(session: .placeholder)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        } else if fold.sessions.isEmpty {
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
                        onOpenPreview: { selectedPreview = $0 },
                        onOpenBrick: { selectedBrick = $0 },
                        onOpenDoneBrick: { selectedDoneBrick = $0 }
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
    let onOpenBrick: (PlannedBrickPreview) -> Void
    let onOpenDoneBrick: (DoneBrickPreview) -> Void

    private var plate: some View {
        SessionPlate(
            session: session,
            showPriorityTag: showPriorityTag,
            celebrateDone: celebrateDone
        )
    }

    /// A single done session opens its own record — only when the screen can actually fetch it.
    /// A fixture-backed Today has no token, and a link that dead-ends is worse than a plate that
    /// does not move.
    @ViewBuilder
    private var doneLink: some View {
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
    }

    var body: some View {
        switch session.kind {
        case .done:
            // A brick opens as the chain it was, each leg beside its activity.
            if let brick = DoneBrickPreview(card: session) {
                Button { onOpenDoneBrick(brick) } label: { plate }
                    .buttonStyle(.sharpitPressable)
            } else {
                doneLink
            }
        case .planned:
            Button {
                // A brick opens as the chain it is, not as its first leg.
                if let brick = PlannedBrickPreview(card: session, date: nil) {
                    onOpenBrick(brick)
                } else {
                    onOpenPreview(PlannedSessionPreview(card: session))
                }
            } label: {
                plate
            }
            .buttonStyle(.sharpitPressable)
        }
    }
}

/// The race card, opening its session once there is one and the screen can fetch it.
private struct TodayRaceLink: View {
    let race: RaceMomentModel
    let tokenProvider: (() async throws -> String)?

    var body: some View {
        if let activityId = race.activityId, let tokenProvider {
            NavigationLink {
                ActivityDetailView(activity: activityId, client: ActivityClient(), tokenProvider: tokenProvider)
            } label: {
                RaceDayCard(race: race, opensSession: true)
            }
            .buttonStyle(.sharpitPressable)
        } else {
            RaceDayCard(race: race)
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

/// Where Résumé's nutrition card leads.
private enum NutritionDestination: Hashable, Identifiable {
    case day
    /// Opened from the « Scanner un produit » widget: the day, its scanner already up.
    case scan

    var id: Self { self }
}

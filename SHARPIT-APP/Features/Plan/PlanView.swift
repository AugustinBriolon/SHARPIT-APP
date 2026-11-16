import Observation
import SwiftUI

struct PlanView: View {
    let client: any PlannedSessionServing
    let linker: any PlannedSessionLinking
    let keyMutator: any PlannedSessionMutating
    /// The coach's memory, read for the week's trips.
    let memoryClient: any CoachMemoryServing
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var store: PlanStore
    @State private var selection: PlanSelection?
    /// The review closes first, then the generator opens: one sheet at a time.
    @State private var opensGeneratorAfterReview = false
    /// The expert reading's load layer, shown above this week (ADR 0006); nil otherwise.
    @State private var trainingLoad: V1TrainingLoad?
    /// Effort and Adaptation for today, under the current week.
    @State private var trajectory = PlanTrajectory()
    @State private var openedTrajectory: PlanTrajectoryDestination?
    @State private var showingCalendar = false
    @State private var showingMacroPlan = false
    /// Owned here, not by the sheet: closing it mid-generation keeps the week coming.
    @State private var generation: PlanGenerationStore
    @State private var showingAdapter = false
    @State private var activeCatchUp: PlanCatchUp?
    /// Plan's, not the sheet's: closing it mid-analysis keeps the proposal coming.
    @State private var adjustment: PlanAdjustmentStore
    /// Plan's, not the sheet's: reopening Objectifs shows the goals at once.
    @State private var goals: GoalStore
    /// Plan's, so a change written behind outlives the drawer or the form that made it.
    @State private var editor: PlanEditor
    @State private var showingNewSession = false
    /// The coach's trips, for the week's « Déplacement » chip (the web's `TravelContextBanner`).
    @State private var travels: [CoachMemoryEntry] = []
    /// The active plan, for the week's phase and the days left to the race.
    @State private var activePlan: V1TrainingPlan?
    @State private var showingTravel = false
    @State private var extrasGate = LoadGate()
    /// Garmin linked: the drawer then offers to send an endurance session to the watch.
    @State private var isGarminLinked = false

    init(
        client: any PlannedSessionServing,
        linker: any PlannedSessionLinking,
        activityClient: any ActivityServing,
        memoryClient: any CoachMemoryServing = CoachMemoryClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.memoryClient = memoryClient
        self.client = client
        self.linker = linker
        keyMutator = (client as? (any PlannedSessionMutating)) ?? PlannedSessionClient()
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
        _generation = State(initialValue: PlanGenerationStore(tokenProvider: tokenProvider))
        _adjustment = State(initialValue: PlanAdjustmentStore(tokenProvider: tokenProvider))
        _goals = State(initialValue: GoalStore(client: GoalClient(), tokenProvider: tokenProvider))
        let store = PlanStore(
            client: client,
            activityClient: activityClient,
            tokenProvider: tokenProvider
        )
        _store = State(initialValue: store)
        _editor = State(
            initialValue: PlanEditor(mutator: self.keyMutator, tokenProvider: tokenProvider, plan: store)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlanWeekPager(
                    store: store,
                    activityClient: activityClient,
                    tokenProvider: tokenProvider,
                    trainingLoad: isExpertReading ? trainingLoad : nil,
                    trajectory: trajectory,
                    chrome: PlanWeekChrome(
                        travels: travels,
                        plan: activePlan,
                        onAdapt: openAdapter,
                        onOpenCalendar: { showingCalendar = true },
                        onOpenTravel: { showingTravel = true },
                        onFillWeek: { router.isShowingPlanGenerator = true },
                        onAddSession: { showingNewSession = true },
                        onOpenGoals: { router.isShowingGoals = true },
                        onOpenMacroPlan: { showingMacroPlan = true },
                        onOpenWeeklyReview: { router.isShowingWeeklyReview = true }
                    ),
                    onSelect: { selection = $0 },
                    onOpenTrajectory: { openedTrajectory = $0 }
                )
            }
            // One wash for the screen, under the bar too: it follows the week on screen.
            .cliniqueSheet(wash: shownWash, height: 260)
            .animation(SharpitMotion.fade, value: shownWash)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            // The bar is its buttons only: no fill, no fade — « Plan » scrolls away with the week.
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedTrajectory) { destination in
                trajectoryDetail(for: destination)
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                // Two actions, two glyphs: have the week written, have it adapted.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.isShowingPlanGenerator = true } label: {
                        Label("Remplir ma semaine", systemImage: "calendar.badge.plus")
                    }
                }
                SharpitBarGap()
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openAdapter) {
                        Label("Adapter", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityHint("Dis au coach ce qui a changé dans ta semaine")
                }
            }
            .sheet(item: $selection) { selected in
                switch selected {
                case .session(let session):
                    PlannedSessionDrawer(
                        preview: PlannedSessionPreview(session: session, isExpertReading: isExpertReading),
                        linking: linkContext(on: session.date),
                        editing: editingContext(for: session),
                        watch: watchContext(for: session),
                        guidedFinish: guidedFinishContext()
                    ) { context in
                        router.discussWithCoach(about: context)
                    }
                case .brick(let brick):
                    BrickSessionDrawer(
                        brick: PlannedBrickPreview(brick: brick, isExpertReading: isExpertReading),
                        linking: linkContext(on: brick.date),
                        guidedFinish: guidedFinishContext()
                    ) { context in
                        router.discussWithCoach(about: context)
                    }
                case .doneBrick(let brick):
                    DoneBrickDrawer(brick: DoneBrickPreview(planned: brick), tokenProvider: tokenProvider)
                }
            }
            .sheet(isPresented: $showingNewSession) {
                PlannedSessionCreateSheet(editor: editor, day: newSessionDay)
            }
            .sheet(isPresented: $showingCalendar) {
                PlanCalendarSheet(store: store)
            }
            .sheet(isPresented: $showingTravel, onDismiss: { Task { await loadTravels() } }) {
                NavigationStack {
                    PlanTripsView(client: memoryClient, tokenProvider: tokenProvider)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("OK") { showingTravel = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .sharpitSheet()
            }
            // Goals moved here from Moi: they are what the plan is built toward.
            .sheet(isPresented: Bindable(router).isShowingGoals) {
                NavigationStack {
                    GoalsView(store: goals)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("OK") { router.isShowingGoals = false }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
                .sharpitSheet()
            }
            .sheet(isPresented: $showingMacroPlan) {
                MacroPlanSheet(tokenProvider: tokenProvider) {
                    Task { await store.loadAroundSelection() }
                }
            }
            .sheet(isPresented: Bindable(router).isShowingPlanGenerator) {
                PlanGeneratorSheet(store: generation) {
                    // Plan reloads on the revision, and Résumé and the session reminders follow.
                    router.noteCalendarChanged()
                }
            }
            .sheet(isPresented: Bindable(router).isShowingWeeklyReview, onDismiss: {
                guard opensGeneratorAfterReview else { return }
                opensGeneratorAfterReview = false
                router.isShowingPlanGenerator = true
            }) {
                NavigationStack {
                    WeeklyReviewView(store: WeeklyReviewStore(tokenProvider: tokenProvider)) {
                        opensGeneratorAfterReview = true
                        router.isShowingWeeklyReview = false
                    }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fermer") { router.isShowingWeeklyReview = false }
                            }
                        }
                }
                .sharpitSheet()
            }
            .environment(\.planCatchUp, PlanCatchUpAction(run: startCatchUp))
            .sheet(isPresented: $showingAdapter) {
                PlanAdapterSheet(store: adjustment) {
                    activeCatchUp?.markSettled()
                    activeCatchUp = nil
                    // Plan reloads on the revision, and Résumé and the session reminders follow.
                    router.noteCalendarChanged()
                }
            }
            .task { await store.loadAroundSelection() }
            .task { await loadPlanExtras() }
            .task(id: isExpertReading) { await loadTrainingLoad(force: true) }
            .task { await generation.resume() }
            .onAppear {
                let router = router
                editor.onChanged = { router.noteCalendarChanged() }
            }
            // « Dommage pour hier » tapped: the adapter, the miss already said.
            .onChange(of: router.pendingCatchUp, initial: true) { _, catchUp in
                guard let catchUp else { return }
                router.pendingCatchUp = nil
                startCatchUp(catchUp)
            }
            // Résumé's « … bouscule ton plan » tapped: the adapter, the trip already said.
            .onChange(of: router.pendingTravelConflict, initial: true) { _, conflict in
                guard let conflict else { return }
                router.pendingTravelConflict = nil
                startAdapter(focus: PlanTripAdaptation.focus(for: conflict))
            }
            // A session to do, tapped in a widget: today's week, its drawer open.
            .onChange(of: router.pendingPlannedSessionId, initial: true) { _, id in
                guard let id else { return }
                router.pendingPlannedSessionId = nil
                Task { await openPlannedSession(id: id) }
            }
            // The Plan tab tapped again: back to the active week.
            .onChange(of: router.planReselectTick) { _, _ in
                if !store.isCurrentWeek { store.goToToday() }
            }
            // Régularité tapped on another day: the week holding it.
            .onChange(of: router.planFocusDay, initial: true) { _, day in
                guard let day else { return }
                router.planFocusDay = nil
                store.selectedOffset = store.offset(forWeekContaining: day)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await generation.resume() } }
            }
            .onChange(of: generation.isReady) { _, ready in
                guard ready, !router.isShowingPlanGenerator else { return }
                toastCenter?.show(String(localized: "Ta semaine est prête"), symbol: "calendar.badge.checkmark", tone: .success, autoDismissAfter: 4.0)
            }
            // Every way of changing week — swipe, the strip's "Aujourd'hui", the calendar —
            // ends in `selectedOffset`, so loading follows from that one change.
            .onChange(of: store.selectedOffset) { _, _ in
                Task { await store.loadAroundSelection() }
            }
            .onChange(of: router.calendarRevision) { _, _ in
                Task {
                    await store.reload()
                    await loadPlanExtras(force: true)
                }
            }
        }
    }
}

extension PlanView {
    /// « Rattraper ma semaine »: the adapter opens with the miss said and starts at once.
    fileprivate func startCatchUp(_ catchUp: PlanCatchUp) {
        startAdapter(focus: catchUp.focus(), catchUp: catchUp)
    }

    /// « Adapter »: the adapter opens empty, for the athlete to say what changed.
    /// How the week on screen stands, as the sheet's wash; neutral until it is read.
    private var shownWash: CliniqueWash {
        guard case .loaded(let entries) = store.phase(forOffset: store.selectedOffset) else { return .neutral }
        return PlanWeekReadout.wash(PlanWeekReadout.status(PlanWeekTotals(entries)).status)
    }

    fileprivate func openAdapter() {
        adjustment.reset()
        activeCatchUp = nil
        showingAdapter = true
    }

    /// The adapter opens with what changed already said, and starts at once.
    fileprivate func startAdapter(focus: String, catchUp: PlanCatchUp? = nil) {
        adjustment.reset()
        activeCatchUp = catchUp
        adjustment.focus = focus
        showingAdapter = true
        Task { await adjustment.start() }
    }

    /// Shows today's week and opens the session's drawer once the week is read.
    fileprivate func openPlannedSession(id: String) async {
        store.goToToday()
        await store.loadAroundSelection()
        guard case .loaded(let entries) = store.phase(forOffset: store.selectedOffset) else { return }
        // A brick's leg opens the brick: the leg alone is not what the athlete does.
        selection = entries.lazy.compactMap { entry -> PlanSelection? in
            switch entry {
            case .planned(let session), .missed(let session): session.id == id ? .session(session) : nil
            case .brick(let brick): brick.contains(sessionId: id) ? .brick(brick) : nil
            case .doneBrick(let brick): brick.contains(sessionId: id) ? .doneBrick(brick) : nil
            case .executed: nil
            }
        }.first
    }

    /// Travels + trajectory (+ training load in expert): one gated burst per tab visit.
    fileprivate func loadPlanExtras(force: Bool = false) async {
        await extrasGate.run(force: force) {
            await loadTravels()
            await loadActivePlan()
            await loadGarminLink()
            await loadTrajectory()
            await loadTrainingLoad(force: true)
            return true
        }
    }

    /// The plan's phases are a quiet extra too: without them the week only loses a line.
    fileprivate func loadActivePlan() async {
        guard let token = try? await tokenProvider(),
              let plan = try? await TrainingPlanClient().fetchActivePlan(token: token) else { return }
        activePlan = plan
    }

    /// The trips are a quiet extra: a failed read leaves the week without its chip.
    fileprivate func loadTravels() async {
        guard let token = try? await tokenProvider(),
              let snapshot = try? await memoryClient.snapshot(token: token) else { return }
        travels = snapshot.entries.filter { $0.type == .travel }
    }

    /// Read only in the expert reading: the essential one never shows it, so never asks for it.
    fileprivate func loadTrainingLoad(force: Bool = false) async {
        guard isExpertReading, let token = try? await tokenProvider() else { return }
        if !force, trainingLoad != nil { return }
        if let load = try? await SharpitClient().trainingLoad(trainingDayId: TrainingDayId.today(), token: token) {
            trainingLoad = load
        }
    }

    /// Today's Effort and Adaptation for the tiles under the week. A reading that fails keeps
    /// the last one; the tile still opens its screen, which says why.
    fileprivate func loadTrajectory() async {
        guard let token = try? await tokenProvider() else { return }
        let client = SharpitClient()
        let day = TrainingDayId.today()
        let effort = try? await client.effort(trainingDayId: day, token: token)
        let adaptation = try? await client.adaptation(trainingDayId: day, token: token)
        trajectory = PlanTrajectory(
            effort: effort ?? trajectory.effort,
            adaptation: adaptation ?? trajectory.adaptation
        )
    }

    @ViewBuilder
    fileprivate func trajectoryDetail(for destination: PlanTrajectoryDestination) -> some View {
        switch destination {
        case .effort:
            EffortView(client: SharpitClient(), tokenProvider: tokenProvider)
        case .adaptation:
            AdaptationView(client: SharpitClient(), tokenProvider: tokenProvider)
        }
    }

    fileprivate func linkContext(on date: Date) -> SessionLinkContext {
        SessionLinkContext(
            referenceDate: date,
            activities: activityClient,
            linker: linker,
            tokenProvider: tokenProvider,
            onLinked: {
                selection = nil
                toastCenter?.show(
                    String(localized: "Séance liée avec succès"),
                    symbol: "link",
                    tone: .success,
                    autoDismissAfter: 3.0
                )
                Task { await store.reload(around: date) }
            }
        )
    }

    /// A new session lands today in this week, else on the week's first day.
    fileprivate var newSessionDay: Date {
        store.isCurrentWeek ? Date() : store.weekStart
    }

    /// Hand editing of a single session. A brick's legs are the coach's chain: not edited here.
    /// Nil for a session done, a sport the watch does not take yet, or without Garmin.
    fileprivate func watchContext(for session: V1PlannedSessionItem) -> SessionWatchContext? {
        guard isGarminLinked, session.completed != true, WatchPushState.canSend(type: session.type) else {
            return nil
        }
        return SessionWatchContext(
            session: session,
            client: GarminWorkoutClient(),
            tokenProvider: tokenProvider,
            onSent: { Task { await store.reload(around: session.date) } }
        )
    }

    /// A failed read keeps what was known: the row is a convenience, not a state to lose.
    fileprivate func loadGarminLink() async {
        guard let token = try? await tokenProvider(),
              let status = try? await SharpitClient().syncStatus(token: token) else { return }
        isGarminLinked = status.providers.contains { $0.key == DisconnectableSource.garmin.statusKey }
    }

    fileprivate func editingContext(for session: V1PlannedSessionItem) -> SessionEditingContext {
        SessionEditingContext(
            session: session,
            editor: editor,
            onSaved: { selection = .session($0) },
            onDeleted: { selection = nil }
        )
    }

    fileprivate func guidedFinishContext() -> GuidedStrengthFinishContext? {
        guard let mutator = activityClient as? any ActivityMutating else { return nil }
        return GuidedStrengthFinishContext(
            client: mutator,
            linker: linker,
            tokenProvider: tokenProvider,
            onFinished: { _ in
                selection = nil
                toastCenter?.show(
                    String(localized: "Séance muscu enregistrée"),
                    symbol: "checkmark.circle.fill",
                    tone: .success,
                    autoDismissAfter: 3.0
                )
                // Forced, everywhere: the week already shown would keep the session as to do.
                router.noteActivitiesChanged()
            }
        )
    }
}

/// « Autour du plan »: the pages the week rests on, a line each at the foot of its sheet.
private struct PlanAroundSection: View {
    let chrome: PlanWeekChrome
    let weekStart: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Autour du plan")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            line(String(localized: "Objectifs"), symbol: "flag", detail: nil, action: chrome.onOpenGoals)
            CliniqueDivider()
            line(
                String(localized: "Plan macro"), symbol: "map",
                detail: PlanPhaseReadout.line(chrome.plan, weekStart: weekStart), action: chrome.onOpenMacroPlan
            )
            CliniqueDivider()
            line(
                String(localized: "Déplacements"), symbol: CoachMemoryType.travel.symbol,
                detail: PlanAroundReadout.trips(chrome.travels.count), action: chrome.onOpenTravel
            )
            CliniqueDivider()
            line(String(localized: "Bilan de la semaine"), symbol: "doc.text.magnifyingglass", detail: nil, action: chrome.onOpenWeeklyReview)
        }
    }

    private func line(_ title: String, symbol: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 36, height: 36)
                    .background(SharpitColor.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
    }
}

enum PlanAroundReadout {
    /// « 2 déclarés » beside Déplacements; nothing while none is.
    static func trips(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: String(localized: "1 déclaré")
        default: String(localized: "\(count) déclarés")
        }
    }
}

/// The weeks, side by side, one screen wide each.
///
/// A paging scroll view positioned by id rather than `TabView(.page)`. With fifty-odd
/// pages and a starting selection in the middle, the tab view started on the wrong page
/// and drifted to another while the neighbours loaded — a selection binding it wrote to
/// itself during the initial layout. Here the position is only ever set by us.
private struct PlanWeekPager: View {
    let store: PlanStore
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let trainingLoad: V1TrainingLoad?
    let trajectory: PlanTrajectory
    let chrome: PlanWeekChrome
    let onSelect: (PlanSelection) -> Void
    let onOpenTrajectory: (PlanTrajectoryDestination) -> Void

    @State private var position: Int?
    static let space = "planWeekPager"

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(PlanStore.offsets, id: \.self) { offset in
                    PlanWeekPage(
                        store: store,
                        offset: offset,
                        activityClient: activityClient,
                        tokenProvider: tokenProvider,
                        trainingLoad: offset == 0 ? trainingLoad : nil,
                        trajectory: offset == 0 ? trajectory : nil,
                        chrome: chrome,
                        onSelect: onSelect,
                        onOpenTrajectory: onOpenTrajectory
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .coordinateSpace(.named(Self.space))
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onAppear { position = store.selectedOffset }
        // Swiping writes `position`; the strip, the calendar and "Aujourd'hui" write the
        // store. Each side follows the other, and equality checks stop the echo.
        .onChange(of: position) { _, new in
            guard let new, new != store.selectedOffset else { return }
            store.selectedOffset = new
        }
        .onChange(of: store.selectedOffset) { _, new in
            guard new != position else { return }
            withAnimation(SharpitMotion.reveal) { position = new }
        }
    }
}

/// One week of the pager. It reads its own state, so a page that has not loaded yet shows
/// a skeleton while its neighbours are already on screen.
private struct PlanWeekPage: View {
    let store: PlanStore
    let offset: Int
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let trainingLoad: V1TrainingLoad?
    /// The current week's only: the readings are today's.
    let trajectory: PlanTrajectory?
    let chrome: PlanWeekChrome
    let onSelect: (PlanSelection) -> Void
    let onOpenTrajectory: (PlanTrajectoryDestination) -> Void

    var body: some View {
        switch store.phase(forOffset: offset) {
        case .loading:
            PlanLoadingView()
        case .loaded(let entries):
            PlanWeekContent(
                store: store,
                offset: offset,
                entries: entries,
                activityClient: activityClient,
                tokenProvider: tokenProvider,
                trainingLoad: trainingLoad,
                trajectory: trajectory,
                chrome: chrome,
                onSelect: onSelect,
                onOpenTrajectory: onOpenTrajectory
            )
        case .error(let message):
            SharpitStateMessage.failed(message) { Task { await store.load(offset: offset, force: true) } }
                .embedded()
        case .unauthorized:
            ContentUnavailableView {
                Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Reconnecte-toi pour retrouver ton plan.")
            }
        }
    }
}

/// What a week's page needs from the screen around it: the trips to name, and the three ways out.
struct PlanWeekChrome {
    var travels: [CoachMemoryEntry] = []
    var plan: V1TrainingPlan? = nil
    var onAdapt: () -> Void = {}
    var onOpenCalendar: () -> Void = {}
    var onOpenTravel: () -> Void = {}
    var onFillWeek: () -> Void = {}
    var onAddSession: () -> Void = {}
    var onOpenGoals: () -> Void = {}
    var onOpenMacroPlan: () -> Void = {}
    var onOpenWeeklyReview: () -> Void = {}
}

/// Where a week sits in the plan: its phase, and the days left to the race.
enum PlanPhaseReadout {
    /// « Spécifique · sem. 3 sur 6 »: the week's phase and its place in that phase's run of weeks.
    static func line(_ plan: V1TrainingPlan?, weekStart: Date, calendar: Calendar = .current) -> String? {
        guard let plan,
              let index = plan.weeks.firstIndex(where: { calendar.isDate($0.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) })
        else { return nil }
        let phase = plan.weeks[index].phase
        var first = index
        while first > 0, plan.weeks[first - 1].phase == phase { first -= 1 }
        var last = index
        while last < plan.weeks.count - 1, plan.weeks[last + 1].phase == phase { last += 1 }
        return String(localized: "\(phase.label) · sem. \(index - first + 1) sur \(last - first + 1)")
    }

    /// « course dans 37 j », « course demain », « course aujourd'hui »; nil once it is behind.
    static func countdown(_ plan: V1TrainingPlan?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let plan else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: plan.raceDate)).day ?? -1
        switch days {
        case ..<0: return nil
        case 0: return String(localized: "course aujourd'hui")
        case 1: return String(localized: "course demain")
        default: return String(localized: "course dans \(days) j")
        }
    }
}

/// How a week stands, said in one status word.
enum PlanWeekReadout {
    static func status(_ totals: PlanWeekTotals) -> (label: String, status: CliniqueStatus) {
        if totals.totalSessions == 0 { return (String(localized: "Semaine libre"), .unknown) }
        if totals.missedSessions > 0 {
            return (String(localized: "\(totals.missedSessions) à rattraper"), .watch)
        }
        if totals.doneSessions == totals.totalSessions { return (String(localized: "Semaine bouclée"), .good) }
        return (String(localized: "Dans les clous"), .good)
    }

    static func wash(_ status: CliniqueStatus) -> CliniqueWash {
        switch status {
        case .good: .good
        case .watch: .watch
        default: .neutral
        }
    }
}

/// One week as a sheet: « Plan » and how the week stands, its three figures as rings, then the
/// days down a rail.
private struct PlanWeekContent: View {
    let store: PlanStore
    let offset: Int
    let entries: [PlanEntry]
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let trainingLoad: V1TrainingLoad?
    let trajectory: PlanTrajectory?
    let chrome: PlanWeekChrome
    let onSelect: (PlanSelection) -> Void
    let onOpenTrajectory: (PlanTrajectoryDestination) -> Void

    private var totals: PlanWeekTotals { PlanWeekTotals(entries) }
    private var days: [Date] { store.weekDays(forOffset: offset) }

    var body: some View {
        let standing = PlanWeekReadout.status(totals)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Held still while a week is turned: the days slide under the title and the
                // status, and the week nearest the middle is the one they speak of. As wide as the
                // page, since the swap is measured against this width — sized to its words, the
                // header left 60 pt into a swipe.
                header(standing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .visualEffect { content, proxy in
                        let x = proxy.frame(in: .named(PlanWeekPager.space)).minX
                        return content.offset(x: -x).opacity(abs(x) < proxy.size.width / 2 ? 1 : 0)
                    }
                if !isEmptyWeekAhead {
                    // The rings stay in place too, and dissolve over the first quarter of the
                    // turn: gone before the next week's page reaches them, back once it has landed.
                    rings
                        .visualEffect { content, proxy in
                            let x = proxy.frame(in: .named(PlanWeekPager.space)).minX
                            return content.offset(x: -x).opacity(max(0, 1 - abs(x) / (proxy.size.width / 4)))
                        }
                }
                weekHeading
                if isEmptyWeekAhead { emptyWeek }
                if !isEmptyWeekAhead {
                PlanTimeline(
                    days: days,
                    entriesOn: { store.entries(on: $0, from: entries) },
                    trips: PlanTravel.trips(chrome.travels, overlapping: days),
                    onOpenTravel: chrome.onOpenTravel,
                    activityClient: activityClient,
                    tokenProvider: tokenProvider,
                    onSelect: onSelect
                )
                .padding(.horizontal, SharpitSpacing.lg)
                }
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    if let trainingLoad, !trainingLoad.days.isEmpty {
                        TrainingLoadCard(load: trainingLoad)
                    }
                    // After the week, as the IA orders My week: the plan, then the trajectory.
                    if let trajectory {
                        PlanTrajectoryCards(trajectory: trajectory, onOpen: onOpenTrajectory)
                    }
                    PlanAroundSection(chrome: chrome, weekStart: store.weekStart(forOffset: offset))
                }
                .padding(.horizontal, SharpitSpacing.lg)
                .padding(.top, SharpitSpacing.lg)
            }
            .padding(.bottom, SharpitSpacing.xl)
        }
        // The held header and rings are drawn outside their page while a week is turned: a
        // clipped page cut them at its edge, so the title vanished for the second half of a swipe.
        .scrollClipDisabled()
        .modifier(ScrollUnderGlass(hidesTopEdge: true))
        // No pull-to-refresh: nested in the horizontal pager, a fast fling to the top
        // fired it and the spinner shoved the week down. Plan reloads on each visit and edit.
    }

    /// A week read, not yet over, with nothing in it: the page says so and offers to fill it,
    /// instead of seven rest days under three empty rings.
    private var isEmptyWeekAhead: Bool {
        guard entries.isEmpty, case .loaded = store.phase(forOffset: offset), let last = days.last else { return false }
        return Calendar.current.startOfDay(for: last) >= Calendar.current.startOfDay(for: .now)
    }

    private var emptyWeek: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(SharpitColor.slate)
                .padding(.top, 36)
                .accessibilityHidden(true)
            Text("Ta semaine est vide")
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
            Text("Donne ta course ou ton objectif. Le plan se remplit autour de tes jours libres et se répare seul si tu rates une séance.")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.slate)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: chrome.onFillWeek) { Text("Remplir ma semaine").frame(maxWidth: .infinity) }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .padding(.top, 10)
            Button("Ajouter une séance à la main", action: chrome.onAddSession)
                .buttonStyle(CliniqueButtonStyle(kind: .plain))
        }
        .padding(.horizontal, 24)
    }

    /// Under the bar's title: how the week stands, then its phase in the plan.
    private func header(_ standing: (label: String, status: CliniqueStatus)) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Plan")
                .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            statusLine(standing)
        }
        .padding(.horizontal, 20)
        // Level with the bar's buttons, which float over the page.
        .padding(.top, -38)
        .padding(.bottom, SharpitSpacing.md)
    }

    private func statusLine(_ standing: (label: String, status: CliniqueStatus)) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            CliniqueStatusPill(standing.label, status: standing.status)
            if let phase = PlanPhaseReadout.line(chrome.plan, weekStart: store.weekStart(forOffset: offset)) {
                Text(phase)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var rings: some View {
        CliniqueScoreStrip {
            CliniqueScoreColumn(
                pillar: .coach, fraction: totals.sessionsFraction,
                title: String(localized: "Séances"),
                value: totals.totalSessions > 0 ? "\(totals.doneSessions)" : nil,
                scale: "\(totals.totalSessions)"
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Séances, \(totals.doneSessions) sur \(totals.totalSessions)")
            CliniqueScoreColumn(
                pillar: .sleep, fraction: totals.volumeFraction, symbol: "clock",
                title: String(localized: "Volume"),
                value: totals.totalMinutes > 0 ? PlanWeekTotals.duration(minutes: totals.doneMinutes) : nil,
                scale: PlanWeekTotals.duration(minutes: totals.totalMinutes)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume, \(PlanWeekTotals.duration(minutes: totals.doneMinutes)) sur \(PlanWeekTotals.duration(minutes: totals.totalMinutes))")
            CliniqueScoreColumn(
                pillar: .recovery, fraction: totals.loadFraction,
                title: String(localized: "Charge"),
                value: totals.totalLoad > 0 ? "\(Int(totals.doneLoad.rounded()))" : nil,
                scale: "\(Int(totals.totalLoad.rounded()))"
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Charge, \(Int(totals.doneLoad.rounded())) sur \(Int(totals.totalLoad.rounded()))")
        }
    }

    /// The week's name, and the way to another one: it opens the calendar.
    private var weekHeading: some View {
        Button(action: chrome.onOpenCalendar) {
            HStack(spacing: SharpitSpacing.xxs) {
                Text("Semaine du \(store.weekStart(forOffset: offset).sharpitFormatted(.dateTime.day().month(.wide)))")
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
                Spacer(minLength: SharpitSpacing.xs)
                if let countdown = PlanPhaseReadout.countdown(chrome.plan) {
                    Text(countdown)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre le calendrier")
        .padding(.horizontal, SharpitSpacing.lg)
        .padding(.top, 20)
        .padding(.bottom, SharpitSpacing.xxs)
    }
}

/// The week's days down a rail: a dot per line says where it stands — filled for done, amber
/// for missed, a bold ring for today, a hollow one ahead, grey for rest.
private struct PlanTimeline: View {
    let days: [Date]
    let entriesOn: (Date) -> [PlanEntry]
    /// The week's trips: the days away sit on one band, named on its first day.
    var trips: [CoachMemoryEntry] = []
    var onOpenTravel: () -> Void = {}
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let onSelect: (PlanSelection) -> Void

    private struct Line: Identifiable {
        let id: String
        let day: Date
        let entry: PlanEntry?
        var trip: CoachMemoryEntry?
        /// 0 for the day's first session; a day holding several ranks the others after it.
        var rank = 0
        /// The next line is the same day's: the two read as one day, with no rule between.
        var sharesDayWithNext = false
    }

    private var lines: [Line] {
        days.flatMap { day -> [Line] in
            let entries = entriesOn(day)
            let trip = PlanTravel.trip(on: day, in: trips)
            if entries.isEmpty { return [Line(id: "rest-\(day.timeIntervalSince1970)", day: day, entry: nil, trip: trip)] }
            return entries.enumerated().map { rank, entry in
                Line(id: entry.id, day: day, entry: entry, trip: trip, rank: rank, sharesDayWithNext: rank < entries.count - 1)
            }
        }
    }

    /// The band behind a day away: rounded where the trip starts and ends in the week, and wider
    /// than the text so the lines keep their margin.
    @ViewBuilder
    private func travelBand(_ lines: [Line], at index: Int) -> some View {
        if let trip = lines[index].trip {
            let opens = index == 0 || lines[index - 1].trip?.id != trip.id
            let closes = index == lines.count - 1 || lines[index + 1].trip?.id != trip.id
            UnevenRoundedRectangle(
                topLeadingRadius: opens ? 14 : 0, bottomLeadingRadius: closes ? 14 : 0,
                bottomTrailingRadius: closes ? 14 : 0, topTrailingRadius: opens ? 14 : 0,
                style: .continuous
            )
            .fill(SharpitColor.tile)
            .padding(.horizontal, -10)
            .padding(.bottom, closes ? 2 : 0)
        }
    }

    var body: some View {
        let lines = lines
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                    PlanRailMark(
                        mark: PlanTimelineReadout.mark(for: line.entry, on: line.day),
                        isFirst: index == 0,
                        isLast: index == lines.count - 1,
                        isFollowUp: line.rank > 0
                    )
                    VStack(spacing: 0) {
                        if let trip = line.trip, index == 0 || lines[index - 1].trip?.id != trip.id {
                            PlanTravelLabel(trip: trip, onOpen: onOpenTravel)
                        }
                        if let entry = line.entry {
                            PlanEntryRow(
                                entry: entry,
                                day: line.day,
                                rank: line.rank,
                                activityClient: activityClient,
                                tokenProvider: tokenProvider,
                                onSelect: onSelect
                            )
                        } else {
                            Text("\(PlanTimelineReadout.dayLabel(line.day)) · Repos")
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                                .foregroundStyle(SharpitColor.slate)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                        }
                        if index < lines.count - 1, !line.sharesDayWithNext { CliniqueDivider() }
                    }
                    .background { travelBand(lines, at: index) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

enum PlanTimelineReadout {
    enum Mark: Equatable {
        case done
        case missed
        case today
        case ahead
        case rest
    }

    static func mark(for entry: PlanEntry?, on day: Date, calendar: Calendar = .current) -> Mark {
        switch entry {
        case nil: .rest
        case .executed, .doneBrick: .done
        case .missed: .missed
        case .brick(let brick) where brick.isMissed: .missed
        case .planned, .brick: calendar.isDateInToday(day) ? .today : .ahead
        }
    }

    /// « Lun. 10 », or « Aujourd'hui » on the day itself.
    /// What opens a line: the day for its first session, « 2ᵉ séance » for the ones that share it.
    static func lead(_ day: Date, rank: Int, calendar: Calendar = .current) -> String {
        rank == 0 ? dayLabel(day, calendar: calendar) : String(localized: "\(rank + 1)ᵉ séance")
    }

    static func dayLabel(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Aujourd'hui") }
        let weekday = day.sharpitFormatted(.dateTime.weekday(.abbreviated))
        return "\(weekday.prefix(1).uppercased())\(weekday.dropFirst()) \(day.sharpitFormatted(.dateTime.day()))"
    }
}

private struct PlanRailMark: View {
    let mark: PlanTimelineReadout.Mark
    let isFirst: Bool
    let isLast: Bool
    /// A day's second session and after: a smaller dot, so the first one stays the day's.
    var isFollowUp = false

    var body: some View {
        let size: CGFloat = isFollowUp ? 8 : 14
        VStack(spacing: 0) {
            segment(hidden: isFirst).frame(height: 20 + (14 - size) / 2)
            dot.frame(width: size, height: size)
            segment(hidden: isLast).frame(maxHeight: .infinity)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    private func segment(hidden: Bool) -> some View {
        Rectangle()
            .fill(hidden ? Color.clear : SharpitColor.outline)
            .frame(width: 1)
    }

    @ViewBuilder
    private var dot: some View {
        switch mark {
        case .done: Circle().fill(SharpitColor.statusGoodMark)
        case .missed: Circle().fill(SharpitColor.statusWatchMark)
        case .today:
            Circle().strokeBorder(SharpitColor.foreground, lineWidth: isFollowUp ? 2.5 : 4)
        case .ahead: Circle().strokeBorder(SharpitColor.slate, lineWidth: 1.5)
        case .rest: Circle().strokeBorder(SharpitColor.outline, lineWidth: 1.5)
        }
    }
}

/// A done session opens its own screen; a prescription opens a drawer, because there is
/// nothing recorded to read yet.
private struct PlanEntryRow: View {
    let entry: PlanEntry
    let day: Date
    var rank = 0
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let onSelect: (PlanSelection) -> Void
    @Environment(\.planCatchUp) private var catchUpAction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            link
            if let catchUpAction, let catchUp = PlanCatchUp.offer(for: entry) {
                PlanCatchUpButton(catchUp: catchUp, action: catchUpAction)
                    .padding(.bottom, SharpitSpacing.xs)
            }
        }
    }

    private var line: PlanTimelineLine { PlanTimelineLine(entry: entry, day: day, rank: rank) }

    @ViewBuilder
    private var link: some View {
        switch entry {
        case .executed(let executed):
            NavigationLink {
                ActivityDetailView(
                    activity: executed.activity.id,
                    initialActivity: executed.activity,
                    client: activityClient,
                    tokenProvider: tokenProvider
                )
            } label: {
                line
            }
            .buttonStyle(.sharpitPressable)
        case .planned(let session), .missed(let session):
            Button { onSelect(.session(session)) } label: { line }
                .buttonStyle(.sharpitPressable)
        case .brick(let brick):
            Button { onSelect(.brick(brick)) } label: { line }
                .buttonStyle(.sharpitPressable)
        case .doneBrick(let brick):
            Button { onSelect(.doneBrick(brick)) } label: { line }
                .buttonStyle(.sharpitPressable)
        }
    }
}

/// One line of the rail: the day and the sport above, the session as the title, and at the
/// end what it stands for — a status once it is behind, its length while it is ahead.
private struct PlanTimelineLine: View {
    let entry: PlanEntry
    let day: Date
    var rank = 0

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// « Natation · Technique 2 400 m »: the sport, then the session's own name.
    private var title: String {
        switch entry {
        case .executed(let executed):
            ActivitySheetReadout.title(sport: executed.activity.type.label, title: executed.activity.title)
        case .planned(let session), .missed(let session):
            ActivitySheetReadout.title(sport: session.displayType, title: session.title)
        case .brick(let brick): brick.chain
        case .doneBrick(let brick): brick.chain
        }
    }

    /// « Lun. 10 », with the start time today and « séance clé » where they are known.
    private var overline: String {
        var parts = [PlanTimelineReadout.lead(day, rank: rank)]
        switch entry {
        case .executed, .doneBrick:
            break
        case .planned(let session), .missed(let session):
            if isToday, let time = session.startTime { parts.append(time) }
            if session.isKey { parts.append(String(localized: "séance clé")) }
        case .brick(let brick):
            if brick.isKey { parts.append(String(localized: "séance clé")) }
        }
        return parts.joined(separator: " · ")
    }

    private var isMissed: Bool {
        PlanTimelineReadout.mark(for: entry, on: day) == .missed
    }

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(overline)
                    .font(SharpitTypography.system(size: 13, weight: isToday ? .semibold : .regular, relativeTo: .caption))
                    .foregroundStyle(isToday ? SharpitColor.foreground : SharpitColor.slate)
                    .lineLimit(1)
                Text(title)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(isMissed ? SharpitColor.slate : SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer(minLength: SharpitSpacing.xs)
            trailing
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var trailing: some View {
        switch entry {
        case .executed(let executed):
            if let score = executed.complianceScore {
                // Green from 85: the session followed its plan.
                CliniqueStatusPill("\(Int(score.rounded())) / 100", status: score >= 85 ? .good : .watch)
            } else {
                CliniqueStatusPill(String(localized: "Fait"), status: .good)
            }
        case .doneBrick:
            CliniqueStatusPill(String(localized: "Fait"), status: .good)
        case .missed:
            CliniqueStatusPill(String(localized: "Non réalisée"), status: .watch)
        case .brick(let brick) where brick.isMissed:
            CliniqueStatusPill(String(localized: "Non réalisé"), status: .watch)
        case .planned(let session):
            ahead(minutes: session.durationMin)
        case .brick(let brick):
            ahead(minutes: brick.totalDurationMin)
        }
    }

    private func ahead(minutes: Int?) -> some View {
        HStack(spacing: SharpitSpacing.xs) {
            if let minutes {
                Text(PlanWeekTotals.duration(minutes: minutes))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            if isToday {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct PlanLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.tile)
                    .frame(height: 86)
                ForEach(0..<7, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius)
                        .fill(SharpitColor.tile)
                        .frame(height: 56)
                }
            }
            .redacted(reason: .placeholder)
            .padding(.horizontal, SharpitSpacing.lg)
            .padding(.top, 96)
        }
        .modifier(ScrollUnderGlass())
        .cliniqueSheet(wash: .neutral, height: 220)
        .accessibilityLabel("Chargement du plan")
    }
}

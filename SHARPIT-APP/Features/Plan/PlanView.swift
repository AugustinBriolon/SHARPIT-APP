import Observation
import SwiftUI

struct PlanView: View {
    let client: any PlannedSessionServing
    let linker: any PlannedSessionLinking
    let watchPusher: any PlannedSessionWatchPushing
    let keyMutator: any PlannedSessionMutating
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var store: PlanStore
    @State private var selection: PlanSelection?
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
    /// Plan's, not the sheet's: closing it mid-analysis keeps the proposal coming.
    @State private var adjustment: PlanAdjustmentStore
    /// Plan's, not the sheet's: reopening Objectifs shows the goals at once.
    @State private var goals: GoalStore
    /// Plan's, so a change written behind outlives the drawer or the form that made it.
    @State private var editor: PlanEditor
    @State private var showingNewSession = false
    /// The coach's trips, for the week's « Déplacement » chip (the web's `TravelContextBanner`).
    @State private var travels: [CoachMemoryEntry] = []
    @State private var showingTravel = false

    init(
        client: any PlannedSessionServing,
        linker: any PlannedSessionLinking,
        watchPusher: (any PlannedSessionWatchPushing)? = nil,
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.linker = linker
        self.watchPusher = watchPusher ?? (client as? (any PlannedSessionWatchPushing)) ?? PlannedSessionClient()
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
                // Fixed above the pager: neither moves when the week does, so neither can
                // fight the pages' own gestures.
                VStack(spacing: SharpitSpacing.xs) {
                    PlanWeekHeader(
                        store: store,
                        onOpenCalendar: { showingCalendar = true },
                        travels: travels,
                        onOpenTravel: { showingTravel = true }
                    )
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    PlanWeekStrip(store: store)
                }

                PlanWeekPager(
                    store: store,
                    activityClient: activityClient,
                    tokenProvider: tokenProvider,
                    trainingLoad: isExpertReading ? trainingLoad : nil,
                    trajectory: trajectory,
                    onSelect: { selection = $0 },
                    onOpenTrajectory: { openedTrajectory = $0 }
                )
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .navigationDestination(item: $openedTrajectory) { destination in
                trajectoryDetail(for: destination)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewSession = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter une séance")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PlanActionsMenu(
                        onOpenGoals: { router.isShowingGoals = true },
                        onOpenMacroPlan: { showingMacroPlan = true },
                        onOpenGenerator: { router.isShowingPlanGenerator = true },
                        onOpenWeeklyReview: { router.isShowingWeeklyReview = true },
                        onOpenAdapter: { showingAdapter = true },
                        onDiscussWithCoach: {
                            router.discussWithCoach(
                                about: CoachDiscuss.describe(.planning(horizonDays: 7))
                            )
                        }
                    )
                }
            }
            .sheet(item: $selection) { selected in
                switch selected {
                case .session(let session):
                    PlannedSessionDrawer(
                        preview: PlannedSessionPreview(session: session, isExpertReading: isExpertReading),
                        linking: linkContext(on: session.date),
                        watchPush: watchPushContext(on: session.date),
                        editing: editingContext(for: session)
                    ) { context in
                        router.discussWithCoach(about: context)
                    }
                case .brick(let brick):
                    BrickSessionDrawer(
                        brick: PlannedBrickPreview(brick: brick, isExpertReading: isExpertReading),
                        linking: linkContext(on: brick.date),
                        watchPush: watchPushContext(on: brick.date)
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
                    CoachMemoryView(client: CoachMemoryClient(), tokenProvider: tokenProvider)
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
            .sheet(isPresented: Bindable(router).isShowingWeeklyReview) {
                NavigationStack {
                    WeeklyReviewView(store: WeeklyReviewStore(tokenProvider: tokenProvider))
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
                    // Plan reloads on the revision, and Résumé and the session reminders follow.
                    router.noteCalendarChanged()
                }
            }
            .task { await store.loadAroundSelection() }
            .task { await loadTravels() }
            .task(id: isExpertReading) { await loadTrainingLoad() }
            .task { await loadTrajectory() }
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
            // A session to do, tapped in a widget: today's week, its drawer open.
            .onChange(of: router.pendingPlannedSessionId, initial: true) { _, id in
                guard let id else { return }
                router.pendingPlannedSessionId = nil
                Task { await openPlannedSession(id: id) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await generation.resume() } }
            }
            .onChange(of: generation.isReady) { _, ready in
                guard ready, !router.isShowingPlanGenerator else { return }
                toastCenter?.show("Ta semaine est prête", symbol: "calendar.badge.checkmark", tone: .success, autoDismissAfter: 4.0)
            }
            // Every way of changing week — swipe, the strip's "Aujourd'hui", the calendar —
            // ends in `selectedOffset`, so loading follows from that one change.
            .onChange(of: store.selectedOffset) { _, _ in
                Task { await store.loadAroundSelection() }
            }
            .onChange(of: router.calendarRevision) { _, _ in
                Task {
                    await store.reload()
                    await loadTrainingLoad()
                    await loadTrajectory()
                }
            }
        }
    }
}

extension PlanView {
    /// « Rattraper ma semaine »: the adapter opens with the miss said and starts at once.
    fileprivate func startCatchUp(_ catchUp: PlanCatchUp) {
        adjustment.reset()
        adjustment.focus = catchUp.focus()
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

    /// The trips are a quiet extra: a failed read leaves the week without its chip.
    fileprivate func loadTravels() async {
        guard let token = try? await tokenProvider(),
              let snapshot = try? await CoachMemoryClient().snapshot(token: token) else { return }
        travels = snapshot.entries.filter { $0.type == .travel }
    }

    /// Read only in the expert reading: the essential one never shows it, so never asks for it.
    fileprivate func loadTrainingLoad() async {
        guard isExpertReading, let token = try? await tokenProvider() else { return }
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
                    "Séance liée avec succès",
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
    fileprivate func editingContext(for session: V1PlannedSessionItem) -> SessionEditingContext {
        SessionEditingContext(
            session: session,
            editor: editor,
            onSaved: { selection = .session($0) },
            onDeleted: { selection = nil }
        )
    }

    fileprivate func watchPushContext(on date: Date) -> SessionWatchPushContext {
        SessionWatchPushContext(
            pusher: watchPusher,
            tokenProvider: tokenProvider,
            onPushed: { _ in
                Task { await store.reload(around: date) }
            }
        )
    }
}

/// The week's actions, gathered behind one control.
///
/// Native sheets for the three key planning operations (macro plan, fill week, adapt plan)
/// and direct bridge to discussion with the Coach.
private struct PlanActionsMenu: View {
    let onOpenGoals: () -> Void
    let onOpenMacroPlan: () -> Void
    let onOpenGenerator: () -> Void
    let onOpenWeeklyReview: () -> Void
    let onOpenAdapter: () -> Void
    let onDiscussWithCoach: () -> Void

    var body: some View {
        Menu {
            Button(action: onOpenGoals) {
                Label("Objectifs", systemImage: "flag.fill")
            }
            Divider()
            Button(action: onOpenMacroPlan) {
                Label("Consulter le plan macro", systemImage: "map")
            }
            Button(action: onOpenGenerator) {
                Label("Remplir ma semaine", systemImage: "calendar.badge.plus")
            }
            Button(action: onOpenAdapter) {
                Label("Ajuster le planning", systemImage: "slider.horizontal.3")
            }
            Button(action: onOpenWeeklyReview) {
                Label("Bilan de la semaine", systemImage: "doc.text.magnifyingglass")
            }
            Divider()
            Button(action: onDiscussWithCoach) {
                Label("Discuter avec le coach", systemImage: "bubble.left.and.bubble.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SharpitTypography.bodyEmphasis)
        }
        .accessibilityLabel("Actions du plan")
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
    let onSelect: (PlanSelection) -> Void
    let onOpenTrajectory: (PlanTrajectoryDestination) -> Void

    @State private var position: Int?

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
                        onSelect: onSelect,
                        onOpenTrajectory: onOpenTrajectory
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
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
                onSelect: onSelect,
                onOpenTrajectory: onOpenTrajectory
            )
        case .error(let message):
            ContentUnavailableView {
                Label("Plan indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load(offset: offset, force: true) } }
            }
        case .unauthorized:
            ContentUnavailableView {
                Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Reconnecte-toi pour retrouver ton plan.")
            }
        }
    }
}

private struct PlanWeekContent: View {
    let store: PlanStore
    let offset: Int
    let entries: [PlanEntry]
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let trainingLoad: V1TrainingLoad?
    let trajectory: PlanTrajectory?
    let onSelect: (PlanSelection) -> Void
    let onOpenTrajectory: (PlanTrajectoryDestination) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    if let trainingLoad, !trainingLoad.days.isEmpty {
                        TrainingLoadCard(load: trainingLoad)
                    }
                    if let focus = store.focusSession(from: entries) {
                        Button { onSelect(focus) } label: {
                            PlanFocusSession(
                                focus: focus,
                                isToday: Calendar.current.isDateInToday(focus.date)
                            )
                        }
                        .buttonStyle(.sharpitPressable)
                    }
                    VStack(spacing: 0) {
                        ForEach(store.weekDays(forOffset: offset), id: \.self) { day in
                            PlanDayRow(
                                day: day,
                                entries: store.entries(on: day, from: entries),
                                activityClient: activityClient,
                                tokenProvider: tokenProvider,
                                onSelect: onSelect
                            )
                            .id(day)
                        }
                    }
                    // After the week, as the IA orders My week: the plan, then the trajectory.
                    if let trajectory {
                        PlanTrajectoryCards(trajectory: trajectory, onOpen: onOpenTrajectory)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.md)
                .padding(.bottom, SharpitSpacing.lg)
            }
            .modifier(ScrollUnderGlass())
            .refreshable { await store.load(offset: offset, force: true) }
            // Only the visible page answers: the strip belongs to the selected week, and
            // a neighbour scrolling in the dark would be wasted work.
            .onChange(of: store.scrollTarget) { _, target in
                guard offset == store.selectedOffset, let target else { return }
                withAnimation(SharpitMotion.reveal) { proxy.scrollTo(target, anchor: .top) }
                store.scrollTarget = nil
            }
        }
    }
}

private struct PlanFocusSession: View {
    let focus: PlanSelection
    let isToday: Bool

    private var title: String {
        switch focus {
        case .session(let session): session.title ?? session.displayType
        case .brick(let brick): brick.chain
        case .doneBrick(let brick): brick.chain
        }
    }

    private var sport: String {
        switch focus {
        case .session(let session): session.displayType
        case .brick, .doneBrick: "Brick"
        }
    }

    private var durationMin: Int? {
        switch focus {
        case .session(let session): session.durationMin
        case .brick(let brick): brick.totalDurationMin
        case .doneBrick(let brick): brick.totalDurationMin
        }
    }

    private var symbolNames: [String] {
        switch focus {
        case .session(let session): [session.symbolName]
        case .brick(let brick): brick.legs.map(\.symbolName)
        case .doneBrick(let brick): brick.symbolNames
        }
    }

    private var isOnWatch: Bool {
        switch focus {
        case .session(let session): session.garminWorkoutId != nil
        case .brick(let brick): brick.isOnWatch
        case .doneBrick: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "À faire aujourd'hui" : "Prochaine séance")
                    .font(SharpitTypography.eyebrow)
                    .tracking(SharpitTypography.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                if isOnWatch {
                    Image(systemName: "applewatch.side.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.primary)
                        .accessibilityLabel("Sur la montre Garmin")
                }
                PlanSportChain(symbolNames: symbolNames, font: .title3.weight(.semibold))
            }
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
            HStack(spacing: SharpitSpacing.md) {
                PlanFocusMetric(label: "Sport", value: sport)
                if let duration = durationMin {
                    PlanFocusMetric(label: "Durée", value: "\(duration) min")
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SharpitColor.analysisSurfaceAlt,
            in: RoundedRectangle(cornerRadius: SharpitRadius.panelLarge, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A session's glyph, or a brick's glyphs joined by arrows: the chain is the brick's mark.
private struct PlanSportChain: View {
    let symbolNames: [String]
    let font: Font

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(symbolNames.enumerated()), id: \.offset) { index, symbol in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Image(systemName: symbol)
                    .font(font)
                    .foregroundStyle(SharpitColor.primary)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PlanFocusMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct PlanDayRow: View {
    let day: Date
    let entries: [PlanEntry]
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let onSelect: (PlanSelection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(spacing: SharpitSpacing.xxs) {
                Text(day.sharpitFormatted(.dateTime.weekday(.abbreviated)))
                    .font(SharpitTypography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(day.sharpitFormatted(.dateTime.day()))
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .foregroundStyle(
                        Calendar.current.isDateInToday(day)
                            ? SharpitColor.primary
                            : SharpitColor.foreground
                    )
            }
            .frame(width: 42)
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(width: 1)

            if entries.isEmpty {
                Text("Repos")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.top, SharpitSpacing.sm)
            } else {
                VStack(spacing: SharpitSpacing.xs) {
                    ForEach(entries) { entry in
                        PlanEntryRow(
                            entry: entry,
                            activityClient: activityClient,
                            tokenProvider: tokenProvider,
                            onSelect: onSelect
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A done session opens its own screen; a prescription opens a drawer, because there is
/// nothing recorded to read yet.
private struct PlanEntryRow: View {
    let entry: PlanEntry
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let onSelect: (PlanSelection) -> Void
    @Environment(\.planCatchUp) private var catchUpAction

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            card
            if let catchUpAction, let catchUp = PlanCatchUp.offer(for: entry) {
                PlanCatchUpButton(catchUp: catchUp, action: catchUpAction)
            }
        }
    }

    @ViewBuilder
    private var card: some View {
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
                PlanExecutedCard(entry: executed)
            }
            .buttonStyle(.sharpitPressable)
        case .planned(let session):
            Button { onSelect(.session(session)) } label: {
                PlanSessionCard(session: session, state: .planned)
            }
            .buttonStyle(.sharpitPressable)
        case .missed(let session):
            Button { onSelect(.session(session)) } label: {
                PlanSessionCard(session: session, state: .missed)
            }
            .buttonStyle(.sharpitPressable)
        case .brick(let brick):
            Button { onSelect(.brick(brick)) } label: {
                PlanBrickCard(brick: brick)
            }
            .buttonStyle(.sharpitPressable)
        case .doneBrick(let brick):
            Button { onSelect(.doneBrick(brick)) } label: {
                PlanDoneBrickCard(brick: brick)
            }
            .buttonStyle(.sharpitPressable)
        }
    }
}

/// What was done. When it came from the plan, the execution score rides along — that is
/// the whole reason the activity absorbs its prescription instead of sitting next to it.
private struct PlanExecutedCard: View {
    let entry: PlanExecutedEntry

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: entry.activity.type.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SharpitSportTone.label(for: entry.activity.type))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(entry.activity.title ?? entry.activity.type.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                HStack(spacing: SharpitSpacing.xs) {
                    Text(entry.activity.type.label)
                    if let duration = entry.activity.duration {
                        Text("\(Int((duration / 60).rounded())) min")
                    }
                    if let plannedTitle = entry.plannedTitle {
                        Text("·")
                        Text("Prévu : \(plannedTitle)")
                            .lineLimit(1)
                    }
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer(minLength: 0)

            if let score = entry.complianceScore {
                PlanComplianceMark(score: score)
            } else if entry.wasPlanned {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Liée")
                        .font(SharpitTypography.meta)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                .foregroundStyle(SharpitColor.primary)
            } else {
                Image(systemName: "checkmark")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["Séance réalisée", entry.activity.title ?? entry.activity.type.label]
        if let score = entry.complianceScore {
            parts.append("exécution \(Int(score.rounded())) sur 100")
        }
        return parts.joined(separator: ", ")
    }
}

/// The execution score, as a number rather than a ring — `design.md` keeps radial gauges
/// out of list rows.
private struct PlanComplianceMark: View {
    let score: Double

    var body: some View {
        Text("\(Int(score.rounded()))")
            .font(SharpitTypography.instrument)
            .foregroundStyle(SharpitColor.primaryForeground)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, SharpitSpacing.xxs)
            .background(SharpitColor.primary, in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct PlanSessionCard: View {
    enum State {
        case planned
        case missed
    }

    let session: V1PlannedSessionItem
    var state: State = .planned

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: session.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    state == .missed ? SharpitColor.mutedForeground : SharpitColor.primary
                )
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(session.title ?? session.displayType)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(
                        state == .missed ? SharpitColor.mutedForeground : SharpitColor.foreground
                    )
                    .lineLimit(2)
                HStack(spacing: SharpitSpacing.xs) {
                    if session.isKey { SharpitInlineTag("Clé") }
                    Text(session.displayType)
                    if let durationMin = session.durationMin { Text("\(durationMin) min") }
                    if state == .missed { Text("Non réalisée") }
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if session.garminWorkoutId != nil {
                Image(systemName: "applewatch.side.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityLabel("Sur la montre Garmin")
            }
            Image(systemName: "chevron.right")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A brick in the day's list: one card for the chain, as it is one session to do — the
/// legs named in order, their total under them.
private struct PlanBrickCard: View {
    let brick: PlanBrick

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(spacing: 2) {
                ForEach(Array(brick.legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 {
                        Rectangle()
                            .fill(brick.isMissed ? SharpitColor.mutedForeground.opacity(0.4) : SharpitColor.primary.opacity(0.5))
                            .frame(width: 1.5, height: 6)
                    }
                    Image(systemName: leg.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(brick.isMissed ? SharpitColor.mutedForeground : SharpitColor.primary)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(brick.chain)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(brick.isMissed ? SharpitColor.mutedForeground : SharpitColor.foreground)
                    .lineLimit(2)
                HStack(spacing: SharpitSpacing.xs) {
                    SharpitInlineTag("Brick")
                    if brick.isKey { SharpitInlineTag("Clé") }
                    Text(brick.legs.map { leg in leg.durationMin.map { "\($0)" } ?? "–" }.joined(separator: " + ") + " min")
                    if brick.isMissed { Text("Non réalisé") }
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if brick.isOnWatch {
                Image(systemName: "applewatch.side.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityLabel("Sur la montre Garmin")
            }
            Image(systemName: "chevron.right")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Brick, \(brick.chain)" + (brick.isKey ? ", séance clé" : "")
                + (brick.totalDurationMin.map { ", \($0) minutes" } ?? "")
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// A brick done, in the day's list: one card for the chain it was, as it was one session —
/// the legs as recorded, their total under them.
private struct PlanDoneBrickCard: View {
    let brick: PlanDoneBrick

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(spacing: 2) {
                ForEach(Array(brick.symbolNames.enumerated()), id: \.offset) { index, symbol in
                    if index > 0 {
                        Rectangle()
                            .fill(SharpitColor.primary.opacity(0.5))
                            .frame(width: 1.5, height: 6)
                    }
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.primary)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                Text(brick.chain)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                HStack(spacing: SharpitSpacing.xs) {
                    Text("Brick réalisé")
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                    if let totalDurationMin = brick.totalDurationMin {
                        Text("\(totalDurationMin) min")
                    }
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.primary)
                .accessibilityHidden(true)
            Image(systemName: "chevron.right")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.mutedForeground)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Brick réalisé, \(brick.chain)" + (brick.totalDurationMin.map { ", \($0) minutes" } ?? ""))
        .accessibilityAddTraits(.isButton)
    }
}

private struct PlanLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(height: 86)
                ForEach(0..<7, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: 56)
                }
            }
            .redacted(reason: .placeholder)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.md)
        }
        .modifier(ScrollUnderGlass())
        .accessibilityLabel("Chargement du plan")
    }
}

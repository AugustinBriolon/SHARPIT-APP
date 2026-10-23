import MapKit
import SwiftUI
import Charts

struct ActivityDetailView: View {
    let activity: String
    let initialActivity: V1ActivityListItem?
    let client: any ActivityServing
    let linker: any PlannedSessionLinking
    let goalClient: any GoalServing
    let tokenProvider: () async throws -> String

    @State private var phase: DetailPhase
    @State private var appeared = false
    @State private var isGeneratingNarrative = false
    /// The analysis is SharpIt Pro (SHARPIT ADR-097): set by the server's refusal.
    @State private var narrativeNeedsPro = false
    @State private var streamPayload: V1ActivityStreamPayload?
    @State private var isEnriching = false
    @State private var showingCompliance = false
    @State private var subjectiveStore: ActivitySubjectiveStore?
    @State private var isMapExpanded = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var mapStyleSelection: MapStyleOption = .standard
    @State private var colorsRouteByIntensity = false
    /// The expanded map moved away from the route: only then is recentring worth a button.
    @State private var isMapOffRoute = false
    /// Built once per stream read, not on every render: the path and samples are hundreds long.
    @State private var routeIntensity: RouteIntensity?
    @State private var editing: ActivityEditing?
    @State private var isConfirmingDeletion = false
    @State private var isPickingGoal = false
    /// A triathlon leg opened on its own recording.
    @State private var openedLeg: String?
    @State private var notice: ActivityNotice?
    /// The pains and injuries the athlete follows, read for the questions owed after a session.
    @State private var zones: SensitiveZonesStore?
    @State private var reassessing: PainReassessment?
    /// Ties the expanded map's compass and scale to the map, so they sit in the safe area
    /// under the map's own buttons rather than where MapKit puts them on a full-bleed map.
    @Namespace private var mapScope
    /// The expanded map's camera once it settles: the 2D/3D button reads its pitch and keeps
    /// its centre, distance and heading when it tilts or flattens the view.
    @State private var mapCamera: MapCamera?
    /// The route drawn again from start to finish, played and paused from the map's buttons.
    @State private var routeReplay = RouteReplay()
    /// A triathlon's legs, from the parent's recording first, then each leg's own.
    @State private var course: [TriathlonLegTrack] = []
    @State private var courseSelection: TriathlonSelection = .overview
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router: ShellRouter?

    private var replaySymbol: String {
        switch routeReplay.state {
        case .playing: "pause.fill"
        case .finished: "arrow.counterclockwise"
        case .idle, .paused: "play.fill"
        }
    }

    private var replayLabel: String {
        switch routeReplay.state {
        case .playing: String(localized: "Mettre en pause le tracé")
        case .paused: String(localized: "Reprendre le tracé")
        case .finished: String(localized: "Rejouer le tracé")
        case .idle: String(localized: "Animer le tracé")
        }
    }

    init(
        activity: String,
        initialActivity: V1ActivityListItem? = nil,
        client: any ActivityServing,
        linker: any PlannedSessionLinking = PlannedSessionClient(),
        goalClient: any GoalServing = GoalClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.activity = activity
        self.initialActivity = initialActivity
        self.client = client
        self.linker = linker
        self.goalClient = goalClient
        self.tokenProvider = tokenProvider
        _phase = State(initialValue: initialActivity.map { .loaded(.preview(from: $0)) } ?? .loading)
        _appeared = State(initialValue: initialActivity != nil)
    }

    var body: some View {
        GeometryReader { proxy in
            switch phase {
            case .loading:
                ActivityDetailLoading(viewportHeight: proxy.size.height)
                    .ignoresSafeArea()
            case .loaded(let detail):
                let route = mapRoute(for: detail)
                let reservesMapSpace = !route.isEmpty ||
                    (isEnriching && detail.type.supportsPotentialRoute)
                if reservesMapSpace {
                    ZStack(alignment: .top) {
                        Group {
                            if colorsRouteByIntensity, let intensity = routeIntensity {
                                ActivityRouteHero(
                                    route: streamPayload?.route ?? route,
                                    tone: activityTone(detail.type),
                                    isExpanded: isMapExpanded,
                                    mapScope: mapScope,
                                    position: $mapCameraPosition,
                                    isOffRoute: $isMapOffRoute,
                                    camera: $mapCamera,
                                    mapStyle: mapStyleSelection.mapStyle,
                                    intensity: intensity,
                                    replay: routeReplay
                                )
                            } else if let stream = detail.stream, stream.available, !stream.route.isEmpty {
                                ActivityRouteHero(
                                    route: stream.route,
                                    tone: activityTone(detail.type),
                                    isExpanded: isMapExpanded,
                                    mapScope: mapScope,
                                    position: $mapCameraPosition,
                                    isOffRoute: $isMapOffRoute,
                                    camera: $mapCamera,
                                    mapStyle: mapStyleSelection.mapStyle,
                                    replay: routeReplay,
                                    course: course,
                                    courseSelection: courseSelection,
                                    initialRegion: courseRegion(.overview, viewport: proxy.size)
                                )
                            } else if !route.isEmpty {
                                ActivityRouteHero(
                                    route: route,
                                    tone: activityTone(detail.type),
                                    isExpanded: isMapExpanded,
                                    mapScope: mapScope,
                                    position: $mapCameraPosition,
                                    isOffRoute: $isMapOffRoute,
                                    camera: $mapCamera,
                                    mapStyle: mapStyleSelection.mapStyle,
                                    replay: routeReplay,
                                    course: course,
                                    courseSelection: courseSelection,
                                    initialRegion: courseRegion(.overview, viewport: proxy.size)
                                )
                            } else {
                                ActivityRouteLoadingSurface()
                            }
                        }
                        .frame(height: proxy.size.height)

                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: proxy.size.height * Self.mapVisibleShare)
                                    .contentShape(Rectangle())
                                    .allowsHitTesting(!isMapExpanded)
                                    .onTapGesture {
                                        guard !route.isEmpty else { return }
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                            isMapExpanded = true
                                        }
                                    }

                                ActivityDetailContent(
                                    detail: detail,
                                    streamPayload: streamPayload,
                                    appeared: appeared,
                                    isGeneratingNarrative: isGeneratingNarrative,
                                    narrativeNeedsPro: narrativeNeedsPro,
                                    onGenerateNarrative: { Task { await generateNarrative() } },
                                    splits: activitySplits(for: detail),
                                    onShowCompliance: { showingCompliance = true },
                                    onShowSubjective: { openSubjective(for: detail) },
                                    clearsBackButton: false,
                                    isMapExpanded: isMapExpanded,
                                    onExpandToggle: {
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                            isMapExpanded.toggle()
                                        }
                                    },
                                    reassessments: reassessments(for: detail),
                                    onReassess: { reassessing = $0 },
                                    onOpenLeg: { openLeg($0, viewport: proxy.size) },
                                    onValidateGoal: { validateGoal(detail) },
                                    course: course,
                                    courseSelection: courseSelection,
                                    onSelectCourse: { select($0, viewport: proxy.size) },
                                    bottomInset: proxy.safeAreaInsets.bottom
                                )
                                .frame(width: proxy.size.width, alignment: .leading)
                            }
                            .frame(width: proxy.size.width, alignment: .leading)
                        }
                        .scrollIndicators(isMapExpanded ? .hidden : .visible)
                        .scrollBounceBehavior(.basedOnSize)
                        .offset(y: isMapExpanded ? proxy.size.height : 0)
                        .opacity(isMapExpanded ? 0 : 1)
                        .allowsHitTesting(!isMapExpanded)
                        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isMapExpanded)
                    }
                    .ignoresSafeArea()
                } else {
                    ScrollView {
                        ActivityDetailContent(
                            detail: detail,
                            streamPayload: streamPayload,
                            appeared: appeared,
                            isGeneratingNarrative: isGeneratingNarrative,
                            narrativeNeedsPro: narrativeNeedsPro,
                            onGenerateNarrative: { Task { await generateNarrative() } },
                            splits: activitySplits(for: detail),
                            onShowCompliance: { showingCompliance = true },
                            onShowSubjective: { openSubjective(for: detail) },
                            clearsBackButton: true,
                            isMapExpanded: false,
                            onExpandToggle: {},
                            reassessments: reassessments(for: detail),
                            onReassess: { reassessing = $0 },
                            onOpenLeg: { openLeg($0, viewport: proxy.size) },
                            onValidateGoal: { validateGoal(detail) },
                            course: course,
                            courseSelection: courseSelection,
                            onSelectCourse: { select($0, viewport: proxy.size) }
                        )
                        .frame(width: proxy.size.width, alignment: .leading)
                    }

                }
            case .failed(let message):
                ScrollView {
                    ContentUnavailableView {
                        Label("Détail indisponible", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") { Task { await load() } }
                    }
                }
            case .unauthorized:
                ScrollView {
                    ContentUnavailableView("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
        .background(SharpitCanvasBackground())
        .modifier(ScrollUnderGlass())
        .toolbar(.hidden, for: .navigationBar)
        .enableInteractivePopGesture()
        .onChange(of: isMapExpanded) { _, expanded in
            if !expanded { routeReplay.stop() }
        }
        .onDisappear { routeReplay.stop() }
        .onChange(of: streamPayload, initial: true) { _, payload in
            routeIntensity = payload.flatMap { RouteIntensity.make(route: $0.route, samples: $0.samples) }
        }
        .overlay(alignment: .topLeading) {
            Button {
                if isMapExpanded {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        isMapExpanded = false
                    }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .sharpitShadow(.control)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel(isMapExpanded ? String(localized: "Réduire la carte") : String(localized: "Retour"))
        }
        .overlay(alignment: .topTrailing) {
            if case .loaded(let detail) = phase {
                let route = mapRoute(for: detail)
                HStack(spacing: 8) {
                    if !route.isEmpty {
                        if isMapExpanded && isMapOffRoute {
                            Button {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    mapCameraPosition = .region(computeRouteRegion(for: route))
                                }
                            } label: {
                                Image(systemName: "location.viewfinder")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(SharpitColor.foreground)
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .sharpitShadow(.control)
                            }
                            .accessibilityLabel("Recentrer la carte")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }

                        if isMapExpanded {
                            Menu {
                                Picker("Style de carte", selection: $mapStyleSelection) {
                                    ForEach(MapStyleOption.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                if routeIntensity != nil {
                                    Divider()
                                    Toggle("Heatmap", isOn: $colorsRouteByIntensity)
                                }
                            } label: {
                                Image(systemName: "square.2.layers.3d")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(SharpitColor.foreground)
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .sharpitShadow(.control)
                            }
                            .accessibilityLabel("Style de carte")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }

                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                isMapExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isMapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SharpitColor.foreground)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                                .sharpitShadow(.control)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityLabel(isMapExpanded ? String(localized: "Réduire la carte") : String(localized: "Agrandir la carte"))
                    }
                    if !isMapExpanded, let mutator = client as? any ActivityMutating {
                        ActivityActionsMenu(
                            isLinkedToGoal: detail.goal != nil,
                            onEdit: { editing = ActivityEditing(id: detail.id, draft: ActivityDraft(detail: detail), mutator: mutator) },
                            onPickGoal: { isPickingGoal = true },
                            onUnlinkGoal: { link(goal: nil, detail: detail, mutator: mutator) },
                            onDelete: { isConfirmingDeletion = true }
                        )
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMapExpanded)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The map ignores the safe area, so MapKit would draw these under the status bar
            // once the map is rotated or pitched; they live in the column under the buttons.
            // The 2D/3D button is always there, so it comes first: the compass, which comes and
            // goes with the heading, appears under it instead of pushing it down. MapKit's own
            // pitch toggle shows only once the map is tilted, so the button is the screen's.
            if isMapExpanded {
                let isPitched = (mapCamera?.pitch ?? 0) > 1
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        guard let camera = mapCamera else { return }
                        withAnimation(.easeInOut(duration: 0.45)) {
                            mapCameraPosition = .camera(MapCamera(
                                centerCoordinate: camera.centerCoordinate,
                                distance: camera.distance,
                                heading: camera.heading,
                                pitch: isPitched ? 0 : 60
                            ))
                        }
                    } label: {
                        Text(isPitched ? "2D" : "3D")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .sharpitShadow(.control)
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(.plain)
                    .disabled(mapCamera == nil)
                    .accessibilityLabel(isPitched ? String(localized: "Vue à plat") : String(localized: "Vue en relief"))
                    Button {
                        routeReplay.toggle()
                    } label: {
                        Image(systemName: replaySymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .sharpitShadow(.control)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(replayLabel)
                    MapCompass(scope: mapScope)
                    MapScaleView(scope: mapScope)
                }
                .padding(.trailing, 18)
                .padding(.top, 72)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if isMapExpanded, colorsRouteByIntensity, let intensity = routeIntensity {
                RouteIntensityLegend(metric: intensity.metric)
                    .padding(.leading, 16)
                    .padding(.top, 72)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if isMapExpanded, case .loaded(let detail) = phase {
                CollapsedActivityBottomBar(
                    detail: detail,
                    tone: activityTone(detail.type),
                    onExpand: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isMapExpanded = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(10)
            }
        }
        .mapScope(mapScope)
        .sheet(isPresented: $showingCompliance) {
            if case .loaded(let detail) = phase, let analysis = detail.plannedSession?.analysis {
                ComplianceDetailSheet(
                    title: detail.plannedSession?.title ?? String(localized: "Séance planifiée"),
                    analysis: analysis,
                    onUnlink: detail.plannedSession?.id.map { sessionId -> () -> Void in
                        { unlink(from: sessionId, detail: detail) }
                    },
                    onReanalyze: detail.plannedSession?.id.map { sessionId -> () -> Void in
                        { reanalyze(sessionId, previous: analysis) }
                    }
                )
                .presentationDetents([.medium, .large])
                .sharpitSheet()
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $reassessing) { item in
            if let zones {
                ZoneCheckinSheet(zone: item.zone, prompt: item.question) { draft in
                    await zones.checkin(item.zone, draft)
                }
            }
        }
        .sheet(item: $editing) { editing in editSheet(editing) }
        .navigationDestination(item: $openedLeg) { id in
            ActivityDetailView(activity: id, client: client, linker: linker, goalClient: goalClient, tokenProvider: tokenProvider)
        }
        .sheet(isPresented: $isPickingGoal) {
            if case .loaded(let detail) = phase, let mutator = client as? any ActivityMutating {
                ActivityGoalPickerSheet(
                    currentGoalId: detail.goalId,
                    activityDate: detail.date,
                    loadGoals: { try await goalClient.goals(token: try await tokenProvider()) },
                    onPick: { goal in link(goal: V1ActivityGoal(goal: goal), detail: detail, mutator: mutator) }
                )
                .presentationDetents([.medium, .large])
                .sharpitSheet()
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Supprimer cette séance ?", isPresented: $isConfirmingDeletion) {
            Button("Supprimer", role: .destructive) { delete() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Elle disparaît de ton historique, de ta charge et du plan qu’elle validait. Une séance synchronisée depuis une montre peut revenir à la prochaine synchronisation.")
        }
        .alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .sheet(item: $subjectiveStore) { store in
            SubjectiveEditorSheet(store: store)
                .presentationDetents([.fraction(0.72), .large])
                .sharpitSheet()
                .presentationDragIndicator(.visible)
        }
        .task {
            await load()
            await waitForCompliance()
        }
        .task(id: phase.loadedDate) {
            await loadZones()
        }
    }

    /// Share of the screen the map shows above the page's panel.
    private static let mapVisibleShare = 0.62

    /// The recorded route; for a triathlon without one of its own, its legs' joined end to end.
    private func mapRoute(for detail: V1ActivityDetail) -> [V1ActivityCoordinate] {
        if let route = detail.stream?.route, !route.isEmpty { return route }
        if let route = streamPayload?.route, !route.isEmpty { return route }
        return course.flatMap(\.route)
    }

    private func openLeg(_ id: String, viewport: CGSize) {
        if let selection = TriathlonCourse.selection(forLegSource: id, in: course) {
            select(selection, viewport: viewport)
        } else {
            openedLeg = id
        }
    }

    /// The leg's reading changes at once; the camera flies to the leg, or jumps under Reduce
    /// Motion, and stays put for a leg without GPS.
    private func select(_ selection: TriathlonSelection, viewport: CGSize) {
        withAnimation(.easeOut(duration: 0.25)) { courseSelection = selection }
        guard let region = courseRegion(selection, viewport: viewport) else { return }
        SharpitMotion.run(.easeInOut(duration: 0.8)) { mapCameraPosition = .region(region) }
    }

    private func courseRegion(_ selection: TriathlonSelection, viewport: CGSize) -> MKCoordinateRegion? {
        guard !course.isEmpty else { return nil }
        return RouteFraming.region(
            for: TriathlonCourse.route(for: selection, in: course),
            viewport: viewport,
            visibleHeightShare: Self.mapVisibleShare,
            minimumSpan: 0.002
        )
    }

    /// A triathlon's legs come from the parent's recording at once; each leg's own recording,
    /// which the server kept when it read the race, then replaces its slice.
    private func loadLegStreams(for detail: V1ActivityDetail, token: String) async {
        guard !course.isEmpty,
              let legStreams = try? await client.multisportStreams(id: activity, token: token),
              !legStreams.isEmpty
        else { return }
        course = TriathlonCourse.tracks(legs: detail.multisportLegs, parent: streamPayload, legStreams: legStreams)
    }

    private func reassessments(for detail: V1ActivityDetail) -> [PainReassessment] {
        PainReassessment.due(after: detail.date, zones: zones?.zones?.zones ?? [])
    }

    /// Read only for a session recent enough to ask about.
    private func loadZones() async {
        guard zones == nil, let date = phase.loadedDate,
              Date.now.timeIntervalSince(date) <= PainReassessment.freshness else { return }
        let store = SensitiveZonesStore(tokenProvider: tokenProvider)
        zones = store
        await store.load()
    }

    private func openSubjective(for detail: V1ActivityDetail) {
        subjectiveStore = ActivitySubjectiveStore(
            activityId: detail.id,
            rpe: detail.rpe,
            feeling: detail.feeling,
            client: client,
            tokenProvider: tokenProvider,
            onSaved: { rpe, feeling in
                guard case .loaded(let current) = phase else { return }
                withAnimation(SharpitMotion.selection) {
                    phase = .loaded(current.withSubjective(rpe: rpe, feeling: feeling))
                }
            }
        )
    }

    /// Takes the activity off its planned session: shown on the tap, sent behind. The plan
    /// reads the session as still to do once the calendar revision moves.
    private func unlink(from sessionId: String, detail: V1ActivityDetail) {
        showingCompliance = false
        withAnimation(SharpitMotion.reveal) {
            phase = .loaded(detail.withoutPlannedSession())
        }
        Task {
            do {
                try await SharpitRetry.run {
                    try await linker.link(sessionId: sessionId, activityId: nil, token: try await tokenProvider())
                }
            } catch {
                SharpitWriteFailures.shared.report(Self.unlinkFailure)
            }
            await client.forgetActivity(id: activity)
            await client.invalidateActivities()
            router?.noteCalendarChanged()
            await load()
        }
    }

    private func editSheet(_ editing: ActivityEditing) -> some View {
        ActivityFormSheet(
            mode: .edit(id: editing.id),
            draft: editing.draft,
            client: editing.mutator,
            tokenProvider: tokenProvider,
            onEdited: showEdited
        ) { _ in
            router?.noteActivitiesChanged()
            Task {
                await client.forgetActivity(id: activity)
                await load()
            }
        }
    }

    /// The edit shows on the tap, before the server answers; the reload that follows confirms it.
    private func showEdited(_ draft: ActivityDraft) {
        guard case .loaded(let current) = phase else { return }
        withAnimation(SharpitMotion.reveal) { phase = .loaded(current.applying(draft)) }
    }

    /// Links the session to a goal, or unlinks it with nil: shown on the tap, sent behind, put
    /// back if the server refuses for good.
    private func link(goal: V1ActivityGoal?, detail: V1ActivityDetail, mutator: any ActivityMutating) {
        isPickingGoal = false
        guard goal?.id != detail.goalId else { return }
        let previous = detail.goal
        withAnimation(SharpitMotion.reveal) {
            phase = .loaded(detail.withGoal(goal))
        }
        Task {
            do {
                try await SharpitRetry.run {
                    try await mutator.updateActivity(
                        id: detail.id,
                        fields: ["goalId": goal.map { .string($0.id) } ?? .null],
                        token: try await tokenProvider()
                    )
                }
                await client.invalidateActivities()
                router?.noteActivitiesChanged()
            } catch {
                if case .loaded(let current) = phase {
                    withAnimation(SharpitMotion.reveal) {
                        phase = .loaded(current.withGoal(previous))
                    }
                }
                SharpitWriteFailures.shared.report(goal == nil
                    ? String(localized: "L’objectif n’a pas pu être délié. Réessaie dans un instant.")
                    : String(localized: "La séance n’a pas pu être liée à l’objectif. Réessaie dans un instant."))
            }
        }
    }

    /// « Valider l'objectif » from the race header: shown on the tap, sent behind, put back if
    /// the server refuses for good.
    private func validateGoal(_ detail: V1ActivityDetail) {
        guard let goal = detail.goal, goal.achieved == false else { return }
        var reached = goal
        reached.achieved = true
        withAnimation(SharpitMotion.reveal) { phase = .loaded(detail.withGoal(reached)) }
        Task {
            do {
                _ = try await SharpitRetry.run {
                    try await goalClient.toggleAchieved(id: goal.id, achieved: true, token: try await tokenProvider())
                }
            } catch {
                if case .loaded(let current) = phase {
                    withAnimation(SharpitMotion.reveal) { phase = .loaded(current.withGoal(goal)) }
                }
                SharpitWriteFailures.shared.report(String(localized: "L’objectif n’a pas pu être validé. Réessaie dans un instant."))
            }
        }
    }

    /// Deletes on the server first; only then leaves the page and refreshes the list — a failed
    /// DELETE must not dismiss as if the session were gone.
    private func delete() {
        guard let mutator = client as? any ActivityMutating else { return }
        let id = activity
        Task {
            do {
                try await SharpitRetry.run {
                    try await mutator.deleteActivity(id: id, token: try await tokenProvider())
                }
                await client.forgetActivity(id: id)
                await client.invalidateActivities()
                router?.noteActivitiesChanged()
                dismiss()
            } catch {
                SharpitWriteFailures.shared.report(String(localized: "La séance n’a pas pu être supprimée. Réessaie dans un instant."))
            }
        }
    }

    /// The coach reads the session again behind; the page looks for the new reading a few
    /// times, then leaves it to the next open.
    private func reanalyze(_ sessionId: String, previous: V1PlannedSessionAnalysis) {
        showingCompliance = false
        Task {
            do {
                try await SharpitRetry.run {
                    try await linker.reanalyze(sessionId: sessionId, token: try await tokenProvider())
                }
                notice = ActivityNotice(title: String(localized: "Analyse relancée"), message: String(localized: "Le coach relit ta séance, la nouvelle analyse s’affiche ici dans un instant."))
            } catch SharpitAPIError.rateLimited {
                notice = ActivityNotice(title: String(localized: "Analyse"), message: String(localized: "Une analyse vient d’être lancée. Réessaie dans quelques minutes."))
                return
            } catch let SharpitAPIError.message(reason) {
                notice = ActivityNotice(title: String(localized: "Analyse"), message: reason)
                return
            } catch SharpitAPIError.proRequired {
                notice = ActivityNotice(title: String(localized: "Analyse"), message: String(localized: "Relire une séance est réservé à SharpIt Pro, avec le reste du coaching."))
                return
            } catch {
                notice = ActivityNotice(title: String(localized: "Analyse"), message: String(localized: "L’analyse n’a pas pu être relancée. Réessaie dans un instant."))
                return
            }
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(8))
                await client.forgetActivity(id: activity)
                await load()
                if case .loaded(let detail) = phase, detail.plannedSession?.analysis != previous { return }
            }
        }
    }

    /// The compliance reading lands a few seconds after the session: while the page says
    /// « Calcul en cours », it looks again a few times, then leaves it to the next open.
    private func waitForCompliance() async {
        for _ in 0..<6 {
            guard case .loaded(let detail) = phase, detail.plannedSession?.awaitsAnalysis == true else { return }
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { return }
            await load()
        }
    }

    static let unlinkFailure = String(localized: "L’activité n’a pas pu être déliée. Réessaie dans un instant.")

    private func activitySplits(for detail: V1ActivityDetail) -> [ActivitySplit] {
        guard detail.type.supportsSplits else { return [] }
        return ActivitySplit.make(
            samples: streamPayload?.samples ?? [],
            totalDuration: detail.duration,
            segmentDistance: detail.type.splitDistance
        )
    }

    private func effectiveDistance(for detail: V1ActivityDetail) -> Double? {
        detail.distanceM ?? streamPayload?.stats?.totalDistance
    }

    @MainActor
    private func generateNarrative() async {
        guard !isGeneratingNarrative else { return }
        isGeneratingNarrative = true
        defer { isGeneratingNarrative = false }
        do {
            let token = try await tokenProvider()
            let detail = try await client.generateNarrative(id: activity, token: token)
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(detail)
            }
        } catch is CancellationError {
        } catch SharpitAPIError.proRequired {
            withAnimation(SharpitMotion.reveal) { narrativeNeedsPro = true }
        } catch {
            SharpitWriteFailures.shared.report(String(localized: "Le récit n’a pas pu être généré. Réessaie dans un instant."))
        }
    }

    @MainActor
    private func load() async {
        do {
            isEnriching = initialActivity != nil
            let token = try await tokenProvider()
            async let detailRequest = client.activity(id: activity, token: token)
            async let streamRequest = client.activityStream(id: activity, token: token)
            let detail = try await detailRequest
            streamPayload = try? await streamRequest
            isEnriching = false
            course = detail.type == .triathlon
                ? TriathlonCourse.tracks(legs: detail.multisportLegs, parent: streamPayload, legStreams: [])
                : []
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(detail)
            }

            if SharpitMotion.reduceMotion {
                appeared = true
            } else {
                SharpitMotion.run {
                    appeared = true
                }
            }
            await loadLegStreams(for: detail, token: token)
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            isEnriching = false
            // The session opened from the list keeps its row's figures; the toast says the rest
            // did not come.
            if case .loaded = phase {
                SharpitWriteFailures.shared.reportStaleRead(SharpitErrorGuidance.message(for: error, subject: String(localized: "Le détail de la séance")))
                return
            }
            phase = .failed(String(localized: "Impossible de récupérer cette activité pour le moment."))
        }
    }
}

private struct ActivityNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum DetailPhase {
    case loading
    case loaded(V1ActivityDetail)
    case failed(String)
    case unauthorized

    var loadedDate: Date? {
        if case .loaded(let detail) = self { detail.date } else { nil }
    }
}

private struct ActivityDetailContent: View {
    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading

    let detail: V1ActivityDetail
    let streamPayload: V1ActivityStreamPayload?
    let appeared: Bool
    let isGeneratingNarrative: Bool
    var narrativeNeedsPro = false
    let onGenerateNarrative: () -> Void
    let splits: [ActivitySplit]
    let onShowCompliance: () -> Void
    let onShowSubjective: () -> Void
    /// Without a map the panel starts at the top of the screen, under the floating back
    /// button, and has to leave room for it. Below a map it does not.
    let clearsBackButton: Bool
    var isMapExpanded: Bool = false
    var onExpandToggle: () -> Void = {}
    var reassessments: [PainReassessment] = []
    var onReassess: (PainReassessment) -> Void = { _ in }
    /// Opens one leg's own recording; nil where the page cannot push it.
    var onOpenLeg: ((String) -> Void)? = nil
    /// Marks the linked race reached, from its header.
    var onValidateGoal: () -> Void = {}
    /// A triathlon's legs, read one at a time under the course map; empty for any other session.
    var course: [TriathlonLegTrack] = []
    var courseSelection: TriathlonSelection = .overview
    var onSelectCourse: (TriathlonSelection) -> Void = { _ in }
    /// The map layout ignores the safe area: the sheet itself grows by the tab bar's height, so its
    /// last card clears the bar and no map shows under the sheet.
    var bottomInset: CGFloat = 0
    @State private var selectedChartMetrics: [ActivityChartMetric] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if !clearsBackButton {
                HStack {
                    Spacer()
                    Capsule()
                        .fill(SharpitColor.mutedForeground.opacity(0.35))
                        .frame(width: 38, height: 5)
                    Spacer()
                }
                .padding(.top, -6)
                .padding(.bottom, -6)
                .contentShape(Rectangle())
                .onTapGesture {
                    onExpandToggle()
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.height > 20 {
                                onExpandToggle()
                            }
                        }
                )
            }

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                HStack {
                    Label { Text(detail.type.label) } icon: { Image(sharpitSymbol: detail.type.symbolName) }
                        .font(SharpitTypography.eyebrow)
                        .tracking(SharpitTypography.eyebrowTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(tone)
                    Spacer()
                    Text(dateLabel)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Text(detail.title ?? detail.type.label)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .lineLimit(3)

                // The session the athlete is reading is exactly what they would ask about,
                // so the way to ask sits with its title rather than below the analysis.
                HStack(spacing: SharpitSpacing.sm) {
                    CoachDiscussButton(title: String(localized: "Discuter de cette séance")) {
                        router.discussWithCoach(
                            about: CoachDiscuss.describe(
                                .activity(activityId: detail.id),
                                name: detail.title ?? detail.type.label
                            )
                        )
                    }
                    Spacer(minLength: 0)
                    if let weather = detail.weather, let weatherLabel = V1ActivityWeather(rawValue: weather).label {
                        Label(weatherLabel, systemImage: "cloud.sun")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .padding(.top, SharpitSpacing.xxs)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isMapExpanded {
                    onExpandToggle()
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .padding(.top, clearsBackButton ? 56 : 0)

            if !course.isEmpty {
                SharpitSegmentedControl(
                    selection: Binding(get: { courseSelection }, set: { onSelectCourse($0) }),
                    options: TriathlonCourse.options(course).map { .init(value: $0.value, label: $0.label) }
                )
                .opacity(appeared ? 1 : 0)
            }

            if let track = TriathlonCourse.track(for: courseSelection, in: course) {
                TriathlonLegSections(track: track, race: detail)
                    .id(track.id)
                    .transition(courseTransition)
            } else {
                Group { overviewSections }
                    .transition(courseTransition)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.lg + bottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if clearsBackButton {
                    Color.clear
                } else {
                    // Drawn past its bottom edge, so pulling beyond the end never shows the map.
                    RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                        .fill(SharpitElevatedColor.sheet)
                        .sharpitShadow(.panel)
                        .padding(.bottom, -800)
                }
            }
        )
        .environment(\.sharpitElevation, clearsBackButton ? .base : .sheet)
        .foregroundStyle(SharpitColor.foreground)
    }

    /// A leg's reading slides up as it fades in; under Reduce Motion it only fades. Any other
    /// session never switches, and keeps the page's own arrival.
    private var courseTransition: AnyTransition {
        if course.isEmpty { return .identity }
        return reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }

    @ViewBuilder
    private var overviewSections: some View {
            if let goal = detail.goal {
                ActivityRaceHeader(goal: goal, result: raceResult, onValidate: onValidateGoal)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 1)), value: appeared)
            }

            contextSection
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 1)), value: appeared)

            metricGrid
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 2)), value: appeared)

            if !reassessments.isEmpty {
                PainReassessmentSection(items: reassessments, onAnswer: onReassess)
                    .opacity(appeared ? 1 : 0)
                    .animation(SharpitMotion.reveal, value: reassessments)
            }

            if detail.type == .strength, !strengthExercises.isEmpty {
                ActivityStrengthSection(exercises: strengthExercises)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 3)), value: appeared)
            }

            if let analysis = detail.raceAnalysis {
                RaceAnalysisSections(analysis: analysis, showsTotal: detail.goal == nil, onOpenLeg: onOpenLeg)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 3)), value: appeared)
            } else if detail.type == .triathlon, !detail.multisportLegs.isEmpty {
                multisportLegsSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 3)), value: appeared)
            }

            if detail.narrativeAnalysis != nil || detail.type.supportsCoachAnalysis {
                coachAnalysis
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 4)), value: appeared)
            }

            if hasSessionSummaryData {
                sessionSummary
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 6)), value: appeared)
            }

            // The expert reading's technical layer (ADR 0006): absent otherwise, never teased.
            if isExpertReading, let analysis = streamPayload?.analysis,
               !ActivityTechnicalSection(analysis: analysis).isEmpty {
                ActivityTechnicalSection(analysis: analysis)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 6)), value: appeared)
            }

            if !splits.isEmpty {
                ActivitySplitsSection(
                    splits: splits,
                    tone: tone,
                    segmentDistance: detail.type.splitDistance
                )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 7)), value: appeared)
            }

            if !availableChartMetrics.isEmpty {
                ActivityChartsSection(
                    samples: streamPayload?.samples ?? [],
                    metrics: availableChartMetrics,
                    selection: $selectedChartMetrics
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(SharpitMotion.staggerDelay(index: 8)), value: appeared)
            }
    }

    private var metricGrid: some View {
        ActivityMetricGrid(
            metrics: ActivityHeroMetricData.primary(for: detail, distanceM: effectiveDistanceM, isExpertReading: isExpertReading)
        )
    }

    /// What the athlete said about the session and how it matched the plan. Both open a
    /// drawer, so both are drawn as raised tiles with a chevron — weather, which opens
    /// nothing, stays a flat chip below them.
    /// What the athlete said about the session and how it matched the plan, side by side:
    /// two short readouts share one row instead of each leaving half a line empty.
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "Ta séance"))
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                SessionFeedbackTile(
                    rpe: detail.rpe.map { Int($0.rounded()) },
                    feeling: SessionFeeling(stored: detail.feeling),
                    accent: tone,
                    action: onShowSubjective
                )
                if let analysis = detail.plannedSession?.analysis {
                    ComplianceTile(analysis: analysis, action: onShowCompliance)
                } else if detail.plannedSession != nil {
                    CompliancePendingTile()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coachAnalysis: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: String(localized: "Analyse du coach"),
                symbol: "sparkles",
                subtitle: detail.narrativeAnalysis == nil ? String(localized: "Prête à être générée") : nil,
                showsChevron: false
            )
            if let narrative = detail.narrativeAnalysis {
                // The headline opens the body, whole: too long for a card title, and cut there.
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(narrative.headline)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(narrative.narrative)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textSelection(.enabled)
            } else if narrativeNeedsPro {
                SharpitProTeaser(
                    title: String(localized: "Analyse de séance"),
                    message: String(localized: "Le coach lit chaque séance avec SharpIt Pro : ce qui a marché, ce qui a coûté, ce que ça change pour la suite.")
                )
            } else {
                Text("SharpIt croise ta séance, ton ressenti et les données disponibles pour te donner une lecture claire et actionnable.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                SharpitPrimaryButton(
                    title: isGeneratingNarrative ? String(localized: "Analyse en cours…") : String(localized: "Générer l’analyse"),
                    trailingSymbol: isGeneratingNarrative ? nil : "arrow.up.right",
                    isBusy: isGeneratingNarrative,
                    action: onGenerateNarrative
                )
                .disabled(isGeneratingNarrative)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: String(localized: "Lecture de séance"), symbol: "list.bullet.rectangle", showsChevron: false)
            let signals = summarySignals
            if !signals.isEmpty {
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ForEach(signals, id: \.caption) { signal in
                        SharpitStatTile(caption: signal.caption, value: signal.value, unit: signal.unit, isFlat: true)
                    }
                }
            }
            if let notes = detail.notes, !notes.isEmpty {
                Text(notes).font(SharpitTypography.body).foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    /// The session's figures beyond the hero grid, per sport.
    private var summarySignals: [(caption: String, value: String, unit: String?)] {
        switch detail.type {
        case .strength:
            return [(String(localized: "Exercices"), "\(exerciseCount)", nil), (String(localized: "Séries"), "\(totalStrengthSets)", nil)]
                + (strengthVolume.map { [(String(localized: "Volume"), "\(Int($0.rounded()))", "kg")] } ?? [])
        case .swim:
            return (detail.swimSets.map { [(String(localized: "Séries"), "\(Int($0.rounded()))", nil)] } ?? [])
                + (detail.swolf.map { [(String(localized: "Swolf"), "\(Int($0.rounded()))", nil)] } ?? [])
        case .triathlon:
            return []
        default:
            return (detail.elevationM.map { [(String(localized: "Dénivelé"), "\(Int($0.rounded()))", "m")] } ?? [])
                + (detail.avgPower.map { [(String(localized: "Puissance"), "\(Int($0.rounded()))", "W")] } ?? [])
                + (detail.calories.map { [(String(localized: "Calories"), "\(Int($0.rounded()))", "kcal")] } ?? [])
        }
    }

    private var hasSessionSummaryData: Bool {
        detail.notes?.isEmpty == false ||
        detail.type == .strength && !detail.strengthSets.isEmpty ||
        detail.type == .swim && (detail.swimSets != nil || detail.swolf != nil) ||
        detail.type != .strength && detail.type != .swim && (detail.elevationM != nil || detail.avgPower != nil || detail.calories != nil)
    }

    private var exerciseCount: Int {
        Set(detail.strengthSets.map(\.exercise)).count
    }

    private var strengthExercises: [StrengthExerciseReadout] {
        StrengthExerciseReadout.exercises(from: detail.strengthSets)
    }

    private var totalStrengthSets: Int { detail.strengthSetCount }

    private var strengthVolume: Double? { detail.strengthVolumeKg }

    private var tone: Color {
        activityTone(detail.type)
    }

    private var availableChartMetrics: [ActivityChartMetric] {
        ActivityChartMetric.available(in: streamPayload?.samples ?? [])
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: detail.date)
    }

    private var distanceValue: String {
        guard let distanceM = effectiveDistanceM else { return "—" }
        return distanceM >= 1_000
            ? String(format: "%.1f", distanceM / 1_000) + " km"
            : "\(Int(distanceM.rounded())) m"
    }

    private var effectiveDistanceM: Double? {
        detail.distanceM ?? streamPayload?.stats?.totalDistance
    }

    private var raceResult: RaceResultModel? {
        RaceResultModel.make(
            durationSec: detail.duration,
            legs: detail.multisportLegs,
            targetPerformance: detail.goal?.targetPerformance
        )
    }

    private var multisportLegsSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(String(localized: "Enchaînement"))
            let segments = RaceLegsTimeline.segments(detail.multisportLegs)
            if !segments.isEmpty {
                RaceLegsBar(segments: segments, compact: true)
            }
            VStack(spacing: 0) {
                ForEach(RaceAnalysisReadout.legRows(detail.multisportLegs)) { row in
                    RaceLegRowLink(row: row, onOpen: onOpenLeg)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elevationValue: String {
        guard let elevationM = detail.elevationM else { return "—" }
        return "\(Int(elevationM.rounded())) m"
    }

    private var paceValue: String {
        let seconds = detail.paceSecPerKm ?? detail.avgPaceSecPer100m
        guard let seconds else { return "—" }
        if detail.type == .swim {
            return "\(Int(seconds / 60))'\(String(format: "%02d", Int(seconds.rounded()) % 60))\""
        }
        return "\(Int(seconds / 60))'\(String(format: "%02d", Int(seconds.rounded()) % 60))\""
    }

    private var heartRateValue: String {
        detail.avgHr.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var cadenceNumber: Double? {
        detail.cadence ?? detail.avgCadence
    }

    private var cadenceValue: String {
        cadenceNumber.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var cadenceLabel: String {
        String(localized: "Cadence")
    }

    private var caloriesValue: String {
        detail.calories.map { "\(Int($0.rounded()))" } ?? "—"
    }
}

private extension V1ActivityType {
    var supportsPotentialRoute: Bool {
        switch self {
        case .run, .bike, .hike, .triathlon:
            true
        case .swim, .strength, .other:
            false
        }
    }
}

extension V1ActivityType {
    /// Per-kilometre splits read one sport's pace; a triathlon's legs are read by leg instead.
    var supportsSplits: Bool {
        switch self {
        case .run, .bike, .hike:
            true
        case .swim, .strength, .triathlon, .other:
            false
        }
    }

    /// Metres per split: a ride is read every 5 km.
    var splitDistance: Double { self == .bike ? 5_000 : 1_000 }

    /// The sports the coach can read on request — the server answers 422 for the others.
    var supportsCoachAnalysis: Bool {
        switch self {
        case .run, .bike, .swim, .triathlon, .strength:
            true
        case .hike, .other:
            false
        }
    }
}

/// The goal a session was raced for, read against it: the goal, its format, and the final time
/// beside the aim.
private struct ActivityRaceHeader: View {
    let goal: V1ActivityGoal
    let result: RaceResultModel?
    var onValidate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Objectif"), systemImage: "flag.checkered")
            Text(goal.title)
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
            if let line = detailLine {
                Text(line)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            if let result {
                RaceTimeReadout(result: result)
            }
            switch goal.achieved {
            case true?:
                Label("Objectif atteint", systemImage: "checkmark.seal.fill")
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.foreground)
            case false?:
                Button("Valider l'objectif", systemImage: "checkmark.circle", action: onValidate)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
                    .buttonStyle(.sharpitPressable)
            case nil:
                EmptyView()
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .contain)
    }

    private var detailLine: String? {
        let clean = { (text: String?) in text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        let parts = [clean(goal.raceFormat), clean(goal.targetPerformance).map { String(localized: "Objectif · \($0)") }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

func activityTone(_ type: V1ActivityType) -> Color {
    SharpitSportTone.label(for: type)
}

struct ActivitySplit: Identifiable, Equatable {
    let id: Int
    let distanceLabel: String
    let paceSeconds: Double
    let variation: Double
    let heartRate: Double?
    let elevationGain: Double
    let progress: Double

    static func make(
        samples: [V1ActivityStreamSample],
        totalDuration: Double?,
        segmentDistance: Double
    ) -> [ActivitySplit] {
        guard samples.count > 1 else { return [] }
        let ordered = samples.sorted { $0.d < $1.d }
        guard let totalDistance = ordered.last?.d, totalDistance >= 500 else { return [] }
        let overallPace = totalDuration.map { $0 / totalDistance * 1_000 }
            ?? duration(for: ordered.last!, after: ordered.first!) / totalDistance * 1_000
        guard overallPace > 0 else { return [] }

        let segmentCount = Int(ceil(totalDistance / segmentDistance))
        return (0..<segmentCount).compactMap { index in
            let startDistance = Double(index) * segmentDistance
            let endDistance = min(Double(index + 1) * segmentDistance, totalDistance)
            guard
                let start = sample(at: startDistance, in: ordered),
                let end = sample(at: endDistance, in: ordered),
                end.d > start.d,
                end.t > start.t
            else { return nil }

            let distance = end.d - start.d
            let pace = (end.t - start.t) / distance * 1_000
            let points = ordered.filter { $0.d >= start.d && $0.d <= end.d }
            let heartRates = points.compactMap(\.hr)
            let elevationGain = zip(points, points.dropFirst())
                .reduce(0) { result, pair in result + max(0, (pair.1.alt ?? pair.0.alt ?? 0) - (pair.0.alt ?? pair.1.alt ?? 0)) }

            return ActivitySplit(
                id: index,
                distanceLabel: endDistance - startDistance < segmentDistance
                    // Where the split ends, like the whole ones: « 13,8 km », not its own 3,8.
                    ? String(format: String(localized: "%.1f km"), endDistance / 1_000).replacingOccurrences(of: ".", with: ",")
                    : "\(Int(endDistance / 1_000)) km",
                paceSeconds: pace,
                variation: (pace / overallPace - 1) * 100,
                heartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                elevationGain: elevationGain,
                progress: max(0.16, min(1, overallPace / pace))
            )
        }
    }

    /// A ride reads in km/h (its 5 km segments); a run or a swim in pace per km.
    func figure(segmentDistance: Double) -> String {
        guard segmentDistance >= 5_000, paceSeconds > 0 else { return ActivityFormat.pace(paceSeconds) }
        return "\(RaceAnalysisReadout.pace(3_600 / paceSeconds, .kmh)) km/h"
    }

    private static func sample(at distance: Double, in samples: [V1ActivityStreamSample]) -> V1ActivityStreamSample? {
        samples.min { abs($0.d - distance) < abs($1.d - distance) }
    }

    private static func duration(for end: V1ActivityStreamSample, after start: V1ActivityStreamSample) -> Double {
        max(0, end.t - start.t)
    }
}

struct ActivitySplitsSection: View {
    let splits: [ActivitySplit]
    let tone: Color
    let segmentDistance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(
                title: segmentDistance == 5_000 ? String(localized: "Splits tous les 5 km") : String(localized: "Splits au kilomètre"),
                symbol: "flag.pattern.checkered",
                subtitle: String(localized: "Barre longue, allure vive"),
                showsChevron: false
            )
            VStack(spacing: SharpitSpacing.sm) {
                ForEach(splits) { split in
                    row(split)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    /// Distance, figure and its gap to the session's average, the bar, then heart rate and climb.
    /// The fastest splits (5 % above the average) fill lime, the rest ink.
    private func row(_ split: ActivitySplit) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Text(split.distanceLabel)
                .font(SharpitTypography.meta.monospacedDigit())
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(split.figure(segmentDistance: segmentDistance))
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                    Text(String(format: "%+.0f %%", split.variation))
                        .font(SharpitTypography.meta.monospacedDigit())
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .lineLimit(1)
                SharpitBarTrack(
                    fraction: split.progress,
                    tone: split.variation <= -5 ? SharpitColor.highlight : SharpitColor.foreground
                )
                .frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 2) {
                if let heartRate = split.heartRate {
                    Text("\(Int(heartRate.rounded())) bpm")
                }
                Text("+\(Int(split.elevationGain.rounded())) m")
            }
            .font(SharpitTypography.meta.monospacedDigit())
            .foregroundStyle(SharpitColor.mutedForeground)
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

enum ActivityChartMetric: String, CaseIterable, Identifiable {
    case heartRate
    case pace
    case power
    case elevation
    case cadence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heartRate: "FC"
        case .pace: String(localized: "Allure")
        case .power: String(localized: "Puissance")
        case .elevation: String(localized: "Dénivelé")
        case .cadence: String(localized: "Cadence")
        }
    }

    var unit: String {
        switch self {
        case .heartRate: "BPM"
        case .pace: "min/km"
        case .power: "W"
        case .elevation: "m"
        case .cadence: "SPM"
        }
    }

    func value(for sample: V1ActivityStreamSample) -> Double? {
        switch self {
        case .heartRate:
            return sample.hr
        case .pace:
            guard let speed = sample.speed, speed > 0.2 else { return nil }
            return 1_000 / speed
        case .power:
            return sample.watts
        case .elevation:
            return sample.alt
        case .cadence:
            return sample.cadence
        }
    }

    static func available(in samples: [V1ActivityStreamSample]) -> [ActivityChartMetric] {
        allCases.filter { metric in samples.contains { metric.value(for: $0) != nil } }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .pace:
            return ActivityFormat.pace(value)
        case .heartRate, .power, .elevation, .cadence:
            return "\(Int(value.rounded()))"
        }
    }
}

private struct DetailMetric: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(SharpitTypography.data)
                .lineLimit(1)
            if let unit { Text(unit).font(.caption).foregroundStyle(SharpitColor.mutedForeground) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitContainerCorner(SharpitSpacing.cardRadius)
        .background(SharpitElevatedColor.panelOnSheet, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
    }
}

struct ActivityHeroMetricData: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let unit: String?
}

extension ActivityHeroMetricData {
    /// « Résumé de séance »: what the session was, then what it cost (ADR 0006).
    static func primary(for detail: V1ActivityDetail, distanceM: Double?, isExpertReading: Bool) -> [ActivityHeroMetricData] {
        var metrics: [ActivityHeroMetricData] = []
        if let duration = detail.duration { metrics.append(.init(label: String(localized: "Durée"), value: ActivityFormat.duration(duration), unit: nil)) }
        if detail.type == .strength {
            if !detail.strengthSets.isEmpty { metrics.append(.init(label: String(localized: "Séries"), value: "\(detail.strengthSetCount)", unit: nil)) }
            if let volume = detail.strengthVolumeKg { metrics.append(.init(label: String(localized: "Volume"), value: "\(Int(volume.rounded()))", unit: "kg")) }
        } else if let distance = distanceM {
            metrics.append(.init(label: String(localized: "Distance"), value: distance >= 1_000 ? String(format: "%.1f", distance / 1_000).replacingOccurrences(of: ".", with: ",") : "\(Int(distance.rounded()))", unit: distance >= 1_000 ? "km" : "m"))
        }
        if let elevation = detail.elevationM, detail.type != .swim && detail.type != .strength { metrics.append(.init(label: String(localized: "Dénivelé"), value: "\(Int(elevation.rounded()))", unit: "m")) }
        if detail.type == .swim, let pace = detail.avgPaceSecPer100m {
            metrics.append(.init(label: String(localized: "Allure"), value: ActivityFormat.paceClock(pace), unit: "/100 m"))
        } else if detail.type == .bike, let distance = distanceM, let duration = detail.duration, duration > 0 {
            // A ride reads in km/h, never as a pace per km.
            metrics.append(.init(label: String(localized: "Vitesse"), value: ActivityFormat.speedKmh(distanceM: distance, duration: duration), unit: "km/h"))
        } else if detail.type != .strength, let pace = detail.paceSecPerKm {
            metrics.append(.init(label: String(localized: "Allure"), value: ActivityFormat.paceClock(pace), unit: "/km"))
        }
        // Last, because it is what the session cost rather than what it was (ADR 0006).
        if let load = detail.load, load > 0 {
            metrics.append(.init(
                label: isExpertReading ? "TSS" : String(localized: "Charge"),
                value: "\(Int(load.rounded()))",
                unit: nil
            ))
        }
        return metrics
    }
}

struct ActivityMetricGrid: View {
    var title = String(localized: "Résumé de séance")
    var symbol = "chart.bar"
    let metrics: [ActivityHeroMetricData]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(title: title, symbol: symbol, showsChevron: false)
            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 0), alignment: .topLeading), GridItem(.flexible(minimum: 0), alignment: .topLeading)],
                alignment: .leading,
                spacing: SharpitSpacing.lg
            ) {
                ForEach(metrics) { metric in
                    SharpitStatTile(caption: metric.label, value: metric.value, unit: metric.unit, isFlat: true)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private func computeRouteRegion(for route: [V1ActivityCoordinate]) -> MKCoordinateRegion {
    let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    let latitudes = coordinates.map(\.latitude)
    let longitudes = coordinates.map(\.longitude)
    guard
        let minLatitude = latitudes.min(),
        let maxLatitude = latitudes.max(),
        let minLongitude = longitudes.min(),
        let maxLongitude = longitudes.max()
    else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.764, longitude: 4.835),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        ),
        span: MKCoordinateSpan(
            latitudeDelta: max(maxLatitude - minLatitude, 0.008) * 1.35,
            longitudeDelta: max(maxLongitude - minLongitude, 0.008) * 1.35
        )
    )
}

private struct ActivityRouteHero: View {
    let route: [V1ActivityCoordinate]
    let tone: Color
    var isExpanded: Bool = false
    /// The scope the screen's own compass and pitch toggle read; the map draws none itself.
    let mapScope: Namespace.ID
    @Binding var position: MapCameraPosition
    @Binding var isOffRoute: Bool
    @Binding var camera: MapCamera?
    var mapStyle: MapStyle = .standard(elevation: .realistic)
    /// When set, the route is drawn stretch by stretch in its intensity's tone.
    var intensity: RouteIntensity? = nil
    /// While it plays or pauses, only the part already travelled is drawn, over a faint route.
    var replay: RouteReplay? = nil
    /// A triathlon's legs, each drawn in its sport's colour; the selected one stays bright.
    var course: [TriathlonLegTrack] = []
    var courseSelection: TriathlonSelection = .overview
    /// Where the camera opens instead of the route's own region.
    var initialRegion: MKCoordinateRegion? = nil

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var replayProgress: Double? { replay?.progress }

    private var drawnRoute: [V1ActivityCoordinate] {
        replayProgress.map { RouteReplayPath.prefix(route, progress: $0) } ?? route
    }

    private var drawnSegments: [RouteIntensity.Segment] {
        guard let intensity else { return [] }
        return replayProgress.map { RouteReplayPath.prefix(intensity.segments, progress: $0) } ?? intensity.segments
    }

    private var replayHead: CLLocationCoordinate2D? {
        guard replayProgress != nil, let head = drawnRoute.last else { return nil }
        return CLLocationCoordinate2D(latitude: head.latitude, longitude: head.longitude)
    }

    private var region: MKCoordinateRegion {
        computeRouteRegion(for: route)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $position, interactionModes: isExpanded ? .all : [], scope: mapScope) {
                if replayProgress != nil {
                    MapPolyline(coordinates: coordinates)
                        .stroke(SharpitColor.mutedForeground.opacity(0.35), lineWidth: 5)
                }
                if intensity != nil {
                    ForEach(Array(drawnSegments.enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment.coordinates.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(RouteIntensityTone.color(level: segment.level), lineWidth: 5)
                    }
                } else if replayProgress == nil, !course.isEmpty {
                    ForEach(courseLayers) { track in
                        let isSelected = courseSelection == .leg(track.id)
                        MapPolyline(coordinates: track.route.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(
                            courseColor(track).opacity(courseSelection == .overview || isSelected ? 1 : 0.3),
                            lineWidth: isSelected ? 6 : 5
                        )
                    }
                } else {
                    MapPolyline(coordinates: drawnRoute.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(tone, lineWidth: 5)
                }
                if let start = coordinates.first {
                    Annotation(String(localized: "Départ"), coordinate: start) {
                        RoutePointMarker(color: .white, stroke: tone)
                    }
                }
                if let finish = coordinates.last {
                    Annotation(String(localized: "Arrivée"), coordinate: finish) {
                        RoutePointMarker(color: tone, stroke: .white)
                    }
                }
                if let head = replayHead {
                    Annotation("", coordinate: head) {
                        Circle()
                            .fill(tone)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.25), radius: 3)
                    }
                }
            }
            .mapStyle(mapStyle)
            .mapControls {}
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(isExpanded)
            .onMapCameraChange(frequency: .onEnd) { context in
                camera = context.camera
                let off = isExpanded && RouteFraming.isOffRoute(visible: context.region, route: route)
                if off != isOffRoute {
                    withAnimation(SharpitMotion.selection) { isOffRoute = off }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .horizontal)
        .accessibilityElement(children: isExpanded ? .contain : .ignore)
        .accessibilityLabel("Tracé GPS de l’activité, \(route.count) points")
        .onAppear {
            if !route.isEmpty {
                position = .region(initialRegion ?? region)
            }
        }
    }

    /// The selected leg last, so it is drawn over the legs it crosses.
    private var courseLayers: [TriathlonLegTrack] {
        course.filter { $0.route.count > 1 }
            .sorted { (courseSelection == .leg($0.id) ? 1 : 0) < (courseSelection == .leg($1.id) ? 1 : 0) }
    }

    private func courseColor(_ track: TriathlonLegTrack) -> Color {
        track.segment.sport.map { SharpitSportTone.accent(for: $0) } ?? SharpitColor.mutedForeground
    }
}

private struct ActivityRouteLoadingSurface: View {
    var body: some View {
        ZStack {
            SharpitColor.analysisSurfaceAlt
            LinearGradient(
                colors: [.clear, SharpitColor.analysisGrid],
                startPoint: .top,
                endPoint: .bottom
            )
            ProgressView()
                .tint(.secondary)
                .accessibilityLabel("Chargement de la carte")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Carte en cours de chargement")
    }
}

private struct RoutePointMarker: View {
    let color: Color
    let stroke: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(stroke, lineWidth: 3))
            .shadow(color: .black.opacity(0.2), radius: 3)
    }
}

private struct ActivityDetailLoading: View {
    let viewportHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, SharpitColor.analysisGrid],
                startPoint: .top,
                endPoint: .bottom
            )

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: viewportHeight * 0.62)

                    ActivityDetailLoadingSheet()
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityLabel("Chargement du détail")
    }
}

private struct ActivityDetailLoadingSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(width: 124, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(width: 104, height: 16)
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(maxWidth: 300, minHeight: 40)

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: 92)
                }
            }

            RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(height: 156)

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: 92)
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                .fill(SharpitElevatedColor.sheet)
                .sharpitShadow(.panel)
        )
        .environment(\.sharpitElevation, .sheet)
        .redacted(reason: .placeholder)
    }
}

struct CollapsedActivityBottomBar: View {
    let detail: V1ActivityDetail
    let tone: Color
    let onExpand: () -> Void

    var subtitleText: String {
        var parts: [String] = [detail.type.label]
        if let dist = detail.distanceM, dist > 0 {
            parts.append(dist >= 1000 ? String(format: String(localized: "%.1f km"), dist / 1000) : "\(Int(dist.rounded())) m")
        }
        if let elev = detail.elevationM, elev > 0 {
            parts.append("\(Int(elev.rounded())) m D+")
        }
        if let dur = detail.duration, dur > 0 {
            parts.append(ActivityFormat.duration(dur))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(SharpitColor.mutedForeground.opacity(0.35))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            HStack(spacing: 12) {
                Image(sharpitSymbol: detail.type.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone)
                    .frame(width: 38, height: 38)
                    .background(tone.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.title ?? detail.type.label)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text("Détails")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(SharpitColor.secondary.opacity(0.7), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            SharpitElevatedColor.sheet
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous))
                .sharpitShadow(.panel)
                .ignoresSafeArea(edges: .bottom)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onExpand()
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -10 {
                        onExpand()
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tiroir réduit. \(detail.title ?? detail.type.label). Appuyer pour afficher les détails.")
        .accessibilityAction {
            onExpand()
        }
    }
}

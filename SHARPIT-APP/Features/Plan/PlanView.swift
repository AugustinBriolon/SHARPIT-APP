import Observation
import SwiftUI

struct PlanView: View {
    let client: any PlannedSessionServing
    let linker: any PlannedSessionLinking
    let watchPusher: any PlannedSessionWatchPushing
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    @Environment(\.openURL) private var openURL
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var store: PlanStore
    @State private var selectedSession: V1PlannedSessionItem?
    @State private var showingCalendar = false
    @State private var showingMacroPlan = false
    @State private var showingGenerator = false
    @State private var showingAdapter = false

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
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
        _store = State(
            initialValue: PlanStore(
                client: client,
                activityClient: activityClient,
                tokenProvider: tokenProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed above the pager: neither moves when the week does, so neither can
                // fight the pages' own gestures.
                VStack(spacing: SharpitSpacing.xs) {
                    PlanWeekHeader(store: store) { showingCalendar = true }
                        .padding(.horizontal, SharpitSpacing.pageInset)
                    PlanWeekStrip(store: store)
                }

                PlanWeekPager(
                    store: store,
                    activityClient: activityClient,
                    tokenProvider: tokenProvider,
                    onSelect: { selectedSession = $0 }
                )
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                // Opposite the actions menu, so the two glass controls frame the title.
                if !store.isCurrentWeek {
                    ToolbarItem(placement: .topBarLeading) {
                        SharpitTodayButton { store.goToToday() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PlanActionsMenu(
                        onOpenMacroPlan: { showingMacroPlan = true },
                        onOpenGenerator: { showingGenerator = true },
                        onOpenAdapter: { showingAdapter = true },
                        onDiscussWithCoach: {
                            router.discussWithCoach(
                                about: CoachDiscuss.describe(.planning(horizonDays: 7))
                            )
                        }
                    )
                }
            }
            .sheet(item: $selectedSession) { session in
                PlannedSessionDrawer(
                    preview: PlannedSessionPreview(session: session, isExpertReading: isExpertReading),
                    linking: SessionLinkContext(
                        referenceDate: session.date,
                        activities: activityClient,
                        linker: linker,
                        tokenProvider: tokenProvider,
                        onLinked: {
                            selectedSession = nil
                            toastCenter?.show(
                                "Séance liée avec succès",
                                symbol: "link",
                                tone: .success,
                                autoDismissAfter: 3.0
                            )
                            Task { await store.reload(around: session.date) }
                        }
                    ),
                    watchPush: SessionWatchPushContext(
                        pusher: watchPusher,
                        tokenProvider: tokenProvider,
                        onPushed: { _ in
                            Task { await store.reload(around: session.date) }
                        }
                    )
                ) { context in
                    router.discussWithCoach(about: context)
                }
            }
            .sheet(isPresented: $showingCalendar) {
                PlanCalendarSheet(store: store)
            }
            .sheet(isPresented: $showingMacroPlan) {
                MacroPlanSheet(tokenProvider: tokenProvider) {
                    Task { await store.loadAroundSelection() }
                }
            }
            .sheet(isPresented: $showingGenerator) {
                PlanGeneratorSheet(tokenProvider: tokenProvider) {
                    Task { await store.loadAroundSelection() }
                }
            }
            .sheet(isPresented: $showingAdapter) {
                PlanAdapterSheet(tokenProvider: tokenProvider) {
                    Task { await store.loadAroundSelection() }
                }
            }
            .task { await store.loadAroundSelection() }
            // Every way of changing week — swipe, the strip's "Aujourd'hui", the calendar —
            // ends in `selectedOffset`, so loading follows from that one change.
            .onChange(of: store.selectedOffset) { _, _ in
                Task { await store.loadAroundSelection() }
            }
        }
    }
}

/// The week's actions, gathered behind one control.
///
/// Native sheets for the three key planning operations (macro plan, fill week, adapt plan)
/// and direct bridge to discussion with the Coach.
private struct PlanActionsMenu: View {
    let onOpenMacroPlan: () -> Void
    let onOpenGenerator: () -> Void
    let onOpenAdapter: () -> Void
    let onDiscussWithCoach: () -> Void

    var body: some View {
        Menu {
            Button(action: onOpenMacroPlan) {
                Label("Consulter le plan macro", systemImage: "map")
            }
            Button(action: onOpenGenerator) {
                Label("Remplir ma semaine", systemImage: "calendar.badge.plus")
            }
            Button(action: onOpenAdapter) {
                Label("Ajuster le planning", systemImage: "slider.horizontal.3")
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
    let onSelect: (V1PlannedSessionItem) -> Void

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
                        onSelect: onSelect
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
    let onSelect: (V1PlannedSessionItem) -> Void

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
                onSelect: onSelect
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
    let onSelect: (V1PlannedSessionItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    if let focusSession = store.focusSession(from: entries) {
                        Button { onSelect(focusSession) } label: {
                            PlanFocusSession(
                                session: focusSession,
                                isToday: Calendar.current.isDateInToday(focusSession.date)
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
    let session: V1PlannedSessionItem
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "À faire aujourd'hui" : "Prochaine séance")
                    .font(SharpitTypography.eyebrow)
                    .tracking(SharpitTypography.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                if session.garminWorkoutId != nil {
                    Image(systemName: "applewatch.side.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.primary)
                        .accessibilityLabel("Sur la montre Garmin")
                }
                Image(systemName: session.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            Text(session.title ?? session.displayType)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
            HStack(spacing: SharpitSpacing.md) {
                PlanFocusMetric(label: "Sport", value: session.displayType)
                if let duration = session.durationMin {
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
    let onSelect: (V1PlannedSessionItem) -> Void

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
    let onSelect: (V1PlannedSessionItem) -> Void

    var body: some View {
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
            Button { onSelect(session) } label: {
                PlanSessionCard(session: session, state: .planned)
            }
            .buttonStyle(.sharpitPressable)
        case .missed(let session):
            Button { onSelect(session) } label: {
                PlanSessionCard(session: session, state: .missed)
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

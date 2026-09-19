import Observation
import SwiftUI

@MainActor
@Observable
final class PlanStore {
    enum Phase {
        case loading
        case loaded([PlanEntry])
        case error(String)
        case unauthorized
    }

    var phase: Phase = .loading
    var weekStart: Date

    private let client: any PlannedSessionServing
    private let activityClient: any ActivityServing
    private let tokenProvider: () async throws -> String
    private let calendar: Calendar

    init(
        client: any PlannedSessionServing,
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Three weeks of days, so the strip can be scrolled into the past and the future
    /// instead of paged by a pair of chevrons.
    var stripDays: [Date] {
        guard let start = calendar.date(byAdding: .day, value: -7, to: weekStart) else {
            return weekDays
        }
        return (0..<21).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func isInVisibleWeek(_ day: Date) -> Bool {
        // Half-open on purpose: `endOfDay` of the last day is midnight on the next one,
        // which would let the following Monday count as an eighth day of the week.
        let start = calendar.startOfDay(for: weekStart)
        guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
        return day >= start && day < nextWeek
    }

    func showWeek(containing day: Date) {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start,
              !calendar.isDate(start, inSameDayAs: weekStart)
        else { return }
        weekStart = start
        Task { await load() }
    }

    func entries(on day: Date, from entries: [PlanEntry]) -> [PlanEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Next actionable session in the visible week: today or later, and still to be done.
    /// Never highlights the past, and never a session already absorbed by an activity.
    func focusSession(from entries: [PlanEntry], now: Date = Date()) -> V1PlannedSessionItem? {
        let startOfToday = calendar.startOfDay(for: now)
        return entries
            .compactMap { entry -> V1PlannedSessionItem? in
                guard case .planned(let session) = entry else { return nil }
                return session
            }
            .filter { $0.date >= startOfToday }
            .sorted { lhs, rhs in
                if calendar.isDateInToday(lhs.date) != calendar.isDateInToday(rhs.date) {
                    return calendar.isDateInToday(lhs.date)
                }
                return lhs.date < rhs.date
            }
            .first
    }

    func moveWeek(by value: Int) {
        guard let date = calendar.date(byAdding: .weekOfYear, value: value, to: weekStart) else { return }
        weekStart = date
        Task { await load() }
    }

    func resetToCurrentWeek() {
        weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        Task { await load() }
    }

    private func endOfDay(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
    }

    func load() async {
        do {
            guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return }
            let token = try await tokenProvider()
            async let planned = client.plannedSessions(from: weekStart, to: end, token: token)
            // The week's activities carry their own link back to the plan, so the merge
            // needs no extra endpoint. A failure here degrades to the prescription alone
            // rather than emptying the week.
            async let recorded = try? activityClient.activities(token: token)

            let entries = PlanEntryBuilder.entries(
                planned: try await planned,
                activities: (await recorded ?? []).filter { activity in
                    activity.date >= weekStart && activity.date <= endOfDay(end)
                },
                calendar: calendar
            )
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(entries)
            }
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}

struct PlanView: View {
    let client: any PlannedSessionServing
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @Environment(ShellRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var store: PlanStore
    @State private var selectedSession: V1PlannedSessionItem?

    init(
        client: any PlannedSessionServing,
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
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
            Group {
                switch store.phase {
                case .loading: PlanLoadingView()
                case .loaded(let entries):
                    PlanWeekContent(
                        store: store,
                        entries: entries,
                        activityClient: activityClient,
                        tokenProvider: tokenProvider
                    ) { selectedSession = $0 }
                case .error(let message):
                    ContentUnavailableView {
                        Label("Plan indisponible", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") { Task { await store.load() } }
                    }
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour retrouver ton plan.")
                    }
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PlanActionsMenu(
                        onOpenWeb: { path in openURL(APIConfiguration.baseURL.appending(path: path)) },
                        onDiscussWithCoach: {
                            router.discussWithCoach(
                                about: CoachDiscuss.describe(.planning(horizonDays: 7))
                            )
                        }
                    )
                }
            }
            .sheet(item: $selectedSession) { session in
                PlannedSessionDrawer(session: session) { context in
                    router.discussWithCoach(about: context)
                }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
        }
    }
}

/// The week's actions, gathered behind one control.
///
/// The three planning actions are web surfaces the app does not have yet, so they open
/// the web rather than pretending to exist here — the paths mirror the web's own routes.
/// "Discuter avec le coach" stays native: it hands the week to the Coach tab as context.
private struct PlanActionsMenu: View {
    let onOpenWeb: (String) -> Void
    let onDiscussWithCoach: () -> Void

    var body: some View {
        Menu {
            Button {
                onOpenWeb("/plan")
            } label: {
                Label("Consulter le plan macro", systemImage: "map")
            }
            Button {
                onOpenWeb("/plan/semaine")
            } label: {
                Label("Remplir ma semaine", systemImage: "square.and.pencil")
            }
            Button {
                onOpenWeb("/plan/adaptation")
            } label: {
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

private struct PlanWeekContent: View {
    let store: PlanStore
    let entries: [PlanEntry]
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String
    let onSelect: (V1PlannedSessionItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                PlanWeekHeader(store: store)
                PlanWeekStrip(store: store)
                if let focusSession = store.focusSession(from: entries) {
                    Button { onSelect(focusSession) } label: {
                        PlanFocusSession(
                            session: focusSession,
                            isToday: Calendar.current.isDateInToday(focusSession.date)
                        )
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(store.weekDays, id: \.self) { day in
                        PlanDayRow(
                            day: day,
                            entries: store.entries(on: day, from: entries),
                            activityClient: activityClient,
                            tokenProvider: tokenProvider,
                            onSelect: onSelect
                        )
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
    }
}

private struct PlanWeekHeader: View {
    let store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            Text(weekRange)
                .font(SharpitTypography.verdict)
                .tracking(SharpitTypography.verdictTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text("Ton rythme des prochains jours")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Button("Revenir à cette semaine") {
                store.resetToCurrentWeek()
            }
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.primary)
            .opacity(isCurrentWeek ? 0 : 1)
            .disabled(isCurrentWeek)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(
            store.weekStart,
            equalTo: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now,
            toGranularity: .weekOfYear
        )
    }

    private var weekRange: String {
        guard let end = Calendar.current.date(byAdding: .day, value: 6, to: store.weekStart) else {
            return store.weekStart.sharpitFormatted(.dateTime.day().month(.wide))
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = SharpitLocale.french
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: store.weekStart, to: end)
            .replacingOccurrences(of: " 2026", with: "")
    }
}

/// The week, scrolled rather than paged.
///
/// Two chevron buttons used to move the week. A horizontal strip says the same thing with
/// the gesture the content already invites, and shows the neighbouring weeks instead of
/// hiding them behind a control.
private struct PlanWeekStrip: View {
    let store: PlanStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SharpitSpacing.xs) {
                    ForEach(store.stripDays, id: \.self) { day in
                        PlanStripDay(day: day, isSelected: store.isInVisibleWeek(day))
                            .id(day)
                            .onTapGesture { store.showWeek(containing: day) }
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
            }
            .scrollClipDisabled()
            .padding(.vertical, SharpitSpacing.sm)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SharpitColor.analysisBorder)
                    .frame(height: 1)
            }
            .onAppear { proxy.scrollTo(store.weekStart, anchor: .leading) }
            .onChange(of: store.weekStart) { _, start in
                withAnimation(SharpitMotion.reveal) { proxy.scrollTo(start, anchor: .leading) }
            }
        }
        // The strip spans the screen; the page inset lives on its content instead.
        .padding(.horizontal, -SharpitSpacing.pageInset)
    }
}

private struct PlanStripDay: View {
    let day: Date
    let isSelected: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text(day.sharpitFormatted(.dateTime.weekday(.narrow)))
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(day.sharpitFormatted(.dateTime.day()))
                .font(SharpitTypography.instrument)
                .foregroundStyle(
                    isToday ? SharpitColor.inkSurfaceForeground : SharpitColor.foreground
                )
                .frame(width: 34, height: 34)
                .background(isToday ? SharpitColor.inkSurface : Color.clear, in: Circle())
        }
        .opacity(isSelected ? 1 : 0.4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
            .buttonStyle(.plain)
        case .planned(let session):
            Button { onSelect(session) } label: {
                PlanSessionCard(session: session, state: .planned)
            }
            .buttonStyle(.plain)
        case .missed(let session):
            Button { onSelect(session) } label: {
                PlanSessionCard(session: session, state: .missed)
            }
            .buttonStyle(.plain)
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
                .foregroundStyle(SharpitSportTone.accent(for: entry.activity.type))
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
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer(minLength: 0)

            if let score = entry.complianceScore {
                PlanComplianceMark(score: score)
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

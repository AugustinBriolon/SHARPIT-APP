import Observation
import SwiftUI

@MainActor
@Observable
final class PlanStore {
    enum Phase {
        case loading
        case loaded([V1PlannedSessionItem])
        case error(String)
        case unauthorized
    }

    var phase: Phase = .loading
    var weekStart: Date

    private let client: any PlannedSessionServing
    private let tokenProvider: () async throws -> String
    private let calendar: Calendar

    init(client: any PlannedSessionServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
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

    func sessions(on day: Date, from sessions: [V1PlannedSessionItem]) -> [V1PlannedSessionItem] {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Next actionable session in the visible week: today or later. Never highlights past sessions.
    func focusSession(from sessions: [V1PlannedSessionItem], now: Date = Date()) -> V1PlannedSessionItem? {
        let startOfToday = calendar.startOfDay(for: now)
        return sessions
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

    func load() async {
        do {
            guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return }
            let token = try await tokenProvider()
            let sessions = try await client.plannedSessions(from: weekStart, to: end, token: token)
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(sessions)
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
    let tokenProvider: () async throws -> String

    @Environment(ShellRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var store: PlanStore
    @State private var selectedSession: V1PlannedSessionItem?

    init(client: any PlannedSessionServing, tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
        _store = State(initialValue: PlanStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .loading: PlanLoadingView()
                case .loaded(let sessions):
                    PlanWeekContent(store: store, sessions: sessions) { selectedSession = $0 }
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
    let sessions: [V1PlannedSessionItem]
    let onSelect: (V1PlannedSessionItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                PlanWeekHeader(store: store)
                PlanWeekStrip(store: store)
                if let focusSession = store.focusSession(from: sessions) {
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
                            sessions: store.sessions(on: day, from: sessions),
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
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(weekRange)
                        .font(SharpitTypography.verdict)
                        .tracking(SharpitTypography.verdictTracking)
                    Text("Ton rythme des prochains jours")
                        .font(.subheadline)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer()
                HStack(spacing: 4) {
                    weekButton(symbol: "chevron.left", label: "Semaine précédente") {
                        store.moveWeek(by: -1)
                    }
                    weekButton(symbol: "chevron.right", label: "Semaine suivante") {
                        store.moveWeek(by: 1)
                    }
                }
            }
            Button("Revenir à cette semaine") {
                store.resetToCurrentWeek()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(SharpitColor.primary)
            .opacity(isCurrentWeek ? 0 : 1)
            .disabled(isCurrentWeek)
        }
    }

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(store.weekStart, equalTo: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now, toGranularity: .weekOfYear)
    }

    private var weekRange: String {
        guard let end = Calendar.current.date(byAdding: .day, value: 6, to: store.weekStart) else {
            return store.weekStart.formatted(.dateTime.day().month(.wide))
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: store.weekStart, to: end)
            .replacingOccurrences(of: " 2026", with: "")
    }

    private func weekButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PlanWeekStrip: View {
    let store: PlanStore

    var body: some View {
        HStack(spacing: 5) {
            ForEach(store.weekDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(day.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isToday ? SharpitColor.inkSurfaceForeground : SharpitColor.foreground)
                        .frame(width: 32, height: 32)
                        .background(isToday ? SharpitColor.inkSurface : Color.clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
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
                Image(systemName: session.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SharpitColor.primary)
            }
            Text(session.title ?? session.displayType)
                .font(.title2.weight(.bold))
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
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(SharpitColor.primary)
                .frame(width: 38, height: 4)
                .padding(.leading, SharpitSpacing.cardPadding)
                .padding(.top, 1)
        }
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
    let sessions: [V1PlannedSessionItem]
    let onSelect: (V1PlannedSessionItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(SharpitTypography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(day.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Calendar.current.isDateInToday(day) ? SharpitColor.primary : SharpitColor.foreground)
            }
            .frame(width: 42)
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(width: 1)
            if sessions.isEmpty {
                Text("Repos")
                    .font(.subheadline)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.top, 11)
            } else {
                VStack(spacing: SharpitSpacing.xxs) {
                    ForEach(sessions) { session in
                        Button { onSelect(session) } label: {
                            PlanSessionCard(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PlanSessionCard: View {
    let session: V1PlannedSessionItem

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: session.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title ?? session.displayType)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(session.displayType)
                    if let durationMin = session.durationMin { Text("\(durationMin) min") }
                    if let intensity = session.intensity { Text(intensity.capitalized) }
                }
                .font(.caption)
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

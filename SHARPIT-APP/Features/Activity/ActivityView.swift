import SwiftUI

struct ActivityView: View {
    let client: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var phase: ActivityPhase = .loading
    @State private var selectedActivity: V1ActivityListItem?
    /// An activity opened from outside the list — a widget — by its id alone.
    @State private var openedActivityId: String?
    @State private var filter = ActivityFilter()
    @State private var isLogging = false
    /// Created on the first open and kept, so Records shows at once when reopened.
    @State private var records: RecordsStore?
    @State private var isShowingRecords = false
    @State private var loadGate = LoadGate()
    /// More of the history waits on the server; the list reads it when its end comes into view.
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @Environment(ShellRouter.self) private var router: ShellRouter?

    var body: some View {
        NavigationStack {
            // One scroll view for every phase, owning the refresh control — as Corps does.
            // The list used to swap its own ScrollView in and out with the phase, and a refresh
            // that ended on a new view left the control with no list to spring back into.
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SharpitSpacing.pageInset)
                    .padding(.bottom, SharpitSpacing.lg)
            }
            .modifier(ScrollUnderGlass())
            .refreshable { await load(force: true) }
            .background(SharpitCanvasBackground())
            .navigationTitle("Activité")
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .searchable(text: $filter.query, placement: .navigationBarDrawer, prompt: String(localized: "Rechercher une séance"))
            .toolbar {
                if case .loaded(let activities) = phase {
                    ToolbarItem(placement: .primaryAction) {
                        ActivityFilterMenu(filter: $filter, sports: ActivityFilter.sports(in: activities))
                    }
                }
                if client is any ActivityMutating {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Saisir une séance", systemImage: "plus") { isLogging = true }
                    }
                }
            }
            .sheet(isPresented: $isLogging) {
                if let mutator = client as? any ActivityMutating {
                    ActivityFormSheet(mode: .create, draft: .new(), client: mutator, tokenProvider: tokenProvider) { id in
                        router?.noteActivitiesChanged()
                        filter = ActivityFilter()
                        selectedActivity = nil
                        openedActivityId = id
                    }
                }
            }
            .navigationDestination(item: $selectedActivity) { activity in
                ActivityDetailView(
                    activity: activity.id,
                    initialActivity: activity,
                    client: client,
                    tokenProvider: tokenProvider
                )
            }
            .navigationDestination(item: $openedActivityId) { id in
                ActivityDetailView(activity: id, client: client, tokenProvider: tokenProvider)
            }
            .navigationDestination(isPresented: $isShowingRecords) {
                if let records {
                    RecordsView(store: records, activityClient: client, tokenProvider: tokenProvider)
                }
            }
            .task {
                await load()
            }
            .onChange(of: router?.pendingActivityId, initial: true) { _, id in
                guard let id else { return }
                router?.pendingActivityId = nil
                selectedActivity = nil
                openedActivityId = id
            }
            .onChange(of: router?.activitiesRevision) { _, _ in
                Task { await load(force: true) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ActivityListLoading()
        case .loaded(let activities):
            let shown = filter.apply(to: activities)
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("Aucune séance", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(hasMore ? String(localized: "Rien dans ce qui est chargé. Le reste de l’historique arrive en cherchant plus loin.") : String(localized: "Rien ne correspond à ces filtres."))
                } actions: {
                    if hasMore {
                        Button("Chercher plus loin") { Task { await loadMore() } }
                    }
                    Button("Tout afficher") {
                        SharpitMotion.run(SharpitMotion.selection) { filter = ActivityFilter() }
                    }
                }
                .containerRelativeFrame(.vertical)
            } else {
                ActivityListContent(
                    activities: shown,
                    week: filter.isActive ? nil : ActivityHistory.week(activities),
                    hasMore: hasMore,
                    selectedActivity: $selectedActivity,
                    openRecords: filter.isActive ? nil : { openRecords() },
                    loadMore: { _ = Task { await loadMore() } }
                )
            }
        case .empty:
            ContentUnavailableView {
                Label("Pas encore d’activité", systemImage: "figure.run")
            } description: {
                Text("Tes séances synchronisées apparaîtront ici.")
            }
            .containerRelativeFrame(.vertical)
        case .failed(let message):
            ContentUnavailableView {
                Label("Activité indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") {
                    Task { await load() }
                }
            }
            .containerRelativeFrame(.vertical)
        case .unauthorized:
            ContentUnavailableView {
                Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Reconnecte-toi pour recharger tes activités.")
            }
            .containerRelativeFrame(.vertical)
        }
    }

    private func openRecords() {
        if records == nil {
            records = RecordsStore(tokenProvider: tokenProvider)
        }
        isShowingRecords = true
    }

    /// A page holds about two months of training: enough to fill the screen and the week.
    private static let pageSize = 60

    /// Reads the page before the oldest session shown and adds it under the list.
    @MainActor
    private func loadMore() async {
        guard hasMore, !isLoadingMore, case .loaded(let shown) = phase, let oldest = shown.last?.date else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let token = try? await tokenProvider(),
              let page = try? await client.activityPage(before: oldest, limit: Self.pageSize, token: token)
        else { return }
        let merged = ActivityHistory.merge(shown, with: page)
        // A page that adds nothing (a server ignoring the cursor) ends the history instead of
        // spinning at its foot.
        hasMore = page.count == Self.pageSize && merged.count > shown.count
        phase = .loaded(merged)
    }

    @MainActor
    private func load(force: Bool = false) async {
        await loadGate.run(force: force) {
            do {
                let token = try await tokenProvider()
                let page = try await client.activityPage(before: nil, limit: Self.pageSize, token: token)
                hasMore = page.count == Self.pageSize
                // A refresh keeps the older pages already read: only the newest page is asked again.
                let activities: [V1ActivityListItem]
                if case .loaded(let shown) = phase, force {
                    let oldestFresh = page.last?.date ?? .distantFuture
                    activities = ActivityHistory.merge(shown.filter { $0.date < oldestFresh }, with: page)
                } else {
                    activities = page
                }
                WidgetSnapshotPublisher.publish(activities)
                // Only a list that changed is swapped in. Replacing an identical list while the
                // pull-to-refresh gesture was ending left the scroll view stuck pulled down.
                if case .loaded(let shown) = phase {
                    if shown != activities {
                        // A list replacing a list is not animated: the refresh control is still
                        // settling, and an animated height change under it is what kept it pulled down.
                        phase = activities.isEmpty ? .empty : .loaded(activities)
                    }
                } else {
                    SharpitMotion.run(SharpitMotion.fade) {
                        phase = activities.isEmpty ? .empty : .loaded(activities)
                    }
                }
                // Widget « Dernière activité » only — the list stays as plain rows.
                let snapshotActivities = activities
                Task(priority: .utility) {
                    guard let previews = try? await client.routePreviews(token: token) else { return }
                    await WidgetSnapshotPublisher.publishLastActivity(from: snapshotActivities, routes: previews)
                }
                return true
            } catch is CancellationError {
                return false
            } catch let error as URLError where error.code == .cancelled {
                // The refresh task ended before its request: what is on screen stays.
                return false
            } catch let error as SharpitAPIError where error == .unauthorized {
                phase = .unauthorized
                return false
            } catch let error as ActivityClientError {
                phase = .failed(error.localizedDescription)
                return false
            } catch {
                phase = .failed(String(localized: "Impossible de charger l’historique : \(error.localizedDescription)"))
                return false
            }
        }
    }
}

private enum ActivityPhase {
    case loading
    case loaded([V1ActivityListItem])
    case empty
    case failed(String)
    case unauthorized
}

/// The history, month by month: the week at a glance first, then each month as one card of rows
/// with what it adds up to. Months are laid out lazily, so years of history cost a screen's worth.
private struct ActivityListContent: View {
    let activities: [V1ActivityListItem]
    let week: ActivityWeekSummary?
    let hasMore: Bool
    @Binding var selectedActivity: V1ActivityListItem?
    var openRecords: (() -> Void)?
    let loadMore: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if let week {
                ActivityWeekCard(week: week)
            }
            if let openRecords {
                Button(action: openRecords) {
                    RecordsEntryTile()
                }
                .buttonStyle(.sharpitPressable)
            }

            ForEach(ActivityHistory.months(activities)) { month in
                ActivityMonthSection(month: month, selectedActivity: $selectedActivity)
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SharpitSpacing.md)
                    // Reaching the end reads the next page.
                    .onAppear(perform: loadMore)
                    .accessibilityLabel("Chargement de séances plus anciennes")
            }
        }
        .padding(.top, SharpitSpacing.xs)
    }
}

/// Activité's one ink card: the week so far — sessions, time, distance, and its days lit.
private struct ActivityWeekCard: View {
    let week: ActivityWeekSummary

    private static let days = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            Text("Cette semaine")
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(SharpitColor.foreground)

            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.lg) {
                figure("\(week.count)", unit: week.count == 1 ? String(localized: "séance") : String(localized: "séances"))
                figure(week.durationSeconds > 0 ? ActivityHistory.hours(week.durationSeconds) : String(localized: "0 min"), unit: nil)
                if week.distanceM >= 1_000 {
                    figure(String(format: "%.0f", week.distanceM / 1_000), unit: "km")
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(Self.days[index])
                            .font(SharpitTypography.meta)
                            .foregroundStyle(index == week.todayIndex ? SharpitColor.foreground : SharpitColor.mutedForeground)
                        Circle()
                            .fill(week.activeDays[index] ? SharpitColor.highlight : SharpitColor.foreground.opacity(0.12))
                            .frame(width: 12, height: 12)
                            .overlay {
                                if index == week.todayIndex, !week.activeDays[index] {
                                    Circle().strokeBorder(SharpitColor.foreground.opacity(0.6), lineWidth: 1.5)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(week.activeDays.filter { $0 }.count) jours actifs cette semaine")
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .sharpitSurface(.ink)
    }

    private func figure(_ value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(SharpitTypography.gaugeScore)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .lineLimit(1)
    }
}

/// A month: its name and what it adds up to, then its sessions as rows on one card.
private struct ActivityMonthSection: View {
    let month: ActivityMonth
    @Binding var selectedActivity: V1ActivityListItem?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Text(month.summary)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
            }
            .padding(.horizontal, SharpitSpacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(month.activities.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 {
                        Divider().padding(.leading, 104)
                    }
                    Button {
                        selectedActivity = activity
                    } label: {
                        ActivityRow(activity: activity)
                    }
                    .buttonStyle(.sharpitPressable)
                }
            }
            .padding(.vertical, SharpitSpacing.xxs)
            .sharpitSurface(.panel)
        }
    }
}

/// The way into Records from the history: what the sessions add up to, one tap away.
private struct RecordsEntryTile: View {
    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            SharpitIconTile(symbol: "trophy")
            VStack(alignment: .leading, spacing: 2) {
                Text("Records")
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Tes meilleures performances par sport")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .contentShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvrir les records")
    }
}

/// One session in its month: the day, the sport's tile, the title and what it measured.
private struct ActivityRow: View {
    let activity: V1ActivityListItem

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(spacing: 0) {
                Text(activity.date.sharpitFormatted(.dateTime.day()))
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .monospacedDigit()
                Text(activity.date.sharpitFormatted(.dateTime.weekday(.abbreviated)))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .textCase(.lowercase)
            }
            .frame(width: 36)

            SharpitSportBadge(type: activity.type, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title ?? activity.type.label)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                Text([
                    activity.type.label,
                    activity.duration.map(ActivityFormat.duration),
                    ActivityFormat.primaryMetric(activity),
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.vertical, SharpitSpacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvrir le détail")
    }
}

private struct ActivityListLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(width: 210, height: 28)
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(width: 280, height: 18)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(height: 78)
            }
        }
        .redacted(reason: .placeholder)
        .padding(.top, SharpitSpacing.md)
        .accessibilityLabel("Chargement de l’historique")
    }
}

enum ActivityFormat {
    static func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Aujourd’hui") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Hier") }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    static func duration(_ seconds: Double) -> String {
        // A corrupt or computed figure (∞, NaN, beyond Int) reads as missing rather than trapping.
        guard let minutes = Int(exactly: (seconds / 60).rounded(.towardZero)), minutes >= 0 else { return "—" }
        return minutes >= 60 ? String(localized: "\(minutes / 60) h \(minutes % 60) min") : "\(minutes) min"
    }

    static func pace(_ seconds: Double) -> String {
        "\(paceClock(seconds))/km"
    }

    /// « 27,4 » — a ride's average speed in km/h, without its unit.
    static func speedKmh(distanceM: Double, duration: Double) -> String {
        let kmh = distanceM / duration * 3.6
        guard duration > 0, kmh >= 0, Int(exactly: kmh.rounded()) != nil else { return "—" }
        return String(format: "%.1f", kmh).replacingOccurrences(of: ".", with: ",")
    }

    /// « 1'46" » — a pace without its unit, for a readout that sets the unit apart (/km, /100 m).
    static func paceClock(_ seconds: Double) -> String {
        guard let rounded = Int(exactly: seconds.rounded()), rounded >= 0 else { return "—" }
        return "\(rounded / 60)'\(String(format: "%02d", rounded % 60))\""
    }

    /// Session load, in the words of the reading it is shown in (ADR 0006).
    ///
    /// Visible in both readings: the magnitude is not the barrier, the acronym is — so the
    /// essential reading keeps the number and calls it « charge », exactly as the web's
    /// `formatTrainingLoad` does.
    static func trainingLoad(_ load: Double, isExpertReading: Bool) -> String {
        let rounded = Int(exactly: load.rounded()) ?? 0
        return isExpertReading ? "\(rounded) TSS" : "charge \(rounded)"
    }

    static func primaryMetric(_ activity: V1ActivityListItem) -> String? {
        guard let distanceM = activity.distanceM, distanceM > 0 else { return nil }
        return distanceM >= 10_000
            ? String(format: String(localized: "%.1f km"), distanceM / 1_000).replacingOccurrences(of: ".", with: ",")
            : "\(Int(distanceM.rounded() / 10) * 10) m"
    }
}

/// The history's filters, in the bar: a sport the athlete did, a period. The glyph fills while
/// one narrows the list, so a shortened history is never mistaken for the whole one.
private struct ActivityFilterMenu: View {
    @Binding var filter: ActivityFilter
    let sports: [V1ActivityType]

    var body: some View {
        Menu {
            Picker("Sport", selection: $filter.sport.animation(SharpitMotion.selection)) {
                Text("Tous les sports").tag(V1ActivityType?.none)
                ForEach(sports, id: \.self) { sport in
                    Label { Text(sport.label) } icon: { Image(sharpitSymbol: sport.symbolName) }.tag(V1ActivityType?.some(sport))
                }
            }
            .pickerStyle(.menu)
            Picker("Période", selection: $filter.period.animation(SharpitMotion.selection)) {
                ForEach(ActivityFilter.Period.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.menu)
            if filter.narrows {
                Divider()
                Button("Réinitialiser les filtres", systemImage: "arrow.counterclockwise") {
                    SharpitMotion.run(SharpitMotion.selection) {
                        filter.sport = nil
                        filter.period = .all
                    }
                }
            }
        } label: {
            Label(
                String(localized: "Filtrer"),
                systemImage: filter.narrows
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue(filter.narrows ? String(localized: "Filtres actifs") : String(localized: "Aucun filtre"))
    }
}

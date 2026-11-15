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
    @State private var isSearching = false
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
            .cliniqueSheet(wash: .neutral, height: 240)
            .navigationTitle("Activité")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .modifier(ActivitySearch(query: $filter.query, isPresented: $isSearching))
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                SharpitBarTitle(String(localized: "Activité"))
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rechercher", systemImage: "magnifyingglass") { isSearching = true }
                }
                if client is any ActivityMutating {
                    SharpitBarGap()
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Saisir une séance", systemImage: "plus") { isLogging = true }
                    }
                }
            }
            .tint(SharpitColor.foreground)
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
                if records == nil { records = RecordsStore(tokenProvider: tokenProvider) }
                async let history: Void = load()
                async let bests: Void? = records?.load()
                _ = await (history, bests)
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
            ActivityFilterChips(filter: $filter, sports: ActivityFilter.sports(in: activities))
                .padding(.horizontal, -SharpitSpacing.pageInset)
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
                .padding(.top, 80)
            } else {
                ActivityListContent(
                    activities: shown,
                    records: filter.isActive ? [] : RecordsReadout.highlights(records?.records),
                    onOpenRecords: openRecords,
                    hasMore: hasMore,
                    selectedActivity: $selectedActivity,
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
                return true
            } catch is CancellationError {
                return false
            } catch let error as URLError where error.code == .cancelled {
                // The refresh task ended before its request: what is on screen stays.
                return false
            } catch let error as SharpitAPIError where error == .unauthorized {
                phase = .unauthorized
                return false
            } catch {
                // A history already shown stays: the toast says the refresh failed.
                if case .loaded = phase {
                    SharpitWriteFailures.shared.reportStaleRead(SharpitErrorGuidance.message(for: error, subject: String(localized: "L’historique")))
                    return false
                }
                if let error = error as? ActivityClientError {
                    phase = .failed(error.localizedDescription)
                } else {
                    phase = .failed(String(localized: "Impossible de charger l’historique : \(error.localizedDescription)"))
                }
                return false
            }
        }
    }
}

/// The search field, only once asked for: the bar's glass button opens it, as on the mock-up.
private struct ActivitySearch: ViewModifier {
    @Binding var query: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if isPresented || !query.isEmpty {
            content.searchable(
                text: $query, isPresented: $isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Rechercher une séance")
            )
        } else {
            content
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

/// The history, week by week: the athlete's records first, then each week's sessions as rows
/// under what it adds up to. Weeks are laid out lazily, so years of history cost a screen's worth.
private struct ActivityListContent: View {
    let activities: [V1ActivityListItem]
    let records: [RecordsReadout.Highlight]
    let onOpenRecords: () -> Void
    let hasMore: Bool
    @Binding var selectedActivity: V1ActivityListItem?
    let loadMore: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            if !records.isEmpty {
                Button(action: onOpenRecords) {
                    ActivityRecordsStrip(records: records).contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Ouvrir les records")
                .padding(.horizontal, -SharpitSpacing.pageInset)
            }

            ForEach(ActivityHistory.weeks(activities)) { week in
                ActivityWeekSection(week: week, selectedActivity: $selectedActivity)
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
        .padding(.top, 14)
    }
}

/// The sports the athlete did, as chips: « Tout » or one sport, the chosen one in ink. The
/// period and the duration wait behind the last chip.
private struct ActivityFilterChips: View {
    @Binding var filter: ActivityFilter
    let sports: [V1ActivityType]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "Tout"), isOn: filter.sport == nil) { filter.sport = nil }
                ForEach(sports, id: \.self) { sport in
                    chip(sport.label, isOn: filter.sport == sport) { filter.sport = sport }
                }
                ActivityFilterMenu(filter: $filter)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
        }
        .padding(.top, SharpitSpacing.xs)
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SharpitMotion.run(SharpitMotion.selection, action)
        } label: {
            Text(title)
                .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isOn ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isOn ? SharpitColor.primary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : SharpitColor.outline, lineWidth: 1))
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Up to three records between two hairlines: what it is, the mark, since when.
private struct ActivityRecordsStrip: View {
    let records: [RecordsReadout.Highlight]

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Rectangle().fill(SharpitColor.divider).frame(width: 1).accessibilityHidden(true)
                    }
                    VStack(spacing: 4) {
                        Text(record.caption)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(SharpitColor.slate)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(record.value)
                            .font(SharpitTypography.system(size: 18, weight: .semibold, relativeTo: .body, digits: true))
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(record.note)
                            .font(SharpitTypography.system(size: 13, weight: record.isRecent ? .semibold : .regular, relativeTo: .caption))
                            .foregroundStyle(record.isRecent ? SharpitColor.statusGoodForeground : SharpitColor.slate)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, SharpitSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)
            CliniqueDivider()
        }
    }
}

/// A week: its name and what it adds up to, then its sessions as rows split by hairlines.
private struct ActivityWeekSection: View {
    let week: ActivityWeek
    @Binding var selectedActivity: V1ActivityListItem?

    private var weekTitle: some View {
        Text(week.title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
    }

    private var weekSummary: some View {
        Text(week.summary)
            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
            .foregroundStyle(SharpitColor.slate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // On one line while both fit whole; the summary under the title otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    weekTitle
                    Spacer(minLength: SharpitSpacing.xs)
                    weekSummary
                }
                VStack(alignment: .leading, spacing: 2) {
                    weekTitle
                    weekSummary
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(week.activities.enumerated()), id: \.element.id) { index, activity in
                if index > 0 { CliniqueDivider() }
                Button {
                    selectedActivity = activity
                } label: {
                    ActivityRow(activity: activity)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }
}

/// One session in its week: the sport's tile, the title over the day and what it measured, and
/// how it went against the plan as a pill.
private struct ActivityRow: View {
    let activity: V1ActivityListItem
    @Environment(\.isExpertReading) private var isExpertReading

    var body: some View {
        let standing = ActivityRowReadout.standing(activity)
        HStack(spacing: 12) {
            CliniqueSportTile(symbol: activity.type.symbolName, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title.named ?? activity.type.label)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(ActivityRowReadout.line(activity, isExpertReading: isExpertReading))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: SharpitSpacing.xs)
            CliniqueStatusPill(standing.word, status: standing.status)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvrir le détail")
    }
}

/// How a session reads on its row.
enum ActivityRowReadout {
    /// « Jeu. 13 · 12,4 km · 58 min · charge 72 ».
    static func line(_ activity: V1ActivityListItem, isExpertReading: Bool) -> String {
        [
            activity.date.sharpitFormatted(.dateTime.weekday(.abbreviated).day()).capitalizedFirst,
            ActivityFormat.primaryMetric(activity),
            activity.duration.map(ActivityFormat.duration),
            activity.load.flatMap { $0 > 0 ? ActivityFormat.trainingLoad($0, isExpertReading: isExpertReading) : nil },
        ].compactMap { $0 }.joinedAsFacts()
    }

    /// Against the plan: the server's verdict, « À lire » until it lands, « Libre » off plan.
    static func standing(_ activity: V1ActivityListItem) -> (word: String, status: CliniqueStatus) {
        guard let planned = activity.plannedSession else { return (String(localized: "Libre"), .unknown) }
        guard let verdict = planned.analysis?.verdict.flatMap(SessionVerdict.init(rawValue:)) else {
            return (String(localized: "Prévue"), .unknown)
        }
        return (verdict.label, ActivitySheetReadout.status(verdict))
    }
}

private struct ActivityListLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.tile)
                .frame(width: 210, height: 28)
            RoundedRectangle(cornerRadius: 8)
                .fill(SharpitColor.tile)
                .frame(width: 280, height: 18)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.tile)
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
        SharpitFigureFormat.duration(seconds: seconds)
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

/// The history's other filters, behind the last chip: a period, a duration. The chip fills
/// while one narrows the list, so a shortened history is never mistaken for the whole one.
private struct ActivityFilterMenu: View {
    @Binding var filter: ActivityFilter

    private var narrows: Bool { filter.period != .all || filter.effortTime != .any }

    var body: some View {
        Menu {
            Picker("Période", selection: $filter.period.animation(SharpitMotion.selection)) {
                ForEach(ActivityFilter.Period.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            Picker("Durée", selection: $filter.effortTime.animation(SharpitMotion.selection)) {
                ForEach(ActivityFilter.EffortTime.allCases) { effortTime in
                    Text(effortTime.label).tag(effortTime)
                }
            }
            if narrows {
                Divider()
                Button("Réinitialiser les filtres", systemImage: "arrow.counterclockwise") {
                    SharpitMotion.run(SharpitMotion.selection) {
                        filter.period = .all
                        filter.effortTime = .any
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(narrows ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(narrows ? SharpitColor.primary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(narrows ? .clear : SharpitColor.outline, lineWidth: 1))
        }
        .tint(SharpitColor.foreground)
        .accessibilityLabel("Période et durée")
        .accessibilityValue(narrows ? String(localized: "Filtres actifs") : String(localized: "Aucun filtre"))
    }
}

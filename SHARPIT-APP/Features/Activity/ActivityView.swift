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
    @Environment(ShellRouter.self) private var router: ShellRouter?
    /// Its completion brings older activities in, so the list reloads when it lands.
    @Environment(GarminHistoryImport.self) private var historyImport: GarminHistoryImport?

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
            .searchable(text: $filter.query, placement: .navigationBarDrawer, prompt: "Rechercher une séance")
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
            .onChange(of: historyImport?.completedAt) { _, _ in
                Task { await load(force: true) }
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
                    Text("Rien ne correspond à ces filtres.")
                } actions: {
                    Button("Tout afficher") {
                        SharpitMotion.run(SharpitMotion.selection) { filter = ActivityFilter() }
                    }
                }
                .containerRelativeFrame(.vertical)
            } else {
                ActivityListContent(
                    activities: shown,
                    isFiltered: filter.isActive,
                    selectedActivity: $selectedActivity,
                    openRecords: openRecords
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

    @MainActor
    private func load(force: Bool = false) async {
        do {
            let token = try await tokenProvider()
            let activities = try await client.activities(forceRefresh: force, token: token)
            WidgetSnapshotPublisher.publish(activities)
            // Only a list that changed is swapped in. Replacing an identical list while the
            // pull-to-refresh gesture was ending left the scroll view stuck pulled down.
            if case .loaded(let shown) = phase {
                if shown == activities { return }
                // A list replacing a list is not animated: the refresh control is still
                // settling, and an animated height change under it is what kept it pulled down.
                phase = activities.isEmpty ? .empty : .loaded(activities)
                return
            }
            SharpitMotion.run(SharpitMotion.fade) {
                phase = activities.isEmpty ? .empty : .loaded(activities)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            // The refresh task ended before its request: what is on screen stays.
            return
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch let error as ActivityClientError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed("Impossible de charger l’historique : \(error.localizedDescription)")
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

private struct ActivityListContent: View {
    let activities: [V1ActivityListItem]
    var isFiltered = false
    @Binding var selectedActivity: V1ActivityListItem?
    var openRecords: (() -> Void)?

    private var groupedActivities: [(String, [V1ActivityListItem])] {
        let groups = Dictionary(grouping: activities) {
            ActivityFormat.dayLabel(for: $0.date)
        }
        return groups.sorted { first, second in
            (first.value.first?.date ?? .distantPast) > (second.value.first?.date ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            if !isFiltered {
                ActivityIntro()
                if let openRecords {
                    Button(action: openRecords) {
                        RecordsEntryTile()
                    }
                    .buttonStyle(.sharpitPressable)
                }
            }

            ForEach(groupedActivities, id: \.0) { group in
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(group.0)
                        .font(SharpitTypography.eyebrow)
                        .tracking(SharpitTypography.eyebrowTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)

                    ForEach(group.1) { activity in
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
    }
}

/// The badge that used to sit here counted the rows the client had fetched — the
/// request asks for `limit=30`, so it read "30" on every full page regardless of what
/// the athlete had actually done. An invented metric, and the design law forbids those.
private struct ActivityIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            Text("Ce que tu as fait")
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
            Text("Les dernières séances, sans le bruit du plan.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, SharpitSpacing.xs)
    }
}

/// The way into Records from the history: what the sessions add up to, one tap away.
private struct RecordsEntryTile: View {
    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            SharpitRowIcon(symbol: "trophy", tone: SharpitColor.recordAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Records")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Tes meilleures performances par sport")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .padding(.vertical, SharpitSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .contentShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvrir les records")
    }
}

private struct ActivityRow: View {
    let activity: V1ActivityListItem

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tone.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: activity.type.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tone)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(activity.title ?? activity.type.label)
                        .font(.headline)
                        .lineLimit(1)
                    if activity.plannedSession != nil {
                        Text("PLAN")
                            .font(SharpitTypography.label)
                            .tracking(0.7)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(activity.type.label)
                    if let duration = activity.duration {
                        Text(ActivityFormat.duration(duration))
                    }
                    if let metric = ActivityFormat.primaryMetric(activity) {
                        Text(metric)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .padding(.vertical, SharpitSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                .fill(SharpitColor.analysisSurface)
        )
        .contentShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvrir le détail")
    }

    private var tone: Color { SharpitSportTone.label(for: activity.type) }
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
        if Calendar.current.isDateInToday(date) { return "Aujourd’hui" }
        if Calendar.current.isDateInYesterday(date) { return "Hier" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    static func pace(_ seconds: Double) -> String {
        "\(Int(seconds / 60))'\(String(format: "%02d", Int(seconds.rounded()) % 60))\"/km"
    }

    /// Session load, in the words of the reading it is shown in (ADR 0006).
    ///
    /// Visible in both readings: the magnitude is not the barrier, the acronym is — so the
    /// essential reading keeps the number and calls it « charge », exactly as the web's
    /// `formatTrainingLoad` does.
    static func trainingLoad(_ load: Double, isExpertReading: Bool) -> String {
        let rounded = Int(load.rounded())
        return isExpertReading ? "\(rounded) TSS" : "charge \(rounded)"
    }

    static func primaryMetric(_ activity: V1ActivityListItem) -> String? {
        guard let distanceM = activity.distanceM, distanceM > 0 else { return nil }
        return distanceM >= 10_000
            ? String(format: "%.1f km", distanceM / 1_000)
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
                    Label(sport.label, systemImage: sport.symbolName).tag(V1ActivityType?.some(sport))
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
                "Filtrer",
                systemImage: filter.narrows
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue(filter.narrows ? "Filtres actifs" : "Aucun filtre")
    }
}

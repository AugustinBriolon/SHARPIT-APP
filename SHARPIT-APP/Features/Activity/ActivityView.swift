import SwiftUI

struct ActivityView: View {
    let client: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var phase: ActivityPhase = .loading
    @State private var selectedActivity: V1ActivityListItem?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ActivityListLoading()
                case .loaded(let activities):
                    ActivityListContent(
                        activities: activities,
                        selectedActivity: $selectedActivity
                    )
                case .empty:
                    ContentUnavailableView {
                        Label("Pas encore d’activité", systemImage: "figure.run")
                    } description: {
                        Text("Tes séances synchronisées apparaîtront ici.")
                    }
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
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger tes activités.")
                    }
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Activité")
            .navigationBarTitleDisplayMode(.large)
            .modifier(LiquidNavChrome())
            .navigationDestination(item: $selectedActivity) { activity in
                ActivityDetailView(
                    activity: activity.id,
                    initialActivity: activity,
                    client: client,
                    tokenProvider: tokenProvider
                )
            }
            .refreshable {
                await load()
            }
            .task {
                await load()
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            let token = try await tokenProvider()
            let activities = try await client.activities(token: token)
            withAnimation(SharpitMotion.reveal) {
                phase = activities.isEmpty ? .empty : .loaded(activities)
            }
        } catch is CancellationError {
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
    @Binding var selectedActivity: V1ActivityListItem?
    @State private var appeared = false

    private var groupedActivities: [(String, [V1ActivityListItem])] {
        let groups = Dictionary(grouping: activities) {
            ActivityFormat.dayLabel(for: $0.date)
        }
        return groups.sorted { first, second in
            (first.value.first?.date ?? .distantPast) > (second.value.first?.date ?? .distantPast)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SharpitSpacing.section) {
                ActivityIntro()

                ForEach(Array(groupedActivities.enumerated()), id: \.element.0) { groupIndex, group in
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        Text(group.0)
                            .font(SharpitTypography.eyebrow)
                            .tracking(SharpitTypography.eyebrowTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        ForEach(Array(group.1.enumerated()), id: \.element.id) { index, activity in
                            Button {
                                selectedActivity = activity
                            } label: {
                                ActivityRow(activity: activity)
                            }
                            .buttonStyle(.sharpitPressable)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(
                                SharpitMotion.reveal.delay(
                                    SharpitMotion.staggerDelay(index: groupIndex + index)
                                ),
                                value: appeared
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .onAppear {
            guard !SharpitMotion.reduceMotion else {
                appeared = true
                return
            }
            SharpitMotion.run {
                appeared = true
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
        ScrollView {
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
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.md)
        }
        .modifier(ScrollUnderGlass())
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

    static func primaryMetric(_ activity: V1ActivityListItem) -> String? {
        guard let distanceM = activity.distanceM, distanceM > 0 else { return nil }
        return distanceM >= 10_000
            ? String(format: "%.1f km", distanceM / 1_000)
            : "\(Int(distanceM.rounded() / 10) * 10) m"
    }
}

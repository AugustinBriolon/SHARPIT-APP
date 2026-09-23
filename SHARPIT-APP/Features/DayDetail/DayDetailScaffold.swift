import SwiftUI

/// The frame every day drill-down shares: the day picker fixed on top, then the day's
/// content, or its loading, empty, failed or signed-out state. The content dims while
/// another day loads over it.
struct DayDetailScaffold<Payload: V1DayResource, Content: View>: View {
    let title: String
    let emptySymbol: String
    let unavailableTitle: String
    let store: DayResourceStore<Payload>
    @ViewBuilder let content: (Payload) -> Content

    var body: some View {
        VStack(spacing: 0) {
            DayDetailDatePicker(
                selectedDay: store.selectedDay,
                hasData: store.hasData(on:)
            ) { day in
                Task { await store.select(day) }
            }
            phaseView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(store.isSwitchingDay ? 0.45 : 1)
                .animation(SharpitMotion.fade, value: store.isSwitchingDay)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch store.phase {
        case .loading:
            ScrollView {
                DayDetailSkeleton()
                    .padding(.top, SharpitSpacing.md)
            }
        case .loaded(let payload):
            ScrollView {
                content(payload)
                    .padding(.top, SharpitSpacing.md)
            }
            .modifier(ScrollUnderGlass())
            .refreshable { await store.load() }
        case .empty(let empty):
            ContentUnavailableView(
                empty.title,
                systemImage: emptySymbol,
                description: empty.message.map(Text.init)
            )
        case .failed(let message):
            ContentUnavailableView {
                Label(unavailableTitle, systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .unauthorized:
            ContentUnavailableView("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }
}

/// The causal column's shape — hero, two tiles, a panel, a chart — before the day answers.
/// Sleep and Recovery both open this way, so one skeleton covers both (`docs/adr/0008`).
private struct DayDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            hero
            panel(height: 140)
            panel(height: 160)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                Text("78")
                    .font(SharpitTypography.heroScore)
                    .tracking(SharpitTypography.heroScoreTracking)
                Text("/100")
                    .font(SharpitTypography.meta)
            }
            HStack(spacing: SharpitSpacing.sm) {
                statTile
                statTile
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SharpitColor.mutedForeground)
    }

    private var statTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("REPÈRE")
                .font(SharpitTypography.label)
            Text("00 h 00")
                .font(SharpitTypography.instrument)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func panel(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: SharpitRadius.panel)
            .fill(SharpitColor.mutedForeground.opacity(0.12))
            .frame(height: height)
    }
}

import SwiftUI
import WidgetKit

/// « Dernière activité »: the session recorded last. Its map fills the face, the route on it,
/// and fades into the session's figures at the foot — distance, time, average pace. A session
/// without a route keeps the same face on a plain plate with its sport's glyph. A tap opens it.
struct LatestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestActivity", provider: SnapshotProvider()) { entry in
            LatestActivityView(entry: entry)
                .sharpitWidgetChrome()
        }
        .configurationDisplayName("Dernière activité")
        .description("Ta dernière séance, sur sa carte quand elle a un tracé.")
        .supportedFamilies([.systemMedium, .systemLarge])
        // The map runs to the widget's edge; the figures keep their own margin.
        .contentMarginsDisabled()
    }
}

struct LatestActivityView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// A tinted or clear Home Screen keeps a colour's alpha only: a map there is a grey slab with
    /// its route lost in it, and the fade to the sheet a white block. The route alone is drawn.
    private var isFullColor: Bool { renderingMode == .fullColor }

    private var map: WidgetSnapshotStore.LatestActivityMap { family == .systemLarge ? .large : .medium }

    var body: some View {
        if let activity = entry.latestActivity {
            ZStack(alignment: .bottom) {
                backdrop(activity)
                if isFullColor {
                    // The map dissolves into the sheet where the figures stand.
                    LinearGradient(
                        stops: [.init(color: SharpitColor.card.opacity(0), location: 0), .init(color: SharpitColor.card, location: 0.62)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: family == .systemLarge ? 150 : 96)
                }
                StatRow(stats: Array(activity.stats.prefix(3)))
                    .padding(.horizontal, 18)
                    .padding(.bottom, family == .systemLarge ? 20 : 14)
            }
            .clipShape(ContainerRelativeShape())
            .widgetURL(activity.link)
            .accessibilityElement(children: .combine)
            // The face names no day or sport: VoiceOver still says which session this is.
            .accessibilityLabel(Text("\(LatestActivityReadout.eyebrow(activity, now: entry.date)), \(activity.title)"))
            .accessibilityValue(Text(activity.stats.map { "\($0.label) \($0.value) \($0.unit)" }.joined(separator: ", ")))
        } else {
            WidgetFrame(String(localized: "Dernière activité"), symbol: "figure.run") {
                WidgetAwaitingData(text: String(localized: "Ouvre Activité pour voir ta dernière séance ici."))
            }
            .padding(16)
            .widgetURL(WidgetSnapshot.link("/activity"))
        }
    }

    /// The session's map; without one, its route alone on the plate; without a route, its sport.
    @ViewBuilder
    private func backdrop(_ activity: WidgetSnapshot.LatestActivity) -> some View {
        if isFullColor, activity.hasMap,
           let url = WidgetSnapshotStore.latestActivityMapURL(map, dark: colorScheme == .dark),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        } else {
            PlainBackdrop(route: activity.route, sport: activity.sport, routeShare: map.routeShare, showsPlate: isFullColor)
        }
    }
}

/// The figures at the foot, each under its name, shared out across the width.
private struct StatRow: View {
    let stats: [WidgetSnapshot.Stat]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.label.uppercased(with: AppLanguage.locale))
                        .font(SharpitTypography.meta)
                        .tracking(0.6)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    WidgetFigure(figure: stat.figure, large: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// No map: the route as one line on the sheet's plate, start hollow; no route either, the sport.
private struct PlainBackdrop: View {
    let route: [[Double]]?
    let sport: V1ActivityType
    let routeShare: Double
    var showsPlate = true

    var body: some View {
        GeometryReader { proxy in
            let band = CGSize(width: proxy.size.width, height: proxy.size.height * routeShare)
            let side = min(band.width, band.height) - 36
            let origin = CGPoint(x: (band.width - side) / 2, y: (band.height - side) / 2 + 6)
            let points = (route ?? []).filter { $0.count >= 2 }.map {
                CGPoint(x: origin.x + $0[0] * side, y: origin.y + $0[1] * side)
            }
            ZStack {
                if showsPlate { SharpitColor.foreground.opacity(0.05) }
                if let start = points.first, points.count >= 2 {
                    Path { path in path.addLines(points) }
                        .stroke(SharpitColor.destructive, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .widgetAccentable()
                    Circle()
                        .fill(showsPlate ? SharpitColor.card : .clear)
                        .overlay(Circle().stroke(SharpitColor.destructive, lineWidth: 2.5).widgetAccentable())
                        .frame(width: 10, height: 10)
                        .position(start)
                } else {
                    Image(sharpitSymbol: sport.symbolName)
                        .font(.system(size: side * 0.55, weight: .light))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.5))
                        .widgetAccentable()
                        .position(x: band.width / 2, y: band.height / 2 + 6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview(as: .systemLarge) {
    LatestActivityWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
    SnapshotEntry(date: .now, snapshot: {
        var snapshot = WidgetSnapshot.preview
        snapshot.latestActivity?.route = nil
        snapshot.latestActivity?.sport = .strength
        return snapshot
    }())
}

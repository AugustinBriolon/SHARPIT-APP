import SwiftUI
import WidgetKit

/// « Dernière activité »: the session recorded last — when, what, its figures — beside its
/// route when it has one, its sport's glyph when it has none. A tap opens the session.
struct LatestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestActivity", provider: SnapshotProvider()) { entry in
            LatestActivityView(entry: entry)
                .sharpitWidgetChrome()
        }
        .configurationDisplayName("Dernière activité")
        .description("Ta dernière séance, avec son tracé quand elle en a un.")
        .supportedFamilies([.systemMedium])
    }
}

struct LatestActivityView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let activity = entry.latestActivity {
            HStack(alignment: .center, spacing: 14) {
                WidgetFrame(title: LatestActivityReadout.eyebrow(activity, now: entry.date)) {
                    WidgetGlyph(symbol: activity.sport.symbolName, tint: SharpitColor.foreground)
                } content: {
                    WidgetTitle(text: activity.title)
                    Spacer(minLength: 6)
                    if let lead = activity.figures.first {
                        WidgetHero(value: lead.value, unit: lead.unit.isEmpty ? nil : lead.unit)
                    }
                    if activity.figures.count > 1 {
                        WidgetFigureRow(figures: Array(activity.figures.dropFirst().prefix(2)))
                            .padding(.top, WidgetMetrics.lineGap)
                    }
                }
                RoutePanel(route: activity.route, sport: activity.sport)
            }
            .widgetURL(activity.link)
            .accessibilityElement(children: .combine)
        } else {
            WidgetFrame(String(localized: "Dernière activité"), symbol: "figure.run") {
                WidgetAwaitingData(text: String(localized: "Ouvre Activité pour voir ta dernière séance ici."))
            }
            .widgetURL(WidgetSnapshot.link("/activity"))
        }
    }
}

/// The plate beside the figures: the route as one line, its start hollow and its end full; with
/// no route, the sport's glyph in the same plate, so the widget keeps its shape.
private struct RoutePanel: View {
    let route: [[Double]]?
    let sport: V1ActivityType

    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - Self.inset * 2
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            let points = (route ?? []).filter { $0.count >= 2 }.map {
                CGPoint(x: origin.x + $0[0] * side, y: origin.y + $0[1] * side)
            }
            ZStack {
                RoundedRectangle(cornerRadius: WidgetMetrics.panelRadius, style: .continuous)
                    .fill(SharpitColor.foreground.opacity(0.05))
                if let start = points.first, let end = points.last, points.count >= 2 {
                    Path { path in path.addLines(points) }
                        .stroke(SharpitColor.pillarRecovery, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .widgetAccentable()
                    Circle()
                        .fill(SharpitColor.card)
                        .overlay(Circle().stroke(SharpitColor.pillarRecovery, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .position(start)
                    Circle()
                        .fill(SharpitColor.foreground)
                        .frame(width: 9, height: 9)
                        .position(end)
                } else {
                    Image(sharpitSymbol: sport.symbolName)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.55))
                        .widgetAccentable()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview(as: .systemMedium) {
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

import SwiftUI
import WidgetKit

/// « Dernière activité »: last GPS session as figures — no map.
///
/// WidgetKit cannot host a live Map. A MapKit snapshot PNG in the App Group proved unreliable
/// (white block). The route still opens in-app; the home-screen face stays text + sport like
/// « Séance du jour ».
struct LastActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastActivity", provider: SnapshotProvider()) { entry in
            LastActivityView(entry: entry)
                .sharpitWidgetChrome()
        }
        .configurationDisplayName("Dernière activité")
        .description("Ta dernière séance GPS : distance, durée, allure.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct LastActivityView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var activity: WidgetSnapshot.LastActivity? {
        guard let activity = entry.lastActivity,
              !activity.id.isEmpty,
              activity.id != "a-last"
        else { return nil }
        // Gallery placeholder still shows the sample face.
        return activity
    }

    // MARK: Lock screen

    @ViewBuilder
    private var rectangular: some View {
        if let activity {
            VStack(alignment: .leading, spacing: 1) {
                Label {
                    Text(activity.sport.label)
                } icon: {
                    Image(sharpitSymbol: activity.sport.symbolName)
                }
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
                Text(activity.title).font(.headline).lineLimit(1)
                Text(statLine(activity))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(activity.link)
        } else {
            Label(entry.snapshot == nil ? "Ouvre SharpIt" : "Pas de tracé GPS", systemImage: "figure.run")
                .font(.headline)
                .widgetURL(entry.link("/activity"))
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let activity {
            Label {
                Text([activity.title, activity.distanceValue.isEmpty ? nil : "\(activity.distanceValue) \(activity.distanceUnit)"]
                    .compactMap { $0 }
                    .joined(separator: " · "))
            } icon: {
                Image(sharpitSymbol: activity.sport.symbolName)
            }
            .widgetURL(activity.link)
        } else {
            Label(entry.snapshot == nil ? "SharpIt" : "Pas de tracé", systemImage: "figure.run")
                .widgetURL(entry.link("/activity"))
        }
    }

    // MARK: Home screen

    @ViewBuilder
    private var small: some View {
        if let activity {
            let tone = SharpitColor.foreground
            WidgetFrame(title: WidgetDay.label(activity.dayId)) {
                WidgetGlyph(symbol: activity.sport.symbolName, tint: tone)
            } content: {
                WidgetEyebrow(text: activity.sport.label, tint: tone)
                WidgetTitle(text: activity.title)
                    .padding(.top, 2)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ForEach(figures(activity, limit: 2), id: \.label) { row in
                        WidgetFigure(figure: .init(value: row.value, unit: row.unit), large: true)
                    }
                }
                .padding(.top, 8)
            }
            .widgetURL(activity.link)
        } else if entry.snapshot == nil {
            WidgetAwaitingDay(eyebrow: "Dernière activité", symbol: "figure.run")
        } else {
            WidgetFrame(title: "Dernière activité") {
                WidgetGlyph(symbol: "figure.run")
            } content: {
                WidgetTitle(text: "Pas encore de tracé")
                WidgetCaption(text: "Ouvre Activité après une séance GPS.")
                    .padding(.top, 4)
            }
            .widgetURL(entry.link("/activity"))
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let activity {
            let tone = SharpitColor.foreground
            WidgetFrame(title: WidgetDay.label(activity.dayId)) {
                WidgetGlyph(symbol: activity.sport.symbolName, tint: tone)
            } content: {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetEyebrow(text: activity.sport.label, tint: tone)
                        WidgetTitle(text: activity.title)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            ForEach(figures(activity, limit: 3), id: \.label) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label)
                                        .font(SharpitTypography.label)
                                        .tracking(SharpitTypography.labelTracking)
                                        .textCase(.uppercase)
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                    WidgetFigure(figure: .init(value: row.value, unit: row.unit))
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .widgetURL(activity.link)
        } else if entry.snapshot == nil {
            WidgetAwaitingDay(eyebrow: "Dernière activité", symbol: "figure.run")
        } else {
            WidgetFrame(title: "Dernière activité") {
                WidgetGlyph(symbol: "figure.run")
            } content: {
                WidgetTitle(text: "Pas encore de tracé")
                WidgetCaption(text: "Ouvre Activité après une séance GPS.")
                    .padding(.top, 4)
            }
            .widgetURL(entry.link("/activity"))
        }
    }

    private func figures(_ activity: WidgetSnapshot.LastActivity, limit: Int) -> [LabeledFigure] {
        var rows: [LabeledFigure] = []
        if !activity.distanceValue.isEmpty {
            rows.append(.init(label: "Distance", value: activity.distanceValue, unit: activity.distanceUnit))
        }
        if !activity.durationValue.isEmpty {
            rows.append(.init(label: "Durée", value: activity.durationValue, unit: activity.durationUnit))
        }
        if !activity.paceValue.isEmpty {
            rows.append(.init(label: activity.paceLabel, value: activity.paceValue, unit: activity.paceUnit))
        }
        return Array(rows.prefix(limit))
    }

    private func statLine(_ activity: WidgetSnapshot.LastActivity) -> String {
        [
            activity.distanceValue.isEmpty ? nil : "\(activity.distanceValue) \(activity.distanceUnit)",
            activity.durationValue.isEmpty ? nil : activity.durationValue,
            activity.paceValue.isEmpty ? nil : "\(activity.paceValue)\(activity.paceUnit)",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct LabeledFigure: Hashable {
    var label: String
    var value: String
    var unit: String
}

#Preview("Dernière activité", as: .systemMedium) {
    LastActivityWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

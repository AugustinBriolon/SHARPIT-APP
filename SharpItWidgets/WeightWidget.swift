import SwiftUI
import WidgetKit

/// « Poids »: the latest weigh-in, its change over the server's window, and the way left to the
/// target. The change is coloured only against a target: towards it reads green, away from it
/// stays quiet — a scale never scolds.
struct WeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Weight", provider: SnapshotProvider()) { entry in
            Group {
                if entry.unlocksExtraWidgets {
                    WeightWidgetView(entry: entry)
                } else {
                    WidgetProLocked(title: "Poids", symbol: "scalemass")
                }
            }
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(entry.extraLink("/corps", feature: .health))
        }
        .configurationDisplayName("Poids")
        .description("Ton poids et l'écart à ton objectif.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct WeightWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.features.isOn(.health) {
            content
        } else {
            WidgetFeatureOff(feature: .health)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let weight = entry.weight {
                Label("\(SharpitFigureFormat.kilograms(weight.kilograms)) kg", systemImage: "scalemass")
            } else {
                Label("Poids", systemImage: "scalemass")
            }
        case .accessoryRectangular:
            if let weight = entry.weight {
                VStack(alignment: .leading, spacing: 1) {
                    Label("\(SharpitFigureFormat.kilograms(weight.kilograms)) kg", systemImage: "scalemass")
                        .font(.headline)
                        .widgetAccentable()
                    if let line = weight.targetLine ?? weight.changeLine {
                        Text(line).font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Aucune pesée", systemImage: "scalemass").font(.headline)
            }
        default:
            WeightSmall(weight: entry.weight)
        }
    }
}

struct WeightSmall: View {
    let weight: WidgetSnapshot.Weight?

    var body: some View {
        WidgetFrame("Poids", symbol: "scalemass") {
            if let weight {
                WidgetHero(value: SharpitFigureFormat.kilograms(weight.kilograms), unit: "kg")
                if let changeLine = weight.changeLine {
                    WidgetCaption(text: changeLine, tint: weight.movesTowardsTarget == true ? SharpitColor.primary : SharpitColor.mutedForeground)
                }
                if let targetLine = weight.targetLine {
                    WidgetCaption(text: targetLine, lines: 2)
                        .padding(.top, WidgetMetrics.lineGap)
                }
            } else {
                WidgetAwaitingData(text: "Aucune pesée pour l'instant.")
            }
        }
    }
}

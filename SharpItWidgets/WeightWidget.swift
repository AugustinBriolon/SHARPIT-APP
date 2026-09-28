import SwiftUI
import WidgetKit

/// « Poids »: the latest weigh-in, its change over the server's window, and the way left to the
/// target. The change is coloured only against a target: towards it reads green, away from it
/// stays quiet — a scale never scolds.
struct WeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Weight", provider: SnapshotProvider()) { entry in
            WeightWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/corps"))
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetEyebrow(text: "Poids")
                Spacer(minLength: 4)
                Image(systemName: "scalemass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if let weight {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(SharpitFigureFormat.kilograms(weight.kilograms))
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("kg")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                if let changeLine = weight.changeLine {
                    Text(changeLine)
                        .font(SharpitTypography.meta.monospacedDigit())
                        .foregroundStyle(weight.movesTowardsTarget == true ? SharpitColor.primary : SharpitColor.mutedForeground)
                        .padding(.top, 2)
                }
                if let targetLine = weight.targetLine {
                    Text(targetLine)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
            } else {
                Text("Aucune pesée pour l'instant.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

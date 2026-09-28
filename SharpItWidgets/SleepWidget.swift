import SwiftUI
import WidgetKit

/// « Sommeil »: last night's score on Résumé's dial, with what the gauge says under it.
struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Sleep", provider: SnapshotProvider()) { entry in
            SleepWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/today"))
        }
        .configurationDisplayName("Sommeil")
        .description("Le score de ta nuit dernière.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct SleepWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var sleep: WidgetSnapshot.Sleep? { entry.day?.sleep }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(sleep?.score ?? 0), in: 0...100) {
                Image(systemName: "moon.zzz")
            } currentValueLabel: {
                Text(sleep?.score.map(String.init) ?? "—").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Sommeil \(sleep?.score.map(String.init) ?? "—")", systemImage: "moon.zzz")
                    .font(.headline)
                    .widgetAccentable()
                if let caption = sleep?.caption {
                    Text(caption).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            SleepSmall(sleep: sleep, hasDay: entry.day != nil)
        }
    }
}

struct SleepSmall: View {
    let sleep: WidgetSnapshot.Sleep?
    let hasDay: Bool

    var body: some View {
        if let sleep, let score = sleep.score {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    WidgetEyebrow(text: "Nuit dernière")
                    Spacer(minLength: 4)
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer(minLength: 0)
                DialReadout(score: CGFloat(score), figure: "\(score)")
                Text(sleep.caption ?? "Score de sommeil")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetEyebrow(text: "Nuit dernière")
                Spacer(minLength: 0)
                Image(systemName: "moon.zzz")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
                Text(hasDay ? "Pas encore de nuit synchronisée." : "Ouvre SharpIt pour charger ta journée.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

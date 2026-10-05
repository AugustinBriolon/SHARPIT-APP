import SwiftUI
import WidgetKit

/// « Sommeil »: last night's score on Résumé's dial, with what the gauge says under it.
struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Sleep", provider: SnapshotProvider()) { entry in
            Group {
                if entry.unlocksExtraWidgets {
                    SleepWidgetView(entry: entry)
                } else {
                    WidgetProLocked(title: "Nuit dernière", symbol: "moon.zzz")
                }
            }
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(entry.extraLink("/sleep"))
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
        WidgetFrame("Nuit dernière", symbol: "moon.zzz") {
            if let sleep, let score = sleep.score {
                DialReadout(score: CGFloat(score), figure: "\(score)")
                WidgetCaption(text: sleep.caption ?? "Score de sommeil")
                    .frame(maxWidth: .infinity)
            } else {
                WidgetAwaitingData(text: hasDay ? "Pas encore de nuit synchronisée." : "Ouvre SharpIt pour charger ta journée.")
            }
        }
    }
}

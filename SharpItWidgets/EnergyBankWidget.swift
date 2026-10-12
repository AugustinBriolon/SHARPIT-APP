import SwiftUI
import WidgetKit

/// « Réserve »: SharpIt Energy Bank dial (ADR-079).
/// Callers: SharpItWidgetsBundle.
/// API: WidgetSnapshot.Day.energyBank from Today fold.
/// Schema: App Group WidgetSnapshot (no DB).
/// User: "Implement the plan as specified… Don't stop until you have completed all the to-dos."
struct EnergyBankWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnergyBank", provider: SnapshotProvider()) { entry in
            Group {
                if entry.unlocksExtraWidgets {
                    EnergyBankWidgetView(entry: entry)
                } else {
                    WidgetProLocked(title: "Réserve", symbol: "battery.100")
                }
            }
            .containerBackground(for: .widget) { WidgetCanvas() }
            .widgetURL(entry.extraLink("/"))
        }
        .configurationDisplayName("Réserve")
        .description("Ta réserve d’énergie du jour.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct EnergyBankWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var energy: WidgetSnapshot.EnergyBank? { entry.day?.energyBank }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(energy?.score ?? 0), in: 0...100) {
                Image(systemName: "battery.100")
            } currentValueLabel: {
                Text(energy?.score.map(String.init) ?? "—").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Réserve \(energy?.score.map(String.init) ?? "—")", systemImage: "battery.100")
                    .font(.headline)
                    .widgetAccentable()
                if let caption = energy?.caption {
                    Text(caption).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EnergyBankSmall(energy: energy, hasDay: entry.day != nil)
        }
    }
}

struct EnergyBankSmall: View {
    let energy: WidgetSnapshot.EnergyBank?
    let hasDay: Bool

    var body: some View {
        WidgetFrame("Réserve", symbol: "battery.100") {
            if let energy, let score = energy.score {
                DialReadout(score: CGFloat(score), figure: "\(score)")
                WidgetCaption(text: energy.caption ?? "Énergie du jour")
                    .frame(maxWidth: .infinity)
            } else {
                WidgetAwaitingData(
                    text: hasDay
                        ? "Pas encore de réserve calculée."
                        : "Ouvre SharpIt pour charger ta journée."
                )
            }
        }
    }
}

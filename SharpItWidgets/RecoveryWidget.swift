import SwiftUI
import WidgetKit

/// « Récupération »: the morning's recovery in its ring, as Résumé reads it. It takes the place
/// of « Réserve », a score Résumé's rings no longer carry.
struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Recovery", provider: SnapshotProvider()) { entry in
            Group {
                if entry.unlocksExtraWidgets {
                    RecoveryWidgetView(entry: entry)
                } else {
                    WidgetProLocked(title: String(localized: "Récupération"), symbol: "bolt")
                }
            }
            .sharpitWidgetChrome()
            .widgetURL(entry.extraLink("/"))
        }
        .configurationDisplayName("Récupération")
        .description("Ta récupération de ce matin.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct RecoveryWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var recovery: WidgetSnapshot.Sleep? { entry.day?.recovery }

    var body: some View {
        // Health values: redacted on a locked device.
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(recovery?.score ?? 0), in: 0...100) {
                    Image(systemName: "bolt")
                } currentValueLabel: {
                    Text(recovery?.score.map(String.init) ?? "—").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Récupération \(recovery?.score.map(String.init) ?? "—")", systemImage: "bolt")
                        .font(.headline)
                        .widgetAccentable()
                    if let caption = recovery?.caption {
                        Text(caption).font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                WidgetFrame(String(localized: "Récupération"), symbol: "bolt", tint: SharpitColor.pillarRecovery) {
                    if let recovery, let score = recovery.score {
                        DialReadout(score: CGFloat(score), figure: "\(score)", hue: SharpitColor.pillarRecovery)
                        WidgetCaption(text: recovery.caption ?? String(localized: "Score de récupération"))
                            .frame(maxWidth: .infinity)
                    } else {
                        WidgetAwaitingData(
                            text: entry.day != nil
                                ? String(localized: "Pas encore de récupération lue.")
                                : String(localized: "Ouvre SharpIt pour charger ta journée.")
                        )
                    }
                }
            }
        }
        .privacySensitive()
    }
}

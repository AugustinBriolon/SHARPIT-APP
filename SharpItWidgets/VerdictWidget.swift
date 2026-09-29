import SwiftUI
import WidgetKit

/// « Verdict du jour »: how hard today can go, and why — what SharpIt reads that no watch app
/// does. The canvas carries the posture's tone in its corner; a tap opens Résumé.
struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Verdict", provider: SnapshotProvider()) { entry in
            VerdictView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas(stateTone: entry.day?.verdict?.posture.tone) }
                .widgetURL(WidgetSnapshot.link("/today"))
        }
        .configurationDisplayName("Verdict du jour")
        .description("Ce que ta forme permet aujourd'hui.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct VerdictView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    fileprivate var verdict: WidgetSnapshot.Verdict? { entry.day?.verdict }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: VerdictSmall(verdict: verdict)
        }
    }
}

/// The small « Verdict du jour ».
struct VerdictSmall: View {
    let verdict: WidgetSnapshot.Verdict?

    var body: some View {
        if let verdict {
            WidgetFrame("Verdict", symbol: verdict.posture.symbolName, tint: verdict.posture.tone) {
                WidgetEyebrow(text: verdict.status, tint: verdict.posture.tone)
                WidgetTitle(text: verdict.headline, lines: 3)
                    .padding(.top, 2)
                if let action = verdict.action {
                    WidgetCaption(text: action, lines: 2)
                        .padding(.top, WidgetMetrics.lineGap)
                }
            }
        } else {
            WidgetAwaitingDay(eyebrow: "Verdict", symbol: "questionmark.circle")
        }
    }
}

extension VerdictView {
    @ViewBuilder
    fileprivate var rectangular: some View {
        if let verdict {
            VStack(alignment: .leading, spacing: 1) {
                Label(verdict.status, systemImage: verdict.posture.symbolName)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(verdict.headline).font(.headline).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Verdict à venir", systemImage: "questionmark.circle").font(.headline)
        }
    }

    fileprivate var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: verdict?.posture.symbolName ?? "questionmark.circle")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
        }
    }

    @ViewBuilder
    fileprivate var inline: some View {
        if let verdict {
            Label(verdict.status, systemImage: verdict.posture.symbolName)
        } else {
            Label("Verdict à venir", systemImage: "questionmark.circle")
        }
    }
}

#Preview(as: .systemSmall) {
    VerdictWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

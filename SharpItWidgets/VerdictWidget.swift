import SwiftUI
import WidgetKit

/// « Verdict du jour »: how hard today can go, and why — what SharpIt reads that no watch app does.
struct VerdictWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Verdict", provider: SnapshotProvider()) { entry in
            VerdictView(entry: entry)
                .containerBackground(SharpitColor.card, for: .widget)
                .widgetURL(WidgetLink.today)
        }
        .configurationDisplayName("Verdict du jour")
        .description("Ce que ta forme permet aujourd'hui.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct VerdictView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var verdict: WidgetSnapshot.Verdict? { entry.today?.verdict }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    @ViewBuilder
    private var small: some View {
        if let verdict {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: verdict.posture.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(verdict.posture.tone)
                Text(verdict.status)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(verdict.posture.tone)
                Spacer(minLength: 0)
                Text(verdict.headline)
                    .font(.headline)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Verdict du jour")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                OpenTheAppHint(text: "Ouvre SharpIt une fois ta nuit synchronisée.")
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
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

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: verdict?.posture.symbolName ?? "questionmark.circle")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
        }
    }

    @ViewBuilder
    private var inline: some View {
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

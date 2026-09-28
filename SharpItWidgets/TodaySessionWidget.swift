import SwiftUI
import WidgetKit

/// « Séance du jour »: the session to do, then — once synced — what was done.
struct TodaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySession", provider: SnapshotProvider()) { entry in
            TodaySessionView(entry: entry)
                .containerBackground(SharpitColor.card, for: .widget)
                .widgetURL(WidgetLink.plan)
        }
        .configurationDisplayName("Séance du jour")
        .description("La séance prévue, puis ce que tu as fait.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodaySessionView: View {
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

    private var sessions: [WidgetSnapshot.Session] { entry.today?.sessions ?? [] }

    @ViewBuilder
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aujourd'hui")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            if let session = entry.today?.leadSession {
                SportMark(sport: session.sport)
                Spacer(minLength: 0)
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                SessionFigures(session: session)
            } else if entry.today == nil {
                OpenTheAppHint(text: "Ouvre SharpIt pour voir ta journée.")
            } else {
                Spacer(minLength: 0)
                Text("Repos")
                    .font(.headline)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Aucune séance prévue.")
                    .font(.caption)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aujourd'hui")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                if sessions.isEmpty {
                    if entry.today == nil {
                        OpenTheAppHint(text: "Ouvre SharpIt pour voir ta journée.")
                    } else {
                        Text("Repos").font(.headline).foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: 0)
                    }
                } else {
                    ForEach(sessions.prefix(2)) { session in
                        HStack(spacing: 10) {
                            SportMark(sport: session.sport, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SharpitColor.foreground)
                                    .lineLimit(1)
                                SessionFigures(session: session)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if let verdict = entry.today?.verdict {
                VStack(alignment: .leading, spacing: 4) {
                    Label(verdict.status, systemImage: verdict.posture.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(verdict.posture.tone)
                    Text(verdict.headline)
                        .font(.caption)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(3)
                }
                .frame(maxWidth: 120, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var rectangular: some View {
        if let session = entry.today?.leadSession {
            VStack(alignment: .leading, spacing: 1) {
                Label(session.isDone ? "Faite" : "Aujourd'hui", systemImage: session.sport.symbolName)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(session.title).font(.headline).lineLimit(1)
                Text(session.figures.joined(separator: " · ")).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(entry.today == nil ? "Ouvre SharpIt" : "Repos aujourd'hui", systemImage: "figure.cooldown")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let session = entry.today?.leadSession {
            Label("\(session.title) · \(session.figures.first ?? "")", systemImage: session.sport.symbolName)
        } else {
            Label(entry.today == nil ? "SharpIt" : "Repos aujourd'hui", systemImage: "figure.cooldown")
        }
    }
}

#Preview(as: .systemSmall) {
    TodaySessionWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

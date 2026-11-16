import SwiftUI
import WidgetKit

/// « Séance du jour »: the session to do, then — once synced — what was done. A tap opens it:
/// the activity once done, its prescription before.
struct TodaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySession", provider: SnapshotProvider()) { entry in
            TodaySessionView(entry: entry)
                .sharpitWidgetChrome()
        }
        .configurationDisplayName("Séance du jour")
        .description("La séance prévue, puis ce que tu as fait.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct TodaySessionView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: TodaySessionSmall(entry: entry)
        }
    }

    private var day: WidgetSnapshot.Day? { entry.day }

    // MARK: Lock screen

    @ViewBuilder
    private var rectangular: some View {
        if let session = day?.leadSession {
            VStack(alignment: .leading, spacing: 1) {
                Label { Text(session.isDone ? String(localized: "Faite") : String(localized: "Aujourd'hui")) } icon: { Image(sharpitSymbol: session.isDone ? "checkmark.circle.fill" : session.sport.symbolName) }
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(session.title).font(.headline).lineLimit(1)
                Text(session.figures.map { "\($0.value) \($0.unit)" }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(session.link)
        } else {
            Label(day == nil ? String(localized: "Ouvre SharpIt") : String(localized: "Repos aujourd'hui"), systemImage: "figure.cooldown")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let session = day?.leadSession {
            Label {
                Text([session.title, session.figures.first.map { "\($0.value) \($0.unit)" }].compactMap { $0 }.joined(separator: " · "))
            } icon: {
                Image(sharpitSymbol: session.isDone ? "checkmark.circle.fill" : session.sport.symbolName)
            }
            .widgetURL(session.link)
        } else {
            Label(day == nil ? "SharpIt" : String(localized: "Repos aujourd'hui"), systemImage: "figure.cooldown")
        }
    }
}

/// The small « Séance du jour ».
struct TodaySessionSmall: View {
    let entry: SnapshotEntry

    private var day: WidgetSnapshot.Day? { entry.day }
    private var eyebrow: String { day.map { WidgetDay.label($0.trainingDayId) } ?? String(localized: "Aujourd'hui") }

    var body: some View {
        if let day {
            if let session = day.leadSession {
                SessionHero(session: session, eyebrow: eyebrow)
                    .widgetURL(session.link)
            } else {
                RestDay(eyebrow: eyebrow, verdict: day.verdict)
                    .widgetURL(WidgetSnapshot.link("/plan"))
            }
        } else {
            WidgetAwaitingDay(eyebrow: String(localized: "Séance du jour"), symbol: "figure.run")
        }
    }
}

/// The small widget's session: the day and its glyph above, the sport, the title, the figures.
private struct SessionHero: View {
    let session: WidgetSnapshot.Session
    let eyebrow: String

    var body: some View {
        WidgetFrame(title: eyebrow) {
            if session.isDone {
                WidgetGlyph(symbol: "checkmark.circle.fill", tint: SharpitColor.pillarRecovery)
            } else {
                WidgetGlyph(symbol: session.sport.symbolName, tint: SharpitColor.foreground)
            }
        } content: {
            WidgetEyebrow(text: session.isDone ? String(localized: "Faite · \(session.sport.label)") : session.sport.label, tint: SharpitColor.foreground)
            WidgetTitle(text: session.title)
                .padding(.top, 2)
            WidgetFigureRow(figures: Array(session.figures.prefix(2)))
                .padding(.top, 8)
        }
    }
}

/// A day with nothing planned: rest, said plainly.
private struct RestDay: View {
    let eyebrow: String
    let verdict: WidgetSnapshot.Verdict?

    var body: some View {
        WidgetFrame(eyebrow, symbol: "figure.cooldown") {
            WidgetTitle(text: String(localized: "Repos"))
            WidgetCaption(text: String(localized: "Rien de prévu aujourd'hui."), lines: 2)
        }
    }
}

#Preview(as: .systemSmall) {
    TodaySessionWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

import SwiftUI
import WidgetKit

/// « Séance du jour »: the session to do, then — once synced — what was done. A tap opens it:
/// the activity once done, its prescription before.
struct TodaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySession", provider: SnapshotProvider()) { entry in
            TodaySessionView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
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
        case .systemMedium: TodaySessionMedium(entry: entry)
        default: TodaySessionSmall(entry: entry)
        }
    }

    private var day: WidgetSnapshot.Day? { entry.day }

    // MARK: Lock screen

    @ViewBuilder
    private var rectangular: some View {
        if let session = day?.leadSession {
            VStack(alignment: .leading, spacing: 1) {
                Label(session.isDone ? "Faite" : "Aujourd'hui", systemImage: session.isDone ? "checkmark.circle.fill" : session.sport.symbolName)
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
            Label(day == nil ? "Ouvre SharpIt" : "Repos aujourd'hui", systemImage: "figure.cooldown")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let session = day?.leadSession {
            Label(
                [session.title, session.figures.first.map { "\($0.value) \($0.unit)" }].compactMap { $0 }.joined(separator: " · "),
                systemImage: session.isDone ? "checkmark.circle.fill" : session.sport.symbolName
            )
            .widgetURL(session.link)
        } else {
            Label(day == nil ? "SharpIt" : "Repos aujourd'hui", systemImage: "figure.cooldown")
        }
    }
}

/// The small « Séance du jour ».
struct TodaySessionSmall: View {
    let entry: SnapshotEntry

    private var day: WidgetSnapshot.Day? { entry.day }
    private var eyebrow: String { day.map { WidgetDay.label($0.trainingDayId) } ?? "Aujourd'hui" }

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
            WidgetAwaitingDay(eyebrow: "Séance du jour", symbol: "figure.run")
        }
    }
}

/// The medium « Séance du jour »: the day's sessions, each opening itself, beside the verdict.
struct TodaySessionMedium: View {
    let entry: SnapshotEntry

    private var day: WidgetSnapshot.Day? { entry.day }
    private var eyebrow: String { day.map { WidgetDay.label($0.trainingDayId) } ?? "Aujourd'hui" }

    var body: some View {
        if let day {
            WidgetFrame(title: eyebrow) {
                if let verdict = day.verdict {
                    WidgetGlyph(symbol: verdict.posture.symbolName, tint: verdict.posture.tone)
                } else {
                    WidgetGlyph(symbol: "calendar")
                }
            } content: {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        if day.sessions.isEmpty {
                            WidgetTitle(text: "Repos")
                            WidgetCaption(text: "Rien de prévu aujourd'hui.")
                        } else {
                            ForEach(day.sessions.prefix(2)) { session in
                                Link(destination: session.link) { SessionLine(session: session) }
                            }
                            if day.sessions.count > 2 {
                                WidgetCaption(text: "+ \(day.sessions.count - 2) autre\(day.sessions.count > 3 ? "s" : "")")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    if let verdict = day.verdict {
                        Link(destination: WidgetSnapshot.link("/today")) { VerdictPanel(verdict: verdict) }
                    }
                }
            }
            .widgetURL(WidgetSnapshot.link("/plan"))
        } else {
            WidgetAwaitingDay(eyebrow: "Séance du jour", symbol: "figure.run")
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
                WidgetGlyph(symbol: "checkmark.circle.fill", tint: SharpitColor.primary)
            } else {
                WidgetGlyph(symbol: session.sport.symbolName, tint: SharpitSportColor.color(session.sport.identity))
            }
        } content: {
            WidgetEyebrow(text: session.isDone ? "Faite · \(session.sport.label)" : session.sport.label, tint: SharpitSportColor.color(session.sport.identity))
            WidgetTitle(text: session.title)
                .padding(.top, 2)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(session.figures.prefix(2), id: \.value) { WidgetFigure(figure: $0, large: true) }
            }
            .padding(.top, 8)
        }
    }
}

/// One session in the medium widget: its sport as a bar of its color, title, figures.
private struct SessionLine: View {
    let session: WidgetSnapshot.Session

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(SharpitSportColor.color(session.sport.identity))
                .frame(width: 3, height: 34)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    ForEach(session.figures.prefix(2), id: \.value) { WidgetFigure(figure: $0) }
                }
            }
            Spacer(minLength: 4)
            if session.isDone { DoneSeal() }
        }
    }
}

/// A day with nothing planned: rest, said plainly.
private struct RestDay: View {
    let eyebrow: String
    let verdict: WidgetSnapshot.Verdict?

    var body: some View {
        WidgetFrame(eyebrow, symbol: "figure.cooldown") {
            WidgetTitle(text: "Repos")
            WidgetCaption(text: "Rien de prévu aujourd'hui.", lines: 2)
        }
    }
}

/// The verdict beside the sessions: a panel in its posture's tone.
struct VerdictPanel: View {
    let verdict: WidgetSnapshot.Verdict

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(verdict.posture.tone).frame(width: 7, height: 7)
                WidgetEyebrow(text: verdict.status, tint: verdict.posture.tone)
            }
            Text(verdict.headline)
                .font(SharpitTypography.cardTitle)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let action = verdict.action {
                Text(action)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(width: 124, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(verdict.posture.tone.opacity(0.12), in: RoundedRectangle(cornerRadius: WidgetMetrics.panelRadius, style: .continuous))
    }
}

#Preview(as: .systemSmall) {
    TodaySessionWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    TodaySessionWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

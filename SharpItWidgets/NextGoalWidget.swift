import SwiftUI
import WidgetKit

/// « Prochain objectif »: the race Objectifs puts first, the days left to it, and what is known
/// of it — format, place, the time aimed at. A count, not an exhortation.
struct NextGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextGoal", provider: SnapshotProvider()) { entry in
            NextGoalWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/goals"))
        }
        .configurationDisplayName("Prochain objectif")
        .description("Le compte à rebours jusqu'à ta prochaine course.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextGoalWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let goal = entry.goal {
                Label("\(goal.title) · J-\(goal.daysLeft(from: entry.date))", systemImage: "flag.checkered")
            } else {
                Label("Aucune course prévue", systemImage: "flag.checkered")
            }
        case .accessoryRectangular:
            if let goal = entry.goal {
                VStack(alignment: .leading, spacing: 1) {
                    Label("J-\(goal.daysLeft(from: entry.date))", systemImage: "flag.checkered")
                        .font(.headline.monospacedDigit())
                        .widgetAccentable()
                    Text(goal.title).font(.caption).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Aucune course prévue", systemImage: "flag.checkered").font(.headline)
            }
        case .systemMedium:
            NextGoalBody(goal: entry.goal, date: entry.date, showsContext: true)
        default:
            NextGoalBody(goal: entry.goal, date: entry.date, showsContext: false)
        }
    }
}

struct NextGoalBody: View {
    let goal: WidgetSnapshot.Goal?
    let date: Date
    let showsContext: Bool

    var body: some View {
        WidgetFrame(showsContext ? "Prochain objectif" : "Objectif", symbol: "flag.checkered", tint: SharpitColor.primary) {
            if let goal {
                let days = goal.daysLeft(from: date)
                WidgetHero(value: days == 0 ? "Jour J" : "\(days)", unit: days == 0 ? nil : (days == 1 ? "jour" : "jours"))
                WidgetTitle(text: goal.title, lines: 1)
                WidgetCaption(text: goal.dateLine)
                if showsContext, let context = goal.contextLine {
                    WidgetCaption(text: context, tint: SharpitColor.primary)
                        .padding(.top, 2)
                }
            } else {
                WidgetAwaitingData(text: "Aucune course prévue. Ajoute-la dans Objectifs.")
            }
        }
    }
}

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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetEyebrow(text: showsContext ? "Prochain objectif" : "Objectif")
                Spacer(minLength: 4)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            if let goal {
                let days = goal.daysLeft(from: date)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(days == 0 ? "Jour J" : "\(days)")
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if days > 0 {
                        Text(days == 1 ? "jour" : "jours")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                Text(goal.title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(showsContext ? 1 : 2)
                Text(goal.dateLine)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                if showsContext, let context = goal.contextLine {
                    Text(context)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.primary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            } else {
                Text("Aucune course prévue. Ajoute-la dans Objectifs.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

import SwiftUI
import WidgetKit

/// « Régularité »: the days around today as Résumé's strip draws them, and the week's sessions
/// counted. No streak — the design law keeps counters of days in a row out.
struct RegularityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Regularity", provider: SnapshotProvider()) { entry in
            RegularityWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/plan"))
        }
        .configurationDisplayName("Régularité")
        .description("Les jours où tu t'es entraîné, et tes séances de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct RegularityWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.regularity.map(\.weekLine) ?? "Régularité")
                    .font(.headline)
                    .widgetAccentable()
                if let regularity = entry.regularity {
                    RegularityMarks(days: regularity.days, size: 9, showsLabels: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            RegularityBody(regularity: entry.regularity, markSize: 14, showsLabels: true)
        default:
            RegularityBody(regularity: entry.regularity, markSize: 11, showsLabels: false)
        }
    }
}

struct RegularityBody: View {
    let regularity: WidgetSnapshot.Regularity?
    let markSize: CGFloat
    let showsLabels: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetEyebrow(text: "Régularité")
                Spacer(minLength: 4)
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if let regularity {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(regularity.weekSessionCount)")
                        .font(SharpitTypography.heroScore)
                        .tracking(SharpitTypography.heroScoreTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .monospacedDigit()
                    Text(regularity.weekSessionCount == 1 ? "séance\ncette semaine" : "séances\ncette semaine")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                }
                .padding(.bottom, 10)
                RegularityMarks(days: regularity.days, size: markSize, showsLabels: showsLabels)
            } else {
                WidgetAwaitingData(text: "Ouvre SharpIt pour charger ta journée.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A mark per day: filled where there was training, a ring on today, faint ahead.
struct RegularityMarks: View {
    let days: [WidgetSnapshot.RegularityDay]
    let size: CGFloat
    let showsLabels: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    mark(day)
                        .frame(width: size, height: size)
                    if showsLabels {
                        Text(day.weekdayLabel.prefix(1).uppercased())
                            .font(SharpitTypography.label)
                            .foregroundStyle(day.isToday ? SharpitColor.foreground : SharpitColor.mutedForeground)
                        Text("\(day.dayOfMonth)")
                            .font(SharpitTypography.meta.monospacedDigit())
                            .foregroundStyle(day.isToday ? SharpitColor.foreground : SharpitColor.mutedForeground)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(days.filter(\.hasActivity).count) jours entraînés sur \(days.filter { !$0.isFuture }.count)")
    }

    @ViewBuilder
    private func mark(_ day: WidgetSnapshot.RegularityDay) -> some View {
        if day.hasActivity {
            Circle().fill(SharpitColor.primary).widgetAccentable()
        } else if day.isToday {
            Circle().strokeBorder(SharpitColor.primary, lineWidth: 1.5)
        } else {
            Circle().fill(SharpitColor.mutedForeground.opacity(day.isFuture ? 0.12 : 0.28))
        }
    }
}

extension WidgetSnapshot.Regularity {
    var weekLine: String { weekSessionCount == 1 ? "1 séance cette semaine" : "\(weekSessionCount) séances cette semaine" }
}

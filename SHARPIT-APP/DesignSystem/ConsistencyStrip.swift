import SwiftUI

/// Regularity — the days around today, and what the week holds so far.
///
/// Deliberately not the web's full panel. `design.md` forbids habit-tracker heatmaps and
/// streak counters *as a primary signal*, so the 184-day grid and the streak stay on the
/// web. What travels is the part that answers a question the athlete actually asks in the
/// morning: have I trained lately, and what does this week look like.
struct ConsistencyStrip: View {
    let consistency: V1TodayConsistency

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Régularité")

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(consistency.days) { day in
                    ConsistencyDayMark(day: day)
                }
            }

            Text(weekSummary)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Plain counting, no encouragement: the design law rules out motivational micro-copy,
    /// and a quiet week is information rather than a failure to soften.
    private var weekSummary: String {
        switch consistency.thisWeekSessionCount {
        case 0: "Aucune séance cette semaine"
        case 1: "1 séance cette semaine"
        default: "\(consistency.thisWeekSessionCount) séances cette semaine"
        }
    }

    private var accessibilityLabel: String {
        let trained = consistency.days
            .filter { $0.hasActivity }
            .map(\.dayOfMonth)
            .map(String.init)
            .joined(separator: ", ")

        return trained.isEmpty
            ? "Régularité. \(weekSummary)."
            : "Régularité. \(weekSummary). Séances les \(trained)."
    }
}

private struct ConsistencyDayMark: View {
    let day: V1TodayConsistencyDay

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text(day.weekdayLabel)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(SharpitColor.mutedForeground)

            Text("\(day.dayOfMonth)")
                .font(SharpitTypography.instrument)
                .foregroundStyle(numberColor)
                .frame(width: 32, height: 32)
                .background(fill, in: Circle())
                .overlay(
                    Circle().strokeBorder(stroke, lineWidth: SharpitStroke.hairline)
                )
        }
        .frame(maxWidth: .infinity)
        // The strip is read as one thing; the label above carries the detail.
        .accessibilityHidden(true)
    }

    private var fill: Color {
        day.hasActivity ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt
    }

    /// Today is marked by its ring, not by another fill — a second filled state would
    /// compete with "you trained", which is the thing the strip is about.
    private var stroke: Color {
        day.isToday ? SharpitColor.primary : .clear
    }

    private var numberColor: Color {
        if day.hasActivity {
            return SharpitColor.primaryForeground
        }
        return day.isFuture ? SharpitColor.mutedForeground : SharpitColor.foreground
    }
}

#Preview {
    ConsistencyStrip(
        consistency: V1TodayConsistency(
            days: [
                V1TodayConsistencyDay(
                    date: "2026-09-14", weekdayLabel: "L", dayOfMonth: 14,
                    hasActivity: true, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-15", weekdayLabel: "M", dayOfMonth: 15,
                    hasActivity: false, isToday: true, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-16", weekdayLabel: "M", dayOfMonth: 16,
                    hasActivity: false, isToday: false, isFuture: true
                ),
            ],
            thisWeekSessionCount: 1
        )
    )
    .padding()
    .background(SharpitCanvasBackground())
}

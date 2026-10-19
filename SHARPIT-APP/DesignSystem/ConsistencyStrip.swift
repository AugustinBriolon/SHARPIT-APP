import SwiftUI

/// Regularity — the days around today, and what the week holds so far.
///
/// The card header, the days as marks (lime when trained, today ringed in ink), then the week's
/// count and the run of weeks in a chip at the foot.
struct ConsistencyStrip: View {
    let consistency: V1TodayConsistency
    var consecutiveWeeks: Int? = nil
    /// Opening the week is the natural next question after "have I trained lately".
    var onOpenPlan: (() -> Void)?

    var body: some View {
        Button {
            onOpenPlan?()
        } label: {
            content
        }
        .buttonStyle(.sharpitPressable)
        .disabled(onOpenPlan == nil)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            header

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(consistency.days) { day in
                    ConsistencyDayMark(day: day)
                }
            }
            .padding(.vertical, 2)

            footSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(onOpenPlan == nil ? [] : .isButton)
        .accessibilityHint(onOpenPlan == nil ? "" : String(localized: "Ouvre le plan de la semaine"))
    }

    private var header: some View {
        SharpitCardHeader(title: String(localized: "Régularité"), symbol: "calendar", showsChevron: onOpenPlan != nil)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The week's count and the streak, side by side; one above the other at the accessibility
    /// sizes, where on one line they pushed the card off the screen.
    private var footLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SharpitSpacing.xxs))
            : AnyLayout(HStackLayout(spacing: SharpitSpacing.xs))
    }

    private var footSummary: some View {
        footLayout {
            HStack(spacing: 6) {
                Image(systemName: consistency.thisWeekSessionCount > 0 ? "flame.fill" : "moon.zzz")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(consistency.thisWeekSessionCount > 0 ? SharpitColor.primary : SharpitColor.mutedForeground)

                if consistency.thisWeekSessionCount > 0 {
                    Text("\(consistency.thisWeekSessionCount)")
                        .font(SharpitTypography.system(size: 15, weight: .bold, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.foreground)

                    let noun = consistency.thisWeekSessionCount == 1 ? String(localized: "séance") : String(localized: "séances")
                    // The week is implied by the strip above, so a narrow card drops it rather than truncate.
                    ViewThatFits(in: .horizontal) {
                        Text("\(noun) cette semaine")
                        Text(noun)
                    }
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                } else {
                    Text("Aucune séance cette semaine")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 4)
            }

            // Number of consecutive weeks with at least 1 activity
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)

                Text(streakText)
                    .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .padding(.vertical, SharpitSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: SharpitSpacing.chipRadius)
    }

    private var streakText: String {
        let count = consecutiveWeeks ?? (consistency.thisWeekSessionCount > 0 ? 1 : 0)
        return String(localized: "\(count) sem. d'affilée")
    }

    /// Plain counting, no encouragement: the design law rules out motivational micro-copy,
    /// and a quiet week is information rather than a failure to soften.
    private var weekSummary: String {
        switch consistency.thisWeekSessionCount {
        case 0: String(localized: "Aucune séance cette semaine")
        case 1: String(localized: "1 séance cette semaine")
        default: String(localized: "\(consistency.thisWeekSessionCount) séances cette semaine")
        }
    }

    private var accessibilityLabel: String {
        let trained = consistency.days
            .filter { $0.hasActivity }
            .map(\.dayOfMonth)
            .map(String.init)
            .joined(separator: ", ")

        let streakDesc = "\(streakText)."
        return trained.isEmpty
            ? String(localized: "Régularité. \(weekSummary). \(streakDesc)")
            : String(localized: "Régularité. \(weekSummary). Séances les \(trained). \(streakDesc)")
    }
}

private struct ConsistencyDayMark: View {
    let day: V1TodayConsistencyDay

    var body: some View {
        VStack(spacing: 6) {
            Text(day.weekdayLabel)
                .font(SharpitTypography.system(size: 12, weight: day.isToday ? .bold : .medium, relativeTo: .caption))
                .foregroundStyle(weekdayColor)

            dayCircle

            Circle()
                .fill(day.isToday ? SharpitColor.foreground : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var weekdayColor: Color {
        day.isToday ? SharpitColor.foreground : SharpitColor.mutedForeground
    }

    /// A trained day is a lime disc, today is ringed in ink, the rest sit on the chip tone.
    @ViewBuilder
    private var dayCircle: some View {
        ZStack {
            if day.hasActivity {
                Circle().fill(SharpitColor.highlight)
            } else if day.isFuture {
                Circle().fill(SharpitColor.track.opacity(0.5))
            } else {
                Circle().fill(SharpitColor.chipSurface)
            }
            if day.isToday {
                Circle()
                    .strokeBorder(SharpitColor.foreground, lineWidth: 2)
                    .padding(day.hasActivity ? -3 : 0)
            }

            Text("\(day.dayOfMonth)")
                .font(SharpitTypography.instrument)
                .fontWeight(day.hasActivity || day.isToday ? .bold : .medium)
                .foregroundStyle(numberColor)
        }
        .frame(width: 32, height: 32)
    }

    private var numberColor: Color {
        if day.hasActivity {
            return SharpitColor.highlightForeground
        }
        if day.isToday {
            return SharpitColor.foreground
        }
        if day.isFuture {
            return SharpitColor.mutedForeground.opacity(0.4)
        }
        return SharpitColor.foreground.opacity(0.8)
    }
}

enum ActivityStreakCalculator {
    /// Computes the number of consecutive calendar weeks (Monday to Sunday) ending at current week
    /// that have at least 1 activity.
    static func consecutiveWeeksWithActivity(
        activities: [V1ActivityListItem],
        calendar: Calendar = .current,
        referenceDate: Date = .now
    ) -> Int {
        guard !activities.isEmpty else { return 0 }

        var cal = calendar
        cal.firstWeekday = 2 // Monday in ISO 8601

        let activityDates = activities.map(\.date)

        guard let currentWeekInterval = cal.dateInterval(of: .weekOfYear, for: referenceDate) else {
            return 0
        }

        var count = 0
        var weekStart = currentWeekInterval.start

        // Check if current week has activity
        guard let nextWeekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return 0 }
        let currentWeekHasActivity = activityDates.contains { date in
            date >= weekStart && date < nextWeekStart
        }

        if currentWeekHasActivity {
            count += 1
            while true {
                guard let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { break }
                let prevWeekEnd = weekStart
                let hasAct = activityDates.contains { date in
                    date >= prevWeekStart && date < prevWeekEnd
                }
                if hasAct {
                    count += 1
                    weekStart = prevWeekStart
                } else {
                    break
                }
            }
        } else {
            // Current week has no activity yet; check backwards from previous week
            guard let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { return 0 }
            let lastWeekHasActivity = activityDates.contains { date in
                date >= lastWeekStart && date < weekStart
            }
            if lastWeekHasActivity {
                count += 1
                var prevStart = lastWeekStart
                while true {
                    guard let earlierWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: prevStart) else { break }
                    let earlierWeekEnd = prevStart
                    let hasAct = activityDates.contains { date in
                        date >= earlierWeekStart && date < earlierWeekEnd
                    }
                    if hasAct {
                        count += 1
                        prevStart = earlierWeekStart
                    } else {
                        break
                    }
                }
            }
        }

        return count
    }
}

#Preview {
    ConsistencyStrip(
        consistency: V1TodayConsistency(
            days: [
                V1TodayConsistencyDay(
                    date: "2026-09-18", weekdayLabel: "V", dayOfMonth: 18,
                    hasActivity: false, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-19", weekdayLabel: "S", dayOfMonth: 19,
                    hasActivity: true, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-20", weekdayLabel: "D", dayOfMonth: 20,
                    hasActivity: true, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-21", weekdayLabel: "L", dayOfMonth: 21,
                    hasActivity: true, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-22", weekdayLabel: "M", dayOfMonth: 22,
                    hasActivity: true, isToday: false, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-23", weekdayLabel: "M", dayOfMonth: 23,
                    hasActivity: false, isToday: true, isFuture: false
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-24", weekdayLabel: "J", dayOfMonth: 24,
                    hasActivity: false, isToday: false, isFuture: true
                ),
                V1TodayConsistencyDay(
                    date: "2026-09-25", weekdayLabel: "V", dayOfMonth: 25,
                    hasActivity: false, isToday: false, isFuture: true
                ),
            ],
            thisWeekSessionCount: 3
        ),
        consecutiveWeeks: 4,
        onOpenPlan: {}
    )
    .padding()
    .background(SharpitColor.background)
}

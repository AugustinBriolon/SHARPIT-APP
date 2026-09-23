import SwiftUI

/// Regularity — the days around today, and what the week holds so far.
///
/// Composed with Apple-grade hierarchy and Golden Ratio spatial balance:
/// - Header: tinted micro-badge icon + uppercase category label + interactive disclosure chevron
/// - Rhythm: 8-day tactile day marks with distinct states (trained, today focus, rest, future)
/// - Footer: structured telemetry capsule with session count and consecutive weeks streak
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
        .sharpitCardSpecularBorder()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(onOpenPlan == nil ? [] : .isButton)
        .accessibilityHint(onOpenPlan == nil ? "" : "Ouvre le plan de la semaine")
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(SharpitColor.primary.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)
            }

            Text("RÉGULARITÉ")
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.foreground.opacity(0.85))

            Spacer(minLength: 0)

            if onOpenPlan != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                    .accessibilityHidden(true)
            }
        }
    }

    private var footSummary: some View {
        HStack(spacing: SharpitSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: consistency.thisWeekSessionCount > 0 ? "flame.fill" : "moon.zzz")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(consistency.thisWeekSessionCount > 0 ? SharpitColor.primary : SharpitColor.mutedForeground)

                if consistency.thisWeekSessionCount > 0 {
                    Text("\(consistency.thisWeekSessionCount)")
                        .font(SharpitTypography.label)
                        .fontWeight(.bold)
                        .foregroundStyle(SharpitColor.foreground)

                    Text(consistency.thisWeekSessionCount == 1 ? "séance cette semaine" : "séances cette semaine")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                } else {
                    Text("Aucune séance cette semaine")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }

            Spacer(minLength: 4)

            // Number of consecutive weeks with at least 1 activity
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SharpitColor.primary)

                Text(streakText)
                    .font(SharpitTypography.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(SharpitColor.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                .fill(SharpitColor.secondary.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                        .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var streakText: String {
        let count = consecutiveWeeks ?? (consistency.thisWeekSessionCount > 0 ? 1 : 0)
        return "\(count) sem. d'affilée"
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

        let streakDesc = "\(streakText)."
        return trained.isEmpty
            ? "Régularité. \(weekSummary). \(streakDesc)"
            : "Régularité. \(weekSummary). Séances les \(trained). \(streakDesc)"
    }
}

private struct ConsistencyDayMark: View {
    let day: V1TodayConsistencyDay

    var body: some View {
        VStack(spacing: 6) {
            Text(day.weekdayLabel)
                .font(.system(size: 11, weight: day.isToday ? .bold : .semibold, design: .rounded))
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(weekdayColor)

            dayCircle

            Circle()
                .fill(day.isToday ? SharpitColor.primary : Color.clear)
                .frame(width: 3.5, height: 3.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var weekdayColor: Color {
        if day.isToday {
            return SharpitColor.primary
        }
        return SharpitColor.mutedForeground.opacity(0.7)
    }

    @ViewBuilder
    private var dayCircle: some View {
        ZStack {
            if day.hasActivity {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                SharpitColor.primary,
                                SharpitColor.primary.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                if day.isToday {
                    Circle()
                        .strokeBorder(SharpitColor.primary, lineWidth: 2)
                        .padding(-3)
                }
            } else if day.isToday {
                Circle()
                    .fill(SharpitColor.primary.opacity(0.08))
                Circle()
                    .strokeBorder(SharpitColor.primary, lineWidth: 2)
            } else if day.isFuture {
                Circle()
                    .fill(SharpitColor.secondary.opacity(0.35))
            } else {
                Circle()
                    .fill(SharpitColor.secondary.opacity(0.65))
                    .overlay(
                        Circle()
                            .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                    )
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
            return SharpitColor.primaryForeground
        }
        if day.isToday {
            return SharpitColor.primary
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

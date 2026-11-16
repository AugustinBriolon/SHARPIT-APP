import Foundation
import SwiftUI

/// The trips the coach knows about (Mémoire du coach, `/api/v1/coach-memory`) that fall in the
/// week Plan shows — the web's `TravelContextBanner` beside the planning week
/// (`filterTravelsOverlappingRange`): a trip is a span of calendar days, kept by the server as
/// UTC midnights, so it is compared day by day, never instant by instant.
nonisolated enum PlanTravel {
    /// The travels overlapping `days` (inclusive), the earliest first. Constraints are not trips.
    static func trips(
        _ entries: [CoachMemoryEntry],
        overlapping days: [Date],
        calendar: Calendar = .current
    ) -> [CoachMemoryEntry] {
        guard let first = days.min(), let last = days.max() else { return [] }
        let weekStart = dayKey(first, in: calendar)
        let weekEnd = dayKey(last, in: calendar)
        return entries
            .filter { $0.type == .travel }
            .filter { entry in
                let start = dayKey(entry.startDate, in: utc)
                let end = dayKey(entry.endDate, in: utc)
                return start <= weekEnd && end >= weekStart
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// The trips and constraints, split on today: those under way, then those ahead, each the
    /// earliest first. Injuries, preferences and notes belong to the coach's memory.
    static func schedule(
        _ entries: [CoachMemoryEntry],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (current: [CoachMemoryEntry], upcoming: [CoachMemoryEntry], isEmpty: Bool) {
        let day = dayKey(today, in: calendar)
        let dated = entries
            .filter { $0.type == .travel || $0.type == .constraint }
            .sorted { $0.startDate < $1.startDate }
        let current = dated.filter { dayKey($0.startDate, in: utc) <= day }
        let upcoming = dated.filter { dayKey($0.startDate, in: utc) > day }
        return (current, upcoming, dated.isEmpty)
    }

    /// The trip a day falls in — the earliest when two overlap; nil on a day at home.
    static func trip(on day: Date, in trips: [CoachMemoryEntry], calendar: Calendar = .current) -> CoachMemoryEntry? {
        let key = dayKey(day, in: calendar)
        return trips.first { dayKey($0.startDate, in: utc) <= key && dayKey($0.endDate, in: utc) >= key }
    }

    /// What VoiceOver reads: each trip and its days.
    static func accessibilityLabel(_ trips: [CoachMemoryEntry]) -> String {
        let parts = trips.map { "\($0.displayTitle), \($0.formattedDateRange)" }
        return String(localized: "Déplacement cette semaine : ") + parts.joined(separator: " ; ")
    }

    /// A calendar day as one comparable number (20261005).
    static func dayKey(_ date: Date, in calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}

/// A trip's name atop its first day of the week: the band under it runs down the days away, so
/// the week shows which sessions fall on the road. It opens the list of trips, where they live.
struct PlanTravelLabel: View {
    let trip: CoachMemoryEntry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(trip.displayTitle)
                    .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .caption))
                    .lineLimit(1)
                Text(trip.formattedDateRange)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(1)
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(SharpitColor.foreground)
            .padding(.top, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(PlanTravel.accessibilityLabel([trip]))
        .accessibilityHint("Ouvre tes déplacements")
    }
}

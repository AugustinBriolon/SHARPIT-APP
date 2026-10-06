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

    /// The chip's words: the first trip's name, and how many more share the week (« Lisbonne +1 »).
    static func chipTitle(_ trips: [CoachMemoryEntry]) -> String? {
        guard let first = trips.first else { return nil }
        let extra = trips.count > 1 ? " +\(trips.count - 1)" : ""
        return first.displayTitle + extra
    }

    /// What VoiceOver reads: each trip and its days.
    static func accessibilityLabel(_ trips: [CoachMemoryEntry]) -> String {
        let parts = trips.map { "\($0.displayTitle), \($0.formattedDateRange)" }
        return "Déplacement cette semaine : " + parts.joined(separator: " ; ")
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

/// The week's trips, beside its dates: the first trip's name in a faint primary capsule — the
/// inline tag's family, raised to a control. It opens the coach's memory, where trips live.
struct PlanTravelChip: View {
    let trips: [CoachMemoryEntry]
    let onOpen: () -> Void

    var body: some View {
        if let title = PlanTravel.chipTitle(trips) {
            Button(action: onOpen) {
                HStack(spacing: SharpitSpacing.xxs) {
                    Image(systemName: "mappin.and.ellipse")
                        .imageScale(.small)
                    Text(title)
                        .lineLimit(1)
                }
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.primary)
                .padding(.horizontal, SharpitSpacing.xs)
                .padding(.vertical, SharpitSpacing.xxs)
                .background(SharpitColor.primary.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.sharpitPressable)
            .frame(maxWidth: 180, alignment: .trailing)
            .accessibilityLabel(PlanTravel.accessibilityLabel(trips))
            .accessibilityHint("Ouvre la mémoire du coach")
        }
    }
}

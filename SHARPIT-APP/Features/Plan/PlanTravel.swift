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

    /// Whether a trip runs past the days shown, on either side: its rail then comes in from, or
    /// leaves by, the week's edge instead of stopping on a day.
    static func overflow(
        of trip: CoachMemoryEntry,
        beyond days: [Date],
        calendar: Calendar = .current
    ) -> (before: Bool, after: Bool) {
        guard let first = days.min(), let last = days.max() else { return (false, false) }
        return (
            dayKey(trip.startDate, in: utc) < dayKey(first, in: calendar),
            dayKey(trip.endDate, in: utc) > dayKey(last, in: calendar)
        )
    }

    /// Above a trip's name, as a day stands above its session: the place when the trip has a name
    /// of its own, « Déplacement » when the place is the name, then its days.
    static func overline(_ trip: CoachMemoryEntry) -> String {
        let label = trip.label ?? ""
        let place = trip.locationLabel ?? ""
        var parts: [String] = []
        if !label.isEmpty, !place.isEmpty, label != place {
            parts.append(place)
        } else if !label.isEmpty || !place.isEmpty {
            parts.append(CoachMemoryType.travel.shortLabel)
        }
        parts.append(trip.formattedDateRange)
        return parts.joined(separator: " · ")
    }

    /// « Course et Mobilité seulement » when the trip narrows the sports; nil when the badge
    /// already says it all (normal, lighter, mobility alone, a pause).
    static func sports(_ trip: CoachMemoryEntry) -> String? {
        let listed = AllowedDiscipline.allCases.filter { (trip.allowedDisciplines ?? []).contains($0.rawValue) }
        guard !listed.isEmpty, listed.count < AllowedDiscipline.allCases.count, listed != [.mobility],
              trip.trainingConstraint != .none
        else { return nil }
        let names = listed.map(\.label).formatted(.list(type: .and).locale(AppLanguage.locale))
        return String(localized: "\(names) seulement")
    }

    /// What VoiceOver reads: each trip, its days and what training becomes.
    static func accessibilityLabel(_ trips: [CoachMemoryEntry]) -> String {
        let parts = trips.map { trip in
            ([trip.displayTitle, trip.formattedDateRange, trip.trainingConstraint.label] + [sports(trip)].compactMap { $0 })
                .joined(separator: ", ")
        }
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

/// A trip's stop on the week's rail, above its first day shown: when and where over its name, as
/// a day stands over its session, and what training becomes at the end. The rail runs in ink from
/// here down the days away. It opens the list of trips, where they live.
struct PlanTripStop: View {
    let trip: CoachMemoryEntry
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PlanTravel.overline(trip))
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                    Text(trip.displayTitle)
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let sports = PlanTravel.sports(trip) {
                        Text(sports)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(SharpitColor.slate)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    // Beside the name it would squeeze it to a word at the largest sizes.
                    if dynamicTypeSize.isAccessibilitySize { badge }
                }
                Spacer(minLength: SharpitSpacing.xs)
                if !dynamicTypeSize.isAccessibilitySize { badge }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(PlanTravel.accessibilityLabel([trip]))
        .accessibilityHint("Ouvre tes déplacements")
    }

    /// Said only when the trip changes training: a trip that changes nothing carries no word.
    @ViewBuilder private var badge: some View {
        if trip.trainingConstraint != .full {
            CliniqueStatusPill(trip.trainingConstraint.badgeText, status: .unknown)
        }
    }
}

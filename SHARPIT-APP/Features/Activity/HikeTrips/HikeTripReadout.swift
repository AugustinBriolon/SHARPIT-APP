import Foundation

/// How a séjour and its stages are written — the web's `buildHikeTripListMeta` and
/// `buildHikeTripMemberMeta`, in the app's French figures. Kept apart from the views so it is tested.
nonisolated enum HikeTripReadout {
    private static let french = Locale(identifier: "fr_FR")

    /// « 3 étapes », « 1 étape »; nothing for an empty trip.
    static func stepCount(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) étape\(count > 1 ? "s" : "")"
    }

    /// « 12,4 km » from a kilometre on, « 850 m » below.
    static func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? "\(SharpitFigureFormat.kilometers(meters / 1_000)) km"
            : "\(Int(meters.rounded())) m"
    }

    /// « D+ 640 m ».
    static func elevationGain(_ meters: Double) -> String {
        "D+ \(Int(meters.rounded()).formatted(.number.locale(french))) m"
    }

    /// The web's `formatDayRange`: « 5 oct. 2026 » for one day, « 3 – 5 oct. 2026 » within a
    /// month, « 28 sept. – 2 oct. 2026 » across two.
    static func dayRange(from start: Date, to end: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let full = formatter("d MMM yyyy", timeZone: timeZone).string(from: end)
        if calendar.isDate(start, inSameDayAs: end) { return full }
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let head = formatter(sameMonth ? "d" : "d MMM", timeZone: timeZone).string(from: start)
        return "\(head) – \(full)"
    }

    /// The list row's line: the days, the stages, the distance — duration and D+ are one tap away.
    static func listMeta(_ summary: HikeTripSummary, timeZone: TimeZone = .current) -> [String] {
        var meta: [String] = []
        if let start = summary.startAt, let end = summary.endAt {
            meta.append(dayRange(from: start, to: end, timeZone: timeZone))
        }
        if let steps = stepCount(summary.memberCount) { meta.append(steps) }
        if let distance = summary.distanceM, distance > 0 { meta.append(self.distance(distance)) }
        return meta
    }

    /// A stage's line: its day, then each measure it has.
    static func memberMeta(_ member: V1HikeTripMember, timeZone: TimeZone = .current) -> [String] {
        var meta = [formatter("EEE d MMM", timeZone: timeZone).string(from: member.date)]
        if let distance = member.distanceM, distance > 0 { meta.append(self.distance(distance)) }
        if let gain = member.elevationM, gain > 0 { meta.append(elevationGain(gain)) }
        if let duration = member.duration, duration > 0 {
            meta.append(SharpitFigureFormat.duration(minutes: duration / 60))
        }
        return meta
    }

    /// The places walked through, in order: « Ceillac → Saint-Véran → Abriès ».
    static func waypoints(_ labels: [String]) -> String? {
        labels.isEmpty ? nil : labels.joined(separator: " → ")
    }

    /// What the picker says under its hikes while a séjour is being made: at least two.
    static func selectionFooter(selected: Int) -> String {
        switch selected {
        case 0: "Choisis au moins deux randonnées."
        case 1: "1 randonnée choisie — il en faut au moins deux."
        default: "\(selected) randonnées seront liées à ce séjour."
        }
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

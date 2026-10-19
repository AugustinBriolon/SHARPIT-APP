import Foundation

/// A raced session read against its goal: the final time, how far it landed from the target,
/// and its legs as shares of the whole. Résumé's race card and the session page draw the same one.
nonisolated struct RaceResultModel: Sendable, Equatable {
    var durationSec: Double
    var delta: RaceDelta?
    var segments: [RaceLegSegment]

    /// « 2:26:48 · −3:12 vs objectif », or the time alone when the aim names none.
    var summaryLine: String {
        [RaceTime.clock(durationSec), delta?.label].compactMap { $0 }.joined(separator: " · ")
    }

    var spokenSummary: String {
        [String(localized: "Temps final \(RaceTime.spoken(durationSec))"), delta?.spokenLabel].compactMap { $0 }.joined(separator: ", ")
    }

    /// Nil without a time to show: the legs' sum stands in when the session carries none.
    static func make(durationSec: Double?, legs: [V1MultisportLeg], targetPerformance: String?) -> RaceResultModel? {
        let legsTotal = legs.reduce(0) { $0 + max($1.durationSec, 0) }
        guard let total = durationSec.flatMap({ $0 > 0 ? $0 : nil }) ?? (legsTotal > 0 ? legsTotal : nil) else {
            return nil
        }
        return RaceResultModel(
            durationSec: total,
            delta: RaceTime.targetSeconds(from: targetPerformance).map { RaceDelta(seconds: total - $0) },
            segments: RaceLegsTimeline.segments(legs)
        )
    }
}

/// The final time against the target: negative when faster.
nonisolated struct RaceDelta: Sendable, Equatable {
    let seconds: Double

    var isAhead: Bool { seconds <= 0 }

    /// « −3:12 vs objectif », « +1:05 vs objectif ».
    var label: String {
        String(localized: "\(isAhead ? "−" : "+")\(RaceTime.clock(abs(seconds))) vs objectif")
    }

    var spokenLabel: String {
        String(localized: "\(RaceTime.spoken(abs(seconds))) \(isAhead ? "sous" : "au-dessus de") l’objectif")
    }
}

/// One stretch of a race as the legs bar draws it: a sport, or a transition between two.
nonisolated struct RaceLegSegment: Sendable, Equatable, Identifiable {
    let id: Int
    /// Nil for a transition.
    let sport: V1ActivityType?
    /// « Natation », « T1 », « Vélo », « T2 », « Course ».
    let label: String
    let durationSec: Double
    /// Share of the race, the segments summing to one.
    let fraction: Double

    var isTransition: Bool { sport == nil }
}

nonisolated enum RaceLegsTimeline {
    /// The legs in order, each with its share of the total; empty when nothing was timed.
    static func segments(_ legs: [V1MultisportLeg]) -> [RaceLegSegment] {
        let timed = legs.filter { $0.durationSec > 0 }
        let total = timed.reduce(0) { $0 + $1.durationSec }
        guard total > 0 else { return [] }
        var transitions = 0
        return timed.enumerated().map { index, leg in
            let isTransition = leg.kind == "transition"
            if isTransition { transitions += 1 }
            let sport: V1ActivityType? = isTransition ? nil : leg.activityType
            return RaceLegSegment(
                id: index,
                sport: sport,
                label: isTransition ? "T\(transitions)" : (sport == .other ? leg.label : sport?.label ?? leg.label),
                durationSec: leg.durationSec,
                fraction: leg.durationSec / total
            )
        }
    }

    /// Each segment's drawn width in `width`, gaps taken out: a segment narrower than `minimum`
    /// is drawn at `minimum`, and the others share what is left in proportion, so the bar
    /// still fills its width exactly.
    static func widths(_ segments: [RaceLegSegment], in width: Double, minimum: Double, gap: Double) -> [Double] {
        let available = max(width - gap * Double(max(segments.count - 1, 0)), 0)
        let isPinned = segments.map { $0.fraction * available < minimum }
        let pinnedCount = Double(isPinned.filter { $0 }.count)
        let freeShare = zip(segments, isPinned).filter { !$1 }.reduce(0) { $0 + $1.0.fraction }
        let freeWidth = available - minimum * pinnedCount
        guard freeShare > 0, freeWidth > 0 else { return segments.map { $0.fraction * available } }
        return zip(segments, isPinned).map { segment, pinned in
            pinned ? minimum : freeWidth * segment.fraction / freeShare
        }
    }
}

nonisolated enum RaceTime {
    /// « 2:26:48 », « 26:48 », « 0:45 ».
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// The same time in words, for VoiceOver: « 2 heures, 26 minutes et 48 secondes ».
    static func spoken(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds.rounded())).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide)
                .locale(AppLanguage.locale)
        )
    }

    /// The target time a goal's free-text performance names — « Sub 2h30 », « 2:28:00 »,
    /// « 45:30 », « 1h05'30 », « 50 min » — or nil when it names none (« Finir », « Top 10 »).
    static func targetSeconds(from performance: String?) -> Double? {
        guard let text = performance?.lowercased(), !text.isEmpty else { return nil }
        if let match = text.firstMatch(of: /(\d{1,2}):(\d{2}):(\d{2})/) {
            return seconds(hours: match.1, minutes: match.2, seconds: match.3)
        }
        if let match = text.firstMatch(of: /(\d{1,2})\s*h\s*(\d{1,2})?(?:\s*(?:'|m|min|:)\s*(\d{1,2}))?/) {
            return seconds(hours: match.1, minutes: match.2, seconds: match.3)
        }
        if let match = text.firstMatch(of: /(\d{1,3}):(\d{2})/) {
            return seconds(hours: nil, minutes: match.1, seconds: match.2)
        }
        if let match = text.firstMatch(of: /(\d{1,3})\s*min/) {
            return seconds(hours: nil, minutes: match.1, seconds: nil)
        }
        return nil
    }

    private static func seconds(hours: Substring?, minutes: Substring?, seconds: Substring?) -> Double? {
        let h = hours.flatMap { Double($0) } ?? 0
        let m = minutes.flatMap { Double($0) } ?? 0
        let s = seconds.flatMap { Double($0) } ?? 0
        let total = h * 3_600 + m * 60 + s
        return total > 0 ? total : nil
    }
}

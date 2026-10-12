import Foundation

/// One leg of the race as « Par rapport à l'objectif » lists it.
struct RaceLegRow: Sendable, Equatable, Identifiable {
    let id: Int
    let segment: RaceLegSegment
    /// « 1,9 km · FC moy 142 »; nil for a transition with nothing more to say.
    let detail: String?
    /// The leg's own recording, which the row opens.
    let sourceActivityId: String?
}

/// One leg's heart rate, zone by zone.
struct RaceZoneRow: Sendable, Equatable, Identifiable {
    let id: Int
    let label: String
    /// Share of the leg in each of the five zones, summing to one.
    let shares: [Double]
    let averageLine: String?
    let spokenLabel: String
}

/// How the race blocks word the server's `raceAnalysis`: the figures are the server's, this only
/// says them.
enum RaceAnalysisReadout {
    private static let french = Locale(identifier: "fr_FR")

    static func objectiveTitle(_ analysis: V1RaceAnalysis) -> String {
        analysis.target?.seconds != nil ? "Par rapport à l'objectif" : "Enchaînement"
    }

    /// « 5:40:03 · +10:03 vs objectif Sub 5h30 », or the time alone without a target.
    static func totalLine(_ analysis: V1RaceAnalysis) -> String {
        let time = RaceTime.clock(analysis.total.seconds)
        guard let delta = analysis.total.deltaSec else { return time }
        let target = analysis.target?.label.map { " \($0)" } ?? ""
        return "\(time) · \(RaceDelta(seconds: delta).label)\(target)"
    }

    static func segments(_ analysis: V1RaceAnalysis) -> [RaceLegSegment] {
        RaceLegsTimeline.segments(analysis.legs.map(\.multisportLeg))
    }

    static func legRows(_ analysis: V1RaceAnalysis) -> [RaceLegRow] {
        legRows(analysis.legs.map(\.multisportLeg))
    }

    /// The same rows from a session's own legs, when the server sent no race reading.
    static func legRows(_ legs: [V1MultisportLeg]) -> [RaceLegRow] {
        let timed = legs.filter { $0.durationSec > 0 }
        return zip(timed, RaceLegsTimeline.segments(legs)).map { leg, segment in
            let parts = [leg.distanceM.map(distance), leg.avgHr.map { "FC moy \(Int($0.rounded()))" }].compactMap { $0 }
            return RaceLegRow(
                id: segment.id,
                segment: segment,
                detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
                sourceActivityId: leg.sourceActivityId
            )
        }
    }

    static func zoneRows(_ analysis: V1RaceAnalysis) -> [RaceZoneRow] {
        let labelled = zip(analysis.legs.filter { $0.durationSec > 0 }, segments(analysis))
        return labelled.compactMap { leg, segment in
            guard !leg.isTransition, let zones = leg.hrZonesSec, zones.count == 5 else { return nil }
            let total = zones.reduce(0, +)
            guard total > 0 else { return nil }
            let shares = zones.map { $0 / total }
            let spoken = shares.enumerated()
                .map { "zone \($0.offset + 1) \(Int(($0.element * 100).rounded())) %" }
                .joined(separator: ", ")
            return RaceZoneRow(
                id: segment.id,
                label: segment.label,
                shares: shares,
                averageLine: leg.avgHr.map { "FC moy \(Int($0.rounded()))" },
                spokenLabel: "\(segment.label) : \(spoken)"
            )
        }
    }

    /// Each leg's first half against its second, then the run's cardiac drift.
    static func effortRows(_ analysis: V1RaceAnalysis) -> [ActivityTechnicalRow] {
        let labelled = zip(analysis.legs.filter { $0.durationSec > 0 }, segments(analysis))
        var rows: [ActivityTechnicalRow] = labelled.compactMap { leg, segment in
            guard let pacing = leg.pacing else { return nil }
            return ActivityTechnicalRow(
                label: segment.label,
                value: "\(pace(pacing.firstHalf, pacing.unit)) → \(pace(pacing.secondHalf, pacing.unit))",
                note: "\(unitLabel(pacing.unit)) · \(changeNote(pacing.changePct))"
            )
        }
        if let drift = analysis.runHrDriftPct {
            rows.append(ActivityTechnicalRow(
                label: "Dérive cardiaque",
                value: "\(drift > 0 ? "+" : "")\(percent(drift)) %",
                note: ActivityTechnicalReadout.decouplingNote(abs(drift))
            ))
        }
        return rows
    }

    static func loadRows(_ analysis: V1RaceAnalysis, isExpertReading: Bool) -> [ActivityTechnicalRow] {
        var rows: [ActivityTechnicalRow] = []
        if let tss = analysis.load?.tss {
            rows.append(ActivityTechnicalRow(label: isExpertReading ? "TSS" : "Charge", value: "\(Int(tss.rounded()))"))
        }
        if let hours = analysis.load?.recoveryHours, hours > 0 {
            rows.append(ActivityTechnicalRow(label: "Récupération", value: "≈ \(Int(hours.rounded())) h"))
        }
        return rows
    }

    /// « Allure tenue » within 2 %, else which way the second half went.
    static func changeNote(_ changePct: Double) -> String {
        if abs(changePct) < 2 { return "Allure tenue" }
        let amount = "\(percent(abs(changePct))) %"
        return changePct > 0 ? "Ralenti de \(amount) en 2e moitié" : "Accéléré de \(amount) en 2e moitié"
    }

    static func pace(_ value: Double, _ unit: V1RaceAnalysis.Pacing.Unit) -> String {
        switch unit {
        case .kmh: value.formatted(.number.precision(.fractionLength(1)).locale(french))
        case .secPer100m, .secPerKm: RaceTime.clock(value)
        }
    }

    /// The unit sits in the note, so the two halves stay on one line in the grid.
    private static func unitLabel(_ unit: V1RaceAnalysis.Pacing.Unit) -> String {
        switch unit {
        case .kmh: "km/h"
        case .secPer100m: "/100 m"
        case .secPerKm: "/km"
        }
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(french))
    }

    private static func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(french))) km"
            : "\(Int(meters.rounded())) m"
    }
}

extension V1RaceAnalysis.Leg {
    /// The shape the legs bar reads.
    nonisolated var multisportLeg: V1MultisportLeg {
        V1MultisportLeg(
            kind: kind, label: label, durationSec: durationSec, movingDurationSec: nil, distanceM: distanceM,
            avgHr: avgHr, avgSpeedMs: nil, elevationM: nil, calories: nil, transitionIndex: nil,
            sourceActivityId: sourceActivityId
        )
    }
}

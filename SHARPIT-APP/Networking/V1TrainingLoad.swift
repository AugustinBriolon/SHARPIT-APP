import Foundation

/// `GET /api/v1/training-load` — mirrors `projectV1TrainingLoad` in the web repository: fitness
/// (CTL), fatigue (ATL) and form (TSB) per day over six weeks, and eight weeks of load totals.
nonisolated struct V1TrainingLoad: Decodable, Sendable, Equatable {
    nonisolated struct Day: Decodable, Sendable, Equatable, Identifiable {
        var date: String
        var tss: Double
        var ctl: Double
        var atl: Double
        var tsb: Double

        var id: String { date }
    }

    nonisolated struct Week: Decodable, Sendable, Equatable, Identifiable {
        var weekEnd: String
        var tss: Double

        var id: String { weekEnd }
    }

    var trainingDayId: String
    var days: [Day]
    var weeks: [Week]
}

nonisolated protocol TrainingLoadServing: Sendable {
    func trainingLoad(trainingDayId: String, token: String) async throws -> V1TrainingLoad
}

/// How the expert reading names the load — the web's Effort words and its form band.
enum TrainingLoadReadout {
    /// The web's `FORM_BAND`: net form usually sits between −20 and +10.
    static let formBand: ClosedRange<Double> = -20...10

    static func isInFormBand(_ tsb: Double) -> Bool { formBand.contains(tsb) }

    /// « +4 », « −12 », « 0 » — with a true minus.
    static func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : rounded < 0 ? "−\(-rounded)" : "0"
    }
}

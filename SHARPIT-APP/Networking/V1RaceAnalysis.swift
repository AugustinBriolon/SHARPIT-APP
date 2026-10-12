import Foundation

/// A raced session read leg by leg (`raceAnalysis` on `/api/v1/activities/[id]`): the time
/// against the target, each leg's heart-rate zones and pacing, the run's drift, the load.
/// Absent for anything but a triathlon or a session linked to a goal, and on older servers.
nonisolated struct V1RaceAnalysis: Decodable, Sendable, Equatable {
    struct Target: Decodable, Sendable, Equatable {
        var label: String?
        var seconds: Double?
    }

    struct Total: Decodable, Sendable, Equatable {
        var seconds: Double
        var deltaSec: Double?
    }

    struct Pacing: Decodable, Sendable, Equatable {
        enum Unit: String, Decodable, Sendable {
            case secPer100m = "sec_per_100m"
            case kmh
            case secPerKm = "sec_per_km"
        }

        var unit: Unit
        var firstHalf: Double
        var secondHalf: Double
        /// Positive when the second half was slower, whatever the unit.
        var changePct: Double
    }

    struct Leg: Decodable, Sendable, Equatable {
        var kind: String
        var label: String
        var durationSec: Double
        var distanceM: Double?
        var sourceActivityId: String?
        var avgHr: Double?
        /// Seconds in each of the athlete's five zones; nil without a heart-rate stream.
        var hrZonesSec: [Double]?
        var pacing: Pacing?

        var isTransition: Bool { kind == "transition" }

        enum CodingKeys: String, CodingKey {
            case kind, label, durationSec, distanceM, sourceActivityId, avgHr, hrZonesSec, pacing
        }

        init(
            kind: String, label: String, durationSec: Double, distanceM: Double? = nil,
            sourceActivityId: String? = nil, avgHr: Double? = nil, hrZonesSec: [Double]? = nil, pacing: Pacing? = nil
        ) {
            self.kind = kind
            self.label = label
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.sourceActivityId = sourceActivityId
            self.avgHr = avgHr
            self.hrZonesSec = hrZonesSec
            self.pacing = pacing
        }

        /// A leg the server sent half-formed keeps what it has: a pacing or zones it could not
        /// read are dropped, not the leg.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            label = try container.decode(String.self, forKey: .label)
            durationSec = try container.decode(Double.self, forKey: .durationSec)
            distanceM = try? container.decodeIfPresent(Double.self, forKey: .distanceM)
            sourceActivityId = try? container.decodeIfPresent(String.self, forKey: .sourceActivityId)
            avgHr = try? container.decodeIfPresent(Double.self, forKey: .avgHr)
            hrZonesSec = try? container.decodeIfPresent([Double].self, forKey: .hrZonesSec)
            pacing = try? container.decodeIfPresent(Pacing.self, forKey: .pacing)
        }
    }

    struct Load: Decodable, Sendable, Equatable {
        var tss: Double?
        var recoveryHours: Double?
    }

    var target: Target?
    var total: Total
    var legs: [Leg]
    var runHrDriftPct: Double?
    var load: Load?

    enum CodingKeys: String, CodingKey {
        case target, total, legs, runHrDriftPct, load
    }

    init(target: Target? = nil, total: Total, legs: [Leg], runHrDriftPct: Double? = nil, load: Load? = nil) {
        self.target = target
        self.total = total
        self.legs = legs
        self.runHrDriftPct = runHrDriftPct
        self.load = load
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try? container.decodeIfPresent(Target.self, forKey: .target)
        total = try container.decode(Total.self, forKey: .total)
        legs = (try? container.decodeIfPresent(LossyRecordArray<Leg>.self, forKey: .legs))?.items ?? []
        runHrDriftPct = try? container.decodeIfPresent(Double.self, forKey: .runHrDriftPct)
        load = try? container.decodeIfPresent(Load.self, forKey: .load)
    }
}

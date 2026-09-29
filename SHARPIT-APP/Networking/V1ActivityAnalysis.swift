import Foundation

/// The technical reading of a recorded session, as the server computes it from the streams —
/// the web's `ActivityAnalysis`, sent with `/api/v1/activities/<id>/streams`. The app reads
/// it, never recomputes it: thresholds, zones and drift live on the server.
///
/// Every block is optional and decoded on its own, so a field the server adds or drops never
/// costs the athlete the streams it came with.
nonisolated struct V1ActivityAnalysis: Decodable, Sendable, Equatable {
    nonisolated struct Thresholds: Decodable, Sendable, Equatable {
        var ftp: Double?
        var maxHr: Double?
        var lthr: Double?
        /// `profile` when the athlete set them, `estimate` when the server inferred them.
        var source: String?
    }

    nonisolated struct Load: Decodable, Sendable, Equatable {
        var tss: Double?
        var intensityFactor: Double?
        /// `power` or `hr`: what the load was computed from.
        var method: String?
    }

    nonisolated struct Zone: Decodable, Sendable, Equatable, Identifiable {
        var id: String
        var label: String
        var shortLabel: String
        var seconds: Double
        var percent: Double
    }

    nonisolated struct HeartRate: Decodable, Sendable, Equatable {
        var zones: [Zone]
        var decouplingPct: Double?
        var efficiencyFactor: Double?
        var efficiencyLabel: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            zones = (try? container.decode([Zone].self, forKey: .zones)) ?? []
            decouplingPct = try? container.decodeIfPresent(Double.self, forKey: .decouplingPct)
            efficiencyFactor = try? container.decodeIfPresent(Double.self, forKey: .efficiencyFactor)
            efficiencyLabel = try? container.decodeIfPresent(String.self, forKey: .efficiencyLabel)
        }

        init(zones: [Zone] = [], decouplingPct: Double? = nil, efficiencyFactor: Double? = nil, efficiencyLabel: String? = nil) {
            self.zones = zones
            self.decouplingPct = decouplingPct
            self.efficiencyFactor = efficiencyFactor
            self.efficiencyLabel = efficiencyLabel
        }

        enum CodingKeys: String, CodingKey { case zones, decouplingPct, efficiencyFactor, efficiencyLabel }
    }

    nonisolated struct Power: Decodable, Sendable, Equatable {
        var normalized: Double?
        var avg: Double?
        var variabilityIndex: Double?
        var zones: [Zone]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            normalized = try? container.decodeIfPresent(Double.self, forKey: .normalized)
            avg = try? container.decodeIfPresent(Double.self, forKey: .avg)
            variabilityIndex = try? container.decodeIfPresent(Double.self, forKey: .variabilityIndex)
            zones = (try? container.decode([Zone].self, forKey: .zones)) ?? []
        }

        init(normalized: Double? = nil, avg: Double? = nil, variabilityIndex: Double? = nil, zones: [Zone] = []) {
            self.normalized = normalized
            self.avg = avg
            self.variabilityIndex = variabilityIndex
            self.zones = zones
        }

        enum CodingKeys: String, CodingKey { case normalized, avg, variabilityIndex, zones }
    }

    nonisolated struct Run: Decodable, Sendable, Equatable {
        var paceVariabilityPct: Double?
    }

    var thresholds: Thresholds?
    var load: Load?
    var hr: HeartRate?
    var power: Power?
    var run: Run?

    init(thresholds: Thresholds? = nil, load: Load? = nil, hr: HeartRate? = nil, power: Power? = nil, run: Run? = nil) {
        self.thresholds = thresholds
        self.load = load
        self.hr = hr
        self.power = power
        self.run = run
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thresholds = try? container.decodeIfPresent(Thresholds.self, forKey: .thresholds)
        load = try? container.decodeIfPresent(Load.self, forKey: .load)
        hr = try? container.decodeIfPresent(HeartRate.self, forKey: .hr)
        power = try? container.decodeIfPresent(Power.self, forKey: .power)
        run = try? container.decodeIfPresent(Run.self, forKey: .run)
    }

    enum CodingKeys: String, CodingKey { case thresholds, load, hr, power, run }
}

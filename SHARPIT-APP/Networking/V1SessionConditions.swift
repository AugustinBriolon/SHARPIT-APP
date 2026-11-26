import Foundation

/// What the forecast asks of a planned session — the server's `environmentContext`, resolved from
/// Open-Meteo and kept fresh by its `planned-forecast` cron (`docs/adr/0041`). The app never reads
/// weather itself.
///
/// Only the advisories that change something the athlete does are kept: the server's
/// « conditions favorables », « séance en intérieur », « prévision indisponible » and the location
/// question have nothing to act on here.
nonisolated enum V1SessionAdvisory: String, Sendable, Hashable, CaseIterable {
    case reduceIntensity = "REDUCE_INTENSITY"
    case shiftEarlier = "SHIFT_EARLIER"
    case hydration = "HYDRATION"
    case indoorAlternative = "INDOOR_ALTERNATIVE"
    case recoveryDemand = "RECOVERY_DEMAND"
    case rainRisk = "RAIN_RISK"
    case coldRisk = "COLD_RISK"
}

/// The advisories of a session's `environmentContext`, in the server's order (most pressing first).
nonisolated struct V1SessionConditions: Decodable, Sendable, Hashable {
    let advisories: [V1SessionAdvisory]

    init(advisories: [V1SessionAdvisory]) {
        self.advisories = advisories
    }

    private enum CodingKeys: String, CodingKey { case advisories }
    private struct RawAdvisory: Decodable { let kind: String }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decodeIfPresent([RawAdvisory].self, forKey: .advisories)) ?? []
        var seen = Set<V1SessionAdvisory>()
        advisories = raw.compactMap { V1SessionAdvisory(rawValue: $0.kind) }.filter { seen.insert($0).inserted }
    }
}

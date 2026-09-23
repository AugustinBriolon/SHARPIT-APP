import Foundation

/// One weigh-in, as `/api/body-composition` returns it.
///
/// The row holds far more than this — Withings Body Scan writes vascular age, pulse wave
/// velocity, nerve health. The app decodes the composition an athlete reads on a phone and
/// leaves the clinical annex to the web, which has the room to explain it.
nonisolated struct V1BodyMeasurement: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let measuredAt: Date
    /// `garmin`, `withings`, `renpho`, `manual` — which scale wrote it.
    let source: String?
    let weightKg: Double?
    let bodyFatPct: Double?
    let musclePct: Double?
    let waterPct: Double?
    let boneKg: Double?
    let bmi: Double?

    private enum CodingKeys: String, CodingKey {
        case id, measuredAt, source, weightKg, bodyFatPct, musclePct, waterPct, boneKg, bmi
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        measuredAt = try Date.fromAPI(try container.decode(String.self, forKey: .measuredAt))
        source = try container.decodeIfPresent(String.self, forKey: .source)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyFatPct = try container.decodeIfPresent(Double.self, forKey: .bodyFatPct)
        musclePct = try container.decodeIfPresent(Double.self, forKey: .musclePct)
        waterPct = try container.decodeIfPresent(Double.self, forKey: .waterPct)
        boneKg = try container.decodeIfPresent(Double.self, forKey: .boneKg)
        bmi = try container.decodeIfPresent(Double.self, forKey: .bmi)
    }

    init(
        id: String,
        measuredAt: Date,
        source: String? = nil,
        weightKg: Double? = nil,
        bodyFatPct: Double? = nil,
        musclePct: Double? = nil,
        waterPct: Double? = nil,
        boneKg: Double? = nil,
        bmi: Double? = nil
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.source = source
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.musclePct = musclePct
        self.waterPct = waterPct
        self.boneKg = boneKg
        self.bmi = bmi
    }

    /// Written only for the app's own cache (`docs/adr/0007`); the server never reads it back.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(measuredAt.toAPI, forKey: .measuredAt)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(weightKg, forKey: .weightKg)
        try container.encodeIfPresent(bodyFatPct, forKey: .bodyFatPct)
        try container.encodeIfPresent(musclePct, forKey: .musclePct)
        try container.encodeIfPresent(waterPct, forKey: .waterPct)
        try container.encodeIfPresent(boneKg, forKey: .boneKg)
        try container.encodeIfPresent(bmi, forKey: .bmi)
    }
}

/// A threshold as it stood when something wrote it — the evidence behind the current value.
nonisolated struct V1ThresholdSnapshot: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    /// `estimated`, `garmin` or `manual`.
    let source: String
    let ftpW: Int?
    let lthr: Int?
    let runThresholdPaceSecPerKm: Double?
    let swimCssSecPer100m: Double?

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, source, ftpW, lthr, runThresholdPaceSecPerKm, swimCssSecPer100m
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try Date.fromAPI(try container.decode(String.self, forKey: .createdAt))
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        ftpW = try container.decodeIfPresent(Int.self, forKey: .ftpW)
        lthr = try container.decodeIfPresent(Int.self, forKey: .lthr)
        runThresholdPaceSecPerKm = try container.decodeIfPresent(Double.self, forKey: .runThresholdPaceSecPerKm)
        swimCssSecPer100m = try container.decodeIfPresent(Double.self, forKey: .swimCssSecPer100m)
    }

    init(
        id: String,
        createdAt: Date,
        source: String,
        ftpW: Int? = nil,
        lthr: Int? = nil,
        runThresholdPaceSecPerKm: Double? = nil,
        swimCssSecPer100m: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.ftpW = ftpW
        self.lthr = lthr
        self.runThresholdPaceSecPerKm = runThresholdPaceSecPerKm
        self.swimCssSecPer100m = swimCssSecPer100m
    }

    /// Who set it, in the athlete's words.
    var sourceLabel: String {
        switch source {
        case "garmin": "Importé de Garmin"
        case "estimated": "Estimé"
        default: "Saisi à la main"
        }
    }
}

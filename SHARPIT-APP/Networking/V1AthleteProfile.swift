import Foundation

/// The athlete's stable attributes, as `/api/athlete-profile` returns them.
///
/// Read as a whole, written one field at a time — see `AthleteProfilePatch`. The row holds
/// more than this (equipment, journal preferences, practiced sports, consents); the app
/// decodes what it renders and never sends back what it did not read.
nonisolated struct V1AthleteProfile: Decodable, Sendable, Equatable {
    /// Reading density: `essential` or `expert`.
    var displayMode: String?
    var tier: String?

    // Identity and rhythm.
    var heightCm: Int?
    var birthDate: Date?
    var targetWeightKg: Double?
    var sleepTargetMinutes: Int?
    /// Minutes after local midnight, as the server stores them.
    var sleepBedtimeTargetMin: Int?

    // Thresholds — the yardstick load is read against.
    var ftpW: Int?
    var maxHr: Int?
    var lthr: Int?
    var runThresholdPaceSecPerKm: Double?
    var swimCssSecPer100m: Double?
    var defaultPoolLengthM: Int?
    var vo2maxRunning: Int?
    var vo2maxCycling: Int?
    var thresholdsSyncedAt: Date?

    var isExpertReading: Bool { displayMode == AthleteProfileField.expertDisplayMode }
    var isPro: Bool { tier == "PRO" }

    init(
        displayMode: String? = nil,
        tier: String? = nil,
        heightCm: Int? = nil,
        birthDate: Date? = nil,
        targetWeightKg: Double? = nil,
        sleepTargetMinutes: Int? = nil,
        sleepBedtimeTargetMin: Int? = nil,
        ftpW: Int? = nil,
        maxHr: Int? = nil,
        lthr: Int? = nil,
        runThresholdPaceSecPerKm: Double? = nil,
        swimCssSecPer100m: Double? = nil,
        defaultPoolLengthM: Int? = nil,
        vo2maxRunning: Int? = nil,
        vo2maxCycling: Int? = nil,
        thresholdsSyncedAt: Date? = nil
    ) {
        self.displayMode = displayMode
        self.tier = tier
        self.heightCm = heightCm
        self.birthDate = birthDate
        self.targetWeightKg = targetWeightKg
        self.sleepTargetMinutes = sleepTargetMinutes
        self.sleepBedtimeTargetMin = sleepBedtimeTargetMin
        self.ftpW = ftpW
        self.maxHr = maxHr
        self.lthr = lthr
        self.runThresholdPaceSecPerKm = runThresholdPaceSecPerKm
        self.swimCssSecPer100m = swimCssSecPer100m
        self.defaultPoolLengthM = defaultPoolLengthM
        self.vo2maxRunning = vo2maxRunning
        self.vo2maxCycling = vo2maxCycling
        self.thresholdsSyncedAt = thresholdsSyncedAt
    }

    private enum CodingKeys: String, CodingKey {
        case displayMode, tier, heightCm, birthDate, targetWeightKg
        case sleepTargetMinutes, sleepBedtimeTargetMin
        case ftpW, maxHr, lthr, runThresholdPaceSecPerKm, swimCssSecPer100m
        case defaultPoolLengthM, vo2maxRunning, vo2maxCycling, thresholdsSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode)
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        heightCm = try container.decodeIfPresent(Int.self, forKey: .heightCm)
        birthDate = Self.date(in: container, forKey: .birthDate)
        targetWeightKg = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        sleepTargetMinutes = try container.decodeIfPresent(Int.self, forKey: .sleepTargetMinutes)
        sleepBedtimeTargetMin = try container.decodeIfPresent(Int.self, forKey: .sleepBedtimeTargetMin)
        ftpW = try container.decodeIfPresent(Int.self, forKey: .ftpW)
        maxHr = try container.decodeIfPresent(Int.self, forKey: .maxHr)
        lthr = try container.decodeIfPresent(Int.self, forKey: .lthr)
        runThresholdPaceSecPerKm = try container.decodeIfPresent(Double.self, forKey: .runThresholdPaceSecPerKm)
        swimCssSecPer100m = try container.decodeIfPresent(Double.self, forKey: .swimCssSecPer100m)
        defaultPoolLengthM = try container.decodeIfPresent(Int.self, forKey: .defaultPoolLengthM)
        vo2maxRunning = try container.decodeIfPresent(Int.self, forKey: .vo2maxRunning)
        vo2maxCycling = try container.decodeIfPresent(Int.self, forKey: .vo2maxCycling)
        thresholdsSyncedAt = Self.date(in: container, forKey: .thresholdsSyncedAt)
    }

    /// `birthDate` is a Prisma `@db.Date` and serialises as `1990-04-12T00:00:00.000Z`,
    /// while `thresholdsSyncedAt` carries fractional seconds. Both are read leniently, and a
    /// date the app cannot parse is dropped rather than failing the whole profile.
    private static func date(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key), !raw.isEmpty else {
            return nil
        }
        return try? Date.fromAPI(raw)
    }
}

/// The profile fields the app can write, with the server's key for each.
///
/// Named rather than stringly-typed at the call site so a patch cannot invent a key the API
/// would ignore in silence. `vo2max*` and `thresholdsSyncedAt` are absent on purpose: the
/// web's patch validator does not accept them, so they are read and never written — a VO₂max
/// comes from Garmin or from an estimate, never from a field.
nonisolated enum AthleteProfileField: String, CaseIterable, Sendable {
    case displayMode
    case heightCm
    case birthDate
    case targetWeightKg
    case sleepTargetMinutes
    case sleepBedtimeTargetMin
    case ftpW
    case maxHr
    case lthr
    case runThresholdPaceSecPerKm
    case swimCssSecPer100m
    case defaultPoolLengthM

    static let expertDisplayMode = "expert"
    static let essentialDisplayMode = "essential"
}

/// The fields of one save, and nothing else.
///
/// The web's validator is explicit about why this matters: a PATCH that materialised every
/// field it had not been given wrote ten nulls for a one-field save, and that is how a
/// profile lost its thresholds. So an untouched field is *absent* from the body, and only a
/// field the athlete cleared is sent as `null`. A Swift `Codable` struct of optionals cannot
/// express that difference — `encodeIfPresent` drops both — so the body is built key by key.
nonisolated struct AthleteProfilePatch: Equatable, Sendable {
    private(set) var fields: [String: JSONValue] = [:]

    init() {}

    var isEmpty: Bool { fields.isEmpty }

    /// Records a field the athlete changed. `nil` clears it server-side.
    mutating func set(_ field: AthleteProfileField, _ value: JSONValue?) {
        fields[field.rawValue] = value ?? .null
    }

    mutating func set(_ field: AthleteProfileField, int value: Int?) {
        set(field, value.map { JSONValue.number(Double($0)) })
    }

    mutating func set(_ field: AthleteProfileField, double value: Double?) {
        set(field, value.map(JSONValue.number))
    }

    mutating func set(_ field: AthleteProfileField, string value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        set(field, trimmed.flatMap { $0.isEmpty ? nil : JSONValue.string($0) })
    }

    /// Records a field only when it differs from what was loaded, so saving a form the
    /// athlete opened and closed sends nothing at all.
    mutating func setIfChanged(_ field: AthleteProfileField, int value: Int?, was previous: Int?) {
        guard value != previous else { return }
        set(field, int: value)
    }

    mutating func setIfChanged(_ field: AthleteProfileField, double value: Double?, was previous: Double?) {
        guard value != previous else { return }
        set(field, double: value)
    }

    var body: [String: Any] {
        fields.mapValues(\.foundationObject)
    }
}

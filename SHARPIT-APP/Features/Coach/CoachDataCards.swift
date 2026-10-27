import Foundation

/// The coach's data cards (SHARPIT ADR-119): the numbers a read tool measured, returned in the
/// tool's output as `card`. The model writes none of it. The server's zod schema is the contract
/// (`coach-data-cards.ts`); the fixtures in `SHARPIT-APPTests/Fixtures/CoachDataCards` are a copy
/// of the web's, kept identical by its tests.
nonisolated enum CoachDataCard: Decodable, Equatable, Sendable {
    case sleepVsReadiness(windowDays: Int, points: [SleepPoint])
    case dayScores(DayScores)
    case targetBand(trainingDayId: String, band: Band, readiness: Double?)

    /// The contract this build draws. A card stamped with another version is left out.
    static let schemaVersion = 1

    static let toolTypes: Set<String> = [
        "tool-explainDayScores", "tool-explainTargetBand", "tool-compareSleepVsReadiness",
    ]

    struct SleepPoint: Decodable, Equatable, Sendable {
        let trainingDayId: String
        let sleepMinutes: Double?
        let readiness: Double?
    }

    struct Band: Decodable, Equatable, Sendable {
        let low: Double
        let high: Double
        let status: String?
    }

    struct DayScores: Decodable, Equatable, Sendable {
        let trainingDayId: String
        let energyBank: EnergyBank?
        let stress: Double?
        let targetBand: Band?
        let readiness: Double?
    }

    struct EnergyBank: Decodable, Equatable, Sendable {
        let value: Double
        let typicalBaseline: Double?
    }

    private enum Keys: String, CodingKey {
        case kind, windowDays, points, trainingDayId, band, readiness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "sleepVsReadiness":
            self = .sleepVsReadiness(
                windowDays: try container.decode(Int.self, forKey: .windowDays),
                points: try container.decode([SleepPoint].self, forKey: .points)
            )
        case "dayScores":
            self = .dayScores(try DayScores(from: decoder))
        case "targetBand":
            self = .targetBand(
                trainingDayId: try container.decode(String.self, forKey: .trainingDayId),
                band: try container.decode(Band.self, forKey: .band),
                readiness: try container.decodeIfPresent(Double.self, forKey: .readiness)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown card kind")
        }
    }

    /// The card a read tool's part carries, or nil while the tool runs, when it answered without
    /// one, or when it was drawn for another version of the contract.
    init?(part: JSONValue) {
        guard let type = part["type"]?.string, Self.toolTypes.contains(type),
              part["state"]?.string == "output-available",
              part["output"]?["schemaVersion"]?.number.map({ Int($0) == Self.schemaVersion }) ?? false,
              let card = part["output"]?["card"],
              let data = try? JSONEncoder().encode(card),
              let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }
}

/// How a data card words its figures — the markdown's own rounding, in the coach's French.
enum CoachDataCardFormat {
    static func score(_ value: Double) -> String {
        Int(exactly: value.rounded()).map(String.init) ?? "—"
    }

    /// « 6 h 50 », « 7 h 00 ».
    static func sleep(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes >= 0, let total = Int(exactly: minutes.rounded()) else { return "—" }
        return String(format: "%d h %02d", total / 60, total % 60)
    }

    static func band(_ band: CoachDataCard.Band) -> String {
        "\(score(band.low))–\(score(band.high))"
    }

    static func status(_ status: String?) -> String? {
        switch status {
        case "below": String(localized: "sous la cible")
        case "within": String(localized: "dans la cible")
        case "above": String(localized: "au-dessus de la cible")
        default: nil
        }
    }

    /// « lun. 26 » from a `yyyy-MM-dd` day id; the id itself when it does not parse.
    static func day(_ trainingDayId: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: trainingDayId) else { return trainingDayId }
        return date.formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguage.locale))
    }
}

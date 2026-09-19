import Foundation

nonisolated struct V1PlannedSessionItem: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let date: Date
    let title: String?
    let type: String?
    let durationMin: Int?
    let intensity: String?
    let load: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, date, title, type, durationMin, intensity, load, notes
    }

    init(
        id: String,
        date: Date,
        title: String? = nil,
        type: String? = nil,
        durationMin: Int? = nil,
        intensity: String? = nil,
        load: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.type = type
        self.durationMin = durationMin
        self.intensity = intensity
        self.load = load
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try Date.fromPlannedAPI(container.decode(String.self, forKey: .date))
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        intensity = try container.decodeIfPresent(String.self, forKey: .intensity)
        load = try container.decodeIfPresent(Double.self, forKey: .load)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    var displayType: String {
        switch type?.uppercased() {
        case "RUN": "Course"
        case "BIKE": "Vélo"
        case "SWIM": "Natation"
        case "STRENGTH": "Force"
        case "HIKE": "Randonnée"
        case "TRIATHLON": "Triathlon"
        default: type?.capitalized ?? "Séance"
        }
    }

    var symbolName: String {
        switch type?.uppercased() {
        case "RUN": "figure.run"
        case "BIKE": "bicycle"
        case "SWIM": "figure.pool.swim"
        case "STRENGTH": "figure.strengthtraining.traditional"
        case "HIKE": "figure.hiking"
        default: "figure.mind.and.body"
        }
    }
}

private extension Date {
    nonisolated static func fromPlannedAPI(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: value) ?? standard.date(from: value) {
            return date
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: value) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid planned session date"))
    }
}

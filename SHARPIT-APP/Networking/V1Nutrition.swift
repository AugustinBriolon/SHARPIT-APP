import Foundation

/// `GET /api/v1/nutrition` — mirrors `projectV1Nutrition` in the web repository. SharpIt Pro
/// only: below Pro the route answers 403 `pro_required`.
///
/// Every measure decodes as `Double`: the food log sums servings and nothing guarantees
/// whole numbers.
nonisolated struct V1NutritionResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    /// A food log is connected (MyFitnessPal today).
    let connected: Bool
    let empty: V1DayEmpty?
    let day: V1NutritionDay?
    let coachReading: V1NutritionCoachReading?
    /// The diet declared in the journal, as labels.
    let diet: [String]
    /// Oldest first, one entry per day of the week ending on `trainingDayId`.
    let history: [V1NutritionHistoryDay]

    enum CodingKeys: String, CodingKey {
        case apiVersion, trainingDayId, connected, empty, day, coachReading, diet, history
    }

    init(
        apiVersion: Int = 1,
        trainingDayId: String,
        connected: Bool = true,
        empty: V1DayEmpty? = nil,
        day: V1NutritionDay?,
        coachReading: V1NutritionCoachReading? = nil,
        diet: [String] = [],
        history: [V1NutritionHistoryDay] = []
    ) {
        self.apiVersion = apiVersion
        self.trainingDayId = trainingDayId
        self.connected = connected
        self.empty = empty
        self.day = day
        self.coachReading = coachReading
        self.diet = diet
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        trainingDayId = try container.decode(String.self, forKey: .trainingDayId)
        connected = try container.decode(Bool.self, forKey: .connected)
        empty = try container.decodeIfPresent(V1DayEmpty.self, forKey: .empty)
        day = try container.decodeIfPresent(V1NutritionDay.self, forKey: .day)
        // The reading is an extra: a shape the app does not know yet must not cost the day.
        coachReading = (try? container.decodeIfPresent(V1NutritionCoachReading.self, forKey: .coachReading)) ?? nil
        diet = try container.decodeIfPresent([String].self, forKey: .diet) ?? []
        history = try container.decodeIfPresent([V1NutritionHistoryDay].self, forKey: .history) ?? []
    }
}

nonisolated struct V1NutritionDay: Decodable, Sendable, Equatable {
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    let fiber: Double?
    let sugar: Double?
    /// The athlete closed the day in their food log.
    let complete: Bool
    let goals: V1NutritionGoals?
    let fuelDensity: V1NutritionFuelDensity?
    let meals: [V1NutritionMeal]
}

nonisolated struct V1NutritionMacro: Decodable, Sendable, Equatable {
    let consumed: Double
    let goal: Double?
    let remaining: Double?
    /// Consumed over goal, in percent, as the server rounds it.
    let pct: Double?
}

nonisolated struct V1NutritionGoals: Decodable, Sendable, Equatable {
    let calories: V1NutritionMacro
    let protein: V1NutritionMacro
    let carbohydrates: V1NutritionMacro
    let fat: V1NutritionMacro
    let exerciseCalories: Double
    let calorieBudget: Double
}

nonisolated struct V1NutritionFuelDensity: Decodable, Sendable, Equatable {
    let proteinGPerKg: Double
    let carbohydratesGPerKg: Double
    let referenceWeightKg: Double
}

nonisolated struct V1NutritionMeal: Decodable, Sendable, Equatable, Hashable {
    let name: String
    let label: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let entries: [V1NutritionEntry]
}

nonisolated struct V1NutritionEntry: Decodable, Sendable, Equatable, Hashable {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

nonisolated struct V1NutritionHistoryDay: Decodable, Sendable, Equatable {
    let date: String
    let calories: Double?
    let goalCalories: Double?
}

/// The coach's reading of the day (the web's `NutritionCoachReadingView`).
nonisolated enum V1NutritionCoachReading: Decodable, Sendable, Equatable {
    case pending
    case awaitingDayEnd
    case unavailable
    case ready(Ready)

    nonisolated struct Ready: Decodable, Sendable, Equatable {
        let status: String
        /// A newer reading is being generated; this one stays visible meanwhile.
        let refreshing: Bool
        let verdict: Verdict
        let findings: [Finding]
        let action: Action
        let flaggedEntries: [FlaggedEntry]

        var isProvisional: Bool { status == "PROVISIONAL" }
    }

    nonisolated struct Verdict: Decodable, Sendable, Equatable {
        let headline: String
        let tone: Tone
    }

    nonisolated enum Tone: String, Decodable, Sendable {
        case onTrack = "on_track"
        case watch
        case offTrack = "off_track"
    }

    nonisolated struct Finding: Decodable, Sendable, Equatable, Hashable {
        let job: String
        let text: String
    }

    nonisolated struct Action: Decodable, Sendable, Equatable {
        let text: String
    }

    nonisolated struct FlaggedEntry: Decodable, Sendable, Equatable, Hashable {
        let meal: String
        let entry: String
        let reason: String
    }

    private enum CodingKeys: String, CodingKey { case state }

    init(from decoder: Decoder) throws {
        let state = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .state)
        switch state {
        case "pending": self = .pending
        case "awaiting_day_end": self = .awaitingDayEnd
        case "ready": self = .ready(try Ready(from: decoder))
        default: self = .unavailable
        }
    }
}

nonisolated extension V1NutritionResponse: V1DayResource {
    var dataByDay: [String: Bool] {
        Dictionary(history.map { ($0.date, $0.calories != nil) }, uniquingKeysWith: { $1 })
    }
}

/// The day's food log. Throws `SharpitAPIError.message("pro_required")` below SharpIt Pro.
nonisolated protocol NutritionServing: Sendable {
    func nutrition(trainingDayId: String, token: String) async throws -> V1NutritionResponse
}

extension SharpitAPIError {
    /// What the nutrition route answers below SharpIt Pro.
    nonisolated static let proRequired = SharpitAPIError.message("pro_required")
}

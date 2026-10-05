import Foundation

/// `GET /api/v1/nutrition` — mirrors `projectV1Nutrition` in the web repository. The food log
/// is the athlete's own data and open to all; only the coach's reading is SharpIt Pro.
///
/// Every measure decodes as `Double`: the food log sums servings and nothing guarantees
/// whole numbers.
nonisolated struct V1NutritionResponse: Decodable, Sendable, Equatable {
    let apiVersion: Int
    let trainingDayId: String
    /// Always true since the food log lives in SHARPIT (ADR-061); older servers sent false
    /// without MyFitnessPal. The server's `mfpConnected` is not read: the iPhone app neither
    /// links nor syncs MyFitnessPal (docs/adr/0010).
    let connected: Bool
    /// The server's words for a day without a log. The page draws its own empty day, with the
    /// week and the way to sync, so the drill-down's generic empty screen is never used.
    let emptyState: V1DayEmpty?
    var empty: V1DayEmpty? { nil }
    let day: V1NutritionDay?
    let coachReading: V1NutritionCoachReading?
    /// The diet declared in the journal, as labels.
    let diet: [String]
    /// Oldest first, one entry per day of the 14 ending on `trainingDayId`.
    let history: [V1NutritionHistoryDay]
    /// How many of those days were logged, and how many kept the calorie goal.
    let regularity: V1NutritionRegularity?

    enum CodingKeys: String, CodingKey {
        case apiVersion, trainingDayId, connected, empty, day, coachReading, diet, history, regularity
    }

    init(
        apiVersion: Int = 1,
        trainingDayId: String,
        connected: Bool = true,
        empty: V1DayEmpty? = nil,
        day: V1NutritionDay?,
        coachReading: V1NutritionCoachReading? = nil,
        diet: [String] = [],
        history: [V1NutritionHistoryDay] = [],
        regularity: V1NutritionRegularity? = nil
    ) {
        self.apiVersion = apiVersion
        self.trainingDayId = trainingDayId
        self.connected = connected
        self.emptyState = empty
        self.day = day
        self.coachReading = coachReading
        self.diet = diet
        self.history = history
        self.regularity = regularity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        trainingDayId = try container.decode(String.self, forKey: .trainingDayId)
        connected = try container.decode(Bool.self, forKey: .connected)
        emptyState = try container.decodeIfPresent(V1DayEmpty.self, forKey: .empty)
        day = try container.decodeIfPresent(V1NutritionDay.self, forKey: .day)
        // The reading is an extra: a shape the app does not know yet must not cost the day.
        coachReading = (try? container.decodeIfPresent(V1NutritionCoachReading.self, forKey: .coachReading)) ?? nil
        diet = try container.decodeIfPresent([String].self, forKey: .diet) ?? []
        history = try container.decodeIfPresent([V1NutritionHistoryDay].self, forKey: .history) ?? []
        regularity = try? container.decodeIfPresent(V1NutritionRegularity.self, forKey: .regularity)
    }
}

nonisolated struct V1NutritionDay: Codable, Sendable, Equatable {
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

nonisolated struct V1NutritionMacro: Codable, Sendable, Equatable {
    let consumed: Double
    let goal: Double?
    let remaining: Double?
    /// Consumed over goal, in percent, as the server rounds it.
    let pct: Double?
}

nonisolated struct V1NutritionGoals: Codable, Sendable, Equatable {
    let calories: V1NutritionMacro
    let protein: V1NutritionMacro
    let carbohydrates: V1NutritionMacro
    let fat: V1NutritionMacro
    let exerciseCalories: Double
    let calorieBudget: Double
}

nonisolated struct V1NutritionFuelDensity: Codable, Sendable, Equatable {
    let proteinGPerKg: Double
    let carbohydratesGPerKg: Double
    let referenceWeightKg: Double
}

nonisolated struct V1NutritionMeal: Codable, Sendable, Equatable, Hashable {
    let name: String
    let label: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let entries: [V1NutritionEntry]
}

nonisolated struct V1NutritionEntry: Codable, Sendable, Equatable, Hashable {
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
    /// How the day kept its calorie goal, as the server reads it.
    var adherence: V1CalorieAdherence = .none

    enum CodingKeys: String, CodingKey { case date, calories, goalCalories, adherence }

    init(date: String, calories: Double?, goalCalories: Double?, adherence: V1CalorieAdherence = .none) {
        self.date = date
        self.calories = calories
        self.goalCalories = goalCalories
        self.adherence = adherence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories)
        goalCalories = try container.decodeIfPresent(Double.self, forKey: .goalCalories)
        adherence = (try? container.decodeIfPresent(V1CalorieAdherence.self, forKey: .adherence))
            ?? (calories == nil ? .none : .onTarget)
    }
}

nonisolated enum V1CalorieAdherence: String, Decodable, Sendable {
    case onTarget = "on_target"
    case under
    case over
    case none
}

nonisolated struct V1NutritionRegularity: Decodable, Sendable, Equatable {
    let days: Int
    let logged: Int
    let onTarget: Int
}

/// The coach's reading of the day (the web's `NutritionCoachReadingView`).
nonisolated enum V1NutritionCoachReading: Decodable, Sendable, Equatable {
    case pending
    case awaitingDayEnd
    case unavailable
    /// Below SharpIt Pro: the reading is what SHARPIT adds, so it is neither generated nor sent.
    case proRequired
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
        case "pro_required": self = .proRequired
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

/// The day's food log.
nonisolated protocol NutritionServing: Sendable {
    func nutrition(trainingDayId: String, token: String) async throws -> V1NutritionResponse
}

/// `GET /api/v1/data-days` — which days of a range carry data for a drill-down, so the day
/// picker marks them before any of them is opened. At most 92 days per request.
nonisolated enum V1DataDaysDomain: String, Sendable {
    case sleep, recovery, effort, adaptation, nutrition, journal
}

nonisolated struct V1DataDays: Decodable, Sendable {
    let days: [String]
}

nonisolated protocol DataDaysServing: Sendable {
    func dataDays(domain: V1DataDaysDomain, from: String, to: String, token: String) async throws -> [String]
}
